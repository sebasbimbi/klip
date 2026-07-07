import AppKit

/// Convierte texto enriquecido del portapapeles (RTF/HTML, p. ej. una respuesta de chat IA en tema oscuro) en
/// Markdown LIMPIO: negrita → **…**, cursiva → *…*, los emojis se conservan tal cual, y colores, fondo y fuentes
/// se descartan. Es lo que guarda "pegar siempre limpio": el clip pega sin arrastrar estilos pero conserva negrita/cursiva.
enum RichText {
    /// Markdown limpio para el texto enriquecido del portapapeles, o nil si no trae texto enriquecido usable.
    static func cleanMarkdown(from pb: NSPasteboard) -> String? {
        // Parsear texto enriquecido corre síncrono en el hilo de captura (poll/main); un blob de varios MB puede
        // tardar segundos y congelar la UI. Limitarlo — por encima del límite, caer al string plano al instante.
        let limit = 256_000
        let rtf = pb.data(forType: .rtf) ?? pb.data(forType: NSPasteboard.PasteboardType("public.rtf"))
        if let rtf, rtf.count < limit, let attr = try? NSAttributedString(
            data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return markdown(from: attr)
        }
        if let html = pb.data(forType: .html), html.count < limit, let attr = try? NSAttributedString(
            data: html, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
            return markdown(from: attr)
        }
        return nil
    }

    private struct Span { var text: String; var bold: Bool; var italic: Bool }

    private static func markdown(from attr: NSAttributedString) -> String {
        let ns = attr.string as NSString
        guard ns.length > 0 else { return "" }
        // Fusionar caracteres consecutivos que comparten el mismo (negrita, cursiva), ignorando color/fondo/fuente,
        // para que runs adyacentes no produzcan marcadores duplicados como **a****b**.
        var spans: [Span] = []
        attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length), options: []) { value, range, _ in
            var bold = false, italic = false
            if let font = value as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                bold = traits.contains(.bold)
                italic = traits.contains(.italic)
            }
            // Cortar sobre el String (seguro a nivel de grafema) para que un borde de run no parta el par sustituto de un emoji.
            let text = Range(range, in: attr.string).map { String(attr.string[$0]) } ?? ns.substring(with: range)
            if var last = spans.last, last.bold == bold, last.italic == italic {
                last.text += text; spans[spans.count - 1] = last
            } else {
                spans.append(Span(text: text, bold: bold, italic: italic))
            }
        }
        var out = ""
        for s in spans {
            let trimmed = s.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, s.bold || s.italic else { out += s.text; continue }
            // Mantener los espacios circundantes FUERA de los marcadores (WhatsApp/Markdown ignoran "* x *").
            let lead = String(s.text.prefix(while: { $0 == " " }))
            let trail = String(s.text.reversed().prefix(while: { $0 == " " }).reversed())
            let marker = s.bold && s.italic ? "***" : (s.bold ? "**" : "*")
            out += lead + marker + trimmed + marker + trail
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
