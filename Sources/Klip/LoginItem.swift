import Foundation
import ServiceManagement
import AppKit

/// Errores legibles para la UI al habilitar el arranque al iniciar sesión.
enum LoginItemError: LocalizedError {
    case invalidSignature
    case requiresApproval
    case translocated
    case underlying(NSError)

    var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return L10n.t("login.err.signature")
        case .requiresApproval:
            return L10n.t("login.err.approval")
        case .translocated:
            return L10n.t("login.err.translocated")
        case .underlying(let e):
            return e.localizedDescription
        }
    }
}

/// Controla el arranque al iniciar sesión vía SMAppService.mainApp (macOS 13+).
final class LoginItem {
    static let shared = LoginItem()
    private let service = SMAppService.mainApp
    private init() {}

    var isEnabled: Bool { service.status == .enabled }

    var requiresApproval: Bool { service.status == .requiresApproval }

    /// Habilitado o pendiente de aprobación del usuario (para reflejar el estado real en la UI).
    var isEnabledOrPending: Bool {
        let s = service.status
        return s == .enabled || s == .requiresApproval
    }

    /// La app debe ejecutarse desde una ubicación estable (no translocada) y firmada.
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
            case 12: return            // kSMErrorAlreadyRegistered -> éxito idempotente
            case 6:  return            // kSMErrorJobNotFound -> ya estaba inactivo
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

    /// Registra el arranque al iniciar sesión la primera vez (idempotente, silencioso).
    func registerIfNeeded() {
        guard service.status != .enabled, service.status != .requiresApproval else { return }
        try? setEnabled(true)
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
