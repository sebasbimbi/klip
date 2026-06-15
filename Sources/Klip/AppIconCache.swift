import AppKit

/// Caché en memoria de iconos de apps por bundle ID, para mostrar el origen sin coste por frame.
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(forBundleID id: String?) -> NSImage? {
        guard let id, !id.isEmpty else { return nil }
        if let cached = cache[id] { return cached }
        let ws = NSWorkspace.shared
        guard let url = ws.urlForApplication(withBundleIdentifier: id) else { return nil }
        let img = ws.icon(forFile: url.path)
        cache[id] = img
        return img
    }
}
