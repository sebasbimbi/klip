import AppKit

/// Editor canvas: draws the base capture and the annotations on top. Handles live drawing,
/// in-place text (a temporary NSTextField — supports accents), and for text: selecting, moving,
/// re-editing, and resizing. Flattens everything to a full-resolution image.
final class AnnotationCanvasView: NSView {
    private let baseImage: NSImage
    private(set) var annotations: [Annotation] = []
    private var draft: Annotation?

    // In-place text / selection.
    private var activeTextField: NSTextField?
    private var editingID: UUID?              // text annotation currently being re-edited
    private var editFontSize: CGFloat = 20
    private var editColor: NSColor = .systemRed
    private(set) var selectedTextID: UUID?    // selected text (highlighted box)
    private var movingTextID: UUID?           // text currently being dragged
    private var moveOffset = CGSize.zero
    private var movedDuringDrag = false
    /// Full-state undo snapshots: add / move / edit / recolor / resize / delete are all reversible.
    private var undoStack: [[Annotation]] = []
    private var preMoveSnapshot: [Annotation]?
    /// Fired when in-place text editing starts (true) / ends (false), so the editor can disable its
    /// ⌘C/⌘Z/⌘S/Esc key equivalents while the user types into the field (otherwise they hijack editing).
    var onTextEditingChanged: ((Bool) -> Void)?

    var currentTool: SnapTool = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 3
    var currentFontSize: CGFloat = 20

    /// Notifies selection changes (so the toolbar reflects the size of the selected text).
    var onSelectionChange: (() -> Void)?

    init(image: NSImage) {
        self.baseImage = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        // The text being re-edited is hidden from the canvas (the NSTextField on top shows it);
        // that way an Undo/cancel during re-editing restores the original instead of losing it.
        for a in annotations where a.id != editingID { a.draw() }
        draft?.draw()
        drawSelectionHighlight()
    }

    private func drawSelectionHighlight() {
        guard let id = selectedTextID,
              let ann = annotations.first(where: { $0.id == id }),
              let box = ann.textBounds()?.insetBy(dx: -4, dy: -4) else { return }
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: box)
        path.lineWidth = 1
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if currentTool == .text {
            commitActiveText()
            // Click on an existing text? (top to bottom)
            if let idx = annotations.lastIndex(where: {
                $0.tool == .text && ($0.textBounds()?.insetBy(dx: -6, dy: -6).contains(p) ?? false)
            }) {
                let ann = annotations[idx]
                if event.clickCount >= 2 {
                    // Double click → re-edit. It is NOT removed from the array: it's hidden via
                    // editingID while editing (draw skips it), so an Undo/cancel restores the original text.
                    editingID = ann.id
                    selectedTextID = nil
                    beginTextEditing(at: ann.start, existing: ann)
                } else {
                    // Single click → select and prepare to drag.
                    selectedTextID = ann.id
                    movingTextID = ann.id
                    moveOffset = CGSize(width: p.x - ann.start.x, height: p.y - ann.start.y)
                    preMoveSnapshot = annotations   // snapshot in case the drag moves it (undoable)
                    movedDuringDrag = false
                    onSelectionChange?()
                }
                needsDisplay = true
                return
            }
            // Empty space → new text.
            selectedTextID = nil
            onSelectionChange?()   // with no text selected, the toolbar reflects the current color/size
            beginTextEditing(at: p, existing: nil)
            needsDisplay = true
            return
        }

