import AppKit
import SwiftUI

/// Standard (titled) Preferences window, distinct from the floating panel.
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
        // Switch to a "regular" app while the window is open: guarantees keyboard focus
        // (needed to type/paste the API key into the SecureField).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // back to a menu-bar app (no Dock)
    }
}
