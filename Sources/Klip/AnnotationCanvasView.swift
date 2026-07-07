import AppKit

/// Lienzo del editor: dibuja la captura base y las anotaciones encima. Gestiona el dibujo en vivo,
/// texto in situ (un NSTextField temporal — soporta tildes) y, para texto: seleccionar, mover,
/// reeditar y redimensionar. Aplana todo a una imagen a resolución completa.
final class AnnotationCanvasView: NSView {
    private let baseImage: NSImage
    private(set) var annotations: [Annotation] = []
    private var draft: Annotation?

    // Texto in situ / selección.
    private var activeTextField: NSTextField?
    private var editingID: UUID?              // anotación de texto en reedición
    private var editFontSize: CGFloat = 20
    private var editColor: NSColor = .systemRed
    private(set) var selectedTextID: UUID?    // texto seleccionado (caja resaltada)
    private var movingTextID: UUID?           // texto que se está arrastrando
    private var moveOffset = CGSize.zero
    private var movedDuringDrag = false
    /// Instantáneas de undo con estado completo: añadir / mover / editar / recolorear / redimensionar / borrar son reversibles.
    private var undoStack: [[Annotation]] = []
    private var preMoveSnapshot: [Annotation]?
    /// Se dispara cuando la edición de texto in situ empieza (true) / termina (false), para que el editor
    /// desactive sus equivalentes ⌘C/⌘Z/⌘S/Esc mientras el usuario escribe en el campo (si no, secuestran la edición).
    var onTextEditingChanged: ((Bool) -> Void)?

    var currentTool: SnapTool = .arrow
    var currentColor: NSColor = .systemRed
    var currentLineWidth: CGFloat = 3
    var currentFontSize: CGFloat = 20

    /// Notifica cambios de selección (para que la barra de herramientas refleje el tamaño del texto seleccionado).
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
        // El texto en reedición se oculta del lienzo (el NSTextField encima lo muestra);
        // así un Undo/cancelar durante la reedición restaura el original en vez de perderlo.
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

    // MARK: - Ratón

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if currentTool == .text {
            commitActiveText()
            // ¿Clic sobre un texto existente? (de arriba hacia abajo)
            if let idx = annotations.lastIndex(where: {
                $0.tool == .text && ($0.textBounds()?.insetBy(dx: -6, dy: -6).contains(p) ?? false)
            }) {
                let ann = annotations[idx]
                if event.clickCount >= 2 {
                    // Doble clic → reeditar. NO se elimina del array: se oculta vía
                    // editingID mientras se edita (draw lo omite), así un Undo/cancelar restaura el texto original.
                    editingID = ann.id
                    selectedTextID = nil
                    beginTextEditing(at: ann.start, existing: ann)
                } else {
                    // Clic simple → seleccionar y preparar el arrastre.
                    selectedTextID = ann.id
                    movingTextID = ann.id
                    moveOffset = CGSize(width: p.x - ann.start.x, height: p.y - ann.start.y)
                    preMoveSnapshot = annotations   // instantánea por si el arrastre lo mueve (deshacible)
                    movedDuringDrag = false
                    onSelectionChange?()
                }
                needsDisplay = true
                return
            }
            // Espacio vacío → texto nuevo.
            selectedTextID = nil
            onSelectionChange?()   // sin texto seleccionado, la barra refleja el color/tamaño actual
            beginTextEditing(at: p, existing: nil)
            needsDisplay = true
            return
        }

