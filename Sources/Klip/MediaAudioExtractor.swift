import Foundation
import AVFoundation
import CoreAudio
import UniformTypeIdentifiers

/// Extrae la pista de audio de un archivo de VIDEO a un archivo de audio temporal pequeño que AMBAS rutas de transcripción aceptan.
/// WhisperKit/AVAudioFile no puede decodificar contenedores de video (.mov/.mkv, y .mp4 con pista de video), y las
/// subidas a la nube tienen tope de tamaño. La salida es AAC .m4a mono a 16 kHz — la tasa nativa de Whisper y la forma EXACTA de
/// las notas de voz de la propia app (ver Recorder.start), así que WhisperKit ya la decodifica, OpenAI la acepta como
/// audio/mp4, y a ~14 MB/hora un clip normal queda bajo los topes de la nube. Usa AVAssetReader → AVAssetWriter
/// (no AVAssetExportSession) porque solo el par reader/writer permite fijar sample rate + canales + códec,
/// y se mantiene en el piso de despliegue macOS 14 (el overload async export() es macOS 15+).
enum MediaAudioExtractor {

    /// Contenedores de video que ADMITIMOS para subir (filtro de drop + selector de archivos). Los solapes con la lista de subida
    /// de audio (mp4/mpeg/webm pueden ser cualquiera de los dos) los resuelve con precisión `audioForTranscription`, que sondea las pistas.
    static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "qt", "avi", "mkv", "webm", "mpg", "mpeg", "m2v",
        "m2ts", "mts", "ts", "3gp", "3g2", "flv", "wmv", "ogv", "mxf", "dv", "asf", "vob"
    ]

    enum ExtractionError: Error, LocalizedError {
        case drmProtected
        case noAudioTrack
        case unreadable
        case readFailed(Error?)
        case writeFailed
        case tooLargeForCloud

        /// Clave L10n mostrada en la fila fallida de la ventana Upload (mapeada por el catch de Recorder).
        var uploadErrorKey: String {
            switch self {
            case .drmProtected:     return "upload.videoProtected"
            case .noAudioTrack:     return "upload.noAudioTrack"
            case .tooLargeForCloud: return "upload.tooLarge"
            case .unreadable, .readFailed, .writeFailed: return "upload.extractFailed"
            }
        }

        var errorDescription: String? {
            switch self {
            case .drmProtected:      return "This video is protected and its audio can't be read."
            case .noAudioTrack:      return "This video has no audio track to transcribe."
            case .unreadable:        return "Couldn't read this video file."
            case .readFailed(let e): return "Failed while reading the video's audio. \(e?.localizedDescription ?? "")"
            case .writeFailed:       return "Failed while extracting the audio."
            case .tooLargeForCloud:  return "The audio is too large for cloud transcription."
            }
        }
    }

    /// Chequeo grueso de admisión para el filtro de drop / selector de archivos: ¿es `url` plausiblemente un contenedor de video?
    /// Prefiere el content type real del SO; un UTI de audio gana. Recurre al conjunto de extensiones para contenedores
    /// que macOS no registra (mkv/webm). Sobre-incluir es inofensivo — `audioForTranscription` toma la decisión real
    /// de extraer-vs-pasar-directo sondeando las pistas reales.
    static func isVideo(_ url: URL) -> Bool {
        if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
            if type.conforms(to: .audio) { return false }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return true }
        }
        return videoExtensions.contains(url.pathExtension.lowercased())
    }

    /// El punto de entrada del pipeline. Devuelve `url` SIN CAMBIOS cuando ya es un archivo solo-audio decodificable (el
    /// caso común m4a/mp3/wav — un no-op barato). Si no, extrae la pista de audio de un contenedor de video a un
    /// .m4a temporal que QUIEN LLAMA debe borrar tras la transcripción. Lanza un ExtractionError específico (mostrado como
    /// fila fallida localizada) para entradas con DRM / sin audio / ilegibles.
    static func audioForTranscription(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)

        // DRM: los medios protegidos con FairPlay no podemos decodificarlos ni nosotros ni la nube.
        if (try? await asset.load(.hasProtectedContent)) == true { throw ExtractionError.drmProtected }

        // Sin pista de video visible → tratarlo como audio y entregar el archivo ORIGINAL al proveedor sin cambios.
        // WhisperKit lee audio común directamente, y las APIs de la nube aceptan webm/ogg/mp3/mp4-audio/etc. Esto
        // cubre .mp4 solo-audio (sin re-encode innecesario — y, una vez guardado, sigue reproducible en el historial) y
        // contenedores que AVFoundation no puede demuxar pero la nube igual acepta. Solo una pista de video REAL se demuxa.
        let videoTracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        if videoTracks.isEmpty { return url }

        // Un video real: sacar su pista de audio. Distinguir un archivo ilegible (load lanza) de uno que es
        // legible pero genuinamente no tiene audio (una grabación de pantalla muda) para que la fila fallida sea específica.
        let audioTracks: [AVAssetTrack]
        do { audioTracks = try await asset.loadTracks(withMediaType: .audio) }
        catch { throw ExtractionError.unreadable }
        guard let track = audioTracks.first else { throw ExtractionError.noAudioTrack }

        return try await extract(asset: asset, track: track)
    }

    // MARK: - Extracción (AVAssetReader → AVAssetWriter, AAC .m4a mono a 16 kHz)

    private static func extract(asset: AVAsset, track: AVAssetTrack) async throws -> URL {
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KlipVideoAudio-\(UUID().uuidString).m4a")

        let reader: AVAssetReader
        let writer: AVAssetWriter
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: outURL, fileType: .m4a)
        } catch { throw ExtractionError.unreadable }

        // Un solo channel layout mono, compartido por el downmix del reader y el encoder AAC (doble seguro para
        // que una fuente multicanal/5.1 se downmixee sin importar qué etapa respete el layout).
        var mono = AudioChannelLayout(); mono.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        let layout = Data(bytes: &mono, count: MemoryLayout<AudioChannelLayout>.size)

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVChannelLayoutKey: layout,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ExtractionError.unreadable }
        reader.add(output)

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVChannelLayoutKey: layout,
            AVEncoderBitRateKey: 32_000,
        ])
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw ExtractionError.writeFailed }
        writer.add(input)

        guard reader.startReading() else { throw ExtractionError.unreadable }
        guard writer.startWriting() else { throw ExtractionError.writeFailed }
        writer.startSession(atSourceTime: .zero)

        // El bombeo corre en un callback de dispatch SIN Task actual, así que Task.isCancelled es inútil ahí;
        // un flag protegido por lock que voltea el handler de cancelación se revisa en cada pasada.
        let cancelled = Flag()
        let queue = DispatchQueue(label: "klip.audio-extraction")

        // Los tipos de AVFoundation no son Sendable, pero el bombeo completo corre en la cola serial de arriba
        // (el handler de cancelación solo toca el Flag), así que envolverlos en una caja @unchecked Sendable es seguro.
        let box = PumpBox(reader: reader, writer: writer, input: input, output: output)

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    box.input.requestMediaDataWhenReady(on: queue) {
                        while box.input.isReadyForMoreMediaData {
                            if cancelled.value {
                                box.reader.cancelReading(); box.input.markAsFinished(); box.writer.cancelWriting()
                                cont.resume(throwing: CancellationError()); return
                            }
                            guard let buf = box.output.copyNextSampleBuffer() else {
                                box.input.markAsFinished()
                                if box.reader.status == .failed {
                                    box.writer.cancelWriting()
                                    cont.resume(throwing: ExtractionError.readFailed(box.reader.error)); return
                                }
                                box.writer.finishWriting {
                                    if box.writer.status == .completed { cont.resume() }
                                    else { cont.resume(throwing: ExtractionError.writeFailed) }
                                }
                                return
                            }
                            if !box.input.append(buf) {
                                box.reader.cancelReading(); box.writer.cancelWriting()
                                cont.resume(throwing: ExtractionError.writeFailed); return
                            }
                        }
                    }
                }
            } onCancel: {
                cancelled.set()
            }
        } catch {
            try? FileManager.default.removeItem(at: outURL)   // nunca dejar huérfano un archivo temporal parcial
            throw error
        }

        return outURL
    }

    /// Bool minúsculo protegido por lock tocado desde dos hilos (handler de cancelación + bombeo de extracción).
    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var flag = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
        func set() { lock.lock(); flag = true; lock.unlock() }
    }

    /// Caja para pasar los objetos (no Sendable) del reader/writer al closure @Sendable del bombeo.
    /// Seguro porque todos se usan solo en la cola serial de extracción.
    private struct PumpBox: @unchecked Sendable {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let output: AVAssetReaderTrackOutput
    }
}
