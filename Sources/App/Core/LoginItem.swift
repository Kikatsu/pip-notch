import Foundation
import ServiceManagement

/// Starts Pip when you log in, so it's back in the notch after a restart or shutdown.
enum LoginItem {
    enum Status: Equatable {
        case on, off
        /// Registered, but switched off in System Settings → General → Login Items.
        case needsApproval
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: .on
        case .requiresApproval: .needsApproval
        default: .off
        }
    }

    static var isEnabled: Bool { status == .on }

    /// Throws with macOS's reason when it refuses (for example, Pip isn't in /Applications).
    static func set(_ on: Bool) throws {
        let current = SMAppService.mainApp.status
        if on {
            guard current != .enabled else { return }
            try SMAppService.mainApp.register()
        } else {
            guard current == .enabled || current == .requiresApproval else { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
