import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Panel flotante que puede recibir el foco del teclado sin convertirse en la ventana principal.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Controla la ventana emergente del historial: vibrancy HUD, posicionamiento contextual,
/// aparición animada, navegación por teclado, cierre al hacer clic fuera, auto-pegado, voz y Markdown.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: KeyablePanel!
    private var effectView: NSVisualEffectView!
    private let manager: ClipboardManager
    private let selection = SelectionModel()
    private let recorder = Recorder()
    /// True mientras se graba, finaliza o transcribe audio — se usa para bloquear una importación destructiva.
    var isBusyWithAudio: Bool { recorder.isRecording || recorder.finishing || recorder.transcribingCount > 0 }
    /// True mientras una de nuestras ventanas auxiliares está en pantalla, para que el auto-ocultado del panel
    /// por clic fuera / resign-key no se dispare cuando el usuario interactúa con una de ellas (Upload/Guide/Welcome/Recording).
    private var auxWindowVisible: Bool {
        [uploadWindow, guideWindow, welcomeWindow, recordingPanel].contains { $0?.isVisible == true }
    }
    private weak var statusItem: NSStatusItem?
    private weak var previousApp: NSRunningApplication?

    /// Inyectado por AppDelegate para abrir Preferencias desde el panel (estado sin API key).
    var onOpenPreferences: (() -> Void)?
    /// Inyectado por AppDelegate para disparar el nuevo Klip Snap desde el botón de cámara del panel.
    var onCaptureAnnotate: (() -> Void)?

    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    /// Número de paneles modales activos (guardar/abrir). Mientras sea > 0 el panel no se cierra al perder
    /// el foco. Es un contador (no un bool) para que dos paneles solapados no se pisen el estado entre sí.
    private var modalCount = 0
    private var isModalActive: Bool { modalCount > 0 }
    /// Evita lanzar una segunda exportación (PDF/ZIP) mientras hay una en curso.
    private var exportInFlight = false
    private var isRenaming = false
    private let cornerRadius: CGFloat = 12
    private var recordingPanel: NSPanel?
    private var guideWindow: NSWindow?
    private var uploadWindow: NSWindow?
    private var welcomeWindow: NSWindow?

    init(manager: ClipboardManager, statusItem: NSStatusItem?) {
        self.manager = manager
        self.statusItem = statusItem
        super.init()
        buildPanel()
    }

    private func buildPanel() {
        recorder.onVoiceNoteStarted = { [weak self] fn, dur in self?.manager.beginVoiceNote(audioFileName: fn, duration: dur) }
        recorder.onVoiceNoteTranscribed = { [weak self] id, text in self?.manager.finishVoiceNote(id: id, text: text) }
        recorder.onVoiceNoteDuration = { [weak self] id, dur in self?.manager.setVoiceNoteDuration(id: id, duration: dur) }
        recorder.onVoiceNoteFailed = { [weak self] id in self?.manager.failVoiceNote(id: id) }
        recorder.onVoiceNoteRetrying = { [weak self] id in self?.manager.markVoiceNoteTranscribing(id: id) }
        recorder.onVoiceNoteDownloadingModel = { [weak self] id in self?.manager.markVoiceNoteDownloadingModel(id: id) }
        recorder.onVoiceNoteAudioStored = { [weak self] id, fn in self?.manager.setVoiceNoteAudioFile(id: id, fileName: fn) }

        let root = HistoryView(
            manager: manager,
            selection: selection,
            recorder: recorder,
            onPick: { [weak self] item in self?.pick(item) },
            onSaveImage: { [weak self] item in self?.saveImage(item) },
            onCopyMarkdown: { [weak self] item in self?.copyMarkdown(of: item) },
            onCopyAllMarkdown: { [weak self] in self?.copyAllMarkdown() },
            onOpenPreferences: { [weak self] in self?.hide(restoreFocus: false); self?.onOpenPreferences?() },
            onUploadAudio: { [weak self] in self?.uploadAudio() },
            onVoiceRecord: { [weak self] in self?.toggleVoiceRecording() },
            onShowGuide: { [weak self] in self?.showGuide() },
            onRename: { [weak self] item in self?.renameItem(item) },
            onRetryTranscription: { [weak self] item in self?.retryTranscription(item) },
            onSaveAsFile: { [weak self] item in self?.saveTextAsFile(item) },
            onCopyAsCode: { [weak self] item in self?.copyAsCode(of: item) },
            onCaptureAnnotate: { [weak self] in self?.onCaptureAnnotate?() },
            onCombinePDF: { [weak self] items in self?.combineSelectedToPDF(items) },
            onExportZip: { [weak self] items in self?.exportSelectedZip(items) },
            onAssignCollection: { [weak self] items in self?.assignSelectedToCollection(items) }
        )

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        // Aparecer en el Space ACTUAL y SOBRE apps a pantalla completa. Sin esto, pulsar el atajo mientras una
        // app a pantalla completa (p. ej. un IDE) tiene el foco dispara la acción pero el panel se abre en otro Space —
        // parece que "no pasó nada". fullScreenAuxiliary le permite superponerse al Space de pantalla completa.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        let fx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        fx.material = .menu
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = cornerRadius
        fx.layer?.masksToBounds = true
        fx.autoresizingMask = [.width, .height]
        self.effectView = fx

        let hosting = NSHostingView(rootView: root)
        hosting.frame = fx.bounds
        hosting.autoresizingMask = [.width, .height]
        fx.addSubview(hosting)

        panel.contentView = fx
        self.panel = panel
    }

    func toggle() {
        if isModalActive { return }   // no abrir/cerrar el panel mientras hay un sheet de guardar/exportar abierto detrás
        panel.isVisible ? hide() : show()
    }

    func show() {
        guard !panel.isVisible else { return }   // idempotente: evita reinstalar los monitores
        previousApp = NSWorkspace.shared.frontmostApplication
        positionPanel()

        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()   // forzarlo al frente incluso cuando Klip no es la app activa (p. ej. sobre un IDE a pantalla completa)
        selection.reset()
        selection.selecting = false               // autoritativo al abrir (no depender del timing de onChange de SwiftUI)
        selection.openToken &+= 1                 // dispara el reseteo de búsqueda/foco en la vista
        if recordingPanel?.isVisible != true { recorder.reset() }  // no cerrar el popup de voz si está abierto

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installMonitors()
    }

    func hide(restoreFocus: Bool = true) {
        removeMonitors()
        AudioPlayer.shared.stop()   // no dejar audio sonando cuando el panel se cierra
        panel.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
    }

    // MARK: - Monitores (teclado + clic fuera)

    private func installMonitors() {
        removeMonitors()   // nunca dejar monitores huérfanos
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { e in e }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.isModalActive, !self.isRenaming, !self.recorder.isRecording,
                  !self.auxWindowVisible else { return }   // no cerrar mientras haya una ventana hija en pantalla
            self.hide(restoreFocus: false)
        }
    }

    private func removeMonitors() {
        [keyMonitor, localClickMonitor, globalClickMonitor].forEach {
            if let m = $0 { NSEvent.removeMonitor(m) }
        }
        keyMonitor = nil; localClickMonitor = nil; globalClickMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if isRenaming { return event }   // el diálogo de renombrar gestiona sus propias teclas
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if event.keyCode == 53 {   // Esc (el monitor siempre corre en el hilo principal)
            if recorder.finishing {
                return nil   // un stop está finalizando: dejar que termine — no cancelar (borraría la nota)
            } else if recorder.state == .recording {
                MainActor.assumeIsolated { recorder.cancel() }   // aborta la grabación, no cierra
            } else if !recorder.isRecording {
                hide(restoreFocus: true)                         // no cerrar mientras se transcribe
            }
            return nil
        }

        // En modo multi-selección por lotes, el teclado NO pega/cierra (rompería el lote en curso):
        // solo navega con flechas; ⌘1-9 / Return no eligen. El ratón sigue alternando (onToggleCheck).
        // El modo por lotes (multi-selección) se maneja con el ratón (checkboxes). No mover aquí un cursor de
        // teclado sin resaltado visible — solo confundía; dejar pasar las teclas (escritura en búsqueda, scroll de la lista).
        if selection.selecting { return event }

        // ⌘↩ → copia el ítem de texto seleccionado como bloque de código (la acción estrella del vibe-coder), solo teclado.
        if flags == .command, event.keyCode == 36,
           let id = selection.selectedID, let item = manager.items.first(where: { $0.id == id }),
           item.kind == .text, item.isCredential != true, !(item.text?.isEmpty ?? true) {   // nunca auto-pegar un secreto
            copyAsCode(of: item); return nil
        }
        if flags.contains(.command) { return event }   // no romper ⌘A/⌘C/⌘V en el campo de búsqueda

        switch event.keyCode {
        case 125: selection.moveDown(); return nil    // ↓
        case 126: selection.moveUp();   return nil    // ↑
        case 36, 76: pickSelected();    return nil    // Return / Enter
        default: return event
        }
    }

    // MARK: - Posicionamiento

    private func positionPanel() {
        let size = panel.frame.size
        let gap: CGFloat = 6
        if let btnWin = statusItem?.button?.window {
            let b = btnWin.frame
            let screen = btnWin.screen ?? NSScreen.main ?? NSScreen.screens.first!
            panel.setFrameOrigin(clamp(x: b.midX - size.width / 2,
                                       y: b.minY - gap - size.height, size: size, into: screen.visibleFrame))
        } else {
            let m = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(m) }
                ?? NSScreen.main ?? NSScreen.screens.first!
            panel.setFrameOrigin(clamp(x: m.x - size.width / 2,
                                       y: m.y - size.height - gap, size: size, into: screen.visibleFrame))
        }
    }

    private func clamp(x: CGFloat, y: CGFloat, size: NSSize, into vf: NSRect) -> NSPoint {
        let hiX = max(vf.minX + 8, vf.maxX - size.width - 8)   // garantiza lo <= hi en pantallas pequeñas
        let hiY = max(vf.minY + 8, vf.maxY - size.height - 8)
        let cx = min(max(x, vf.minX + 8), hiX)
        let cy = min(max(y, vf.minY + 8), hiY)
        return NSPoint(x: cx, y: cy)
    }

    // MARK: - Acciones

    private func pick(_ item: ClipboardItem) {
        // Nota de voz sin transcripción: no hay texto que pegar → reproducir el audio y dejar el panel abierto.
        if item.kind == .text, (item.text?.isEmpty ?? true) {
            if let af = item.audioFileName { AudioPlayer.shared.toggle(fileName: af) }
            return
        }
        manager.copyToPasteboard(item)
        let target = previousApp
        hide(restoreFocus: false)
        if item.isCredential == true { target?.activate() }   // no auto-pegar secretos: solo copiar + restaurar el foco
        else { pasteOrRestore(target) }
    }

    private func pickSelected() {
        guard let id = selection.selectedID,
              let item = manager.items.first(where: { $0.id == id }) else { return }
        pick(item)
    }

    /// Auto-pega en la app anterior (si hay permiso y una app destino), o solo restaura el foco.
    private func pasteOrRestore(_ target: NSRunningApplication?) {
        guard let target, !target.isTerminated else { return }   // sin destino: simplemente queda copiado
        if Settings.shared.autoPaste { Paster.paste(into: target) }
        else { target.activate() }
    }

    private func copyMarkdown(of item: ClipboardItem) {
        guard item.isCredential != true else { return }   // nunca auto-pegar un secreto como Markdown
        let md = Markdownify.fromText(item.text ?? "")
        let target = previousApp
        manager.setClipboardText(md)
        hide(restoreFocus: false)
        pasteOrRestore(target)
    }

    private func copyAllMarkdown() {
        let md = MarkdownExporter.history(manager.items)
        let target = previousApp
        manager.setClipboardText(md)
        hide(restoreFocus: false)
        pasteOrRestore(target)
    }

    /// Copia el texto envuelto en un bloque de código Markdown (``` ```), listo para pegar en un chat de IA.
    private func copyAsCode(of item: ClipboardItem) {
        guard item.isCredential != true else { return }   // nunca envolver+auto-pegar un secreto
        guard let t = item.text, !t.isEmpty else { return }
        let target = previousApp
        manager.setClipboardText("```\(Markdownify.inferCodeLanguage(t))\n\(t)\n```")
        hide(restoreFocus: false)
        pasteOrRestore(target)
    }

    /// Guarda el texto del ítem como archivo (.txt/.md) para poder arrastrarlo a una herramienta de IA
    /// cuando el chat no acepta pegarlo (textos/logs muy grandes).
    private func saveTextAsFile(_ item: ClipboardItem) {
        guard item.isCredential != true else { return }   // no escribir un secreto en un archivo de texto plano
        guard let t = item.text, !t.isEmpty else { return }
        let sp = NSSavePanel()
        var types: [UTType] = [.plainText]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        sp.allowedContentTypes = types
        sp.nameFieldStringValue = (item.name?.isEmpty == false ? item.name! : "klip-text") + ".txt"
        sp.canCreateDirectories = true
        modalCount += 1   // guarda de "hay un panel modal abierto" (no cerrar el panel detrás)
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            if resp == .OK, let url = sp.url { try? t.data(using: .utf8)?.write(to: url, options: .atomic) }
            self?.modalCount -= 1
        }
    }

    // MARK: - Combinar / exportar selección

    func combineSelectedToPDF(_ items: [ClipboardItem]) {
        guard !items.isEmpty, !exportInFlight else { return }   // no solapar exportaciones
        exportInFlight = true
        modalCount += 1   // protege el panel durante toda la generación + guardado (cierra la ventana de carrera)
        manager.pauseMonitoring()   // evita que el trim del poll borre media seleccionada a mitad de la generación
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Storage.shared.combinedPDF(from: items)
            DispatchQueue.main.async {
                guard let self else { return }
                self.manager.resumeMonitoring()   // las lecturas de media terminaron
                guard let result else {   // nada exportable: avisar en vez de "el botón no hace nada"
                    self.modalCount -= 1; self.exportInFlight = false
                    self.showAlert(L10n.t("export.empty.title"), L10n.t("export.empty.info"))
                    return
                }
                let sp = NSSavePanel()
                sp.allowedContentTypes = [.pdf]
                sp.nameFieldStringValue = "klip.pdf"
                sp.canCreateDirectories = true
                if result.exported < items.count {
                    sp.message = String(format: L10n.t("export.partial"), result.exported, items.count)
                }
                NSApp.activate(ignoringOtherApps: true)
                sp.begin { resp in
                    if resp == .OK, let url = sp.url { try? result.data.write(to: url, options: .atomic) }
                    self.modalCount -= 1; self.exportInFlight = false
                }
            }
        }
    }

    func exportSelectedZip(_ items: [ClipboardItem]) {
        guard !items.isEmpty, !exportInFlight else { return }
        let exportable = Storage.shared.zipExportableCount(items)
        guard exportable > 0 else { showAlert(L10n.t("export.empty.title"), L10n.t("export.empty.info")); return }
        exportInFlight = true
        let sp = NSSavePanel()
        sp.allowedContentTypes = [.zip]
        sp.nameFieldStringValue = "klip-selection.zip"
        sp.canCreateDirectories = true
        if exportable < items.count {
            sp.message = String(format: L10n.t("export.partial"), exportable, items.count)
        }
        modalCount += 1
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            guard let self else { return }
            self.modalCount -= 1
            guard resp == .OK, let url = sp.url else { self.exportInFlight = false; return }
            self.manager.pauseMonitoring()   // evita que el trim del poll borre media seleccionada a mitad de la copia
            DispatchQueue.global(qos: .userInitiated).async {
                let err: Error? = { do { try Storage.shared.exportItemsZip(items, to: url); return nil } catch { return error } }()
                DispatchQueue.main.async {
                    self.manager.resumeMonitoring()
                    self.exportInFlight = false
                    if let err { self.showAlert(L10n.t("export.empty.title"), err.localizedDescription) }   // no fallar en silencio
                }
            }
        }
    }

    private func showAlert(_ title: String, _ info: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = info
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    func assignSelectedToCollection(_ items: [ClipboardItem]) {
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = L10n.t("collection.add.title")
        alert.informativeText = L10n.t("collection.add.info")
        alert.addButton(withTitle: L10n.t("common.ok"))
        let cancel = alert.addButton(withTitle: L10n.t("common.cancel")); cancel.keyEquivalent = "\u{1b}"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        // Precargar solo si TODOS comparten la misma colección; si difieren, dejarlo vacío (no sobrescribir
        // con una colección arbitraria del lote heterogéneo).
        let current = Set(items.map { $0.collection ?? "" })
        field.stringValue = current.count == 1 ? (current.first ?? "") : ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        isRenaming = true
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        isRenaming = false
        if resp == .alertFirstButtonReturn {
            manager.assignCollection(Set(items.map { $0.id }), to: field.stringValue)
        }
        if panel.isVisible { panel.makeKeyAndOrderFront(nil); selection.focusToken &+= 1 }
    }

    /// Atajo global de voz: abre el popup de grabación dedicado y alterna grabar/detener.
    func toggleVoiceRecording() {
        MainActor.assumeIsolated {
            if recorder.state == .recording { recorder.stop(); return }
            guard !recorder.isRecording else { return }
            if recordingPanel?.isVisible != true {   // al regrabar con el popup abierto, conservar la app original
                previousApp = NSWorkspace.shared.frontmostApplication
            }
            showRecordingPopup()
            recorder.start()
        }
    }

    private func showRecordingPopup() {
        if recordingPanel == nil {
            let view = RecordingView(
                recorder: recorder,
                onStop: { [weak self] in MainActor.assumeIsolated { self?.recorder.stop() } },
                onCancel: { [weak self] in MainActor.assumeIsolated { self?.recorder.cancel() } },
                onClose: { [weak self] in self?.closeRecordingPopup() },
                onOpenPreferences: { [weak self] in self?.onOpenPreferences?() }
            )
            let p = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 320),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
            p.level = .floating; p.isReleasedWhenClosed = false
            p.isMovableByWindowBackground = true   // arrastrable desde el fondo (panel sin bordes y sin barra de título)
            p.hidesOnDeactivate = false   // no ocultar cuando el foco vuelve a la app del usuario
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]   // mostrar también sobre apps a pantalla completa
            let fx = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 360, height: 320))
            fx.material = .hudWindow; fx.blendingMode = .behindWindow; fx.state = .active
            fx.wantsLayer = true; fx.layer?.cornerRadius = 16; fx.layer?.masksToBounds = true
            fx.autoresizingMask = [.width, .height]
            let host = NSHostingView(rootView: view)
            host.frame = fx.bounds; host.autoresizingMask = [.width, .height]; fx.addSubview(host)
            p.contentView = fx
            recordingPanel = p
            // Posicionar SOLO al crear: si el usuario arrastró el popup, no lo devolvemos al centro
            // cada vez que vuelve a grabar.
            if let screen = NSScreen.main {
                let vf = screen.visibleFrame; let s = p.frame.size
                p.setFrameOrigin(NSPoint(x: vf.midX - s.width / 2, y: vf.midY + 120))
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        recordingPanel?.makeKeyAndOrderFront(nil)
        recordingPanel?.orderFrontRegardless()
    }

    private func closeRecordingPopup() {
        recordingPanel?.orderOut(nil)
        previousApp?.activate()   // la transcripción corre en segundo plano; solo restauramos el foco
    }

    /// Ventana de onboarding de primer uso. Se muestra una vez; "Get started" activa el flag y la cierra.
    func showWelcome() {
        if welcomeWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 580),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = L10n.t("win.welcome")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: WelcomeView(onStart: { [weak self] in
                Settings.shared.hasSeenWelcome = true
                self?.welcomeWindow?.orderOut(nil)
            }))
            w.center()
            welcomeWindow = w
        }
        Settings.shared.hasSeenWelcome = true   // se muestra una vez: no reaparece aunque se cierre con el botón rojo
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.orderFrontRegardless()
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    func showGuide() {
        if guideWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = L10n.t("win.guide")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: GuideView())
            w.center()
            guideWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        guideWindow?.makeKeyAndOrderFront(nil)
    }

    /// Abre la ventana "Upload audio to transcribe". Punto de entrada compartido para el botón del panel
    /// de historial, el ítem de la barra de menús y el atajo global.
    func uploadAudio() {
        // recorder.state es compartido; limpiar un .error/.missingAPIKey previo para mostrar la dropzone — pero NO
        // mientras el popup de grabación está en pantalla (eso borraría su propio error/estado).
        if recorder.state != .recording, recordingPanel?.isVisible != true { recorder.reset() }
        // Sesión nueva (nada en curso): empezar con la lista de resultados vacía para que no queden resultados viejos.
        if recorder.transcribingCount == 0 { recorder.clearUploadResults() }
        showUploadWindow()
    }

    private func showUploadWindow() {
        if uploadWindow == nil {
            let view = UploadView(
                recorder: recorder,
                onChoose: { [weak self] lang in self?.chooseAudioFiles(language: lang) },
                onFiles: { [weak self] urls, lang in MainActor.assumeIsolated { self?.submitAudioFiles(urls, language: lang) } },
                onClose: { [weak self] in self?.uploadWindow?.orderOut(nil) },
                onOpenPreferences: { [weak self] in self?.onOpenPreferences?() },
                onCopy: { [weak self] in self?.manager.setClipboardText($0) }
            )
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 440),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = L10n.t("win.upload")
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 400, height: 360)
            w.contentView = NSHostingView(rootView: view)
            w.center()
            uploadWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        uploadWindow?.makeKeyAndOrderFront(nil)
    }

    private func chooseAudioFiles(language: String) {
        let p = NSOpenPanel()
        // Audio + video: la pista de audio de un video se extrae antes de transcribir (ver MediaAudioExtractor).
        // El .opus de WhatsApp no siempre conforma a public.audio, así que lo añadimos (y .oga) explícitamente; las
        // extensiones de video cubren contenedores para los que macOS no registra UTType (mkv/webm → nil, inofensivo).
        let types = [UTType.audio, .movie, .audiovisualContent]
            + ["opus", "oga"].compactMap { UTType(filenameExtension: $0) }
            + MediaAudioExtractor.videoExtensions.compactMap { UTType(filenameExtension: $0) }
        p.allowedContentTypes = types
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        modalCount += 1   // evita que el panel de historial se cierre mientras este panel de apertura está en pantalla
        NSApp.activate(ignoringOtherApps: true)
        p.begin { [weak self] resp in
            self?.modalCount -= 1
            guard resp == .OK, !p.urls.isEmpty else { return }
            MainActor.assumeIsolated { self?.submitAudioFiles(p.urls, language: language) }
        }
    }

    /// Envía los audios a transcribir (en segundo plano). La ventana queda abierta mostrando el progreso
    /// ("Transcribiendo N…"); el usuario la cierra cuando quiera (las notas aparecen en el historial).
    @MainActor
    private func submitAudioFiles(_ urls: [URL], language: String) {
        recorder.transcribeFiles(urls, language: language)
    }

    /// Reintenta transcribir una nota de voz fallida (usa su audio guardado).
    private func retryTranscription(_ item: ClipboardItem) {
        guard let af = item.audioFileName, Storage.shared.audioExists(fileName: af) else { return }
        // Evita un segundo reintento (doble clic) mientras hay uno en curso → no duplica la llamada a la API.
        guard manager.items.first(where: { $0.id == item.id })?.transcribing != true else { return }
        guard AIProvider.hasKey else { onOpenPreferences?(); return }   // sin key: ofrecer configurarla
        MainActor.assumeIsolated { recorder.retry(itemID: item.id, audioFileName: af) }
    }

    /// Diálogo para poner (o cambiar) el nombre de cualquier ítem. Buscable después.
    private func renameItem(_ item: ClipboardItem) {
        let alert = NSAlert()
        alert.messageText = L10n.t("rename.title")
        alert.informativeText = L10n.t("rename.info")
        alert.addButton(withTitle: L10n.t("rename.save"))
        let cancel = alert.addButton(withTitle: L10n.t("common.cancel"))
        cancel.keyEquivalent = "\u{1b}"   // Esc cancela (no se asigna automáticamente en español)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = item.name ?? ""
        field.placeholderString = L10n.t("rename.placeholder")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        isRenaming = true
        NSApp.activate(ignoringOtherApps: true)
        let resp = alert.runModal()
        isRenaming = false
        if resp == .alertFirstButtonReturn { manager.rename(item, to: field.stringValue) }
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            selection.focusToken &+= 1   // restaurar el foco al campo de búsqueda (sin limpiar búsqueda/filtro)
        }
    }

    private func saveImage(_ item: ClipboardItem) {
        guard item.kind == .image, let fn = item.imageFileName,
              let img = Storage.shared.loadImage(fileName: fn),
              let png = Storage.shared.pngData(from: img) else { return }
        let sp = NSSavePanel()
        sp.allowedContentTypes = [.png]
        sp.nameFieldStringValue = "klip-capture.png"
        sp.canCreateDirectories = true
        modalCount += 1
        NSApp.activate(ignoringOtherApps: true)
        sp.begin { [weak self] resp in
            if resp == .OK, let url = sp.url { try? png.write(to: url, options: .atomic) }
            self?.modalCount -= 1
        }
    }

    // MARK: - NSWindowDelegate (respaldo para cerrar cuando se pierde el foco)

    func windowDidResignKey(_ notification: Notification) {
        guard !isModalActive, !isRenaming, !recorder.isRecording, !auxWindowVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible, !self.isModalActive, !self.isRenaming,
                  !self.recorder.isRecording, !self.auxWindowVisible, !self.panel.isKeyWindow else { return }
            self.hide(restoreFocus: false)
        }
    }
}
