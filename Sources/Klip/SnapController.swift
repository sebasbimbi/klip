import AppKit

/// Orquesta el flujo de captura de "Klip Snap": permiso → capturar la pantalla bajo el cursor →
/// overlay de selección → editor de anotaciones → historial de Klip.
final class SnapController {
    private let manager: ClipboardManager
    private var overlay: CaptureOverlayController?
    private var editor: SnapEditorController?
    private var inProgress = false

    /// Se invoca tras añadir una captura al historial (para revelar el panel: el elemento "vuela" hacia Klip).
    var onCaptured: (() -> Void)?

    /// Qué hacer con la región seleccionada: abrir el editor de anotaciones, o extraer su texto (OCR) directo al portapapeles.
    enum Mode { case annotate, text }

    init(manager: ClipboardManager) {
        self.manager = manager
        ScreenCapturer.warmUp()
    }

    /// Punto de entrada (atajo o menú): capturar una región y abrir el editor de anotaciones.
    func start() { begin(mode: .annotate) }

    /// Punto de entrada: capturar una región y extraer su texto (OCR) directo al portapapeles — sin editor.
    func startTextCapture() { begin(mode: .text) }

    private func begin(mode: Mode) {
        // Bloquear la reentrada durante TODO el flujo: mientras se captura (inProgress) y mientras el overlay de
        // selección o el editor están en pantalla. Si no, un segundo disparo apilaría ventanas escudo y filtraría la primera.
        guard !inProgress, overlay == nil, editor == nil else { return }

        guard ScreenCapturer.hasPermission() else {
            promptForPermission()
            return
        }

        inProgress = true
        let mouse = NSEvent.mouseLocation
        Task { @MainActor in
            do {
                let shot = try await ScreenCapturer.captureDisplay(containing: mouse)
                self.inProgress = false
                self.presentOverlay(shot, mode: mode)
            } catch CaptureError.noPermission {
                self.inProgress = false          // liberar ANTES del modal (evita reentrancia del runloop)
                self.promptForPermission()
            } catch {
                self.inProgress = false
                NSSound.beep()
            }
        }
    }

    @MainActor
    private func presentOverlay(_ shot: DisplayShot, mode: Mode) {
        let overlay = CaptureOverlayController(shot: shot) { [weak self] image in
            self?.overlay = nil
            guard let self, let image else { return }
            switch mode {
            case .annotate: self.openEditor(with: image)
            case .text:     self.extractText(from: image)
            }
        }
        self.overlay = overlay
        overlay.present()
    }

    /// Aplica OCR a la región seleccionada FUERA del hilo principal, luego pone el texto en el portapapeles + en el historial.
    @MainActor
    private func extractText(from image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { NSSound.beep(); return }
        Task { @MainActor [weak self] in
            let text = await Task.detached { OCR.recognizeText(in: cg) }.value   // OCR fuera del hilo principal
            guard let self else { return }
            guard self.manager.addCapturedText(text) else { NSSound.beep(); return }   // nada reconocido
            self.onCaptured?()
        }
    }

    @MainActor
    private func openEditor(with image: NSImage) {
        let editor = SnapEditorController(image: image) { [weak self] result in
            self?.editor = nil
            guard let self, let result else { return }   // nil = cerrado sin guardar
            self.manager.addAnnotatedScreenshot(result, copyToClipboard: true)
            self.onCaptured?()
        }
        self.editor = editor
        editor.present()
    }

    /// Sin permiso de Grabación de Pantalla. La PRIMERA vez solo mostramos el aviso nativo del sistema
    /// (`requestPermission`); en intentos posteriores (cuando el aviso nativo ya no reaparece) mostramos
    /// nuestra propia guía con un acceso directo a Ajustes. Así los dos mensajes nunca se solapan.
    private func promptForPermission() {
        let askedKey = "klip.askedScreenRecording"
        if !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            ScreenCapturer.requestPermission()   // solo el aviso nativo la primera vez
            return
        }
        let alert = NSAlert()
        alert.messageText = L10n.t("perm.screen.title")
        alert.informativeText = L10n.t("perm.screen.info")
        alert.addButton(withTitle: L10n.t("perm.screen.open"))
        alert.addButton(withTitle: L10n.t("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
