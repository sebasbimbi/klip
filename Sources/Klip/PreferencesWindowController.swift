import AppKit
import SwiftUI

/// Ventana de Preferencias estándar (con título), distinta del panel flotante.
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {

    convenience init(onHotKeyChange: @escaping (KeyCombo) -> Void,
                     onVoiceHotKeyChange: @escaping (KeyCombo) -> Void,
                     onCaptureHotKeyChange: @escaping (KeyCombo) -> Void,
                     onUploadHotKeyChange: @escaping (KeyCombo) -> Void,
                     onTextCaptureHotKeyChange: @escaping (KeyCombo) -> Void,
                     onMaxItemsChange: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = L10n.t("win.prefs")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: PreferencesView(onHotKeyChange: onHotKeyChange,
                                      onVoiceHotKeyChange: onVoiceHotKeyChange,
                                      onCaptureHotKeyChange: onCaptureHotKeyChange,
                                      onUploadHotKeyChange: onUploadHotKeyChange,
                                      onTextCaptureHotKeyChange: onTextCaptureHotKeyChange,
                                      onMaxItemsChange: onMaxItemsChange))
        window.center()
        self.init(window: window)
        window.delegate = self
    }

    func show() {
        // Cambiar a app "regular" mientras la ventana está abierta: garantiza el foco de teclado
        // (necesario para escribir/pegar la API key en el SecureField).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // De vuelta a app de barra de menús (sin Dock) — pero solo si no nos lanzaron como app regular
        // (KLIP_REGULAR); si no, cerrar Preferencias quitaría indebidamente el icono del Dock.
        if ProcessInfo.processInfo.environment["KLIP_REGULAR"] == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
