import Foundation

/// One agent Pip can connect to: where its hook config lives and how Pip's hooks look in it.
/// Installing only ever adds or removes Pip's own entries and keeps a backup of the file.
struct AgentIntegration: Identifiable {
    enum Mode: Equatable {
        /// Runs in the background; the agent never waits.
        case async
        /// The agent waits for the answer (approvals).
        case blocking(timeout: Int)
        /// Runs inline with a short timeout (events the agent can't run in the background).
        case sync(timeout: Int)
    }

    enum Format {
        /// `{"hooks": {Event: [{"matcher"?, "hooks": [{"type","command",…}]}]}}`: Claude Code and Codex.
        case claudeStyle([(event: String, mode: Mode)])
        /// Claude-style groups under `{"hooks": {"enabled": true, "events": {…}}}`: ZCode, which
        /// runs no hook unless `enabled` is set.
        case zcode([(event: String, mode: Mode)])
        /// `{"version"?, "hooks": {event: [{"command", …extras}]}}`: Cursor (version 1) and Windsurf.
        case flat(events: [String], version: Int?, extras: [String: Any])
        /// `{"pip": {"enabled", Event: [...]}}`: Antigravity.
        case antigravity
        /// A whole file that belongs to Pip (a plugin, an extension, a hooks file of its own).
        /// Installing writes it; disconnecting deletes it. The closure gets the bridge path.
        case ownedFile((String) -> String)
        /// A marked block Pip appends to a shared TOML file (Kimi Code, Mistral Vibe). Everything
        /// outside the markers is the user's and never touched.
        case tomlBlock((String) -> String)
    }

    let agent: AgentKind
    let configURL: URL
    let format: Format
    /// Any of these existing means the agent is installed on this Mac.
    let detectPaths: [String]
    /// Shown under the connect button when the agent needs a manual step.
    let note: String?
    /// More files Pip owns alongside `configURL` (e.g. a plugin manifest), written and removed with it.
    var extraFiles: [(url: URL, contents: (String) -> String)] = []

    var id: String { agent.rawValue }

    var isDetected: Bool {
        detectPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    func isInstalled() -> Bool {
        if case .tomlBlock = format {
            return (try? String(contentsOf: configURL, encoding: .utf8)).map(TomlBlock.contains) ?? false
        }
        if case .ownedFile = format {
            return (try? String(contentsOf: configURL, encoding: .utf8))?.contains(HookConfig.marker) ?? false
        }
        return (try? HookFile(url: configURL).read()).map(HookConfig.containsPip) ?? false
    }

    /// Connected, but the agent won't run Pip's hooks until the user approves them in the agent.
    /// Codex skips hooks it hasn't reviewed (`/hooks`) without any error, so the notch just stays empty.
    func awaitsTrust() -> Bool {
        guard agent == .codex, isInstalled() else { return false }
        let configTOML = configURL.deletingLastPathComponent().appendingPathComponent("config.toml")
        return !CodexHookTrust.hasTrustedHooks(configTOML: try? String(contentsOf: configTOML, encoding: .utf8))
    }

    /// Installed and pointing at this copy of the bridge, with an up-to-date Pip file.
    func isInstalled(bridgePath: String) -> Bool {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return false }
        if case .ownedFile(let contents) = format {
            return text == contents(bridgePath)
        }
        let extrasCurrent = extraFiles.allSatisfy { (try? String(contentsOf: $0.url, encoding: .utf8)) == $0.contents(bridgePath) }
        if case .tomlBlock(let contents) = format {
            return TomlBlock.extract(from: text) == TomlBlock.wrap(contents(bridgePath)) && extrasCurrent
        }
        return isInstalled() && text.contains(bridgePath) && extrasCurrent
    }

