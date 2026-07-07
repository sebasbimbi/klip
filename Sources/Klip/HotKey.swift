import Carbon.HIToolbox
import AppKit

/// GLOBAL keyboard shortcut (works even when the app is not in the foreground),
/// using the Carbon RegisterEventHotKey API. Does not require Accessibility permissions.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32
    private let callback: () -> Void

    /// Static map so the C callback (which can't capture) can locate the instance.
    private static var instances: [UInt32: HotKey] = [:]
    private static var handlerInstalled = false

    /// - Parameters:
    ///   - keyCode: virtual key code (e.g. kVK_ANSI_V).
    ///   - modifiers: Carbon combination (e.g. cmdKey | shiftKey).
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

    /// Hot-reloads with a new combination, reusing the id and callback.
    /// The already-installed global handler stays valid; it is not reinstalled.
    @discardableResult
    func reRegister(keyCode: UInt32, modifiers: UInt32) -> Bool {
        // Register the NEW one in a temporary ref; only release the old one if it succeeded,
        // so we don't end up without a shortcut if the combination collides.
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
        // The Carbon event handler is a single process-lifetime global (installHandlerIfNeeded), shared by
        // all HotKey instances via the static `instances` map — intentionally not removed per-instance.
        HotKey.instances[id] = nil
    }
}
