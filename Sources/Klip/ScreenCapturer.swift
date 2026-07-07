import AppKit
import ScreenCaptureKit
import CoreGraphics

/// Resultado de una captura: la pantalla capturada, su bitmap de píxeles y el factor de escala.
struct DisplayShot {
    let screen: NSScreen
    let cgImage: CGImage
    let scale: CGFloat
}

enum CaptureError: Error { case noDisplay, noPermission }

/// Captura de pantalla con ScreenCaptureKit (macOS 14+). Reemplaza `CGDisplayCreateImage`
/// (obsoleto). Estrategia: capturar SOLO la pantalla que contiene el cursor — esto evita los
/// clásicos bugs de coordenadas multi-monitor y encaja con el uso real (seleccionas donde estás).
enum ScreenCapturer {

    /// ¿El usuario ya concedió el permiso de Grabación de Pantalla? (no dispara el prompt)
    static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Dispara el prompt del sistema (solo una vez). Devuelve si terminó concedido.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// Precalienta el subsistema de captura para que el primer disparo real no tenga latencia visible.
    static func warmUp() {
        Task.detached(priority: .utility) {
            _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        }
    }

    /// Captura la pantalla que contiene `point` (coordenadas Cocoa globales, origen abajo-izquierda).
    static func captureDisplay(containing point: NSPoint) async throws -> DisplayShot {
        guard hasPermission() else { throw CaptureError.noPermission }

        let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
            ?? NSScreen.main
        guard let screen else { throw CaptureError.noDisplay }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let scd = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.noDisplay
        }

        // Excluir las ventanas propias de Klip (panel/overlay) para que no aparezcan en la captura.
        let ownBundleID = Bundle.main.bundleIdentifier
        let ownApps = content.applications.filter { $0.bundleIdentifier == ownBundleID }
        let filter = SCContentFilter(display: scd, excludingApplications: ownApps, exceptingWindows: [])
        let config = SCStreamConfiguration()
        // Píxeles físicos = puntos × escala (correcto en Retina).
        config.width  = Int(screen.frame.width  * screen.backingScaleFactor)
        config.height = Int(screen.frame.height * screen.backingScaleFactor)
        config.showsCursor = false
        config.scalesToFit = false

        let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return DisplayShot(screen: screen, cgImage: cg, scale: screen.backingScaleFactor)
    }
}

extension NSScreen {
    /// CGDirectDisplayID de esta pantalla (para emparejarla con SCDisplay).
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
