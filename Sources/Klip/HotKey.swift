import Carbon.HIToolbox
import AppKit

/// Atajo de teclado GLOBAL (funciona incluso cuando la app no está en primer plano),
/// usando la API Carbon RegisterEventHotKey. No requiere permisos de Accesibilidad.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32
    private let callback: () -> Void

    /// Mapa estático para que el callback C (que no puede capturar) pueda localizar la instancia.
    private static var instances: [UInt32: HotKey] = [:]
    private static var handlerInstalled = false

    /// - Parameters:
    ///   - keyCode: código de tecla virtual (p. ej. kVK_ANSI_V).
    ///   - modifiers: combinación Carbon (p. ej. cmdKey | shiftKey).
    init?(keyCode: UInt32, modifiers: UInt32, id: UInt32 = 1, callback: @escaping () -> Void) {
        self.id = id
        self.callback = callback
        HotKey.instances[id] = self

        HotKey.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x50415354), id: id) // 'PAST'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            HotKey.instances[id] = nil
            return nil
        }
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            if let instance = HotKey.instances[hkID.id] {
                DispatchQueue.main.async { instance.callback() }
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    /// Recarga en caliente con una combinación nueva, reutilizando el id y el callback.
    /// El handler global ya instalado sigue siendo válido; no se reinstala.
    @discardableResult
    func reRegister(keyCode: UInt32, modifiers: UInt32) -> Bool {
        // Registrar el NUEVO en un ref temporal; liberar el antiguo solo si tuvo éxito,
        // para no quedarnos sin atajo si la combinación colisiona.
        let hotKeyID = EventHotKeyID(signature: OSType(0x50415354), id: id) // 'PAST'
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else { return false }
        if let old = hotKeyRef { UnregisterEventHotKey(old) }
        hotKeyRef = newRef
        return true
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        // El handler de eventos Carbon es un global único de vida del proceso (installHandlerIfNeeded), compartido
        // por todas las instancias de HotKey vía el mapa estático `instances` — a propósito no se quita por instancia.
        HotKey.instances[id] = nil
    }
}