    func install(bridgePath: String) throws {
        for extra in extraFiles {
            try FileManager.default.createDirectory(at: extra.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(extra.contents(bridgePath).utf8).write(to: extra.url, options: .atomic)
        }
        if case .ownedFile(let contents) = format {
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents(bridgePath).utf8).write(to: configURL, options: .atomic)
            return
        }
        if case .tomlBlock(let contents) = format {
            let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            try TomlBlock.write(TomlBlock.installing(contents(bridgePath), into: text), to: configURL)
            return
        }
        let file = HookFile(url: configURL)
        try file.write(HookConfig.installing(format, agent: agent, bridgePath: bridgePath, into: try file.read()))
    }

    func uninstall() throws {
        if case .tomlBlock = format {
            for extra in extraFiles { try? FileManager.default.removeItem(at: extra.url) }
            guard let text = try? String(contentsOf: configURL, encoding: .utf8), TomlBlock.contains(text) else { return }
            try TomlBlock.write(TomlBlock.removing(from: text), to: configURL)
            return
        }
        if case .ownedFile = format {
            guard isInstalled() else { return }
            try FileManager.default.removeItem(at: configURL)
            for extra in extraFiles { try? FileManager.default.removeItem(at: extra.url) }
            return
        }
        let file = HookFile(url: configURL)
        try file.write(HookConfig.removing(format, from: try file.read()))
    }

    // MARK: Known agents

