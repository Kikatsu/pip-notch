import Foundation

/// Locations shared by the app and the bridge binary.
enum PipPaths {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Pip", isDirectory: true)
    }

    /// Unix socket the app listens on. `PIP_SOCKET` overrides it (used by tests and demos).
    static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["PIP_SOCKET"], !override.isEmpty {
            return override
        }
        return supportDirectory.appendingPathComponent("pip.sock").path
    }

    /// Stable copy of the bridge that agent hooks call, so hooks survive the app moving.
    static var bridgeInstallURL: URL {
        supportDirectory.appendingPathComponent("bin/pip-bridge")
    }
}

enum BridgeWire {
    static let version = 1
    /// Hook events where the agent waits for Pip's answer.
    static let blockingEvents: Set<String> = ["PermissionRequest"]
    /// How long the bridge waits for the user before handing back to the agent's own prompt.
    /// Kept under the 600 s hook timeout registered in the agent settings.
    static let replyTimeout: TimeInterval = 590
}
