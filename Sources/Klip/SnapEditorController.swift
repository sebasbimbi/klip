import AppKit

/// Ventana del editor de capturas: barra de herramientas + lienzo. Al copiar/guardar devuelve la imagen anotada;
/// al cerrar sin guardar devuelve nil.
final class SnapEditorController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let canvas: AnnotationCanvasView
    private let onFinish: (NSImage?) -> Void
    private var toolButtons: [SnapTool: NSButton] = [:]
    private var colorButtons: [NSButton] = []
    private var colorIndex = 0
    private var lastToolWasMarker = false
    /// Botones cuyos equivalentes de tecla ⌘ deben liberarse mientras el usuario escribe en el campo de texto in situ
    /// (de lo contrario ⌘C/⌘Z/⌘S/Esc caen en la barra de herramientas en vez del editor de campo).
    private var keyEquivControls: [(button: NSButton, key: String, mods: NSEvent.ModifierFlags)] = []
    /// Paleta para dibujo normal y una paleta de tonos de resaltador (usada con el marcador).
    private let normalColors: [NSColor] = [.systemRed, .systemBlue, .black, .white]
    private let markerColors: [NSColor] = [.systemYellow, .systemGreen, .systemPink, .systemOrange]
    private var palette: [NSColor] { canvas.currentTool == .marker ? markerColors : normalColors }
    private var finished = false

    init(image: NSImage, onFinish: @escaping (NSImage?) -> Void) {
        self.canvas = AnnotationCanvasView(image: image)
        self.onFinish = onFinish
        super.init()
    }

    func present() {
        let imgSize = canvas.bounds.size
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let minBarWidth: CGFloat = 780   // ancho mínimo para que la barra de herramientas no se solape consigo misma
        let maxW = screen.width * 0.9, maxH = screen.height * 0.85 - 52
        let scale = min(1, min(maxW / imgSize.width, maxH / imgSize.height))
        let contentW = max(minBarWidth, imgSize.width * scale)
        let contentH = imgSize.height * scale + 52   // 52 = barra de herramientas

        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = L10n.t("win.editor")
        win.minSize = NSSize(width: minBarWidth, height: 240)
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH))

        // Lienzo dentro de un scroll view (por si la captura es grande).
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: contentW, height: contentH - 52))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = canvas
        scroll.backgroundColor = .underPageBackgroundColor
        content.addSubview(scroll)

        let toolbar = buildToolbar(width: contentW)
        toolbar.frame = NSRect(x: 0, y: contentH - 52, width: contentW, height: 52)
        toolbar.autoresizingMask = [.width, .minYMargin]
        content.addSubview(toolbar)

        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(canvas)
        canvas.currentLineWidth = 4   // trazo por defecto más grueso (más visible)
        selectTool(.arrow)
        // Al seleccionar/deseleccionar un texto, reflejar su color en la paleta de la barra de herramientas.
        canvas.onSelectionChange = { [weak self] in self?.syncColorSelectionFromCanvas() }
        // Mientras se escribe en el campo de texto in situ, liberar ⌘C/⌘Z/⌘S/Esc de la barra para que editen el
        // texto (copiar/deshacer/cancelar) en vez de disparar las acciones de la barra de herramientas.
        canvas.onTextEditingChanged = { [weak self] editing in self?.setKeyEquivalents(enabled: !editing) }
        self.window = win
    }

    /// Activa/desactiva los equivalentes de tecla de los botones de la barra (se usa para liberarlos mientras se edita texto).
    private func setKeyEquivalents(enabled: Bool) {
        for c in keyEquivControls {
            c.button.keyEquivalent = enabled ? c.key : ""
            c.button.keyEquivalentModifierMask = enabled ? c.mods : []
        }
    }

    // MARK: - Barra de herramientas

    private func buildToolbar(width: CGFloat) -> NSView {
        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: 52))
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.state = .active
        let size: CGFloat = 30

        // Grupo izquierdo: herramientas + color + grosor + deshacer.
        let leading = NSStackView()
        leading.orientation = .horizontal
        leading.spacing = 4
        leading.alignment = .centerY
        leading.translatesAutoresizingMaskIntoConstraints = false

        for tool in SnapTool.allCases {
            let b = makeToolButton(tool)
            b.widthAnchor.constraint(equalToConstant: 36).isActive = true
            b.heightAnchor.constraint(equalToConstant: 32).isActive = true
            toolButtons[tool] = b
            leading.addArrangedSubview(b)
        }

        leading.addArrangedSubview(separator())

        // Colores: 4 predefinidos (cambian a tonos de resaltador con el marcador) + "más" para el resto.
        for i in 0..<4 {
            let b = makeColorButton(tag: i)
            b.widthAnchor.constraint(equalToConstant: 24).isActive = true
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            colorButtons.append(b)
            leading.addArrangedSubview(b)
        }
        let more = makeActionButton(symbol: "ellipsis.circle", tip: L10n.t("editor.morecolors"), action: #selector(moreColorTapped))
        more.translatesAutoresizingMaskIntoConstraints = false
        more.widthAnchor.constraint(equalToConstant: 30).isActive = true
        leading.addArrangedSubview(more)

        leading.addArrangedSubview(separator())

        // Grosor: solo dos niveles (fino / grueso), más grueso y visible que antes.
        let widths = NSSegmentedControl(images: [lineImage(4), lineImage(10)],
                                        trackingMode: .selectOne,
                                        target: self, action: #selector(widthChanged(_:)))
        widths.setWidth(40, forSegment: 0); widths.setWidth(40, forSegment: 1)
        widths.selectedSegment = 0
        widths.toolTip = L10n.t("editor.strokewidth")
        leading.addArrangedSubview(widths)

        leading.addArrangedSubview(separator())

        // Tamaño de texto (afecta al texto seleccionado o al siguiente que escribas).
        let smaller = makeActionButton(symbol: "textformat.size.smaller", tip: L10n.t("editor.textsmaller"), action: #selector(textSmaller))
        let larger = makeActionButton(symbol: "textformat.size.larger", tip: L10n.t("editor.textlarger"), action: #selector(textLarger))
        for b in [smaller, larger] {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.widthAnchor.constraint(equalToConstant: size).isActive = true
            leading.addArrangedSubview(b)
        }

        let undo = makeActionButton(symbol: "arrow.uturn.backward", tip: L10n.t("editor.undo"), action: #selector(undoTapped))
        undo.keyEquivalent = "z"; undo.keyEquivalentModifierMask = [.command]
        undo.translatesAutoresizingMaskIntoConstraints = false
        undo.widthAnchor.constraint(equalToConstant: size).isActive = true
        leading.addArrangedSubview(undo)
        keyEquivControls.append((undo, "z", [.command]))

        // Grupo derecho: copiar + guardar + cerrar.
        let trailing = NSStackView()
        trailing.orientation = .horizontal
        trailing.spacing = 6
        trailing.alignment = .centerY
        trailing.translatesAutoresizingMaskIntoConstraints = false

        let copy = makeTextButton(title: L10n.t("editor.copy"), tip: L10n.t("editor.copy.tip"), action: #selector(copyTapped))
        copy.keyEquivalent = "c"; copy.keyEquivalentModifierMask = [.command]
        let save = makeTextButton(title: L10n.t("editor.save"), tip: L10n.t("editor.save.tip"), action: #selector(saveTapped))
        save.keyEquivalent = "s"; save.keyEquivalentModifierMask = [.command]
        let close = makeActionButton(symbol: "xmark", tip: L10n.t("editor.close"), action: #selector(closeTapped))
        close.keyEquivalent = "\u{1b}"   // Esc
        close.translatesAutoresizingMaskIntoConstraints = false
        close.widthAnchor.constraint(equalToConstant: size).isActive = true
        keyEquivControls.append((copy, "c", [.command]))
        keyEquivControls.append((save, "s", [.command]))
        keyEquivControls.append((close, "\u{1b}", []))
        trailing.addArrangedSubview(copy)
        trailing.addArrangedSubview(save)
        trailing.addArrangedSubview(close)

        bar.addSubview(leading)
        bar.addSubview(trailing)
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            leading.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            trailing.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            leading.trailingAnchor.constraint(lessThanOrEqualTo: trailing.leadingAnchor, constant: -16)
        ])
        return bar
    }

    private func makeActionButton(symbol: String, tip: String, action: Selector) -> NSButton {
        let b = NSButton(title: "", target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.toolTip = tip
        return b
    }

    private func makeTextButton(title: String, tip: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.toolTip = tip
        b.keyEquivalent = ""
        return b
    }

    // MARK: - Acciones de la barra de herramientas

    @objc private func toolTapped(_ sender: NSButton) {
        let tool = SnapTool.allCases[sender.tag]
        selectTool(tool)
    }

    private func selectTool(_ tool: SnapTool) {
        canvas.currentTool = tool
        for (t, b) in toolButtons {
            let on = (t == tool)
            b.layer?.backgroundColor = on ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
            b.contentTintColor = on ? .white : .labelColor   // resalta claramente la herramienta activa
        }
        refreshColorSwatches()                                // el marcador muestra tonos de resaltador
        // Solo re-aplicar el color POR DEFECTO cuando la PALETA cambia de tipo (normal↔marcador). Entre
        // herramientas normales se conserva el color elegido. Usar setDefaultColor para que un cambio de
        // herramienta nunca recoloree una anotación de texto seleccionada ya confirmada.
        let isMarker = (tool == .marker)
        if isMarker != lastToolWasMarker {
            if colorIndex < 0 { colorIndex = 0 }              // ajustar un color personalizado a una muestra al cambiar de paleta
            refreshColorSwatches()
            canvas.setDefaultColor(palette[min(colorIndex, palette.count - 1)])
        }
        lastToolWasMarker = isMarker
    }

    @objc private func widthChanged(_ sender: NSSegmentedControl) {
        canvas.currentLineWidth = sender.selectedSegment == 1 ? 10 : 4   // grueso / fino
    }

    // MARK: - Color

    @objc private func colorTapped(_ sender: NSButton) {
        colorIndex = sender.tag
        canvas.setColor(palette[min(colorIndex, palette.count - 1)])
        refreshColorSwatches()
    }

    @objc private func moreColorTapped() {
        let panel = NSColorPanel.shared
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        panel.color = canvas.effectiveColor
        panel.isContinuous = true
        canvas.armColorCoalescing()   // el arrastre continuo que sigue es UN solo paso de deshacer, no docenas
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        colorIndex = -1                                        // color personalizado: ningún predefinido marcado
        canvas.setColorCoalesced(sender.color)
        refreshColorSwatches()
    }

    /// Si el texto seleccionado usa un color de la paleta, marcar esa muestra (si no, ninguna).
    private func syncColorSelectionFromCanvas() {
        colorIndex = palette.firstIndex(where: { Self.approxEqual($0, canvas.effectiveColor) }) ?? -1
        refreshColorSwatches()
    }

    private func refreshColorSwatches() {
        let colors = palette
        for (i, b) in colorButtons.enumerated() {
            b.image = Self.swatchImage(i < colors.count ? colors[i] : .clear)
            b.layer?.cornerRadius = 12
            let on = (i == colorIndex)
            b.layer?.borderWidth = on ? 2.5 : 0
            b.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }

    // MARK: - Constructores de controles

    private func makeToolButton(_ tool: SnapTool) -> NSButton {
        let b = NSButton(title: "", target: self, action: #selector(toolTapped(_:)))
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = 7
        b.imageScaling = .scaleProportionallyDown
        let cfg = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        b.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: tool.tooltip)?
            .withSymbolConfiguration(cfg)
        b.toolTip = tool.tooltip
        b.tag = SnapTool.allCases.firstIndex(of: tool) ?? 0
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func makeColorButton(tag: Int) -> NSButton {
        let b = NSButton(title: "", target: self, action: #selector(colorTapped(_:)))
        b.isBordered = false
        b.wantsLayer = true
        b.tag = tag
        b.toolTip = L10n.t("editor.color")
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return box
    }

    private static func swatchImage(_ color: NSColor) -> NSImage {
        let d: CGFloat = 20
        let img = NSImage(size: NSSize(width: d, height: d))
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: d - 4, height: d - 4)).fill()
        NSColor.separatorColor.setStroke()                     // borde para que el blanco sea visible
        let ring = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: d - 4, height: d - 4))
        ring.lineWidth = 1; ring.stroke()
        img.unlockFocus()
        return img
    }

    private func lineImage(_ thickness: CGFloat) -> NSImage {
        let w: CGFloat = 24, h: CGFloat = 16
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSColor.labelColor.setStroke()
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 4, y: h / 2)); p.line(to: NSPoint(x: w - 4, y: h / 2))
        p.lineWidth = thickness; p.lineCapStyle = .round; p.stroke()
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    private static func approxEqual(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        return abs(x.redComponent - y.redComponent) < 0.02
            && abs(x.greenComponent - y.greenComponent) < 0.02
            && abs(x.blueComponent - y.blueComponent) < 0.02
    }

    @objc private func textSmaller() { canvas.bumpFontSize(-4) }
    @objc private func textLarger() { canvas.bumpFontSize(+4) }

    @objc private func undoTapped() { canvas.undo() }

    @objc private func copyTapped() {
        let image = canvas.flattened()
        finish(with: image)
    }

    @objc private func saveTapped() {
        guard let window else { return }
        let image = canvas.flattened()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = L10n.t("editor.savefilename")
        // Hoja anclada a la ventana del editor (no flotante) para que no quede huérfana si esta se cierra.
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard let self else { return }
            guard resp == .OK, let url = panel.url else { return }   // cancelar: el editor sigue abierto
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                self.showError(L10n.t("editor.err.png")); return
            }
            do {
                try png.write(to: url)
                self.finish(with: image)
            } catch {
                // Fallo de escritura (disco lleno, ruta de solo lectura…): avisar y NO cerrar el editor,
                // para no perder la anotación creyendo que se guardó.
                self.showError(String(format: L10n.t("editor.err.save"), error.localizedDescription))
            }
        }
    }

    private func showError(_ msg: String) {
        let a = NSAlert(); a.messageText = L10n.t("editor.err.title"); a.informativeText = msg
        a.addButton(withTitle: L10n.t("common.ok")); a.runModal()
    }

    @objc private func closeTapped() { finish(with: nil) }

    /// Al cerrar el editor, cerrar también el NSColorPanel compartido (si se abrió vía "más colores"):
    /// de lo contrario seguiría flotando sobre una app de barra de menús sin ventanas, apuntando a un
    /// editor ya destruido.
    private func dismissColorUI() {
        guard NSColorPanel.sharedColorPanelExists else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.setAction(nil)
        NSColorPanel.shared.orderOut(nil)
    }

    private func finish(with image: NSImage?) {
        guard !finished else { return }
        finished = true
        dismissColorUI()
        window?.orderOut(nil)
        window = nil
        onFinish(image)
    }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        dismissColorUI()
        onFinish(nil)
    }
}