    static var all: [AgentIntegration] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func at(_ path: String) -> URL { home.appendingPathComponent(path) }
        return [
            AgentIntegration(
                agent: .claude,
                configURL: at(".claude/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("PostToolUseFailure", .async),
                    ("PermissionRequest", .blocking(timeout: 600)), ("Notification", .async),
                    ("Stop", .async), ("StopFailure", .async),
                ]),
                detectPaths: [at(".claude").path, "/Applications/Claude.app"],
                note: "CLI, desktop app and editor extensions. Approvals in the notch."
            ),
            AgentIntegration(
                agent: .codex,
                configURL: at(".codex/hooks.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .sync(timeout: 3)), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async),
                    ("PermissionRequest", .blocking(timeout: 600)), ("Stop", .async),
                ]),
                detectPaths: [at(".codex").path, "/Applications/Codex.app", "/Applications/ChatGPT.app"],
                note: "CLI, Codex and ChatGPT apps, editor extensions. Run /hooks once to trust Pip."
            ),
            AgentIntegration(
                agent: .gemini,
                configURL: at(".gemini/settings.json"),
                // Gemini has no async hooks and counts timeouts in milliseconds.
                format: .claudeStyle([
                    ("SessionStart", .sync(timeout: 5000)), ("SessionEnd", .sync(timeout: 5000)),
                    ("BeforeAgent", .sync(timeout: 5000)), ("AfterAgent", .sync(timeout: 5000)),
                    ("BeforeTool", .sync(timeout: 5000)), ("AfterTool", .sync(timeout: 5000)),
                    ("Notification", .sync(timeout: 5000)),
                ]),
                detectPaths: [at(".gemini/settings.json").path, "/opt/homebrew/bin/gemini", "/usr/local/bin/gemini"],
                note: "Status and alerts."
            ),
            AgentIntegration(
                agent: .copilot,
                configURL: at(".copilot/hooks/pip.json"),
                format: .ownedFile(AgentPlugins.copilot(bridgePath:)),
                detectPaths: [at(".copilot").path],
                note: "Status and alerts."
            ),
            AgentIntegration(
                agent: .droid,
                configURL: droidConfig(home: home),
                format: .claudeStyle([
                    ("SessionStart", .sync(timeout: 5)), ("SessionEnd", .sync(timeout: 5)),
                    ("UserPromptSubmit", .sync(timeout: 5)), ("PreToolUse", .sync(timeout: 5)),
                    ("PostToolUse", .sync(timeout: 5)), ("Notification", .sync(timeout: 5)),
                    ("Stop", .sync(timeout: 5)),
                ]),
                detectPaths: [at(".factory").path],
                note: "Status and alerts."
            ),
            AgentIntegration(
                agent: .opencode,
                configURL: at(".config/opencode/plugins/pip.js"),
                format: .ownedFile(AgentPlugins.openCode(bridgePath:)),
                detectPaths: [at(".config/opencode").path, at(".opencode").path],
                note: "Status and alerts. Restart OpenCode after connecting."
            ),
            AgentIntegration(
                agent: .pi,
                configURL: at(".pi/agent/extensions/pip.ts"),
                format: .ownedFile(AgentPlugins.pi(bridgePath:)),
                detectPaths: [at(".pi").path],
                note: "Status and replies. Restart Pi after connecting."
            ),
            AgentIntegration(
                agent: .kiro,
                configURL: at(".kiro/hooks/pip.json"),
                format: .ownedFile(AgentPlugins.kiro(bridgePath:)),
                detectPaths: [at(".kiro").path, at(".local/bin/kiro-cli").path, "/opt/homebrew/bin/kiro-cli"],
                note: "Status and replies. Needs Kiro CLI 3 or later."
            ),
            AgentIntegration(
                agent: .qoder,
                configURL: at(".qoder/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("PostToolUseFailure", .async),
                    ("PermissionRequest", .blocking(timeout: 600)), ("Notification", .async),
                    ("Stop", .async), ("StopFailure", .async),
                ]),
                detectPaths: [at(".qoder").path, "/Applications/Qoder.app"],
                note: "Approvals in the notch."
            ),
            AgentIntegration(
                agent: .augment,
                configURL: at(".augment/settings.json"),
                // Augment runs hooks inline and counts timeouts in milliseconds.
                format: .claudeStyle([
                    ("SessionStart", .sync(timeout: 5000)), ("SessionEnd", .sync(timeout: 5000)),
                    ("PreToolUse", .sync(timeout: 5000)), ("PostToolUse", .sync(timeout: 5000)),
                    ("Stop", .sync(timeout: 5000)),
                ]),
                detectPaths: [at(".augment").path],
                note: "Status and replies for the auggie CLI."
            ),
            AgentIntegration(
                agent: .goose,
                configURL: at(".agents/plugins/pip/hooks/hooks.json"),
                format: .ownedFile(AgentPlugins.goose(bridgePath:)),
                detectPaths: [at(".config/goose").path, "/Applications/Goose.app"],
                note: "Status and replies. Installs a small Pip plugin.",
                extraFiles: [(at(".agents/plugins/pip/plugin.json"), AgentPlugins.gooseManifest(bridgePath:))]
            ),
            AgentIntegration(
                agent: .grok,
                configURL: at(".grok/hooks/pip.json"),
                format: .ownedFile(AgentPlugins.grok(bridgePath:)),
                detectPaths: [at(".grok").path, "/opt/homebrew/bin/grok", at(".local/bin/grok").path],
                note: "Status and replies for xAI's Grok Build."
            ),
            AgentIntegration(
                agent: .kimi,
                configURL: at(".kimi-code/config.toml"),
                format: .tomlBlock(AgentPlugins.kimi(bridgePath:)),
                detectPaths: [at(".kimi-code").path],
                note: "Status and alerts. Pip adds a marked block to config.toml."
            ),
            AgentIntegration(
                agent: .vibe,
                configURL: at(".vibe/hooks.toml"),
                format: .tomlBlock(AgentPlugins.vibe(bridgePath:)),
                detectPaths: [at(".vibe").path],
                note: "Status and replies. Pip adds a marked block to hooks.toml."
            ),
            AgentIntegration(
                agent: .qwen,
                configURL: at(".qwen/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("PermissionRequest", .async),
                    ("Notification", .async), ("Stop", .async), ("StopFailure", .async),
                ]),
                detectPaths: [at(".qwen").path],
                note: "Status and alerts."
            ),
            AgentIntegration(
                agent: .cursor,
                configURL: at(".cursor/hooks.json"),
                format: .flat(events: [
                    "sessionStart", "sessionEnd", "beforeSubmitPrompt", "postToolUse",
                    "afterShellExecution", "afterFileEdit", "afterAgentResponse", "stop",
                ], version: 1, extras: [:]),
                detectPaths: [at(".cursor").path, "/Applications/Cursor.app", at(".local/bin/cursor-agent").path, "/Applications/Grok Bot.app"],
                note: "Cursor, cursor-agent and Grok Bot's local agents. Status and alerts."
            ),
            AgentIntegration(
                agent: .windsurf,
                configURL: at(".codeium/windsurf/hooks.json"),
                format: .flat(events: [
                    "pre_user_prompt", "post_run_command", "post_write_code", "post_mcp_tool_use", "post_cascade_response",
                ], version: nil, extras: ["show_output": false]),
                detectPaths: [at(".codeium/windsurf").path, "/Applications/Windsurf.app"],
                note: "Cascade status and replies."
            ),
            AgentIntegration(
                agent: .antigravity,
                configURL: at(".gemini/config/hooks.json"),
                format: .antigravity,
                detectPaths: [
                    at(".gemini/antigravity").path, at(".gemini/antigravity-cli").path, at(".gemini/config").path,
                    "/Applications/Antigravity.app", "/opt/homebrew/bin/agy", "/usr/local/bin/agy", at(".local/bin/agy").path,
                ],
                note: "App and agy CLI. Status and alerts."
            ),
            AgentIntegration(
                agent: .zcode,
                // Only the user config runs hooks; project files and ~/.zcode/settings.json don't.
                configURL: at(".zcode/cli/config.json"),
                format: .zcode([
                    ("SessionStart", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("PostToolUseFailure", .async),
                    ("PermissionRequest", .blocking(timeout: 600)), ("Stop", .async),
                ]),
                detectPaths: [at(".zcode").path, "/Applications/ZCode.app", at(".local/bin/zcode").path, "/opt/homebrew/bin/zcode"],
                note: "Approvals in the notch."
            ),
            AgentIntegration(
                agent: .trae,
                configURL: at(".trae/hooks.json"),
                format: .flat(events: [
                    "sessionStart", "sessionEnd", "beforeSubmitPrompt", "postToolUse",
                    "afterShellExecution", "afterFileEdit", "afterAgentResponse", "stop",
                ], version: 1, extras: [:]),
                detectPaths: [at(".trae").path, "/Applications/Trae.app", at(".local/bin/trae").path],
                note: "ByteDance Trae IDE. Status and alerts."
            ),
            AgentIntegration(
                agent: .mimocode,
                configURL: at(".mimocode/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("PostToolUseFailure", .async),
                    ("PermissionRequest", .blocking(timeout: 600)), ("Notification", .async),
                    ("Stop", .async), ("StopFailure", .async),
                ]),
                detectPaths: [at(".mimocode").path, "/Applications/MiMoCode.app", at(".local/bin/mimocode").path],
                note: "MiMoCode agent. Approvals in the notch."
            ),
            AgentIntegration(
                agent: .devin,
                configURL: at(".devin/hooks.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("PostToolUseFailure", .async),
                    ("PermissionRequest", .blocking(timeout: 600)), ("Notification", .async),
                    ("Stop", .async), ("StopFailure", .async),
                ]),
                detectPaths: [at(".devin").path, "/Applications/Devin.app", at(".local/bin/devin").path, "/opt/homebrew/bin/devin"],
                note: "Devin CLI and app. Approvals in the notch."
            ),
            AgentIntegration(
                agent: .qoderwork,
                configURL: at(".qoderwork/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("PostToolUseFailure", .async),
                    ("PermissionRequest", .blocking(timeout: 600)), ("Notification", .async),
                    ("Stop", .async), ("StopFailure", .async),
                ]),
                detectPaths: [at(".qoderwork").path, "/Applications/QoderWork.app", at(".local/bin/qoderwork").path],
                note: "QoderWork multi-agent workspace. Approvals in the notch."
            ),
            AgentIntegration(
                agent: .qwenwork,
                configURL: at(".qwenwork/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("PermissionRequest", .async),
                    ("Notification", .async), ("Stop", .async), ("StopFailure", .async),
                ]),
                detectPaths: [at(".qwenwork").path, "/Applications/QwenWork.app", at(".local/bin/qwenwork").path],
                note: "QwenWork workspace. Status and alerts."
            ),
            AgentIntegration(
                agent: .deepseek,
                configURL: at(".deepseek/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("Stop", .async), ("StopFailure", .async),
                ]),
                detectPaths: [at(".deepseek").path, "/Applications/DeepSeek.app", at(".local/bin/deepseek").path, "/opt/homebrew/bin/deepseek", at(".local/bin/codewhale").path],
                note: "DeepSeek CLI and desktop. Status and replies."
            ),
            AgentIntegration(
                agent: .dsh,
                // dsh never reads a settings.json; hooks load only when its hooks-claude-code
                // bridge is mounted from a patch layer and pointed at a hooks file.
                configURL: at(".dsh/cordis.patch.yml"),
                format: .tomlBlock { _ in AgentPlugins.dshPatch(hooksPath: at(".dsh/pip-hooks.json").path) },
                detectPaths: [at(".dsh").path, at(".local/bin/dsh").path, "/opt/homebrew/bin/dsh"],
                note: "Status, tools and replies. Pip adds a marked block to cordis.patch.yml.",
                extraFiles: [(at(".dsh/pip-hooks.json"), AgentPlugins.dshHooks(bridgePath:))]
            ),
            AgentIntegration(
                agent: .codebuddy,
                configURL: at(".codebuddy/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("Stop", .async),
                ]),
                detectPaths: [at(".codebuddy").path, "/Applications/CodeBuddy.app", at(".local/bin/codebuddy").path],
                note: "CodeBuddy coding companion. Status and replies."
            ),
            AgentIntegration(
                agent: .workbuddy,
                configURL: at(".workbuddy/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("Stop", .async),
                ]),
                detectPaths: [at(".workbuddy").path, "/Applications/WorkBuddy.app", at(".local/bin/workbuddy").path],
                note: "WorkBuddy assistant. Status and replies."
            ),
            AgentIntegration(
                agent: .hermes,
                configURL: at(".hermes/hooks.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("Stop", .async),
                ]),
                detectPaths: [at(".hermes").path, at(".local/bin/hermes").path, "/opt/homebrew/bin/hermes"],
                note: "Hermes agent. Status and replies."
            ),
            AgentIntegration(
                agent: .amp,
                // Global settings; `.amp/settings.json` is Amp's per-project file.
                configURL: at(".config/amp/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("Stop", .async),
                ]),
                detectPaths: [at(".config/amp").path, at(".amp").path, at(".local/bin/amp").path, "/opt/homebrew/bin/amp"],
                note: "Amp agent. Status and replies."
            ),
            AgentIntegration(
                agent: .ohmypi,
                configURL: at(".ohmypi/extensions/pip.ts"),
                format: .ownedFile(AgentPlugins.ohmypi(bridgePath:)),
                detectPaths: [at(".ohmypi").path, at(".local/bin/ohmypi").path],
                note: "Status and replies. Restart Oh My Pi after connecting."
            ),
            AgentIntegration(
                agent: .gajaecode,
                configURL: at(".gajaecode/settings.json"),
                format: .claudeStyle([
                    ("SessionStart", .async), ("SessionEnd", .async), ("UserPromptSubmit", .async),
                    ("PreToolUse", .async), ("PostToolUse", .async), ("Stop", .async),
                ]),
                detectPaths: [at(".gajaecode").path, at(".gajae").path, at(".local/bin/gajaecode").path, "/Applications/Gajae.app"],
                note: "Gajae Code agent. Status and replies."
            ),
        ]
    }
}

