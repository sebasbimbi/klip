import Foundation

/// Metadatos de la app para "Acerca de" y enlaces.
enum AppInfo {
    static let name = "Klip"
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.4"
    }
    /// ⚠️ Cambia esta URL por la de tu repositorio real cuando lo publiques.
    static let repoURL = "https://github.com/proper/klip"
    static let issuesURL = "https://github.com/proper/klip/issues"
}
