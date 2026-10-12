import XCTest
@testable import Pip

final class AllAgentsTests: XCTestCase {
    private let bridge = "/Users/me/Library/Application Support/Pip/bin/pip-bridge"

    func testAllAgentKindCasesHaveInitialsAndTints() {
        for agent in AgentKind.allCases {
            XCTAssertFalse(agent.displayName.isEmpty, "Agent \(agent) should have a display name")
            XCTAssertEqual(agent.initials.count, 2, "Agent \(agent) should have a 2-letter initials")
            _ = agent.tint
        }
    }

    func testVibeIslandAgentsRawMapping() {
        let expectedMappings: [String: AgentKind] = [
            "claude": .claude,
            "claude-code": .claude,
            "claudecode": .claude,
            "codex": .codex,
            "zcode": .zcode,
            "z-code": .zcode,
            "gemini": .gemini,
            "gemini-cli": .gemini,
            "geminicli": .gemini,
            "antigravity": .antigravity,
            "antigravity-cli": .antigravity,
            "agy": .antigravity,
            "cursor": .cursor,
            "cursor-agent": .cursor,
            "trae": .trae,
            "opencode": .opencode,
            "open-code": .opencode,
            "mimocode": .mimocode,
            "mimo-code": .mimocode,
            "droid": .droid,
            "factory-droid": .droid,
            "devin": .devin,
            "qoder": .qoder,
            "qoder-cli": .qoder,
            "qodercn": .qoder,
            "qoderwork": .qoderwork,
            "qoder-work": .qoderwork,
            "qwen": .qwen,
            "qwen-code": .qwen,
            "qwencode": .qwen,
            "qwenwork": .qwenwork,
            "qwen-work": .qwenwork,
            "grok": .grok,
            "grok-build": .grok,
            "grokbuild": .grok,
            "kimi": .kimi,
            "kimi-code": .kimi,
            "kimicode": .kimi,
            "deepseek": .deepseek,
            "deepseek-cli": .deepseek,
            "codewhale": .deepseek,
            "dsh": .dsh,
            "deepseek-harness": .dsh,
            "deepseekharness": .dsh,
            "vibe": .vibe,
            "mistral-vibe": .vibe,
            "mistralvibe": .vibe,
            "copilot": .copilot,
            "copilot-cli": .copilot,
            "codebuddy": .codebuddy,
            "code-buddy": .codebuddy,
            "workbuddy": .workbuddy,
            "work-buddy": .workbuddy,
            "kiro": .kiro,
            "kiro-cli": .kiro,
            "hermes": .hermes,
            "hermes-agent": .hermes,
            "amp": .amp,
            "pi": .pi,
            "pi-agent": .pi,
            "ohmypi": .ohmypi,
            "oh-my-pi": .ohmypi,
            "gajaecode": .gajaecode,
            "gajae-code": .gajaecode,
            "gajae": .gajaecode,
            "augment": .augment,
            "auggie": .augment,
            "goose": .goose,
            "windsurf": .windsurf,
        ]

        for (raw, expectedKind) in expectedMappings {
            XCTAssertEqual(AgentKind(raw: raw), expectedKind, "Raw '\(raw)' should map to \(expectedKind)")
        }
    }

    func testIsIDEFlag() {
        XCTAssertTrue(AgentKind.cursor.isIDE)
        XCTAssertTrue(AgentKind.grokBot.isIDE)
        XCTAssertTrue(AgentKind.windsurf.isIDE)
        XCTAssertTrue(AgentKind.antigravity.isIDE)
        XCTAssertTrue(AgentKind.trae.isIDE)
        XCTAssertFalse(AgentKind.claude.isIDE)
        XCTAssertFalse(AgentKind.codex.isIDE)
        XCTAssertFalse(AgentKind.zcode.isIDE)
        XCTAssertFalse(AgentKind.devin.isIDE)
    }

