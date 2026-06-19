import Foundation

/// Local (offline) conversion of text to Markdown.
enum Markdownify {
    static func fromText(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }

        // URL on its own? → link.
        if t.range(of: "^https?://\\S+$", options: .regularExpression) != nil {
            return "[\(t)](\(t))"
        }
        // Looks like code? → fenced block.
        if looksLikeCode(t) {
            return "```\n\(text)\n```"
        }
        // Normal text → paragraphs separated by a blank line.
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
}

/// Exports the entire history as a Markdown document.
enum MarkdownExporter {
    static func history(_ items: [ClipboardItem]) -> String {
        var out = "# Klip — Historial del portapapeles\n\n"
        let df = DateFormatter()
        df.locale = Locale(identifier: "es")
        df.dateFormat = "yyyy-MM-dd HH:mm"

        for item in items {
            let time = df.string(from: item.createdAt)
            var meta = time
            if item.isRemote == true { meta += " · Otro dispositivo" }
            else if let s = item.sourceName { meta += " · \(s)" }
            if item.isVoiceNote == true { meta += " · 🎙 Nota de voz" }
            out += "## \(meta)\n\n"

            switch item.kind {
            case .text:
                if item.isCredential == true {
                    // Don't export secrets in the clear: masked only.
                    out += "🔑 _Credencial oculta (\(CredentialDetector.masked(item.text ?? "")))_\n\n"
                } else {
                    out += Markdownify.fromText(item.text ?? "") + "\n\n"
                }
            case .image:
                out += "![imagen](images/\(item.imageFileName ?? "imagen.png"))\n\n"
            }
        }
        return out
    }
}
