import AppKit
import Combine

/// Instantánea de la fuente tomada al inicio de poll().
struct CaptureSource {
    let name: String?
    let bundleID: String?
}

/// Monitorea el pasteboard, mantiene el historial y expone acciones.
/// @MainActor: todo el estado (items, voicePasteGuards…) se maneja desde el poll del RunLoop principal y SwiftUI, así que
/// el requisito de hilo principal lo garantiza el compilador en vez de la convención.
@MainActor
final class ClipboardManager: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    private var timer: Timer?
    private var lastChangeCount: Int
    private var maxItems: Int { Settings.shared.maxItems }
    private let storage = Storage.shared
    private let settings = Settings.shared
    private let ownBundleID = Bundle.main.bundleIdentifier

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        items = storage.loadItemsRaw()   // las credenciales selladas siguen selladas aquí: NADA de acceso al Llavero en el
                                         // hilo de arranque/principal (puede lanzar un prompt de confianza bloqueante → cuelgue)
        decryptCredentialsInBackground() // descifra fuera del main y luego fusiona el texto plano de vuelta
        reconcileVoiceNotesOnLoad()
        // Limpia huérfanos (audios/imágenes sin ítem, p. ej. tras cerrar a mitad de una transcripción).
        // Solo si hay ítems: un array de ítems vacío también ocurre cuando items.json está corrupto/ilegible, y en
        // ese caso el barrido borraría TODOS los medios (evitamos esa pérdida; los archivos quedan ahí para recuperación).
        if !items.isEmpty {
            storage.pruneOrphans(
                referencedAudio: Set(items.compactMap { $0.audioFileName }),
                referencedImages: Set(items.compactMap { $0.imageFileName }))
        }
    }

    /// Repara notas de voz que quedaron en "Transcribiendo…" (la app se cerró durante la transcripción):
    /// si aún conservan su audio, pasan a "sin transcripción" (recuperable); si no, se descartan.
    private func reconcileVoiceNotesOnLoad() {
        var changed = false
        for idx in items.indices where items[idx].isVoiceNote == true && items[idx].transcribing == true {
            if let af = items[idx].audioFileName, storage.audioExists(fileName: af) {
                items[idx].text = nil
                items[idx].preview = Self.voiceFailed
                items[idx].transcribing = false   // recuperable: ya no está "en curso"
            } else {
                items[idx].audioFileName = nil     // marcar para eliminación (mantiene transcribing == true)
            }
            changed = true
        }
        let before = items.count
        items.removeAll { $0.isVoiceNote == true && $0.transcribing == true && $0.audioFileName == nil }
        if changed || items.count != before { storage.saveItems(items) }
    }

    /// Descifra las credenciales selladas FUERA del hilo principal y luego fusiona el texto plano de vuelta. El acceso al Llavero
    /// puede lanzar un prompt de confianza bloqueante (p. ej. tras re-firmar la app); hacerlo en el hilo de
    /// arranque/principal atascaría la app. Hasta que esto termina, las credenciales selladas simplemente muestran el
    /// placeholder enmascarado. Fusiona por id y solo toca los campos de credencial, así que un clip capturado (o un ítem
    /// fijado/borrado) durante la breve ventana no se pisa.
    private func decryptCredentialsInBackground() {
        let snapshot = items
        guard !snapshot.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            let decrypted = Storage.shared.decryptCredentials(snapshot)
            let byId = Dictionary(decrypted.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            // ¿Se marcó algún secreto legado en texto claro? Si es así, su texto plano debe persistirse (sellado) —
            // pre-crear la clave de cifrado AQUÍ (fuera del main) para que el saveItems en el main de abajo nunca ejecute una
            // ESCRITURA al Llavero (SecItemAdd) en el hilo principal.
            let snapById = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let promoted = decrypted.contains { d in snapById[d.id]?.isCredential != true && d.isCredential == true }
            if promoted { CredentialCrypto.warmKey() }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.items = self.items.map { cur in
                    guard let d = byId[cur.id], let snap = snapById[cur.id] else { return cur }
                    // Omitir si el usuario editó este ítem durante la ventana fuera del main (alternó credencial,
                    // re-copió, renombró…): aplicar el descifrado SOLO cuando aún coincide con la instantánea
                    // previa al descifrado, para nunca revertir en silencio el cambio del usuario.
                    guard cur.text == snap.text, cur.isCredential == snap.isCredential, cur.preview == snap.preview else { return cur }
                    guard cur.text != d.text || cur.isCredential != d.isCredential || cur.preview != d.preview else { return cur }
                    var c = cur
                    c.text = d.text; c.isCredential = d.isCredential; c.preview = d.preview
                    return c
                }
                // Solo re-guardar para promociones legadas; un descifrado simple sellado→texto plano es solo en memoria
                // (la forma sellada en disco ya es correcta), así que no reescribir items.json en cada arranque.
                // La clave se precalentó fuera del main arriba, así que seal() aquí solo lee la clave (rápido, sin prompt).
                if promoted { self.storage.saveItems(self.items) }
            }
        }
    }

    func start() {
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }   // corre en RunLoop.main; lo afirmamos para el compilador
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Pausa el monitoreo del pasteboard (p. ej. durante una importación: evita escribir en el mismo
    /// directorio que la importación en segundo plano). Llamar en el hilo principal.
    func pauseMonitoring() { timer?.invalidate(); timer = nil }

    /// Reanuda el monitoreo. Re-ancla lastChangeCount para que lo copiado durante la pausa no se capture.
    func resumeMonitoring() {
        guard timer == nil else { return }
        lastChangeCount = NSPasteboard.general.changeCount
        start()
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        let source = currentSource()                // fuente ANTES del filtro (el foco puede cambiar)
        guard !shouldIgnore(pb) else { return }
        capture(from: pb, source: source)
    }

    private func currentSource() -> CaptureSource {
        // Deshabilitado: atribuir la "fuente" a la app en primer plano al momento del poll era poco fiable
        // (marcaba la app activa equivocada, p. ej. la que tenía el foco 0.5s después).
        CaptureSource(name: nil, bundleID: nil)
    }

    // MARK: - Filtro de privacidad

    private func shouldIgnore(_ pb: NSPasteboard) -> Bool {
        hasPrivacyMarker(pb) || isFrontmostAppExcluded()
    }

    private func hasPrivacyMarker(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        let s = Set(types)
        if settings.ignoreConcealed     && s.contains(PasteboardPrivacyTypes.concealed)     { return true }
        if settings.ignoreTransient     && s.contains(PasteboardPrivacyTypes.transient)     { return true }
        if settings.ignoreAutoGenerated && s.contains(PasteboardPrivacyTypes.autoGenerated) { return true }
        return false
    }

    private func isFrontmostAppExcluded() -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        if id == ownBundleID { return false }
        return settings.excludedBundleIDs.contains(id)
    }

    // MARK: - Captura

    private func capture(from pb: NSPasteboard, source: CaptureSource) {
        let remote = settings.detectRemoteSource
            && RemoteClipboardHeuristic.looksRemote(pb: pb, source: source,
                                                    captureSourceEnabled: settings.captureSource)
        // Una copia de archivo del Finder (y algunas copias enriquecidas) trae A LA VEZ una miniatura y la URL/texto del archivo.
        // Preferir el texto/URL para no perderlo guardando la miniatura como contenido.
        let trimmedString = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmedString?.isEmpty ?? true),
           let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            addText(urls.map { $0.isFileURL ? $0.path : $0.absoluteString }.joined(separator: "\n"),
                    source: source, remote: remote); return
        }
        if let str = trimmedString, !str.isEmpty {
            let raw = pb.string(forType: .string) ?? str
            // "Pegar siempre limpio": si la copia trae texto enriquecido, guardar una versión Markdown limpia que conserva
            // negritas/cursivas + emojis pero descarta fondo oscuro / colores / fuentes. Las copias planas no se ven afectadas.
            // Usar la versión limpia solo si produjo contenido real — un resultado vacío/en blanco (p. ej. un
            // RTF solo con imagen) NO debe reemplazar el texto plano del usuario.
            let cleaned = settings.cleanCapture ? RichText.cleanMarkdown(from: pb) : nil
            let text = (cleaned?.isEmpty == false) ? cleaned! : raw
            addText(text, source: source, remote: remote); return
        }
        if hasImageData(pb), let image = NSImage(pasteboard: pb) {
            addImage(image, source: source, remote: remote)
        }
    }

    private func hasImageData(_ pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        if types.contains(.tiff) || types.contains(.png)
            || types.contains(NSPasteboard.PasteboardType("public.jpeg")) { return true }
        // Aceptar cualquier cosa que NSImage realmente pueda decodificar (HEIC, GIF, WebP, …) en vez de descartarla en silencio.
        let readable = Set(NSImage.imageTypes)
        return types.contains { readable.contains($0.rawValue) }
    }

    private func addText(_ text: String, source: CaptureSource, remote: Bool) {
        if let idx = items.firstIndex(where: { $0.kind == .text && $0.isVoiceNote != true && $0.text == text }) {
            var item = items.remove(at: idx)
            item.createdAt = Date()
            item.sourceName = source.name           // refrescar la fuente con la nueva captura
            item.sourceBundleID = source.bundleID
            item.isRemote = remote ? true : nil
            // Re-evaluar el estado de credencial al re-copiar para que un secreto re-copiado se enmascare de nuevo (no seguir
            // mostrando en la vista previa, en texto claro, un secreto que antes no fue marcado).
            let isCred = CredentialDetector.looksLikeCredential(text)
            item.isCredential = isCred ? true : nil
            item.preview = isCred ? CredentialDetector.maskedPlaceholder
                : String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            items.insert(item, at: 0)
        } else {
            let isCred = CredentialDetector.looksLikeCredential(text)
            let preview = isCred
                ? CredentialDetector.maskedPlaceholder   // placeholder constante: nunca persistir caracteres derivados del secreto (la fila muestra masked(text) en vivo)
                : String(text.prefix(160)).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            items.insert(ClipboardItem(kind: .text, text: text, preview: preview,
                                       sourceName: source.name, sourceBundleID: source.bundleID,
                                       isRemote: remote ? true : nil,
                                       isCredential: isCred ? true : nil), at: 0)
        }
        trimAndSave()
    }

    private func addImage(_ image: NSImage, source: CaptureSource, remote: Bool) {
        let fileName = "\(UUID().uuidString).png"
        guard storage.saveImage(image, fileName: fileName) != nil else { return }   // no agregar una fila fantasma si el archivo no se guardó
        let size = image.pixelDimensions
        let preview = String(format: L10n.t("preview.image"), Int(size.width), Int(size.height))
        items.insert(ClipboardItem(kind: .image, imageFileName: fileName, preview: preview,
                                   sourceName: source.name, sourceBundleID: source.bundleID,
                                   isRemote: remote ? true : nil), at: 0)
        trimAndSave()
    }

    /// Inserta una captura anotada (Klip Snap) en el historial persistente y, opcionalmente, la deja
    /// en el pasteboard. Contraparte pública de `addImage`, pero para imágenes generadas por la app
    /// (no capturadas del pasteboard). Queda disponible para OCR y búsqueda como cualquier otra imagen.
    @discardableResult
    func addAnnotatedScreenshot(_ image: NSImage, copyToClipboard: Bool = true) -> UUID {
        let fileName = "\(UUID().uuidString).png"
        let size = image.pixelDimensions   // píxeles reales (no puntos): badge consistente en Retina
        let preview = String(format: L10n.t("preview.capture"), Int(size.width), Int(size.height))
        let item = ClipboardItem(kind: .image, imageFileName: fileName, preview: preview)
        if storage.saveImage(image, fileName: fileName) != nil {
            items.insert(item, at: 0)   // solo agregar una fila al historial si el archivo realmente se guardó
            trimAndSave()
        } else {
            NSSound.beep()
        }
        if copyToClipboard {            // entregar igual la imagen al portapapeles aunque el guardado fallara
            let pb = NSPasteboard.general
            pb.clearContents(); pb.writeObjects([image])
            lastChangeCount = pb.changeCount   // ya gestionado aquí: no re-capturarlo como un ítem nuevo
        }
        return item.id
    }

    // MARK: - Notas de voz (audio guardado + transcripción en 3 pasos)

    static var voiceTranscribing: String { "🎙 " + L10n.t("voice.transcribing") }
    static var voiceFailed: String { "🎙 " + L10n.t("voice.failed") }
    static var voiceFailedNoAudio: String { "🎙 " + L10n.t("voice.failedNoAudio") }

    private static func voicePreview(_ clean: String) -> String {
        "🎙 " + String(clean.prefix(160))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// changeCount del pasteboard cuando cada nota comienza: solo auto-pegamos su transcripción si el
    /// usuario NO copió nada más mientras se transcribía (no pisar su pasteboard en segundo plano).
    private var voicePasteGuards: [UUID: Int] = [:]

    /// Crea el ítem de nota de voz con su audio (placeholder "Transcribiendo…") y devuelve su id.
    @discardableResult
    func beginVoiceNote(audioFileName: String?, duration: Double?) -> UUID {
        let item = ClipboardItem(kind: .text, preview: Self.voiceTranscribing,
                                 isVoiceNote: true, transcribing: true,
                                 audioFileName: audioFileName, audioDuration: duration)
        items.insert(item, at: 0)
        voicePasteGuards[item.id] = NSPasteboard.general.changeCount
        trimAndSave()
        return item.id
    }

    /// Rellena la duración del audio de una nota de voz una vez leída fuera del hilo. Solo en memoria — el
    /// resultado inminente de la transcripción (finishVoiceNote/failVoiceNote) la persiste, así que no hay guardado extra aquí.
    func setVoiceNoteDuration(id: UUID, duration: Double) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].audioDuration = duration
    }

    /// Adjunta a posteriori el archivo de audio guardado a una nota de voz (una subida solo-audio que llegó en un
    /// contenedor con tipo de video y se guardó al confirmar que no era un video real). La mantiene reproducible/reintentable.
    func setVoiceNoteAudioFile(id: UUID, fileName: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].audioFileName = fileName
        // Persistir YA: si la app se cierra a mitad de la transcripción, reconcileVoiceNotesOnLoad descartaría
        // una nota "transcribiendo" sin audioFileName y pruneOrphans borraría el audio recién importado.
        storage.saveItems(items)
    }

    /// Marca un ítem como "Transcribiendo…" de nuevo (reintento de una nota fallida).
    func markVoiceNoteTranscribing(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].text = nil
        items[idx].preview = Self.voiceTranscribing
        items[idx].transcribing = true
        // Re-registrar el guard del pasteboard: si no, un reintento exitoso nunca auto-pegaría
        // (removeValue devolvería nil → canPaste=false). El auto-pegado en reintentos estaba muerto.
        voicePasteGuards[id] = NSPasteboard.general.changeCount
        storage.saveItems(items)
    }

    static var voiceDownloading: String { "🎙 " + L10n.t("voice.downloading") }

    /// Primer uso en el dispositivo: el modelo aún se está descargando. Mostrar eso en vez del genérico "Transcribiendo…".
    func markVoiceNoteDownloadingModel(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].preview = Self.voiceDownloading
        storage.saveItems(items)
    }

    /// Rellena la transcripción. Solo la deja en el pasteboard si el usuario NO copió otra cosa
    /// mientras se transcribía (evita pisar su pasteboard en segundo plano).
    func finishVoiceNote(id: UUID, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let canPaste = voicePasteGuards.removeValue(forKey: id).map { $0 == NSPasteboard.general.changeCount } ?? false
        guard let idx = items.firstIndex(where: { $0.id == id }) else {
            // El ítem ya no existe: el usuario lo borró (o fue reemplazado en una importación). No tocar su
            // pasteboard con la transcripción de una nota que eliminó intencionalmente.
            return
        }
        // Un secreto dictado/transcrito debe pasar por la misma ruta de enmascarado + sellado-al-guardar que uno
        // copiado — si no, persistiría en texto claro (text + preview) y se auto-pegaría.
        let isCred = !clean.isEmpty && CredentialDetector.looksLikeCredential(clean)
        items[idx].text = clean.isEmpty ? nil : clean
        items[idx].isCredential = isCred ? true : nil
        items[idx].preview = clean.isEmpty ? Self.voiceFailed
                           : isCred ? CredentialDetector.maskedPlaceholder : Self.voicePreview(clean)
        items[idx].transcribing = false
        let item = items[idx]
        trimAndSave()
        if !clean.isEmpty, !isCred, canPaste {   // nunca auto-pegar un secreto detectado
            copyToPasteboard(item)     // solo si nada cambió el pasteboard
            rebaselineVoiceGuards()    // NUESTRO propio pegado no es un pisotón del usuario: mantener auto-pegables las notas hermanas
        }
    }

    /// Re-ancla cada guard de pegado de nota de voz aún pendiente al changeCount actual del pasteboard.
    /// Se llama justo después de que ESTA app pega una nota terminada, para que una segunda nota concurrente
    /// no sea suprimida falsamente por nuestra propia escritura (changeCount es un único contador global).
    private func rebaselineVoiceGuards() {
        let cc = NSPasteboard.general.changeCount
        for id in voicePasteGuards.keys { voicePasteGuards[id] = cc }
    }

    /// La transcripción falló: mantiene el ítem visible (con audio reproducible si lo hay) en vez de
    /// borrarlo en silencio, para que el usuario sepa qué pasó y pueda recuperarlo o eliminarlo.
    func failVoiceNote(id: UUID) {
        voicePasteGuards.removeValue(forKey: id)
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].text = nil
        items[idx].transcribing = false
        items[idx].preview = items[idx].audioFileName != nil ? Self.voiceFailed : Self.voiceFailedNoAudio
        storage.saveItems(items)
    }

    /// No se recorta: ni los ítems fijados ni una nota de voz aún transcribiéndose (se perdería su audio/texto).
    private func isProtectedFromTrim(_ it: ClipboardItem) -> Bool {
        it.pinned || (it.isVoiceNote == true && it.transcribing == true)
    }

    private func trimAndSave() {
        if items.count > maxItems {
            let keep = items.filter { isProtectedFromTrim($0) }
            var trimmable = items.filter { !isProtectedFromTrim($0) }
            let allowed = max(0, maxItems - keep.count)
            if trimmable.count > allowed {
                for it in trimmable[allowed...] {
                    if it.kind == .image, let f = it.imageFileName { storage.deleteImage(fileName: f) }
                    if let af = it.audioFileName { AudioPlayer.shared.stopIfPlaying(af); storage.deleteAudio(fileName: af) }
                }
                trimmable = Array(trimmable.prefix(allowed))
            }
            items = (keep + trimmable).sorted { $0.createdAt > $1.createdAt }
        }
        storage.saveItems(items)
    }

    func applyMaxItems() { trimAndSave() }

    // MARK: - Acciones

    func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        switch item.kind {
        case .text:
            guard let t = item.text, !t.isEmpty else { return }   // nota de voz sin texto: no tocar el pasteboard
            if item.isCredential == true, CredentialCrypto.isSealed(t) { return }   // indescifrable en este Mac: no copiar el token crudo
            pb.clearContents(); pb.setString(t, forType: .string)
        case .image:
            guard let f = item.imageFileName, let img = storage.loadImage(fileName: f) else { return }
            pb.clearContents(); pb.writeObjects([img])
        }
        lastChangeCount = pb.changeCount
    }

    func setClipboardText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount   // evita re-capturar la salida Markdown/OCR como un ítem nuevo
    }

    /// Copia para el cuerpo de un correo como texto ENRIQUECIDO (RTF): renderiza **negritas**/*cursivas*/enlaces y CONSERVA
    /// los saltos de línea, para que Mail/Gmail lo muestren formateado en vez de texto plano chato. Encabezados/viñetas se limpian a plano/•.
    func copyForEmail(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var md = t.replacingOccurrences(of: "\r\n", with: "\n")
        md = md.replacingOccurrences(of: "(?m)^#{1,6}[ \\t]+", with: "", options: .regularExpression)          // encabezados → plano
        md = md.replacingOccurrences(of: "(?m)^[ \\t]*[-*+•◦][ \\t]+", with: "• ", options: .regularExpression) // viñetas (incl. viñetas con tab) → "• "
        md = restoreParagraphSpacing(md)   // la captura rich→text aplana las líneas en blanco; reponer una línea en blanco entre párrafos de prosa
        let pb = NSPasteboard.general
        pb.clearContents()
        // inlineOnlyPreservingWhitespace renderiza énfasis/enlaces pero conserva cada salto de línea (sin colapso de párrafos).
        if let parsed = try? NSAttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            // El parser marca negritas/cursivas como `inlinePresentationIntent` (semántico), que RTF ignora —
            // convertirlo en una FUENTE negrita/cursiva real para que Mail/Gmail realmente lo rendericen.
            let attr = NSMutableAttributedString(attributedString: parsed)
            let full = NSRange(location: 0, length: attr.length)
            attr.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: full)
            attr.enumerateAttribute(.inlinePresentationIntent, in: full) { value, range, _ in
                guard let raw = (value as? NSNumber)?.uintValue else { return }
                let intent = InlinePresentationIntent(rawValue: raw)
                var f = NSFont.systemFont(ofSize: 13)
                if intent.contains(.stronglyEmphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { f = NSFontManager.shared.convert(f, toHaveTrait: .italicFontMask) }
                attr.addAttribute(.font, value: f, range: range)
            }
            if let rtf = try? attr.data(from: full, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                pb.setData(rtf, forType: .rtf)
                pb.setString(attr.string, forType: .string)   // fallback plano para apps que ignoran RTF
            } else {
                pb.setString(attr.string, forType: .string)
            }
        } else {
            pb.setString(Markdownify.toEmail(t), forType: .string)
        }
        lastChangeCount = pb.changeCount   // nuestra propia escritura — no re-capturarla
    }

    /// La captura de texto enriquecido aplana el espaciado de párrafos a saltos simples. Reponer una línea en blanco ENTRE
    /// líneas de prosa (para que el correo no sea un bloque denso), manteniendo compacta una lista de viñetas y sin agregar
    /// blancos donde ya existe uno.
    private func restoreParagraphSpacing(_ md: String) -> String {
        let lines = md.components(separatedBy: "\n")
        func isBullet(_ s: String) -> Bool { s.hasPrefix("• ") }
        var out = ""
        for (i, line) in lines.enumerated() {
            if i > 0 {
                let prev = lines[i - 1].trimmingCharacters(in: .whitespaces)
                let curr = line.trimmingCharacters(in: .whitespaces)
                let tight = prev.isEmpty || curr.isEmpty || (isBullet(prev) && isBullet(curr))
                out += tight ? "\n" : "\n\n"
            }
            out += line
        }
        return out
    }

    /// Resultado de la captura de texto OCR: ponerlo en el portapapeles (listo para pegar) Y agregarlo al historial. Devuelve
    /// false si no había nada que agregar (OCR vacío).
    @discardableResult
    func addCapturedText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        setClipboardText(t)   // listo para pegar; esto también sube lastChangeCount para que el poll no lo agregue dos veces
        addText(t, source: CaptureSource(name: nil, bundleID: nil), remote: false)
        return true
    }

    func delete(_ item: ClipboardItem) {
        if item.kind == .image, let f = item.imageFileName { storage.deleteImage(fileName: f) }
        if let af = item.audioFileName { AudioPlayer.shared.stopIfPlaying(af); storage.deleteAudio(fileName: af) }
        voicePasteGuards.removeValue(forKey: item.id)
        items.removeAll { $0.id == item.id }
        storage.saveItems(items)
    }

    /// Reemplaza el historial en memoria tras importar un respaldo.
    /// True mientras al menos una nota de voz sigue transcribiéndose en segundo plano.
    var hasActiveTranscription: Bool { items.contains { $0.transcribing == true } }

    func reload(_ newItems: [ClipboardItem]) {
        AudioPlayer.shared.stop()
        voicePasteGuards.removeAll()   // los ids viejos desaparecen tras un reload/import: no pegar una transcripción obsoleta
        items = newItems
        storage.saveItems(items)
    }

    func clearAll() {
        AudioPlayer.shared.stop()
        voicePasteGuards.removeAll()
        for it in items {
            if it.kind == .image, let f = it.imageFileName { storage.deleteImage(fileName: f) }
            if let af = it.audioFileName { storage.deleteAudio(fileName: af) }
        }
        items.removeAll()
        storage.saveItems(items)
    }

    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        trimAndSave()   // re-evaluar el recorte al desfijar (puede exceder maxItems)
    }

    // MARK: - Colecciones (vibe coders)

    /// Asigna (o limpia, con un nombre vacío) una colección a varios ítems.
    func assignCollection(_ ids: Set<UUID>, to name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        for idx in items.indices where ids.contains(items[idx].id) { items[idx].collection = value }
        storage.saveItems(items)
    }

    /// Nombres de las colecciones existentes (para los filtros).
    var collections: [String] { Array(Set(items.compactMap { $0.collection })).sorted() }

    /// Establece (o limpia) la etiqueta/nombre de un ítem. El nombre es buscable y se muestra como título.
    func rename(_ item: ClipboardItem, to name: String) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        items[idx].name = trimmed.isEmpty ? nil : trimmed
        storage.saveItems(items)
    }

    /// Marca o desmarca un ítem como credencial (mini gestor).
    func toggleCredential(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if let t = items[idx].text, CredentialCrypto.isSealed(t) {
            // Sellado-pero-indescifrable en este Mac (cifrado en otra máquina): el "text" es texto cifrado,
            // no el secreto. No dejar que desmarcar eche el token klipenc1: crudo a la vista previa — mantenerlo como
            // credencial con el placeholder constante.
            items[idx].isCredential = true
            items[idx].preview = CredentialDetector.maskedPlaceholder
            storage.saveItems(items)
            return
        }
        let nowCred = !(items[idx].isCredential == true)
        items[idx].isCredential = nowCred ? true : nil
        if let t = items[idx].text {   // regenerar la vista previa (enmascarar / desenmascarar)
            items[idx].preview = nowCred
                ? CredentialDetector.maskedPlaceholder   // constante: la fila calcula masked(text) en vivo
                : String(t.prefix(160)).replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        }
        storage.saveItems(items)
    }
}

/// Heurística de mejor esfuerzo para "otro dispositivo" (NO hay una API pública fiable de Universal Clipboard).
enum RemoteClipboardHeuristic {
    static func looksRemote(pb: NSPasteboard, source: CaptureSource, captureSourceEnabled: Bool) -> Bool {
        // Solo marcamos "otro dispositivo" si el marcador fiable de Apple está presente.
        // La heurística de "sin app de origen" producía falsos positivos (SecurityAgent, helpers…);
        // se eliminó: preferimos NO marcar antes que marcar mal.
        pb.types?.contains(where: { $0.rawValue == "com.apple.is-remote-clipboard" }) == true
    }
}
