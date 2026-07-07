import Foundation

/// Almacén local para la API key, en un archivo dentro del directorio de soporte de la app.
///
/// Se usa un archivo (permisos 0600) en lugar del Llavero porque, con firma **ad-hoc**,
/// macOS vuelve a pedir permiso del Llavero en cada rebuild (la identidad cambia),
/// lo que rompía la transcripción. El archivo es texto plano en tu Mac (mismo nivel que el
/// historial). Para cifrado real, firma con un Developer ID y vuelve al Llavero.
enum SecretStore {
    /// Cada proveedor guarda su clave en un archivo separado (0600) en el directorio de la app.
    enum Key: String { case openai = "openai.key", gemini = "gemini.key" }

    private static func fileURL(_ k: Key) -> URL {
        Storage.shared.baseURL.appendingPathComponent(k.rawValue)
    }

    static func get(_ k: Key = .openai) -> String? {
        guard let s = try? String(contentsOf: fileURL(k), encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Guarda la clave y la CONFIRMA releyéndola. Devuelve `true` solo si el archivo
    /// se escribió con exactamente el valor esperado. Propaga el error real si la escritura falla
    /// (p. ej. permisos del directorio), en lugar de tragárselo con `try?`.
    @discardableResult
    static func set(_ value: String, _ k: Key = .openai) throws -> Bool {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let url = fileURL(k)
        // Asegurar que el directorio base exista (Storage lo crea, pero no está de más ir a lo seguro).
        try? FileManager.default.createDirectory(at: Storage.shared.baseURL,
                                                 withIntermediateDirectories: true)
        try t.write(to: url, atomically: true, encoding: .utf8)   // sin try?: dejar que el error se propague
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // Confirmación: releer del disco y comparar (detecta escrituras fallidas en silencio).
        return get(k) == t
    }

    static func delete(_ k: Key = .openai) { try? FileManager.default.removeItem(at: fileURL(k)) }

    static func hasKey(_ k: Key = .openai) -> Bool { get(k) != nil }

    static func last4(_ k: Key = .openai) -> String? {
        guard let v = get(k), v.count >= 4 else { return nil }
        return String(v.suffix(4))
    }
}
