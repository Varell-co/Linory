import Carbon

/// Global ⌥⇧L hotkey via Carbon, the only API that works without Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private static let signature: OSType = 0x4C595243

    /// Returns false when the handler or the key combination could not be registered.
    func register(handler: @escaping () -> Void) -> Bool {
        self.handler = handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var eventID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID)
            guard status == noErr, eventID.signature == HotKey.signature, eventID.id == 1 else { return OSStatus(eventNotHandledErr) }
            Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue().handler?()
            return noErr
        }, 1, &eventType, context, &handlerRef)
        guard handlerStatus == noErr else { return false }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        return RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(optionKey | shiftKey), id, GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        ref = nil; handlerRef = nil
    }
}