        // Herramientas de dibujo.
        selectedTextID = nil
        onSelectionChange?()
        commitActiveText()
        draft = Annotation(tool: currentTool, color: currentColor,
                           lineWidth: currentLineWidth, points: [p], text: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        // Mover un texto seleccionado.
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
            if movedDuringDrag, let snap = preMoveSnapshot { pushUndo(snap) }   // registra el movimiento para undo
            movingTextID = nil; preMoveSnapshot = nil; movedDuringDrag = false
            return
        }
        guard let d = draft else { return }
        draft = nil
        // Exigir un trazo real: un clic sin arrastre (count == 1) no debe crear una anotación invisible
        // que consuma en silencio una pulsación de Undo.
        if d.points.count > 1 {
            pushUndo()
            annotations.append(d)
        }
        needsDisplay = true
    }

    // MARK: - Texto in situ

    private func beginTextEditing(at point: NSPoint, existing: Annotation?) {
        let fontSize = existing?.fontSize ?? currentFontSize
        let color = existing?.color ?? currentColor
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let lineHeight = font.ascender - font.descender
        let fieldHeight = max(24, lineHeight + 8)
        // Posicionar el campo de modo que, al confirmar, el texto dibujado caiga en `point`.
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
        onTextEditingChanged?(true)   // deja que la barra libere ⌘C/⌘Z/⌘S/Esc mientras se escribe
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
        onTextEditingChanged?(false)   // restaura los equivalentes de teclado de la barra
        // Registrar undo solo si este commit cambia realmente las anotaciones (texto nuevo, o reedición).
        if !text.isEmpty || id != nil { pushUndo() }
        // Si se estaba reeditando un texto, eliminar el original: lo reemplazamos abajo, o (si quedó
        // vacío) lo borramos al confirmar vacío.
        if let id { annotations.removeAll { $0.id == id } }
        guard !text.isEmpty else { needsDisplay = true; return }
        let lineHeight = font.ascender - font.descender
        let drawY = frame.minY + (frame.height - lineHeight) / 2
        let origin = CGPoint(x: frame.minX + 4, y: drawY)
        var ann = Annotation(tool: .text, color: editColor, lineWidth: currentLineWidth,
                             points: [origin], text: text, fontSize: editFontSize)
        if let id { ann.id = id }   // conserva la identidad al reeditar
        annotations.append(ann)
        selectedTextID = ann.id
        onSelectionChange?()
        needsDisplay = true
    }

    // MARK: - Tamaño de fuente

    /// Tamaño efectivo a mostrar en la barra de herramientas: el del texto seleccionado, o el actual.
    var effectiveFontSize: CGFloat {
        if let id = selectedTextID, let a = annotations.first(where: { $0.id == id }) { return a.fontSize }
        return currentFontSize
    }

    /// Color efectivo a reflejar en la barra de herramientas: el del texto seleccionado, o el actual.
    var effectiveColor: NSColor {
        if let id = selectedTextID, let a = annotations.first(where: { $0.id == id }) { return a.color }
        return currentColor
    }

    /// Aplica un nuevo tamaño: al texto seleccionado (si lo hay) y como tamaño por defecto para el siguiente.
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

    /// Establece el color actual y, si hay texto seleccionado o en edición, lo recolorea.
    /// Usar para acciones de color explícitas del usuario (tocar una muestra / el panel de color).
    func setColor(_ color: NSColor) {
        currentColor = color
        if let field = activeTextField { field.textColor = color; editColor = color }
        if let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            pushUndo()
            annotations[idx].color = color
        }
        needsDisplay = true
    }

    /// Los arrastres del panel de color disparan de forma continua (isContinuous), así que un setColor normal
    /// por tick inundaría la pila de undo de 50 entradas y borraría el historial real. armColorCoalescing()
    /// se rearma antes de un arrastre; el PRIMER cambio coalescido toma una instantánea, el resto recolorea in situ.
    private var colorCoalescingArmed = false
    func armColorCoalescing() { colorCoalescingArmed = true }

    func setColorCoalesced(_ color: NSColor) {
        if colorCoalescingArmed {
            colorCoalescingArmed = false
            if selectedTextID != nil { pushUndo() }   // una instantánea para todo el arrastre
        }
        currentColor = color
        if let field = activeTextField { field.textColor = color; editColor = color }
        if let id = selectedTextID, let idx = annotations.firstIndex(where: { $0.id == id }) {
            annotations[idx].color = color   // sin pushUndo: ya hay instantánea del inicio del arrastre
        }
        needsDisplay = true
    }

    /// Establece el color por defecto solo para trazos FUTUROS — nunca recolorea una anotación ya confirmada.
    /// Se usa al cambiar de herramienta para no reescribir en silencio el color de un texto existente.
    func setDefaultColor(_ color: NSColor) {
        currentColor = color
        if let field = activeTextField { field.textColor = color; editColor = color }
        needsDisplay = true
    }

    // MARK: - Acciones

    private func pushUndo(_ snapshot: [Annotation]? = nil) {
        undoStack.append(snapshot ?? annotations)
        if undoStack.count > 50 { undoStack.removeFirst() }   // acota la memoria
    }

    func undo() {
        // Si se está editando texto, cancelar la edición primero: el original permanece en el array (oculto
        // por editingID) y reaparece al limpiar editingID. El texto reeditado no se pierde.
        if activeTextField != nil {
            activeTextField?.removeFromSuperview(); activeTextField = nil; editingID = nil
            onTextEditingChanged?(false)
            needsDisplay = true
            return
        }
        // Restaurar la última instantánea — revierte CUALQUIER operación (añadir/mover/editar/recolorear/redimensionar/borrar),
        // no solo la anotación añadida más recientemente.
        guard let prev = undoStack.popLast() else { return }
        annotations = prev
        selectedTextID = nil
        onSelectionChange?()
        needsDisplay = true
    }

    /// Borra la anotación de texto seleccionada (Delete / Backspace), de forma deshacible.
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

    /// Aplana base + anotaciones en un NSImage a resolución completa de píxeles (Retina).
    func flattened() -> NSImage {
        commitActiveText()
        let savedSelection = selectedTextID
        selectedTextID = nil   // no rasterizar la caja de selección
        defer { selectedTextID = savedSelection }

        let pxW = baseImage.representations.first?.pixelsWide ?? Int(bounds.width)
        let pxH = baseImage.representations.first?.pixelsHigh ?? Int(bounds.height)
        // Rasterizar en el espacio de color PROPIO de la imagen base. Un bitmap rep genérico `.deviceRGB`
        // eliminaría un perfil Display P3 (gama amplia) y produciría un PNG deslavado en pantallas capaces; un
        // CGContext en `baseCG.colorSpace` conserva los colores que el usuario vio realmente.
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

        // Fallback (no se pudo crear el bitmap a resolución de píxeles): rasterizar a tamaño en puntos
        // PERO incluyendo las anotaciones. Nunca devolver la base limpia: perdería el trabajo del usuario.
        let out = NSImage(size: bounds.size)
        out.lockFocus()
        baseImage.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        for a in annotations { a.draw() }
        out.unlockFocus()
        return out
    }
}
