import AppKit

/// Turns rich clipboard text (RTF/HTML, e.g. an AI chat answer on a dark theme) into CLEAN Markdown:
/// bold → **…**, italic → *…*, emojis kept as-is, while colors, background and fonts are dropped. This is
/// what "always paste clean" stores, so a clip pastes without dragging styling but keeps its bold/italic.
enum RichText {
    /// Clean Markdown for the pasteboard's rich text, or nil if it carries no usable rich text.
    static func cleanMarkdown(from pb: NSPasteboard) -> String? {
        let rtf = pb.data(forType: .rtf)
            ?? pb.data(forType: NSPasteboard.PasteboardType("public.rtf"))
        if let rtf, let attr = try? NSAttributedString(
            data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return markdown(from: attr)
        }
        if let html = pb.data(forType: .html), let attr = try? NSAttributedString(
            data: html, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
            return markdown(from: attr)
        }
        return nil
    }

    private struct Span { var text: String; var bold: Bool; var italic: Bool }

    private static func markdown(from attr: NSAttributedString) -> String {
        let ns = attr.string as NSString
        guard ns.length > 0 else { return "" }
        // Merge consecutive characters that share the same (bold, italic), ignoring colour/background/font,
        // so adjacent runs don't produce doubled markers like **a****b**.
        var spans: [Span] = []
        attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length), options: []) { value, range, _ in
            var bold = false, italic = false
            if let font = value as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                bold = traits.contains(.bold)
                italic = traits.contains(.italic)
            }
            let text = ns.substring(with: range)
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
            // Keep surrounding spaces OUTSIDE the markers (WhatsApp/Markdown ignore "* x *").
            let lead = String(s.text.prefix(while: { $0 == " " }))
            let trail = String(s.text.reversed().prefix(while: { $0 == " " }).reversed())
            let marker = s.bold && s.italic ? "***" : (s.bold ? "**" : "*")
            out += lead + marker + trimmed + marker + trail
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
