import AppKit
import ApplicationServices   // AXIsProcessTrusted, kAXTrustedCheckOptionPrompt
import CoreGraphics          // CGEvent, CGEventSource

/// Reactiva la app previa y sintetiza ⌘V para pegar automáticamente el elemento elegido.
/// Requiere permiso de Accesibilidad; si falta, degrada a solo devolver el foco (el contenido
/// ya está en el portapapeles y el usuario pega manualmente).
enum Paster {

    private static let keyCodeV: CGKeyCode = 9          // kVK_ANSI_V (posición física, válido para ⌘V)
    private static let activationDelay: TimeInterval = 0.13

    /// Comprobación silenciosa (sin diálogo). Para decidir auto-paste vs fallback.
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Comprobación que ABRE el diálogo del sistema si aún no hay permiso.
    /// Llamar solo bajo acción explícita del usuario.
    @discardableResult
    static func ensureAccessibilityPermission(prompt: Bool) -> Bool {
        guard prompt else { return AXIsProcessTrusted() }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Reactiva `target` y, si hay permiso, sintetiza ⌘V tras un breve delay.
    /// El contenido ya debe estar en el portapapeles ANTES de llamar.
    /// - Returns: true si se intentó auto-paste; false si fue fallback (solo-copiar).
    @discardableResult
    static func paste(into target: NSRunningApplication?) -> Bool {
        target?.activate()

        guard hasAccessibilityPermission else { return false }

        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            postCommandV()
        }
        return true
    }

    private static func postCommandV() {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCodeV, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCodeV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
