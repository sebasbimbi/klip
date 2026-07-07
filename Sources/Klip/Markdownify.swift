import Foundation

/// Conversión local (offline) de texto a Markdown.
enum Markdownify {

    private static func rx(_ s: String, _ pattern: String, _ template: String) -> String {
        s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    /// Reformatea Markdown/texto enriquecido (p. ej. una respuesta de chat de IA) al markup propio de WhatsApp para
    /// que se pegue limpio: *negrita*, _cursiva_, ~tachado~, • viñetas; los encabezados pasan a negrita; los enlaces
    /// pasan a "texto (url)". El clip ya es texto plano de entrada, así que cualquier fondo oscuro / estilo rico se descarta solo.
    static func toWhatsApp(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
        s = s.replacingOccurrences(of: "\u{1}", with: "")            // quita cualquier SOH literal para que nuestro placeholder de negrita sea inequívoco
        s = rx(s, "(?m)^[ \\t]*[-*+][ \\t]+", "• ")                   // viñetas PRIMERO → el * al inicio de línea no se ve como cursiva
        s = rx(s, "(?m)^#{1,6}[ \\t]+(.+)$", "\u{1}$1\u{1}")         // encabezados → negrita (placeholder, protegido de la cursiva)
        s = rx(s, "\\*\\*\\*(.+?)\\*\\*\\*", "_\u{1}$1\u{1}_")       // ***negrita-cursiva*** → _*x*_ (anidado)
        s = rx(s, "\\*\\*(.+?)\\*\\*", "\u{1}$1\u{1}")               // **negrita** → placeholder
        s = rx(s, "__(.+?)__", "\u{1}$1\u{1}")                        // __negrita__ → placeholder
        s = rx(s, "(?<![\\*\\w])\\*(\\S(?:.*?\\S)?)\\*(?![\\*\\w])", "_$1_")  // *cursiva* → _cursiva_ (contenido sin espacios en los bordes)
        s = s.replacingOccurrences(of: "\u{1}", with: "*")           // restaura negrita → *negrita*
        s = rx(s, "~~(.+?)~~", "~$1~")                                // ~~tachado~~ → ~tachado~
        s = rx(s, "`([^`\\n]+)`", "$1")                               // `código` inline → código (sin mono inline)
        if s.count < 20_000 { s = rx(s, "\\[(.+?)\\]\\((.+?)\\)", "$1 ($2)") }   // enlaces (acotado: evita backtracking)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reformatea Markdown/texto enriquecido a texto plano limpio para el cuerpo de un email: quita los símbolos de
    /// Markdown, conserva estructura legible (viñetas, enlaces "texto (url)"), elimina los fences de código. La app de email pone su propio estilo.
    static func toEmail(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "\r\n", with: "\n")
        s = rx(s, "(?m)^[ \\t]*[-*+][ \\t]+", "• ")                   // viñetas PRIMERO → el * al inicio de línea no se ve como cursiva
        s = rx(s, "(?m)^#{1,6}[ \\t]+", "")                           // encabezados → línea normal
        s = rx(s, "\\*\\*\\*(.+?)\\*\\*\\*", "$1")                    // ***negrita-cursiva***
        s = rx(s, "\\*\\*(.+?)\\*\\*", "$1")                          // **negrita**
        s = rx(s, "__(.+?)__", "$1")                                  // __negrita__
        s = rx(s, "(?<![\\*\\w])\\*(\\S(?:.*?\\S)?)\\*(?![\\*\\w])", "$1")  // *cursiva* (contenido sin espacios en los bordes)
        s = rx(s, "(?<![_\\w])_(\\S(?:.*?\\S)?)_(?![_\\w])", "$1")    // _cursiva_
        s = rx(s, "~~(.+?)~~", "$1")                                  // ~~tachado~~
        s = rx(s, "(?m)^```[a-zA-Z0-9]*\\n?", "")                     // fences de código ```lang
        s = rx(s, "`([^`\\n]+)`", "$1")                               // `código` inline
        if s.count < 20_000 { s = rx(s, "\\[(.+?)\\]\\((.+?)\\)", "$1 ($2)") }   // enlaces (acotado: evita backtracking)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fromText(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }

        // ¿URL sola? → enlace.
        if t.range(of: "^https?://\\S+$", options: .regularExpression) != nil {
            return "[\(t)](\(t))"
        }
        // ¿Parece código? → bloque con fences (con etiqueta de lenguaje best-effort).
        if looksLikeCode(t) {
            return "```\(inferCodeLanguage(t))\n\(text)\n```"
        }
        // Texto normal → párrafos separados por una línea en blanco.
        let paras = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return paras.joined(separator: "\n\n")
    }

    static func looksLikeCode(_ s: String) -> Bool {
        let keywords = ["func ", "var ", "let ", "import ", "class ", "struct ",
                        "def ", "function ", "const ", "#include", "public ", "private ",
                        "=>", "</", "/>", "});"]
        if keywords.contains(where: { s.contains($0) }) { return true }
        let codeChars = Set("{};=<>()[]")
        let symbolCount = s.filter { codeChars.contains($0) }.count
        return s.count > 0 && Double(symbolCount) / Double(s.count) > 0.06
    }

    /// Etiqueta de lenguaje best-effort para un bloque de código con fences (heurísticas baratas). Devuelve "" ante la duda —
    /// una etiqueta errónea/vacía se renderiza bien igualmente, solo ayuda a la IA/editor a resaltar cuando hay confianza.
    static func inferCodeLanguage(_ s: String) -> String {
        // Inspecciona solo un prefijo: el lenguaje se detecta desde el inicio, y esto acota el trabajo del regex
        // (la alternativa SELECT…FROM usa [\s\S]+, que podría hacer backtracking con un blob pegado enorme).
        let t = String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        let lower = t.lowercased()
        if (t.hasPrefix("{") || t.hasPrefix("[")), t.contains("\""), t.contains(":") { return "json" }
        if t.hasPrefix("#!"), lower.contains("sh") { return "bash" }
        // Palabras clave ancladas al inicio de línea para que una palabra en prosa ("git is great") no dispare una etiqueta.
        if t.range(of: "(?m)^\\s*(\\$ |sudo |npm |yarn |pnpm |brew |curl |cd |git (clone|pull|push|commit|checkout|switch|status|add|rebase|merge|log|diff|branch|stash|fetch|reset|init|remote|tag) )", options: .regularExpression) != nil { return "bash" }
        if t.hasPrefix("<") { return (lower.contains("<!doctype html") || lower.contains("<html")) ? "html" : "xml" }
        // SQL solo cuando las palabras clave en MAYÚSCULAS van en pareja (SELECT…FROM), para que la prosa "select the file from…" no haga match.
        if t.range(of: "\\b(SELECT\\b[\\s\\S]+\\bFROM\\b|INSERT INTO\\b|UPDATE\\b[\\s\\S]+\\bSET\\b|DELETE FROM\\b|CREATE TABLE\\b)", options: .regularExpression) != nil { return "sql" }
        if t.contains("func ") || t.range(of: "@(MainActor|objc|State|Published|IBOutlet|escaping)", options: .regularExpression) != nil
            || t.range(of: "(?m)^\\s*(import \\w+$|guard .+ else \\{)", options: .regularExpression) != nil { return "swift" }
        if t.range(of: "(?m)^\\s*(def |class \\w+.*:|from \\w[\\w.]* import |import \\w)", options: .regularExpression) != nil { return "python" }
        if t.range(of: "=>", options: .regularExpression) != nil
            || t.range(of: "(?m)^\\s*(function |const |let |var |export )", options: .regularExpression) != nil
            || t.contains("require(") { return "javascript" }
        return ""
    }
}

/// Exporta todo el historial como un documento Markdown.
enum MarkdownExporter {
    static func history(_ items: [ClipboardItem]) -> String {
        var out = "# \(L10n.t("export.doc.title"))\n\n"
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "yyyy-MM-dd HH:mm"

        for item in items {
            let time = df.string(from: item.createdAt)
            var meta = time
            if item.isRemote == true { meta += " · \(L10n.t("export.otherDevice"))" }
            else if let s = item.sourceName { meta += " · \(s)" }
            if item.isVoiceNote == true { meta += " · 🎙 \(L10n.t("export.voiceNote"))" }
            out += "## \(meta)\n\n"

            switch item.kind {
            case .text:
                if item.isCredential == true {
                    // No exportar secretos en claro, y tampoco filtrar los últimos 4 reales: placeholder constante.
                    out += "🔑 _\(String(format: L10n.t("export.credentialHidden"), CredentialDetector.maskedPlaceholder))_\n\n"
                } else {
                    out += Markdownify.fromText(item.text ?? "") + "\n\n"
                }
            case .image:
                out += "![image](images/\(item.imageFileName ?? "image.png"))\n\n"
            }
        }
        return out
    }
}
