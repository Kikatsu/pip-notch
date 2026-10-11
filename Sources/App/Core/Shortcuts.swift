import AppKit
import Carbon.HIToolbox

/// Pip's global keyboard shortcuts. Fixed combinations built on ⌃⌥ so they rarely collide.
enum Shortcut: UInt32, CaseIterable, Identifiable {
    case togglePanel = 1, allow, deny, jump, mute

    var id: UInt32 { rawValue }

    var keyCode: UInt32 {
        switch self {
        case .togglePanel: UInt32(kVK_Space)
        case .allow: UInt32(kVK_Return)
        case .deny: UInt32(kVK_Delete)
        case .jump: UInt32(kVK_ANSI_J)
        case .mute: UInt32(kVK_ANSI_M)
        }
    }

    var modifiers: UInt32 { UInt32(controlKey | optionKey) }

    var keys: String {
        switch self {
        case .togglePanel: "⌃⌥Space"
        case .allow: "⌃⌥↩"
        case .deny: "⌃⌥⌫"
        case .jump: "⌃⌥J"
        case .mute: "⌃⌥M"
        }
    }

    var title: String {
        switch self {
        case .togglePanel: "Open or close the notch"
        case .allow: "Allow the request (or approve the plan)"
        case .deny: "Deny the request (or keep planning)"
        case .jump: "Go to the session that needs you most"
        case .mute: "Mute or unmute sounds"
        }
    }

    /// Allow and Deny are only registered while a request is waiting, so they never take
    /// those keys away from other apps the rest of the time.
    var onlyWhileApprovalPending: Bool { self == .allow || self == .deny }
}

/// Registers system-wide hotkeys with Carbon's RegisterEventHotKey. Unlike key-event monitors,
/// this needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    static let enabledKey = "shortcuts.enabled"

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handlerInstalled = false
    private static let signature: OSType = 0x5049_5048 // "PIPH"

    func set(_ shortcut: Shortcut, active: Bool, action: @escaping () -> Void) {
        actions[shortcut.rawValue] = action
        if active { register(shortcut) } else { unregister(shortcut) }
    }

    func isRegistered(_ shortcut: Shortcut) -> Bool { refs[shortcut.rawValue] != nil }

    private func register(_ shortcut: Shortcut) {
        guard refs[shortcut.rawValue] == nil else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: shortcut.rawValue)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[shortcut.rawValue] = ref
        } else {
            Log.ui.error("Shortcut \(shortcut.keys, privacy: .public) is taken by another app (\(status))")
        }
    }

    private func unregister(_ shortcut: Shortcut) {
        if let ref = refs.removeValue(forKey: shortcut.rawValue) { UnregisterEventHotKey(ref) }
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = id.id
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.fire(pressed) } }
            return noErr
        }, 1, &type, nil, nil)
    }
}