/// Droid reads `~/.factory/hooks.json` when it exists, otherwise the `hooks` key of `settings.json`.
private func droidConfig(home: URL) -> URL {
    let hooks = home.appendingPathComponent(".factory/hooks.json")
    return FileManager.default.fileExists(atPath: hooks.path) ? hooks : home.appendingPathComponent(".factory/settings.json")
}

/// Pure transforms over a parsed config file. Pip's entries are recognised by the bridge path.
enum HookConfig {
    static let marker = "pip-bridge"
    static let antigravityKey = "pip"

    static func command(bridgePath: String, agent: AgentKind, event: String? = nil) -> String {
        var command = "\"\(bridgePath)\" \(agent.rawValue)"
        if let event { command += " \(event)" }
        return command
    }

    static func installing(_ format: AgentIntegration.Format, agent: AgentKind, bridgePath: String, into config: [String: Any]) -> [String: Any] {
        var result = removing(format, from: config)
        switch format {
        case .claudeStyle(let events):
            result["hooks"] = adding(events, agent: agent, bridgePath: bridgePath, to: result["hooks"] as? [String: Any] ?? [:])

        case .zcode(let events):
            var hooks = result["hooks"] as? [String: Any] ?? [:]
            hooks["enabled"] = true
            hooks["events"] = adding(events, agent: agent, bridgePath: bridgePath, to: hooks["events"] as? [String: Any] ?? [:])
            result["hooks"] = hooks

        case .flat(let events, let version, let extras):
            var hooks = result["hooks"] as? [String: Any] ?? [:]
            for event in events {
                var handler = extras
                handler["command"] = command(bridgePath: bridgePath, agent: agent)
                hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [handler]
            }
            result["hooks"] = hooks
            if let version, result["version"] == nil { result["version"] = version }

        case .ownedFile, .tomlBlock:
            break

        case .antigravity:
            func handler(_ event: String) -> [String: Any] {
                ["type": "command", "command": command(bridgePath: bridgePath, agent: agent, event: event), "timeout": 5]
            }
            result[antigravityKey] = [
                "enabled": true,
                "PostToolUse": [["matcher": ".*", "hooks": [handler("PostToolUse")]]],
                "PreInvocation": [handler("PreInvocation")],
                "Stop": [handler("Stop")],
            ] as [String: Any]
        }
        return result
    }

