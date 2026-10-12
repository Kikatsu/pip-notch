import AppKit
import SwiftUI

/// Borderless panel that sits over the menu bar and never steals focus from the user's app.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        // Become key on click (without activating Pip) so buttons respond like in any window.
        becomesKeyOnlyIfNeeded = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a button work even though the panel is never the active window.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Where the physical notch is, or where a stand-in pill goes on screens without one.
struct NotchGeometry {
    let screen: NSScreen

    var hasNotch: Bool { screen.safeAreaInsets.top > 0 }

    var notchSize: CGSize {
        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return CGSize(width: 160, height: max(menuBar, 24))
    }

    /// The notch itself, in screen coordinates.
    var notchRect: CGRect {
        let size = notchSize
        return CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    static func preferredScreen(pointer: CGPoint = NSEvent.mouseLocation) -> NSScreen? {
        NotchDisplay.current.screen(among: NSScreen.screens, pointer: pointer)
    }
}

/// Which display the notch lives on. Stored as "auto", "primary", "pointer", or a display's UUID.
enum NotchDisplay: Equatable {
    static let key = "notch.display"

    /// The built-in notch when there is one (lid open), otherwise the primary display.
    case automatic
    /// The display with the menu bar in System Settings → Displays.
    case primary
    /// Whichever display the pointer is on.
    case followPointer
    /// One specific display, remembered across reconnects. Falls back to automatic while it's unplugged.
    case display(uuid: String)

    init(rawValue: String?) {
        switch rawValue {
        case nil, "auto": self = .automatic
        case "primary": self = .primary
        case "pointer": self = .followPointer
        case let uuid?: self = .display(uuid: uuid)
        }
    }

    var rawValue: String {
        switch self {
        case .automatic: "auto"
        case .primary: "primary"
        case .followPointer: "pointer"
        case .display(let uuid): uuid
        }
    }

    static var current: NotchDisplay {
        NotchDisplay(rawValue: UserDefaults.standard.string(forKey: key))
    }

    func screen(among screens: [NSScreen], pointer: CGPoint) -> NSScreen? {
        // `screens.first` is the primary display; `NSScreen.main` is wherever Pip's last window was.
        let primary = screens.first
        let automatic = screens.first { $0.safeAreaInsets.top > 0 } ?? primary
        switch self {
        case .automatic:
            return automatic
        case .primary:
            return primary
        case .followPointer:
            return screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(pointer) } ?? automatic
        case .display(let uuid):
            return screens.first { $0.displayUUID == uuid } ?? automatic
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// Stable across reboots and reconnects, unlike the display ID.
    var displayUUID: String? {
        guard let id = displayID, let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
