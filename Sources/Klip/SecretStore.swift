import Foundation

/// Almacén local de la API key, en un archivo del directorio de soporte de la app.
///
/// Se usa un archivo (perms 0600) en lugar del Llavero porque, con firma **ad-hoc**,
/// macOS vuelve a pedir permiso del Llavero en cada recompilación (la identidad cambia),
/// lo que rompía la transcripción. El archivo es texto plano en tu Mac (mismo nivel que el
/// historial). Para cifrado real, firma con Developer ID y vuelve a usar el Llavero.
enum SecretStore {
    /// Cada proveedor guarda su clave en un archivo distinto (0600) del directorio de la app.
    enum Key: String { case openai = "openai.key", gemini = "gemini.key" }

    private static func fileURL(_ k: Key) -> URL {
        Storage.shared.baseURL.appendingPathComponent(k.rawValue)
    }

    static func get(_ k: Key = .openai) -> String? {
        guard let s = try? String(contentsOf: fileURL(k), encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func set(_ value: String, _ k: Key = .openai) {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let url = fileURL(k)
        try? t.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func delete(_ k: Key = .openai) { try? FileManager.default.removeItem(at: fileURL(k)) }

    static func hasKey(_ k: Key = .openai) -> Bool { get(k) != nil }

    static func last4(_ k: Key = .openai) -> String? {
        guard let v = get(k), v.count >= 4 else { return nil }
        return String(v.suffix(4))
    }
}