        // Drawing tools.
        selectedTextID = nil
        onSelectionChange?()
        commitActiveText()
        draft = Annotation(tool: currentTool, color: currentColor,
                           lineWidth: currentLineWidth, points: [p], text: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        // Move a selected text.
        if let movingID = movingTextID, let idx = annotations.firstIndex(where: { $0.id == movingID }) {
            annotations[idx].points = [CGPoint(x: p.x - moveOffset.width, y: p.y - moveOffset.height)]
            movedDuringDrag = true
            needsDisplay = true
            return
        }

        guard var d = draft else { return }
        if d.tool == .pencil || d.tool == .marker {
            d.points.append(p)
        } else {
            d.points = [d.points.first ?? p, p]
        }
        draft = d
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if movingTextID != nil {
            if movedDuringDrag, let snap = preMoveSnapshot { pushUndo(snap) }   // record the move for undo
            movingTextID = nil; preMoveSnapshot = nil; movedDuringDrag = false
            return
        }
        guard let d = draft else { return }
        draft = nil
        // Require an actual stroke: a no-drag click (count == 1) must not create an invisible annotation
        // that silently consumes an Undo press.
        if d.points.count > 1 {
            pushUndo()
            annotations.append(d)
        }
        needsDisplay = true
    }

    // MARK: - In-place text

    private func beginTextEditing(at point: NSPoint, existing: Annotation?) {
        let fontSize = existing?.fontSize ?? currentFontSize
        let color = existing?.color ?? currentColor
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let lineHeight = font.ascender - font.descender
        let fieldHeight = max(24, lineHeight + 8)
        // Position the field so that, on commit, the drawn text lands at `point`.
        let field = NSTextField(frame: NSRect(x: point.x - 4,
                                              y: point.y - (fieldHeight - lineHeight) / 2,
                                              width: 260, height: fieldHeight))
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.backgroundColor = .white.withAlphaComponent(0.92)
        field.font = font
        field.textColor = color
        field.focusRingType = .none
        field.placeholderString = L10n.t("editor.text.placeholder")
        field.stringValue = existing?.text ?? ""
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
        editFontSize = fontSize
        editColor = color
        onTextEditingChanged?(true)   // let the toolbar release ⌘C/⌘Z/⌘S/Esc while typing
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) { commitActiveText() }

