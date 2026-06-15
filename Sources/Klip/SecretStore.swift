import Foundation

/// Almacén local de la API key, en un archivo del directorio de soporte de la app.
///
/// Se usa un archivo (perms 0600) en lugar del Llavero porque, con firma **ad-hoc**,
/// macOS vuelve a pedir permiso del Llavero en cada recompilación (la identidad cambia),
/// lo que rompía la transcripción. El archivo es texto plano en tu Mac (mismo nivel que el
/// historial). Para cifrado real, firma con Developer ID y vuelve a usar el Llavero.
enum SecretStore {
    private static var fileURL: URL {
        Storage.shared.baseURL.appendingPathComponent("openai.key")
    }

    static func get() -> String? {
        guard let s = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func set(_ value: String) {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        try? t.write(to: fileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func delete() { try? FileManager.default.removeItem(at: fileURL) }

    static func hasKey() -> Bool { get() != nil }

    static func last4() -> String? {
        guard let k = get(), k.count >= 4 else { return nil }
        return String(k.suffix(4))
    }
}
