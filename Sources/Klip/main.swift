import AppKit

// Punto de entrada. App accesoria (sin icono en el Dock); vive en la barra de menús.
// El código de nivel superior es nonisolated; todo el arranque corre en el hilo principal, así que se afirma
// MainActor para el AppDelegate @MainActor. `delegate` se retiene aquí de por vida (NSApplication.delegate es weak).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(ProcessInfo.processInfo.environment["KLIP_REGULAR"] == nil ? .accessory : .regular)
    app.run()
}
