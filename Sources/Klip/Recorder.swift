import Foundation
import AVFoundation
import AppKit
import Combine
import CoreAudio

enum RecorderState: Equatable {
    case idle
    case recording
    case missingAPIKey
    case micDenied          // permiso de micrófono denegado → guiar a Ajustes del Sistema
    case error(String)      // error ANTES de que empiece la grabación (permiso/clave). La transcripción corre en segundo plano.
}

/// La transcripción de un archivo de audio subido, mostrada en vivo en la ventana de Upload. `text == nil` mientras corre.
struct UploadTranscription: Identifiable, Equatable {
    let id: UUID            // el id del ítem de nota de voz
    let name: String        // nombre original del archivo
    var text: String?       // se rellena cuando la transcripción termina
    var failed: Bool = false
    var errorKey: String? = nil   // clave L10n para un fallo ESPECÍFICO (sin pista de audio / DRM / demasiado grande); nil → genérico
}

/// Graba una nota de voz a .m4a y la transcribe con OpenAI (no en vivo: la nota completa de una vez).
/// La transcripción corre en segundo plano: una vez detenida, el grabador queda libre para grabar otra.
@MainActor
final class Recorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var state: RecorderState = .idle
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var level: Float = 0
    /// true cuando llevamos >2 min en silencio: la UI muestra "¿Sigues ahí?".
    @Published private(set) var silenceWarning = false
    /// Número de transcripciones corriendo en segundo plano (para el indicador del encabezado).
    @Published private(set) var transcribingCount = 0
    /// True mientras una transcripción en el dispositivo espera a que el modelo cargue por primera vez en esta
    /// sesión (el calentamiento único de ~20 s del Neural Engine). Permite que la UI diga "Preparando modelo…"
    /// para que la primera nota no parezca atascada en un simple spinner de "Transcribiendo…".
    @Published private(set) var preparingModel = false
    /// Transcripciones de archivos soltados/elegidos en la ventana de Upload, las más nuevas primero — para que el
    /// resultado aparezca ahí mismo al terminar (no solo en el historial). Con tope; se limpia al abrir una sesión de subida nueva.
    @Published private(set) var uploadResults: [UploadTranscription] = []
    /// Número de subidas actualmente DEMUXEANDO la pista de audio de un video (antes de que empiece la transcripción).
    /// Alimenta el estado "Extrayendo audio…" para que un video largo no parezca atascado en un simple spinner de "Transcribiendo…".
    @Published private(set) var extractingCount = 0

    /// El audio ya está guardado: crea el ítem de nota de voz (placeholder) y devuelve su id.
    /// `audioFileName` puede ser nil si el archivo no se pudo guardar (la transcripción se guarda igual).
    var onVoiceNoteStarted: ((String?, Double?) -> UUID?)?
    /// Rellena la transcripción en el ítem ya creado.
    var onVoiceNoteTranscribed: ((UUID, String) -> Void)?
    /// Rellena la duración del audio una vez leída fuera del hilo principal (evita que la UI se congele en subidas masivas).
    var onVoiceNoteDuration: ((UUID, Double) -> Void)?
    /// La transcripción falló o no había voz: el ítem conserva el audio para reproducirlo/recuperarlo.
    var onVoiceNoteFailed: ((UUID) -> Void)?
    /// Reintento: marca un ítem existente como "Transcribiendo…" de nuevo.
    var onVoiceNoteRetrying: ((UUID) -> Void)?
    /// Primer uso en el dispositivo: el modelo se está descargando, así que se muestra un estado distinto en vez de "Transcribiendo…".
    var onVoiceNoteDownloadingModel: ((UUID) -> Void)?
    /// Una subida clasificada como video resultó ser audio puro (.mp4 solo-audio, etc.): su audio se almacenó, así que
    /// se adjunta a la nota para que reproducción/reintento sigan funcionando (los videos reales intencionalmente no se almacenan).
    var onVoiceNoteAudioStored: ((UUID, String) -> Void)?

    // Detección de silencio (timer a 0.1 s): avisa a los 2 min, detiene a los 3 min.
    private var silentTicks = 0
    private let silenceLevel: Float = 0.10
    private let warnTicks = 1200    // 120 s
    private let stopTicks = 1800    // 180 s

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var currentFileName: String?
    private let storage = Storage.shared
    /// Listener de CoreAudio para detectar cambios en el micrófono por defecto (p. ej. conectar audífonos).
    private var deviceListener: AudioObjectPropertyListenerBlock?

    /// Intención pendiente de grabar (cubre la ventana asíncrona del permiso).
    private var startRequested = false
    /// true desde que se pide detener hasta que el delegate termina (el estado sigue en .recording en ese lapso).
    private(set) var finishing = false
    /// Solo bloquea iniciar otra GRABACIÓN; transcribir en segundo plano no cuenta como ocupado.
    var isRecording: Bool { startRequested || state == .recording }

    private func requestMicPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied:  return false
        case .undetermined:
            return await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { ok in cont.resume(returning: ok) }
            }
        @unknown default: return false
        }
    }

    @MainActor
    func start() {
        guard !isRecording else { return }
        startRequested = true
        Task { @MainActor in
            guard AIProvider.hasKey else { state = .missingAPIKey; startRequested = false; return }
            guard await requestMicPermission() else {
                state = .micDenied; startRequested = false; return
            }
            guard startRequested else { return }   // stop()/cancel() mientras se esperaba el permiso
            let name = "\(UUID().uuidString).m4a"
            let url = storage.audioURL(for: name)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            do {
                let rec = try AVAudioRecorder(url: url, settings: settings)
                rec.delegate = self
                rec.isMeteringEnabled = true
                guard rec.prepareToRecord(), rec.record() else {
                    storage.deleteAudio(fileName: name)   // prepareToRecord() creó el archivo; record() falló → no dejarlo huérfano
                    state = .error(L10n.t("rec.err.start")); startRequested = false; return
                }
                recorder = rec
                currentFileName = name
                duration = 0; level = 0
                silentTicks = 0; silenceWarning = false
                state = .recording
                startRequested = false
                startMeterTimer()
                installDeviceListener()
            } catch {
                state = .error(error.localizedDescription); startRequested = false
            }
        }
    }

    @MainActor
    func stop() {
        startRequested = false
        guard state == .recording, !finishing, let rec = recorder else { return }   // ignorar doble stop
        finishing = true
        stopMeterTimer()
        removeDeviceListener()
        rec.stop()   // dispara audioRecorderDidFinishRecording
    }

    @MainActor
    func cancel() {
        startRequested = false
        finishing = false
        stopMeterTimer()
        removeDeviceListener()
        recorder?.delegate = nil   // evita que el delegate sobrescriba .idle con .error
        recorder?.stop()
        recorder = nil
        if let f = currentFileName { storage.deleteAudio(fileName: f) }
        currentFileName = nil
        state = .idle
    }

    // MARK: - Cambio de dispositivo de entrada (audífonos)

    /// Vigila el micrófono por defecto. Si cambia DURANTE la grabación (p. ej. conectas audífonos),
    /// AVAudioRecorder se queda en el dispositivo viejo y el medidor se congela → terminamos la nota
    /// limpiamente (lo grabado hasta ahí se guarda y se transcribe) en vez de dejar un estado roto.
    private func installDeviceListener() {
        guard deviceListener == nil else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        // El block se despacha en DispatchQueue.main (pasado abajo), así que ya corre en el hilo
        // principal — asertar MainActor directamente en vez de un salto async extra.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.handleInputDeviceChange() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        if status == noErr { deviceListener = block }
    }

    private func removeDeviceListener() {
        guard let block = deviceListener else { return }
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        deviceListener = nil
    }

    @MainActor
    private func handleInputDeviceChange() {
        guard state == .recording, !finishing else { return }
        stop()   // terminar y transcribir lo grabado hasta el cambio de dispositivo
    }

    /// Vuelve a .idle desde estados terminales (error o falta de API key) para revalidar al reabrir.
    func reset() {
        switch state {
        case .error, .missingAPIKey, .micDenied: state = .idle
        default: break
        }
    }

    private func startMeterTimer() {
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {   // corre en RunLoop.main; asertarlo para el compilador
                guard let self, let rec = self.recorder else { return }
                rec.updateMeters()
                self.duration = rec.currentTime
                let lvl = Self.normalized(power: rec.averagePower(forChannel: 0))
                self.level = lvl
                self.trackSilence(level: lvl)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        meterTimer = t
    }

    private func trackSilence(level lvl: Float) {
        if lvl >= silenceLevel {
            silentTicks = 0
            if silenceWarning { silenceWarning = false }
            return
        }
        silentTicks += 1
        if silentTicks == warnTicks {
            silenceWarning = true
            NSSound.beep()
        } else if silentTicks >= stopTicks {
            stop()   // detener por inactividad: terminar y transcribir (ya en MainActor vía el timer del medidor)
        }
    }

    /// El usuario pulsa "Continuar": reinicia el contador de silencio.
    func continueRecording() { silentTicks = 0; silenceWarning = false }

    /// Transcribe uno o más archivos de audio subidos por el usuario (en segundo plano).
    /// Cada audio se copia a nuestro almacén para poder reproducirlo y conservarlo después.
    /// `language` sobrescribe la pista de idioma hablado solo para ESTA subida (p. ej. el usuario soltó un audio
    /// en francés mientras el default de la app es español). Pasa "" para autodetección, nil para usar el default global.
    @MainActor
    func transcribeFiles(_ urls: [URL], language: String? = nil) {
        guard !urls.isEmpty else { return }
        guard AIProvider.hasKey else {
            // `state` se comparte con una grabación en vivo (RecordingView/UploadView lo observan ambas). Solo
            // reportar "falta la clave" a través de él cuando está idle, para que una subida sin clave no mate una nota en curso.
            if state != .recording && !finishing { state = .missingAPIKey }
            return
        }
        // Sin auto-copiado forzado: finishVoiceNote ya deja la transcripción en el portapapeles cuando es
        // seguro (guard de changeCount — no pisa lo que el usuario copió mientras tanto — y nunca un secreto).
        for url in urls {
            // Video: no copiar el archivo (a menudo grande) al almacén de audio — transcribir directo del
            // original (la app no está sandboxeada, así que la URL sigue legible) y dejar que el cuello de
            // botella de la transcripción demuxee su audio a un archivo temporal. La nota resultante es solo
            // texto (sin reproducción/reintento), lo cual es honesto porque deliberadamente no conservamos el
            // video. El audio mantiene el copiado al almacén para seguir reproducible/reintentable en el historial.
            let isVideo = MediaAudioExtractor.isVideo(url)
            let stored = isVideo ? nil : storage.importAudio(from: url)        // copia a audio/ (nil si falla)
            let transcribeURL = stored.map { storage.audioURL(for: $0) } ?? url
            enqueueTranscription(audioFileName: stored, transcribeURL: transcribeURL,
                                 uploadName: url.lastPathComponent, language: language)
        }
    }

    /// Limpia la lista de resultados de la ventana de Upload (se llama al abrir una sesión de subida nueva, ver PanelController).
    @MainActor func clearUploadResults() { uploadResults.removeAll() }

    private func fillUploadResult(_ id: UUID, text: String?, failed: Bool, errorKey: String? = nil) {
        guard let i = uploadResults.firstIndex(where: { $0.id == id }) else { return }   // no es una subida: no-op
        uploadResults[i].text = text
        uploadResults[i].failed = failed
        uploadResults[i].errorKey = errorKey
    }

    /// Crea el ítem de nota de voz con su audio ya guardado y lanza la transcripción.
    /// El audio NUNCA se borra aquí: sigue accesible aunque la transcripción falle.
    /// `state` vuelve a .idle de inmediato → el grabador queda libre para grabar otra nota.
    @MainActor
    private func ingest(audioFileName name: String) {
        storage.protectAudio(fileName: name)   // 0600: la grabación contiene la voz del usuario
        enqueueTranscription(audioFileName: name, transcribeURL: storage.audioURL(for: name))
        state = .idle
    }

    /// Lanza una transcripción en segundo plano: crea el ítem placeholder y lo rellena al terminar.
    /// No toca `state` (solo el contador), así que no interfiere con una grabación nueva en curso.
    @MainActor
    private func enqueueTranscription(audioFileName: String?, transcribeURL: URL, uploadName: String? = nil, language: String? = nil) {
        let id = onVoiceNoteStarted?(audioFileName, nil)
        // Leer la duración construye un AVAudioPlayer (parsea el archivo) — hacerlo fuera del main actor para que
        // una subida masiva no congele la UI, y luego rellenarla. Lo persiste el guardado inminente de la transcripción.
        if let id {
            Task { @MainActor in
                if let dur = await Task.detached(priority: .utility, operation: { AudioPlayer.duration(of: transcribeURL) }).value {
                    onVoiceNoteDuration?(id, dur)
                }
            }
        }
        if let uploadName, let id {   // mostrar el progreso + resultado de este archivo en la ventana de Upload
            uploadResults.insert(UploadTranscription(id: id, name: uploadName), at: 0)
            // Tope de la lista: preferir desalojar una entrada COMPLETADA/fallida (nunca una en vuelo — eso
            // dejaría huérfano su fillUploadResult). Si TODAS siguen en vuelo, un tope duro descarta la más
            // vieja para que la lista no crezca sin límite.
            if uploadResults.count > 25 {
                if let i = uploadResults.lastIndex(where: { $0.text != nil || $0.failed }) { uploadResults.remove(at: i) }
                else if uploadResults.count > 50 { uploadResults.removeLast() }
            }
        }
        transcribeInBackground(id: id, url: transcribeURL, languageOverride: language)
    }

    /// Reintenta transcribir el audio de un ítem que ya existe (una nota fallida con su audio).
    @MainActor
    func retry(itemID: UUID, audioFileName: String) {
        onVoiceNoteRetrying?(itemID)
        transcribeInBackground(id: itemID, url: storage.audioURL(for: audioFileName))
    }

    /// Núcleo de la transcripción en segundo plano (compartido por grabar, subir y reintentar). No toca `state`.
    @MainActor
    private func transcribeInBackground(id: UUID?, url: URL, languageOverride: String? = nil) {
        transcribingCount += 1
        // Resolver el modelo del proveedor activo aquí, en el MainActor (evita leer Settings.shared
        // desde el hilo de transcripción). Gemini y OpenAI tienen cada uno su propio ajuste de modelo.
        // Resolver el proveedor + su modelo aquí, en el MainActor (un solo snapshot — evita tanto un data race
        // leyendo Settings.shared fuera del hilo como un TOCTOU de proveedor/modelo). Cada proveedor usa su propia
        // clave, así que no hay fallback entre proveedores (grabar ya está condicionado a AIProvider.hasKey para la selección).
        let provider = Settings.shared.aiProvider
        let model = provider == "gemini" ? Settings.shared.geminiModel
                  : provider == "local"  ? Settings.shared.localModel
                  : Settings.shared.transcriptionModel
        let language = languageOverride ?? Settings.shared.transcriptionLanguage   // el override por subida gana
        let vocabulary = Settings.shared.transcriptionVocabulary
        // El primer uso en el dispositivo descarga el modelo: mostrar "Descargando modelo…" para que no parezca atascado.
        if provider == "local", !LocalTranscriber.isModelReady(model), let id { onVoiceNoteDownloadingModel?(id) }
        // La primera transcripción en el dispositivo de la sesión paga un calentamiento único de Core ML / Neural
        // Engine (~20 s, luego en caché): mostrarlo como "Preparando modelo…" en vez de un simple spinner de "Transcribiendo…".
        if provider == "local", !LocalTranscriber.pipelineReady { preparingModel = true }
        Task { @MainActor in
            // Limpiar "Preparando…" cuando el contador se vacía O el pipeline ya está caliente (una transcripción
            // solapada entonces está realmente transcribiendo, no preparando).
            defer { transcribingCount -= 1; if transcribingCount == 0 || LocalTranscriber.pipelineReady { preparingModel = false } }
            do {
                // NORMALIZACIÓN DE VIDEO: WhisperKit/AVAudioFile no pueden decodificar contenedores de video, así
                // que primero demuxear la pista de audio a un .m4a temporal AAC mono de 16 kHz. Solo corre para
                // entradas de video; el audio (grabar / reintentar / subir audio) se lo salta por completo. Corre
                // fuera del MainActor → el await suspende sin bloquear la UI. Aguas arriba del switch de proveedor,
                // así que local + ambas nubes reciben audio decodificable (y arregla el bug latente donde un .mp4 con pista de video fallaba en silencio en la ruta local).
                let mediaURL: URL
                if MediaAudioExtractor.isVideo(url) {
                    extractingCount += 1
                    do { mediaURL = try await MediaAudioExtractor.audioForTranscription(from: url) }
                    catch { extractingCount -= 1; throw error }
                    extractingCount -= 1
                    // Passthrough (mediaURL == url) significa que era audio en un contenedor tipado como película
                    // (p. ej. un .mp4 solo-audio), NO un video real — así que almacenarlo ahora para que la nota siga
                    // reproducible/reintentable (un video real deliberadamente no se almacena, ver transcribeFiles).
                    // Guardas: (1) no re-importar en un reintento (la fuente ya vive en el almacén — duplicaría el
                    // archivo en cada reintento); (2) solo con pista de audio CONFIRMADA — un contenedor que
                    // AVFoundation no puede demuxear (mkv/wmv/vob…) también cae en passthrough, y sin esta
                    // comprobación copiaríamos el video completo al almacén como "audio" irreproducible.
                    if mediaURL == url, let id,
                       !url.path.hasPrefix(storage.audioBaseURL.path),
                       (try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio))?.isEmpty == false,
                       let stored = storage.importAudio(from: url) {
                        onVoiceNoteAudioStored?(id, stored)
                    }
                } else {
                    mediaURL = url
                }
                let cleanupTemp = (mediaURL != url)
                defer { if cleanupTemp { try? FileManager.default.removeItem(at: mediaURL) } }

                // Guardia previa de tamaño para la nube: AAC mono a 16 kHz es ~14 MB/h, así que un clip muy largo
                // aún puede exceder los topes de la nube. OpenAI envía bytes crudos (límite ~25 MB → piso de 24 MB);
                // Gemini envía inline_data en base64 (inflación de ~4/3 contra un tope de request de ~20 MB → ~15 MB de audio crudo).
                // Convertir el fallo HTTP opaco en una fila clara de "demasiado grande — cambia a en-dispositivo". Local
                // (WhisperKit) no tiene límite de tamaño → saltar.
                let cloudLimit = provider == "gemini" ? 15_000_000 : 24_000_000
                if provider != "local",
                   let sz = try? FileManager.default.attributesOfItem(atPath: mediaURL.path)[.size] as? Int,
                   sz > cloudLimit {
                    throw MediaAudioExtractor.ExtractionError.tooLargeForCloud
                }

                let text = try await AIProvider.transcribe(provider: provider, audioURL: mediaURL, language: language, model: model, vocabulary: vocabulary)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { if let id { onVoiceNoteFailed?(id); fillUploadResult(id, text: nil, failed: true) } }
                else { if let id { onVoiceNoteTranscribed?(id, trimmed); fillUploadResult(id, text: trimmed, failed: false) } }
            } catch {
                NSLog("Klip: transcription failed — %@", String(describing: error))   // hacerlo visible, no fallar en silencio
                let key = (error as? MediaAudioExtractor.ExtractionError)?.uploadErrorKey
                if let id { onVoiceNoteFailed?(id); fillUploadResult(id, text: nil, failed: true, errorKey: key) }   // el audio queda en el historial para reintentar/recuperar
            }
        }
    }

    private func stopMeterTimer() { meterTimer?.invalidate(); meterTimer = nil }

    private static func normalized(power db: Float) -> Float {
        let minDb: Float = -50
        if db < minDb { return 0 }
        return min(1, (db - minDb) / -minDb)
    }

    nonisolated func audioRecorderDidFinishRecording(_ r: AVAudioRecorder, successfully ok: Bool) {
        Task { @MainActor in
            removeDeviceListener()   // asegura quitar el listener también si el delegate se dispara por su cuenta
            finishing = false
            recorder = nil
            guard let name = currentFileName else { return }   // cancelado: no es un error, solo salir
            currentFileName = nil
            guard ok else { state = .error(L10n.t("rec.err.failed")); return }
            ingest(audioFileName: name)   // conserva el .m4a y transcribe
        }
    }

    deinit {
        // Red de seguridad. deinit es nonisolated y no puede llamar al método @MainActor, así que quitar el
        // listener de CoreAudio inline (acceder a la propiedad almacenada propia de la instancia en deinit está permitido).
        if let block = deviceListener {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        }
    }
}