    static func removing(_ format: AgentIntegration.Format, from config: [String: Any]) -> [String: Any] {
        var result = config
        switch format {
        case .claudeStyle:
            guard let hooks = config["hooks"] as? [String: Any] else { return config }
            let kept = removingPip(from: hooks)
            result["hooks"] = kept.isEmpty ? nil : kept

        case .zcode:
            guard var hooks = config["hooks"] as? [String: Any] else { return config }
            let events = removingPip(from: hooks["events"] as? [String: Any] ?? [:])
            hooks["events"] = events.isEmpty ? nil : events
            // `enabled` alone is what Pip added; anything else in the block is the user's.
            if hooks.keys.allSatisfy({ $0 == "enabled" }) { hooks = [:] }
            result["hooks"] = hooks.isEmpty ? nil : hooks

        case .flat:
            guard var hooks = config["hooks"] as? [String: Any] else { return config }
            for (event, value) in hooks {
                guard let handlers = value as? [[String: Any]] else { continue }
                let kept = handlers.filter { !containsPip($0) }
                hooks[event] = kept.isEmpty ? nil : kept
            }
            result["hooks"] = hooks.isEmpty ? nil : hooks
            if result["hooks"] == nil, result.count == 1, result["version"] != nil {
                result["version"] = nil
            }

        case .antigravity:
            result[antigravityKey] = nil

        case .ownedFile, .tomlBlock:
            break
        }
        return result
    }

