import Foundation

/// Detecta si un texto parece una credencial (API key, token, secreto) para el mini gestor.
enum CredentialDetector {
    private static let patterns: [String] = [
        "sk-[A-Za-z0-9_-]{20,}",                              // OpenAI
        "ghp_[A-Za-z0-9]{20,}", "github_pat_[A-Za-z0-9_]{20,}", "gho_[A-Za-z0-9]{20,}", // GitHub
        "xox[baprs]-[A-Za-z0-9-]{10,}",                        // Slack
        "AKIA[0-9A-Z]{16}",                                    // AWS
        "AIza[0-9A-Za-z_-]{30,}",                              // Google API
        "ya29\\.[0-9A-Za-z_-]+",                               // Google OAuth
        "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{6,}", // JWT
        "(sk|rk|pk)_(live|test)_[A-Za-z0-9]{16,}", "whsec_[A-Za-z0-9]{16,}",  // Stripe
        "SG\\.[A-Za-z0-9_-]{16,}\\.[A-Za-z0-9_-]{16,}",        // SendGrid
        "SK[0-9a-fA-F]{32}", "AC[0-9a-fA-F]{32}",              // Twilio
        "(?i)npm_[A-Za-z0-9]{20,}",                            // token de npm
        "glpat-[A-Za-z0-9_-]{20,}",                            // PAT de GitLab
        "-----BEGIN [A-Z ]*PRIVATE KEY-----",                  // clave privada PEM
        "hf_[A-Za-z0-9]{20,}",                                 // Hugging Face
        "(?i)bearer\\s+[A-Za-z0-9._-]{20,}",                   // token Bearer
        "(?i)[a-z][a-z0-9+.-]*://[^\\s:/@]+:[^\\s:/@]{6,}@",    // credenciales incrustadas en una URL: scheme://user:pass@host (postgres/mongodb/redis/https…)
        "(?i)AccountKey=[A-Za-z0-9+/]{40,}={0,2}",             // cadena de conexión de Azure Storage
        "(?i)(api[_-]?key|secret|access[_-]?token|password|token)\\s*[:=]\\s*\"?[A-Za-z0-9._\\-+/]{12,}"
    ]

    static func looksLikeCredential(_ text: String) -> Bool {
        matchedSecret(in: text) != nil
    }

    /// Subconjunto más estricto, de PREFIJO INEQUÍVOCO, usado SOLO para la promoción silenciosa en reposo al cargar
    /// (Storage.decryptCredentials). El `sk-…` laxo (que coincide con kebab/CSS como `sk-modal-overlay-backdrop`) y
    /// los patrones propensos a prosa `key:value` / `bearer …` quedan deliberadamente EXCLUIDOS aquí, para que cargar
    /// el historial nunca cifre+oculte en silencio un clip ordinario. La captura en vivo sigue usando el
    /// `looksLikeCredential` más amplio (donde un falso positivo es visible y se deshace con un clic).
    private static let strongPatterns: [String] = [
        "sk-(proj|svcacct|admin|ant)-[A-Za-z0-9_-]{20,}",      // claves estructuradas de OpenAI/Anthropic
        "sk-[A-Za-z0-9]{40,}",                                 // clave legacy sin prefijo: tira larga puramente alfanumérica (el kebab no puede)
        "ghp_[A-Za-z0-9]{20,}", "github_pat_[A-Za-z0-9_]{20,}", "gho_[A-Za-z0-9]{20,}",
        "xox[baprs]-[A-Za-z0-9-]{10,}",
        "AKIA[0-9A-Z]{16}",
        "AIza[0-9A-Za-z_-]{30,}", "ya29\\.[0-9A-Za-z_-]+",
        "(sk|rk|pk)_(live|test)_[A-Za-z0-9]{16,}", "whsec_[A-Za-z0-9]{16,}",
        "SG\\.[A-Za-z0-9_-]{16,}\\.[A-Za-z0-9_-]{16,}",
        "SK[0-9a-fA-F]{32}", "AC[0-9a-fA-F]{32}",
        "(?i)npm_[A-Za-z0-9]{20,}", "glpat-[A-Za-z0-9_-]{20,}", "hf_[A-Za-z0-9]{20,}",
        "-----BEGIN [A-Z ]*PRIVATE KEY-----",
        "eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{6,}",   // JWT
    ]

    /// True solo ante un secreto estructurado de alta confianza — seguro para la promoción silenciosa en reposo (ver arriba).
    static func looksLikeHighConfidenceCredential(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 16, t.count <= 20_000 else { return false }
        for line in t.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.count >= 16 else { continue }
            for p in strongPatterns where s.range(of: p, options: .regularExpression) != nil { return true }
        }
        return false
    }

    /// La subcadena que coincidió con un patrón de secreto, o nil. Escanea LÍNEA POR LÍNEA para que un secreto
    /// dentro de un blob multilínea más grande (p. ej. un .env pegado, un bloque de config o un mensaje de chat con un token)
    /// igual se detecte — la regla anterior `(newline && >=200 chars) → no es credencial` los dejaba pasar
    /// y los mostraba en texto claro. Solo queda un tope superior de bytes, puramente por rendimiento.
    static func matchedSecret(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 12, t.count <= 20_000 else { return nil }
        for line in t.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.count >= 12 else { continue }
            for p in patterns {
                if let r = s.range(of: p, options: .regularExpression) { return String(s[r]) }
            }
        }
        return nil
    }

    /// Un placeholder constante SIN caracteres derivados del secreto. Se usa para todo lo PERSISTIDO (el preview
    /// en disco, backups) para que la pista de los últimos 4 de `masked` nunca acabe en items.json / el .zip.
    static let maskedPlaceholder = "🔑 ••••••"

    /// Versión enmascarada para mostrar sin revelar el secreto. Para blobs multilínea nunca hacemos eco del
    /// contenido (enmascarar solo la cola ocultaría una línea final inocua, no el secreto).
    static func masked(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.contains("\n") { return "🔑 ••••••" }
        guard t.count > 4 else { return "••••" }
        return "••••" + String(t.suffix(4))
    }
}