    private func commitActiveText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let frame = field.frame
        let font = field.font ?? NSFont.systemFont(ofSize: editFontSize, weight: .semibold)
        let id = editingID
        activeTextField = nil
        editingID = nil
        field.removeFromSuperview()
        onTextEditingChanged?(false)   // restore the toolbar key equivalents
        // Record undo only if this commit actually changes the annotations (new text, or re-edit).
        if !text.isEmpty || id != nil { pushUndo() }
        // If a text was being re-edited, remove the original: we replace it below, or (if it ended up
        // empty) we delete it by committing empty.
        if let id { annotations.removeAll { $0.id == id } }
        guard !text.isEmpty else { needsDisplay = true; return }
        let lineHeight = font.ascender - font.descender
        let drawY = frame.minY + (frame.height - lineHeight) / 2
        let origin = CGPoint(x: frame.minX + 4, y: drawY)
        var ann = Annotation(tool: .text, color: editColor, lineWidth: currentLineWidth,
                             points: [origin], text: text, fontSize: editFontSize)
        if let id { ann.id = id }   // preserves identity when re-editing
        annotations.append(ann)
        selectedTextID = ann.id
        onSelectionChange?()
        needsDisplay = true
    }

    // MARK: - Font size

    /// Effective size to show in the toolbar: that of the selected text, or the current one.
    var effectiveFontSize: CGFloat {
        if let id = selectedTextID, let a = annotations.first(where: { $0.id == id }) { return a.fontSize }
        return currentFontSize
    }

    /// Effective color to reflect in the toolbar: that of the selected text, or the current one.
    var effectiveColor: NSColor {
        if let id = selectedTextID, let a = annotations.first(where: { $0.id == id }) { return a.color }
        return currentColor
    }

    /// Applies a new size: to the selected text (if any) and as the default size for the next one.
    func setFontSize(_ size: CGFloat) {
        let clamped = max(10, min(120, size))
        currentFontSize = clamped
        if let field = activeTextField {
            field.font = NSFont.systemFont(ofSize: clamped, weight: .semibold)
            editFontSize = clamped
        }
        if let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            pushUndo()
            annotations[idx].fontSize = clamped
        }
        needsDisplay = true
    }

    func bumpFontSize(_ delta: CGFloat) { setFontSize(effectiveFontSize + delta) }

    /// Sets the current color and, if there is selected or being-edited text, recolors it.
    /// Use for explicit user color actions (tapping a swatch / the color panel).
    func setColor(_ color: NSColor) {
        currentColor = color
        if let field = activeTextField { field.textColor = color; editColor = color }
        if let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            pushUndo()
            annotations[idx].color = color
        }
        needsDisplay = true
    }

    /// Sets the default color for FUTURE strokes only — never recolors a committed selected annotation.
    /// Used on tool switches so changing tools doesn't silently rewrite an existing text's color.
    func setDefaultColor(_ color: NSColor) {
        currentColor = color
        if let field = activeTextField { field.textColor = color; editColor = color }
        needsDisplay = true
    }

    // MARK: - Actions

    private func pushUndo(_ snapshot: [Annotation]? = nil) {
        undoStack.append(snapshot ?? annotations)
        if undoStack.count > 50 { undoStack.removeFirst() }   // bound memory
    }

    func undo() {
        // If text is being edited, cancel the edit first: the original stays in the array (hidden by
        // editingID) and reappears once editingID is cleared. The re-edited text is not lost.
        if activeTextField != nil {
            activeTextField?.removeFromSuperview(); activeTextField = nil; editingID = nil
            onTextEditingChanged?(false)
            needsDisplay = true
            return
        }
        // Restore the last snapshot — reverses ANY operation (add/move/edit/recolor/resize/delete),
        // not just the most-recently-added annotation.
        guard let prev = undoStack.popLast() else { return }
        annotations = prev
        selectedTextID = nil
        onSelectionChange?()
        needsDisplay = true
    }

    /// Deletes the currently selected text annotation (Delete / Backspace), undoably.
    override func keyDown(with event: NSEvent) {
        let isDelete = event.keyCode == 51 || event.keyCode == 117   // Backspace / Forward-Delete
        if isDelete, activeTextField == nil, let id = selectedTextID,
           annotations.contains(where: { $0.id == id }) {
            pushUndo()
            annotations.removeAll { $0.id == id }
            selectedTextID = nil
            onSelectionChange?()
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }

    /// Flattens base + annotations into an NSImage at full pixel resolution (Retina).
    func flattened() -> NSImage {
        commitActiveText()
        let savedSelection = selectedTextID
        selectedTextID = nil   // don't rasterize the selection box
        defer { selectedTextID = savedSelection }

        let pxW = baseImage.representations.first?.pixelsWide ?? Int(bounds.width)
        let pxH = baseImage.representations.first?.pixelsHigh ?? Int(bounds.height)
        // Rasterize in the base image's OWN color space. Using a generic `.deviceRGB` bitmap rep would
        // strip a Display P3 (wide-gamut) profile and produce a washed-out PNG on capable displays; a
        // CGContext in `baseCG.colorSpace` preserves the colors the user actually saw.
        let baseCG = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let colorSpace = baseCG?.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        if pxW > 0, pxH > 0, bounds.width > 0, bounds.height > 0, let colorSpace,
           let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8,
                               bytesPerRow: 0, space: colorSpace,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.scaleBy(x: CGFloat(pxW) / bounds.width, y: CGFloat(pxH) / bounds.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
            for a in annotations { a.draw() }
            NSGraphicsContext.restoreGraphicsState()
            if let outCG = ctx.makeImage() {
                let rep = NSBitmapImageRep(cgImage: outCG)
                rep.size = bounds.size
                let out = NSImage(size: bounds.size)
                out.addRepresentation(rep)
                return out
            }
        }

        // Fallback (couldn't create the pixel-resolution bitmap): rasterize at point size
        // BUT including the annotations. Never return the clean base: it would lose the user's work.
        let out = NSImage(size: bounds.size)
        out.lockFocus()
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        for a in annotations { a.draw() }
        out.unlockFocus()
        return out
    }
}
