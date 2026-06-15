import AppKit

// Punto de entrada. App accesoria (sin icono en el Dock); vive en la barra de menú.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(ProcessInfo.processInfo.environment["KLIP_REGULAR"] == nil ? .accessory : .regular)
app.run()