    /// Appends one Claude-style group per event, `{Event: [{"hooks": [handler]}]}`.
    private static func adding(_ events: [(event: String, mode: AgentIntegration.Mode)], agent: AgentKind, bridgePath: String, to hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for (event, mode) in events {
            var handler: [String: Any] = ["type": "command", "command": command(bridgePath: bridgePath, agent: agent)]
            switch mode {
            case .async: handler["async"] = true
            case .blocking(let timeout), .sync(let timeout): handler["timeout"] = timeout
            }
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [["hooks": [handler]]]
        }
        return hooks
    }

    /// Drops Pip's handlers from Claude-style groups, and groups and events left empty.
    private static func removingPip(from hooks: [String: Any]) -> [String: Any] {
        var hooks = hooks
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let remaining = handlers.filter { !containsPip($0) }
                if remaining.isEmpty { return nil }
                var copy = group
                copy["hooks"] = remaining
                return copy
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        return hooks
    }

    /// True if any string anywhere in `value` points at the bridge.
    static func containsPip(_ value: Any) -> Bool {
        switch value {
        case let string as String: string.contains(marker)
        case let dict as [String: Any]: dict.values.contains(where: containsPip)
        case let array as [Any]: array.contains(where: containsPip)
        default: false
        }
    }
}

/// Reads and writes a JSON config, refusing to touch files that aren't valid JSON objects.
struct HookFile {
    let url: URL

