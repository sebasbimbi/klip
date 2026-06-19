import AppKit

// Entry point. Accessory app (no Dock icon); lives in the menu bar.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(ProcessInfo.processInfo.environment["KLIP_REGULAR"] == nil ? .accessory : .regular)
app.run()
