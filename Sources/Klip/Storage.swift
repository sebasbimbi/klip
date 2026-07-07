import Foundation
import AppKit
import PDFKit

/// Persistencia en disco: metadatos del historial (JSON), imágenes (PNG) y audio temporal (m4a).
final class Storage {
    static let shared = Storage()

    let baseURL: URL
    let imagesURL: URL
    let audioBaseURL: URL
    private let itemsURL: URL

    init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        let newBase = appSupport.appendingPathComponent("Klip", isDirectory: true)
        let oldBase = appSupport.appendingPathComponent("PastaClip", isDirectory: true)

        // Migración: si la carpeta antigua existe y la nueva aún no, moverla completa (rename atómico).
        if fm.fileExists(atPath: oldBase.path), !fm.fileExists(atPath: newBase.path) {
            do { try fm.moveItem(at: oldBase, to: newBase) }
            catch { try? fm.copyItem(at: oldBase, to: newBase) }
        }

        baseURL = newBase
        imagesURL = baseURL.appendingPathComponent("images", isDirectory: true)
        audioBaseURL = baseURL.appendingPathComponent("audio", isDirectory: true)
        itemsURL = baseURL.appendingPathComponent("items.json")
        try? fm.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: audioBaseURL, withIntermediateDirectories: true)
        // Igual que items.json (0600): el almacén contiene datos personales (texto, voz, imágenes).
        Self.restrict(baseURL.path, 0o700)
        Self.restrict(imagesURL.path, 0o700)
        Self.restrict(audioBaseURL.path, 0o700)
    }

    /// Restringe un archivo/carpeta al propietario (privacidad consistente con items.json).
    static func restrict(_ path: String, _ perms: Int) {
        try? FileManager.default.setAttributes([.posixPermissions: perms], ofItemAtPath: path)
    }

    // MARK: - Historial (metadatos)

    /// Los secretos de credenciales se guardan cifrados en disco (ver CredentialCrypto). Se descifran de vuelta
    /// a texto plano para su uso en memoria; el texto no-credencial y el nunca cifrado (legacy) pasan tal cual.
    func decryptCredentials(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.map { item in
            if item.isCredential == true, let t = item.text, CredentialCrypto.isSealed(t) {
                // CRÍTICO: si open() falla (clave de otro Mac / Llavero reseteado), CONSERVAR el token sellado.
                // Ponerlo a nil dejaría que el próximo saveItems escriba null sobre la única copia del secreto —
                // pérdida permanente de datos. Con el token preservado, el guard isSealed de saveItems lo devuelve intacto.
                guard let plain = CredentialCrypto.open(t) else { return item }
                var copy = item
                copy.text = plain
                return copy
            }
            // Promover secretos legacy en texto plano nunca marcados (capturados antes de esta función, o importados
            // de un respaldo antiguo) para que el próximo guardado los selle — si no, quedarían en claro en items.json.
            // Usa el detector de ALTA CONFIANZA: un cifrado+ocultado silencioso en reposo no debe dispararse con un
            // identificador kebab/CSS ni una línea de prosa "clave: valor".
            if item.kind == .text, item.isVoiceNote != true, item.isCredential != true,
               let t = item.text, !CredentialCrypto.isSealed(t), CredentialDetector.looksLikeHighConfidenceCredential(t) {
                var copy = item
                copy.isCredential = true
                copy.preview = CredentialDetector.maskedPlaceholder   // constante: nunca persistir caracteres derivados del secreto
                return copy
            }
            return item
        }
    }

    /// Decodifica los ítems SIN tocar el Llavero (sin descifrar credenciales). Seguro en el hilo de arranque /
    /// principal: una lectura del Llavero aquí puede levantar un prompt bloqueante de confianza "la app quiere usar
    /// tu llavero" que cuelga toda la app antes de arrancar. Descifrar aparte, fuera del hilo principal (decryptCredentials).
    func loadItemsRaw() -> [ClipboardItem] {
        guard let data = try? Data(contentsOf: itemsURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let items = try? decoder.decode([ClipboardItem].self, from: data) { return items }
        // La decodificación falló pero el archivo existe → respaldarlo antes de que algo lo sobrescriba.
        if !data.isEmpty {
            try? data.write(to: baseURL.appendingPathComponent("items.corrupt.json"), options: .atomic)
        }
        return []
    }

    /// Conveniencia: carga cruda + descifrado. Llamar solo FUERA del hilo principal (toca el Llavero).
    func loadItems() -> [ClipboardItem] { decryptCredentials(loadItemsRaw()) }

    func saveItems(_ items: [ClipboardItem]) {
        // Cifrar los secretos de credenciales antes de que lleguen al disco (y al zip de respaldo). Los ítems en
        // memoria no se tocan; si el cifrado no está disponible conservamos el texto plano antes que perder el valor.
        let toStore = items.map { item -> ClipboardItem in
            guard item.isCredential == true, let t = item.text, !t.isEmpty, !CredentialCrypto.isSealed(t) else { return item }
            guard let sealed = CredentialCrypto.seal(t) else {
                // Clave del Llavero ilegible (p. ej. la app se re-firmó con otra identidad y el usuario
                // negó el prompt de acceso). Conservamos el valor antes que perderlo, pero quedaría en
                // texto claro — hacerlo NO-SILENCIOSO para poder diagnosticarlo en vez de degradar la privacidad en silencio.
                NSLog("KLIP: could not encrypt a credential (Keychain key inaccessible); value kept unsealed")
                return item
            }
            var copy = item
            copy.text = sealed
            return copy
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(toStore) else { return }
        try? data.write(to: itemsURL, options: .atomic)
        // Defensa en profundidad sobre el cifrado: restringir el archivo solo al usuario.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: itemsURL.path)
    }

    // MARK: - Imágenes

    @discardableResult
    func saveImage(_ image: NSImage, fileName: String) -> URL? {
        guard let png = pngData(from: image) else { return nil }
        let url = imagesURL.appendingPathComponent(fileName)
        do {
            try png.write(to: url, options: .atomic)
            Self.restrict(url.path, 0o600)
            return url
        } catch { return nil }
    }

    func imageURL(for fileName: String) -> URL { imagesURL.appendingPathComponent(fileName) }
    func loadImage(fileName: String) -> NSImage? { NSImage(contentsOf: imageURL(for: fileName)) }
    func deleteImage(fileName: String) {
        imageCache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: imageURL(for: fileName))
    }

    private let imageCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>(); c.countLimit = 60; return c
    }()

    /// Imagen cacheada en memoria: evita releer/decodificar desde disco en cada render de la lista.
    func cachedImage(fileName: String) -> NSImage? {
        if let c = imageCache.object(forKey: fileName as NSString) { return c }
        guard let img = loadImage(fileName: fileName) else { return nil }
        imageCache.setObject(img, forKey: fileName as NSString)
        return img
    }

    func pngData(from image: NSImage) -> Data? {
        // Si la imagen ya tiene un bitmap, codificar el PNG directamente desde la rep de mayor resolución
        // (evita el round-trip por TIFF, que duplica la memoria en capturas grandes).
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { $0.pixelsWide < $1.pixelsWide }),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Audio (notas de voz: el original se conserva junto a la transcripción)

    func audioURL(for fileName: String) -> URL { audioBaseURL.appendingPathComponent(fileName) }
    func deleteAudio(fileName: String) { try? FileManager.default.removeItem(at: audioURL(for: fileName)) }
    func audioExists(fileName: String) -> Bool { FileManager.default.fileExists(atPath: audioURL(for: fileName).path) }

    /// Restringe el archivo de audio de una nota de voz a 0600 (AVAudioRecorder lo crea con el umask por defecto).
    func protectAudio(fileName: String) { Self.restrict(audioURL(for: fileName).path, 0o600) }

    /// Copia un archivo de audio externo (subido por el usuario) a nuestro almacén y devuelve el nuevo nombre,
    /// para poder reproducirlo y conservarlo aunque el archivo original se mueva o se borre.
    func importAudio(from url: URL) -> String? {
        let ext = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let name = "\(UUID().uuidString).\(ext)"
        let dest = audioURL(for: name)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            Self.restrict(dest.path, 0o600)
            return name
        } catch { return nil }
    }

    /// Borra archivos de audio/imagen que ya no referencia ningún ítem (huérfanos por un crash, etc.).
    func pruneOrphans(referencedAudio: Set<String>, referencedImages: Set<String>) {
        prune(dir: audioBaseURL, keep: referencedAudio)
        prune(dir: imagesURL, keep: referencedImages)
    }

    private func prune(dir: URL, keep: Set<String>) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where !keep.contains(name) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: - Respaldo (exportar / importar)

    /// Exporta el historial (items.json + imágenes + audio) a un .zip. NO incluye las API keys.
    func exportBackup(to dest: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("KlipExport-\(UUID().uuidString)", isDirectory: true)
        let stage = work.appendingPathComponent("Klip", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        if fm.fileExists(atPath: itemsURL.path) {
            try fm.copyItem(at: itemsURL, to: stage.appendingPathComponent("items.json"))
        }
        if fm.fileExists(atPath: imagesURL.path) {
            try fm.copyItem(at: imagesURL, to: stage.appendingPathComponent("images"))
        }
        if fm.fileExists(atPath: audioBaseURL.path) {
            try fm.copyItem(at: audioBaseURL, to: stage.appendingPathComponent("audio"))
        }
        try? fm.removeItem(at: dest)
        try Self.runDitto(["-c", "-k", "--keepParent", stage.path, dest.path])
    }

    /// Importa un respaldo .zip y REEMPLAZA el historial actual, **transaccionalmente**:
    /// valida el respaldo, mueve los datos actuales a `.importbak`, copia los datos nuevos y, ante CUALQUIER fallo,
    /// restaura desde el respaldo → el historial existente nunca se pierde. Devuelve los ítems.
    /// (Pesado: ejecutarlo fuera del hilo principal.)
    func importBackup(from src: URL) throws -> [ClipboardItem] {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("KlipImport-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        try Self.runDitto(["-x", "-k", src.path, tmp.path])

        guard let root = Self.findBackupRoot(in: tmp) else {
            throw Self.err(L10n.t("backup.err.notBackup"))
        }
        // Validar que el items.json del respaldo decodifica ANTES de tocar nada (no importar basura).
        let newItemsFile = root.appendingPathComponent("items.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: newItemsFile),
              let decoded = try? decoder.decode([ClipboardItem].self, from: data) else {
            throw Self.err(L10n.t("backup.err.corrupt"))
        }

        let newImages = root.appendingPathComponent("images")
        let newAudio = root.appendingPathComponent("audio")
        // Respaldos con nombre único por intento → los restos de un import abortado nunca chocan
        // con el moveItem de abajo (evita restaurar un .bak viejo sobre el original intacto).
        let token = UUID().uuidString
        let bakItems = baseURL.appendingPathComponent("items.json.\(token).importbak")
        let bakImages = baseURL.appendingPathComponent("images.\(token).importbak")
        let bakAudio = baseURL.appendingPathComponent("audio.\(token).importbak")
        // Limpiar restos de imports abortados anteriores — pero NUNCA los respaldos de este intento (saltar nuestro
        // token), para que un import solapado no pueda borrar el respaldo del que dependeremos para el rollback.
        if let leftovers = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
            for f in leftovers where f.lastPathComponent.hasSuffix(".importbak") && !f.lastPathComponent.contains(token) {
                try? fm.removeItem(at: f)
            }
        }

        // Restaura un destino desde su respaldo (solo si el respaldo existe → el original está a salvo).
        func restore(_ live: URL, _ bak: URL) {
            guard fm.fileExists(atPath: bak.path) else { return }   // sin bak: la copia viva es el original intacto
            try? fm.removeItem(at: live)
            try? fm.moveItem(at: bak, to: live)
        }

        do {
            // Mover los datos actuales a .bak (renames atómicos dentro del mismo volumen).
            if fm.fileExists(atPath: itemsURL.path)     { try fm.moveItem(at: itemsURL, to: bakItems) }
            if fm.fileExists(atPath: imagesURL.path)    { try fm.moveItem(at: imagesURL, to: bakImages) }
            if fm.fileExists(atPath: audioBaseURL.path) { try fm.moveItem(at: audioBaseURL, to: bakAudio) }
            // Colocar los datos nuevos en su sitio.
            try fm.copyItem(at: newItemsFile, to: itemsURL)
            if fm.fileExists(atPath: newImages.path) { try fm.copyItem(at: newImages, to: imagesURL) }
            else { try fm.createDirectory(at: imagesURL, withIntermediateDirectories: true) }
            if fm.fileExists(atPath: newAudio.path) { try fm.copyItem(at: newAudio, to: audioBaseURL) }
            else { try fm.createDirectory(at: audioBaseURL, withIntermediateDirectories: true) }
        } catch {
            restore(itemsURL, bakItems)        // rollback: deja el historial como estaba
            restore(imagesURL, bakImages)
            restore(audioBaseURL, bakAudio)
            throw error
        }

        [bakItems, bakImages, bakAudio].forEach { try? fm.removeItem(at: $0) }   // éxito: limpiar los respaldos
        Self.restrict(itemsURL.path, 0o600)
        Self.restrict(imagesURL.path, 0o700)
        Self.restrict(audioBaseURL.path, 0o700)
        imageCache.removeAllObjects()
        let result = decryptCredentials(decoded)   // las credenciales del items.json importado están cifradas en disco
        // importBackup corre FUERA del hilo principal. Si alguna credencial importada necesitará sellarse en el
        // próximo guardado (un secreto legacy en texto plano recién promovido), pre-crear la clave del Llavero AQUÍ
        // para que el reload→saveItems en main solo la LEA — nunca ESCRIBIR al Llavero en el hilo principal (evita esa clase de cuelgues).
        if result.contains(where: { $0.isCredential == true && ($0.text.map { !CredentialCrypto.isSealed($0) } ?? false) }) {
            CredentialCrypto.warmKey()
        }
        return result
    }

    private static func err(_ msg: String) -> NSError {
        NSError(domain: "Klip", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }

    /// Localiza la carpeta del respaldo que contiene items.json (keepParent → .../Klip/items.json).
    private static func findBackupRoot(in dir: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("items.json").path) { return dir }
        guard let subs = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for sub in subs where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if fm.fileExists(atPath: sub.appendingPathComponent("items.json").path) { return sub }
        }
        return nil
    }

    private static func runDitto(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw NSError(domain: "Klip", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: String(format: L10n.t("backup.err.ditto"), p.terminationStatus)])
        }
    }

    // MARK: - Combinar / exportar selección (vibe coders)

    /// Combina varios ítems en un PDF (una página por ítem): las imágenes como página de imagen,
    /// el texto como página de texto. Para subir varias capturas/notas a una IA de una sola vez.
    /// Devuelve los datos y cuántas páginas se generaron (pueden ser menos que items.count si algún
    /// ítem no tenía contenido exportable). nil si no se pudo generar ninguna página.
    /// Texto seguro para escribir a un archivo/PDF exportado: las credenciales van enmascaradas, nunca en claro
    /// (refleja MarkdownExporter). Devuelve nil si no hay texto que exportar.
    static func exportableText(_ item: ClipboardItem) -> String? {
        guard let t = item.text, !t.isEmpty else { return nil }
        // Usar el placeholder sin caracteres reales (no masked(), que filtraría los últimos 4 reales del secreto
        // a un export PDF/ZIP/Markdown compartido).
        return item.isCredential == true ? CredentialDetector.maskedPlaceholder : t
    }

    func combinedPDF(from items: [ClipboardItem]) -> (data: Data, exported: Int)? {
        let doc = PDFDocument()
        var idx = 0
        for it in items {
            var pageImage: NSImage?
            if it.kind == .image, let f = it.imageFileName { pageImage = loadImage(fileName: f) }
            else if let t = Self.exportableText(it) { pageImage = Self.pageImage(forText: t) }
            if let img = pageImage, let page = PDFPage(image: img) { doc.insert(page, at: idx); idx += 1 }
        }
        guard idx > 0, let data = doc.dataRepresentation() else { return nil }
        return (data, idx)
    }

    /// Renderiza texto en una "página" (imagen tamaño carta) con márgenes, para incrustarla en el PDF.
    /// Usa un drawingHandler (thread-safe fuera del hilo principal) en vez de lockFocus, ya que combinedPDF
    /// corre en una cola en segundo plano.
    private static func pageImage(forText text: String) -> NSImage {
        let pageW: CGFloat = 612, margin: CGFloat = 40   // Carta US a 72 dpi
        let style = NSMutableParagraphStyle(); style.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.black, .paragraphStyle: style]
        let textW = pageW - margin * 2
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: textW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let pageH = max(200, ceil(bounds.height) + margin * 2)
        return NSImage(size: NSSize(width: pageW, height: pageH), flipped: false) { _ in
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: pageW, height: pageH).fill()
            (text as NSString).draw(with: NSRect(x: margin, y: margin, width: textW, height: pageH - margin * 2),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
            return true
        }
    }

    /// Cuántos de los ítems tienen contenido que exportar a ZIP (imagen en disco, audio o texto).
    func zipExportableCount(_ items: [ClipboardItem]) -> Int {
        let fm = FileManager.default
        return items.reduce(0) { acc, it in
            if it.kind == .image, let f = it.imageFileName, fm.fileExists(atPath: imageURL(for: f).path) { return acc + 1 }
            if let af = it.audioFileName, audioExists(fileName: af) { return acc + 1 }
            if let t = it.text, !t.isEmpty { return acc + 1 }
            return acc
        }
    }

    /// Exporta los ítems seleccionados a un .zip (imágenes PNG, texto .txt, audio). Para subir el lote junto.
    func exportItemsZip(_ items: [ClipboardItem], to dest: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("KlipSel-\(UUID().uuidString)", isDirectory: true)
        let stage = work.appendingPathComponent("Klip", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        for (i, it) in items.enumerated() {
            let n = String(format: "%02d", i + 1)
            let base = (it.name?.isEmpty == false ? it.name! : "item").replacingOccurrences(of: "/", with: "-")
            if it.kind == .image, let f = it.imageFileName, fm.fileExists(atPath: imageURL(for: f).path) {
                try? fm.copyItem(at: imageURL(for: f), to: stage.appendingPathComponent("\(n)-\(base).png"))
            } else if let af = it.audioFileName, audioExists(fileName: af) {
                try? fm.copyItem(at: audioURL(for: af), to: stage.appendingPathComponent("\(n)-\(base).m4a"))
                if let t = Self.exportableText(it) { try? t.data(using: .utf8)?.write(to: stage.appendingPathComponent("\(n)-\(base).txt")) }
            } else if let t = Self.exportableText(it) {
                try? t.data(using: .utf8)?.write(to: stage.appendingPathComponent("\(n)-\(base).txt"))
            }
        }
        try? fm.removeItem(at: dest)
        try Self.runDitto(["-c", "-k", "--keepParent", stage.path, dest.path])
    }
}

extension NSImage {
    /// Dimensiones REALES en píxeles (no puntos): toma la rep de mayor resolución. En pantallas
    /// retina, `size` viene en puntos (la mitad), así que esto es lo que el usuario espera ver.
    var pixelDimensions: NSSize {
        var w = 0, h = 0
        for r in representations { w = max(w, r.pixelsWide); h = max(h, r.pixelsHigh) }
        return (w > 0 && h > 0) ? NSSize(width: w, height: h) : size
    }
}
