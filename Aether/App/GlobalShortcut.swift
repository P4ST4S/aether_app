import Carbon.HIToolbox
import Foundation

@MainActor final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?

    func register(modifiers: String, key: String, action: @escaping () -> Void) -> String? {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        self.action = action
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { shortcut.action?() }
                return noErr
            }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return "The global shortcut could not be installed. Use the menu bar icon." }
        }
        let flags: UInt32 = switch modifiers {
        case "controlOption": UInt32(controlKey | optionKey)
        case "commandShift": UInt32(cmdKey | shiftKey)
        case "controlShift": UInt32(controlKey | shiftKey)
        default: UInt32(optionKey)
        }
        let keys = ["space": kVK_Space, "a": kVK_ANSI_A, "return": kVK_Return, "f1": kVK_F1]
        let code = keys[key] ?? kVK_Space
        let status = RegisterEventHotKey(UInt32(code), flags, EventHotKeyID(signature: 0x41455448, id: 1),
                                         GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr ? nil : "This shortcut is unavailable (\(status)). Choose another combination or use the menu bar icon."
    }
}
