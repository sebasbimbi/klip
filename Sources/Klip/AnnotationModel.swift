import AppKit

/// Drawing tools for the snapshot editor (parity with Lightshot).
enum SnapTool: String, CaseIterable {
    case pencil, line, arrow, rectangle, ellipse, marker, text

    /// Our own SF Symbol (we don't use Lightshot's assets — they're Skillbrains' IP).
    var symbol: String {
        switch self {
        case .pencil:    return "pencil.tip"
        case .line:      return "line.diagonal"
        case .arrow:     return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse:   return "circle"
        case .marker:    return "highlighter"
        case .text:      return "textformat"
        }
    }

    var tooltip: String {
        switch self {
        case .pencil:    return L10n.t("tool.pencil")
        case .line:      return L10n.t("tool.line")
        case .arrow:     return L10n.t("tool.arrow")
        case .rectangle: return L10n.t("tool.rect")
        case .ellipse:   return L10n.t("tool.ellipse")
        case .marker:    return L10n.t("tool.marker")
        case .text:      return L10n.t("tool.text")
        }
    }
}

/// A drawable annotation. `points` holds the freehand stroke (pencil/marker); shapes use the
/// first and last point; text stores its string and its origin.
struct Annotation {
    var id = UUID()
    var tool: SnapTool
    var color: NSColor
    var lineWidth: CGFloat
    var points: [CGPoint]
    var text: String?
    var fontSize: CGFloat = 20   // only for .text

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? .zero }

    var textFont: NSFont { NSFont.systemFont(ofSize: fontSize, weight: .semibold) }

    /// Rectangle occupied by the text (for selection/hit-testing/moving). nil if not text.
    func textBounds() -> CGRect? {
        guard tool == .text, let text, !text.isEmpty else { return nil }
        let size = (text as NSString).size(withAttributes: [.font: textFont])
        let o = points.first ?? .zero
        return CGRect(x: o.x, y: o.y, width: size.width, height: size.height)
    }

    /// Draws the annotation in the current context (view coordinates, not flipped).
    func draw() {
        color.set()
        switch tool {
        case .pencil:
            strokePath(points, width: lineWidth)
        case .marker:
            color.withAlphaComponent(0.35).set()
            strokePath(points, width: max(lineWidth * 4, 14), round: true)
        case .line:
            let p = NSBezierPath(); p.move(to: start); p.line(to: end)
            p.lineWidth = lineWidth; p.lineCapStyle = .round; p.stroke()
        case .arrow:
            drawArrow(from: start, to: end, width: lineWidth)
        case .rectangle:
            let r = NSBezierPath(rect: rect(start, end)); r.lineWidth = lineWidth; r.stroke()
        case .ellipse:
            let e = NSBezierPath(ovalIn: rect(start, end)); e.lineWidth = lineWidth; e.stroke()
        case .text:
            guard let text, !text.isEmpty else { return }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: color
            ]
            (text as NSString).draw(at: start, withAttributes: attrs)
        }
    }

    private func strokePath(_ pts: [CGPoint], width: CGFloat, round: Bool = false) {
        guard pts.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = round ? .square : .round   // marker: square cap (highlighter stroke)
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.line(to: p) }
        path.stroke()
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private func drawArrow(from a: CGPoint, to b: CGPoint, width: CGFloat) {
        // `a` = where you press, `b` = where you release → the tip points at `b`. A FILLED triangle head
        // makes it unmistakable which end is the point.
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head = max(14, width * 4.5)
        // Stop the shaft at the base of the head so the line doesn't poke through the filled tip.
        let base = CGPoint(x: b.x - cos(angle) * head, y: b.y - sin(angle) * head)
        let shaft = NSBezierPath(); shaft.move(to: a); shaft.line(to: base)
        shaft.lineWidth = width; shaft.lineCapStyle = .round; shaft.stroke()
        let w1 = CGPoint(x: b.x + cos(angle + .pi - .pi / 7) * head, y: b.y + sin(angle + .pi - .pi / 7) * head)
        let w2 = CGPoint(x: b.x + cos(angle + .pi + .pi / 7) * head, y: b.y + sin(angle + .pi + .pi / 7) * head)
        let tri = NSBezierPath(); tri.move(to: b); tri.line(to: w1); tri.line(to: w2); tri.close()
        tri.fill()
    }
}