    func read() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookFileError.unreadable(url)
        }
        return object
    }

    func write(_ config: [String: Any]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConfigBackup.save(url)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

/// Keeps `<file>.pip-backup` as the user's last version without Pip's hooks.
enum ConfigBackup {
    static func url(for url: URL) -> URL { url.appendingPathExtension("pip-backup") }

    /// Refreshes the backup only from a file Pip hasn't touched, so repairs and
    /// reconnects never replace the original with a copy that already has Pip's hooks.
    static func save(_ url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let backup = self.url(for: url)
        let hasPip = (try? String(contentsOf: url, encoding: .utf8))?.contains(HookConfig.marker) ?? false
        if hasPip, fm.fileExists(atPath: backup.path) { return }
        try? fm.removeItem(at: backup)
        try fm.copyItem(at: url, to: backup)
    }
}

enum HookFileError: LocalizedError {
    case unreadable(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "\(url.path) isn't valid JSON, so Pip left it untouched."
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
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }
        return destination.path
    }
}

/// Pip's marked section inside a TOML file the user also edits.
enum TomlBlock {
    static let start = "# >>> Pip (managed by Pip; remove it in Pip Settings)"
    static let end = "# <<< Pip"

    static func wrap(_ body: String) -> String {
        "\(start)\n\(body.trimmingCharacters(in: .newlines))\n\(end)"
    }

    static func contains(_ text: String) -> Bool { extract(from: text) != nil }

    static func extract(from text: String) -> String? {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return nil }
        return String(text[a.lowerBound..<b.upperBound])
    }

    /// Replaces Pip's block, or appends it at the end, where `[[hooks]]` tables can't swallow the user's keys.
    static func installing(_ body: String, into text: String) -> String {
        var base = removing(from: text)
        if !base.isEmpty, !base.hasSuffix("\n") { base += "\n" }
        if !base.isEmpty { base += "\n" }
        return base + wrap(body) + "\n"
    }

    static func removing(from text: String) -> String {
        guard let block = extract(from: text), let range = text.range(of: block) else { return text }
        var result = text
        result.removeSubrange(range)
        // Tidy the blank lines Pip added around its block.
        while result.hasSuffix("\n\n") { result.removeLast() }
        if result == "\n" { result = "" }
        return result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
    }

    static func write(_ text: String, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ConfigBackup.save(url)
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}