    func testTraeEventNormalization() {
        // Cursor-like payload
        let cursorStyle = AgentAdapter.trae([
            "hook_event_name": "beforeSubmitPrompt",
            "conversation_id": "conv-123",
            "prompt": "Fix bug",
        ])
        XCTAssertEqual(cursorStyle["hook_event_name"] as? String, "UserPromptSubmit")
        XCTAssertEqual(cursorStyle["session_id"] as? String, "conv-123")
        XCTAssertEqual(cursorStyle["prompt"] as? String, "Fix bug")

        // Shell execution
        let shellStyle = AgentAdapter.trae([
            "hook_event_name": "afterShellExecution",
            "conversation_id": "conv-123",
            "command": "cargo check",
        ])
        XCTAssertEqual(shellStyle["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(shellStyle["tool_name"] as? String, "Bash")
        XCTAssertEqual((shellStyle["tool_input"] as? [String: Any])?["command"] as? String, "cargo check")

        // Claude / generic style payload
        let genericStyle = AgentAdapter.trae([
            "hook_event_name": "PreToolUse",
            "session_id": "trae-session",
            "tool_name": "run_command",
            "tool_input": ["command": "pytest"],
        ])
        XCTAssertEqual(genericStyle["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(genericStyle["session_id"] as? String, "trae-session")
        XCTAssertEqual(genericStyle["tool_name"] as? String, "Bash")
    }

    func testNewAgentsNormalizationThroughAdapter() {
        let agentsWithClaudeStyle: [AgentKind] = [
            .zcode, .mimocode, .devin, .qoderwork, .dsh, .deepseek,
            .codebuddy, .workbuddy, .hermes, .amp, .gajaecode,
        ]

        for agent in agentsWithClaudeStyle {
            let normalized = AgentAdapter.normalize([
                "hook_event_name": "PreToolUse",
                "session_id": "\(agent.rawValue)-session",
                "tool_name": "run_shell_command",
                "tool_input": ["command": "echo hello"],
            ], agent: agent)

            XCTAssertEqual(normalized["hook_event_name"] as? String, "PreToolUse", "\(agent)")
            XCTAssertEqual(normalized["tool_name"] as? String, "Bash", "\(agent)")
            XCTAssertEqual((normalized["tool_input"] as? [String: Any])?["command"] as? String, "echo hello", "\(agent)")
        }

        // QwenWork permission request
        let qwenworkNorm = AgentAdapter.normalize([
            "hook_event_name": "PermissionRequest",
            "session_id": "qw1",
        ], agent: .qwenwork)
        XCTAssertEqual(qwenworkNorm["hook_event_name"] as? String, "Notification")
        XCTAssertEqual(qwenworkNorm["notification_type"] as? String, "agent_needs_input")
    }

    func testOhMyPiExtensionGeneratesValidScript() {
        let script = AgentPlugins.ohmypi(bridgePath: bridge)
        XCTAssertTrue(script.contains("Pip: shows Oh My Pi sessions in the MacBook notch"))
        XCTAssertTrue(script.contains("\"ohmypi\""))
        XCTAssertTrue(script.contains(bridge))
    }

    func testNewAgentIntegrationsExistAndCanInstall() throws {
        let newAgents: [AgentKind] = [
            .zcode, .trae, .mimocode, .devin, .qoderwork, .qwenwork,
            .deepseek, .dsh, .codebuddy, .workbuddy, .hermes, .amp,
            .ohmypi, .gajaecode,
        ]

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pip-agent-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        for agent in newAgents {
            guard let integration = AgentIntegration.all.first(where: { $0.agent == agent }) else {
                XCTFail("Missing integration for \(agent)")
                continue
            }

            let fakeConfigURL = dir.appendingPathComponent("\(agent.rawValue)/config.json")
            let testIntegration = AgentIntegration(
                agent: agent,
                configURL: fakeConfigURL,
                format: integration.format,
                detectPaths: integration.detectPaths,
                note: integration.note,
                extraFiles: integration.extraFiles
            )

            XCTAssertFalse(testIntegration.isInstalled())
            try testIntegration.install(bridgePath: bridge)
            XCTAssertTrue(testIntegration.isInstalled(), "\(agent) failed isInstalled")
            try testIntegration.uninstall()
            XCTAssertFalse(testIntegration.isInstalled(bridgePath: bridge), "\(agent) failed uninstall")
        }
    }
}
