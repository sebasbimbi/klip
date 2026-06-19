import Foundation
import ServiceManagement
import AppKit

/// Human-readable errors for the UI when enabling launch at login.
enum LoginItemError: LocalizedError {
    case invalidSignature
    case requiresApproval
    case translocated
    case underlying(NSError)

    var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return "Pasta no está firmada correctamente; no se puede activar el inicio automático."
        case .requiresApproval:
            return "Actívalo en Ajustes del Sistema › General › Ítems de inicio de sesión."
        case .translocated:
            return "Mueve Pasta a la carpeta Aplicaciones para activar el inicio automático."
        case .underlying(let e):
            return e.localizedDescription
        }
    }
}

/// Controls launch at login via SMAppService.mainApp (macOS 13+).
final class LoginItem {
    static let shared = LoginItem()
    private let service = SMAppService.mainApp
    private init() {}

    var isEnabled: Bool { service.status == .enabled }

    var requiresApproval: Bool { service.status == .requiresApproval }

    /// Enabled or pending user approval (to reflect the real state in the UI).
    var isEnabledOrPending: Bool {
        let s = service.status
        return s == .enabled || s == .requiresApproval
    }

    /// The app must run from a stable (non-translocated) and signed location.
    private func preflight() -> LoginItemError? {
        if Bundle.main.bundlePath.contains("/AppTranslocation/") { return .translocated }
        return nil
    }

    func setEnabled(_ enabled: Bool) throws {
        if let pre = preflight() { throw pre }
        do {
            if enabled { try service.register() }
            else       { try service.unregister() }
        } catch let e as NSError {
            switch e.code {
            case 12: return            // kSMErrorAlreadyRegistered -> idempotent success
            case 6:  return            // kSMErrorJobNotFound -> was already inactive
            case 3:  throw LoginItemError.invalidSignature
            case 11: throw LoginItemError.requiresApproval
            default: throw LoginItemError.underlying(e)
            }
        }
    }

    @discardableResult
    func toggle() -> Result<Bool, LoginItemError> {
        let target = !isEnabled
        do {
            try setEnabled(target)
            return .success(isEnabled)
        } catch let err as LoginItemError {
            return .failure(err)
        } catch {
            return .failure(.underlying(error as NSError))
        }
    }

    /// Registers launch at login the first time (idempotent, silent).
    func registerIfNeeded() {
        guard service.status != .enabled, service.status != .requiresApproval else { return }
        try? setEnabled(true)
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
