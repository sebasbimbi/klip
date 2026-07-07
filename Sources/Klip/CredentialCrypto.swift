import Foundation
import CryptoKit
import Security

/// Cifra el texto de credenciales EN REPOSO. La clave AES-256 vive en el Llavero de macOS (protegida por el SO,
/// no solo permisos de archivo), así que items.json — y el .zip de respaldo que lo copia — nunca contienen
/// secretos de credenciales en claro. El cifrado ocurre solo en la frontera de persistencia (Storage.save/loadItems);
/// todo en memoria sigue trabajando con texto plano. El texto cifrado lleva un prefijo de versión para que historiales
/// antiguos en claro migren de forma transparente en el siguiente guardado, y para no tocar nunca texto no-credencial.
enum CredentialCrypto {
    private static let prefix = "klipenc1:"
    private static let keyAccount = "com.proper.klip.credentialKey"

    /// True si la cadena es uno de nuestros tokens sellados (para no sellar dos veces ni intentar descifrar texto plano).
    static func isSealed(_ s: String) -> Bool { s.hasPrefix(prefix) }

    /// Devuelve un token sellado para `plaintext`, o nil si el cifrado no está disponible (el llamador conserva el texto plano).
    static func seal(_ plaintext: String) -> String? {
        guard let key = loadOrCreateKey(),
              let sealed = try? AES.GCM.seal(Data(plaintext.utf8), using: key),
              let combined = sealed.combined else { return nil }
        return prefix + combined.base64EncodedString()
    }

    /// Descifra un token sellado de vuelta a texto plano, o nil si no es nuestro / la clave es de otra máquina.
    static func open(_ token: String) -> String? {
        guard token.hasPrefix(prefix),
              let data = Data(base64Encoded: String(token.dropFirst(prefix.count))),
              let key = loadKey(),
              let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    /// Asegura que la clave de cifrado exista (creándola si falta) SIN devolverla. Llamar FUERA del hilo
    /// principal antes de un guardado que pueda necesitar sellar, para que el SecItemAdd único de la clave no corra en main.
    static func warmKey() { _ = loadOrCreateKey() }

    // MARK: - Clave simétrica guardada en el Llavero

    private static func loadKey() -> SymmetricKey? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyAccount,
            kSecReturnData as String: true,
            // NUNCA mostrar un prompt bloqueante del Llavero. Esta lectura corre durante el arranque (loadItems
            // en el hilo principal). Si la identidad de firma cambió (p. ej. un rebuild ad-hoc), el ACL del ítem
            // ya no confía en nosotros y el comportamiento POR DEFECTO es un diálogo modal "Klip wants to use your
            // keychain" que ATASCA toda la app antes de que llegue a correr (sin barra de menús, sin poll, sin
            // captura). Mejor fallar rápido: open() devuelve entonces nil, el token sellado se conserva, y el
            // descifrado se reanuda cuando vuelva una identidad de confianza (un certificado de firma estable).
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return SymmetricKey(data: data)
    }

    /// Serializa loadKey()+SecItemAdd para que un warmKey() concurrente (fuera de main) y saveItems→seal (main)
    /// no puedan generar ambos una clave y competir por el insert (que si no podría divergir o dar errSecDuplicateItem).
    private static let keyLock = NSLock()

    private static func loadOrCreateKey() -> SymmetricKey? {
        keyLock.lock(); defer { keyLock.unlock() }
        if let k = loadKey() { return k }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data(Array($0)) }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyAccount,
            kSecValueData as String: data,
            // ThisDeviceOnly: disponible para el poll en segundo plano, pero NO se copia a respaldos del
            // dispositivo/iCloud — así la clave no puede viajar a otro Mac y descifrar allí un items.json exportado.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecSuccess { return key }
        return loadKey()   // errSecDuplicateItem (otro camino ganó la carrera) o transitorio → usar lo almacenado
    }
}
