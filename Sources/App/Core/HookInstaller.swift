import Foundation

/// Adds and removes Pip's hooks in Claude Code's user settings without touching anything else.
struct HookInstaller {
    static let marker = "pip-bridge"

    /// Every Claude Code event Pip listens to. Only PermissionRequest blocks the agent.
    static let claudeEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure",
    ]

    let settingsURL: URL
    let bridgePath: String

    static var claudeSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    var command: String { "\"\(bridgePath)\" claude" }

    func isInstalled() -> Bool {
        guard let settings = try? readSettings() else { return false }
        return Self.containsPipHooks(settings)
    }

    func install() throws {
        let settings = try readSettings()
        try write(Self.installing(into: settings, command: command))
    }

    func uninstall() throws {
        let settings = try readSettings()
        try write(Self.removingPipHooks(from: settings))
    }

    // MARK: Pure transforms (tested)

    static func installing(into settings: [String: Any], command: String) -> [String: Any] {
        var result = removingPipHooks(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in claudeEvents {
            var handler: [String: Any] = ["type": "command", "command": command]
            if BridgeWire.blockingEvents.contains(event) {
                handler["timeout"] = 600
            } else {
                handler["async"] = true
            }
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [handler]])
            hooks[event] = groups
        }
        result["hooks"] = hooks
        return result
    }

    static func removingPipHooks(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = handlers.filter { !isPipHandler($0) }
                if remaining.isEmpty { return nil }
                var copy = group
                copy["hooks"] = remaining
                return copy
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        var result = settings
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    static func containsPipHooks(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            (value as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isPipHandler)
            }
        }
    }

    private static func isPipHandler(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains(marker) == true
    }

    // MARK: File access

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.unreadableSettings
        }
        return object
    }

    private func write(_ settings: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("pip-backup")
            try? fm.removeItem(at: backup)
            try fm.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    enum InstallError: LocalizedError {
        case unreadableSettings

        var errorDescription: String? {
            "Claude Code's settings.json isn't valid JSON, so Pip left it untouched."
        }
    }
}

/// Keeps a stable copy of the bundled bridge where hooks can always find it.
enum BridgeInstaller {
    static func installBundledBridge() throws -> String {
        let destination = PipPaths.bridgeInstallURL
        guard let source = Bundle.main.url(forAuxiliaryExecutable: "pip-bridge") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.contentsEqual(atPath: source.path, andPath: destination.path) { return destination.path }
        let staging = destination.appendingPathExtension("new")
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: source, to: staging)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
        _ = try fm.replaceItemAt(destination, withItemAt: staging)
        return destination.path
    }
}
