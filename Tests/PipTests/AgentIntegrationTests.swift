import XCTest
@testable import Pip

final class AgentIntegrationTests: XCTestCase {
    private let bridge = "/Users/me/Library/Application Support/Pip/bin/pip-bridge"

    private func integration(_ agent: AgentKind) -> AgentIntegration {
        AgentIntegration.all.first { $0.agent == agent }!
    }

    private func same(_ a: [String: Any], _ b: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(NSDictionary(dictionary: a), NSDictionary(dictionary: b), file: file, line: line)
    }

    // MARK: Claude Code

    private let claudeSettings: [String: Any] = [
        "model": "opus",
        "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "~/guard.sh"]]]]],
    ]

    func testClaudeInstallKeepsUserHooksAndOnlyApprovalsBlock() {
        let format = integration(.claude).format
        let result = HookConfig.installing(format, agent: .claude, bridgePath: bridge, into: claudeSettings)
        XCTAssertEqual(result["model"] as? String, "opus")
        let hooks = result["hooks"] as! [String: Any]
        XCTAssertEqual((hooks["PreToolUse"] as! [[String: Any]]).count, 2)

        let permission = ((hooks["PermissionRequest"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        XCTAssertEqual(permission["timeout"] as? Int, 600)
        XCTAssertNil(permission["async"])
        XCTAssertEqual(permission["command"] as? String, "\"\(bridge)\" claude")
        let stop = ((hooks["Stop"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        XCTAssertEqual(stop["async"] as? Bool, true)
    }

    func testEveryFormatIsIdempotentAndUninstallsCleanly() {
        let originals: [AgentKind: [String: Any]] = [
            .claude: claudeSettings,
            .codex: [:],
            .cursor: ["version": 1, "hooks": ["stop": [["command": "./notify.sh"]]]],
            .antigravity: ["my-check": ["enabled": true, "Stop": [["type": "command", "command": "./x.sh"]]]],
            .windsurf: ["hooks": ["pre_run_command": [["command": "./guard.sh", "show_output": true]]]],
        ]
        for (agent, original) in originals {
            let format = integration(agent).format
            let once = HookConfig.installing(format, agent: agent, bridgePath: bridge, into: original)
            let twice = HookConfig.installing(format, agent: agent, bridgePath: bridge, into: once)
            XCTAssertTrue(HookConfig.containsPip(once), "\(agent)")
            same(once, twice)
            same(HookConfig.removing(format, from: once), original)
        }
    }

    func testCodexSessionEndRunsInlineWithShortTimeout() {
        let hooks = HookConfig.installing(integration(.codex).format, agent: .codex, bridgePath: bridge, into: [:])["hooks"] as! [String: Any]
        let end = ((hooks["SessionEnd"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        XCTAssertEqual(end["timeout"] as? Int, 3)
        XCTAssertNil(end["async"])
        XCTAssertEqual(end["command"] as? String, "\"\(bridge)\" codex")
    }

    func testCursorFormatUsesFlatCommandsAndVersion() {
        let result = HookConfig.installing(integration(.cursor).format, agent: .cursor, bridgePath: bridge, into: [:])
        XCTAssertEqual(result["version"] as? Int, 1)
        let hooks = result["hooks"] as! [String: Any]
        XCTAssertEqual(hooks["stop"] as? [[String: String]], [["command": "\"\(bridge)\" cursor"]])
        XCTAssertNil(hooks["beforeShellExecution"], "Pip must never answer Cursor's permission hooks")
        XCTAssertTrue(HookConfig.removing(integration(.cursor).format, from: result).isEmpty)
    }

    func testAntigravityPassesEventNameOnTheCommandLine() {
        let result = HookConfig.installing(.antigravity, agent: .antigravity, bridgePath: bridge, into: [:])
        let pip = result["pip"] as! [String: Any]
        let stop = (pip["Stop"] as! [[String: Any]])[0]
        XCTAssertEqual(stop["command"] as? String, "\"\(bridge)\" antigravity Stop")
        let post = (pip["PostToolUse"] as! [[String: Any]])[0]
        XCTAssertEqual(post["matcher"] as? String, ".*")
        XCTAssertNil(pip["PreToolUse"], "Pip must never answer Antigravity's permission decisions")
    }

    // MARK: Files

    func testFileRoundTripWritesBackupAndRefusesInvalidJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("hooks.json")
        let codex = AgentIntegration(agent: .codex, configURL: url, format: integration(.codex).format, detectPaths: [], note: nil)
        XCTAssertFalse(codex.isInstalled())
        try codex.install(bridgePath: bridge)
        XCTAssertTrue(codex.isInstalled())
        try codex.install(bridgePath: bridge)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("pip-backup").path))
        try codex.uninstall()
        XCTAssertFalse(codex.isInstalled())

        try Data("{ not json".utf8).write(to: url)
        XCTAssertThrowsError(try codex.install(bridgePath: bridge))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{ not json")
    }

    func testRepeatedInstallsKeepTheOriginalBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("hooks.json")
        let backup = url.appendingPathExtension("pip-backup")
        let original = #"{"theme":"dark"}"#
        try Data(original.utf8).write(to: url)
        let codex = AgentIntegration(agent: .codex, configURL: url, format: integration(.codex).format, detectPaths: [], note: nil)

        try codex.install(bridgePath: bridge)
        try codex.uninstall()
        try codex.install(bridgePath: bridge)
        try codex.install(bridgePath: "/other/pip-bridge")
        let saved = try String(contentsOf: backup, encoding: .utf8)
        XCTAssertFalse(saved.contains(HookConfig.marker))
        XCTAssertTrue(saved.contains("dark"))
    }
}

final class AgentAdapterTests: XCTestCase {
    func testCursorEventsMapToClaudeShape() {
        let prompt = AgentAdapter.cursor([
            "hook_event_name": "beforeSubmitPrompt", "conversation_id": "c1",
            "workspace_roots": ["/Users/me/app"], "prompt": "hi",
        ])
        XCTAssertEqual(prompt["hook_event_name"] as? String, "UserPromptSubmit")
        XCTAssertEqual(prompt["session_id"] as? String, "c1")
        XCTAssertEqual(prompt["cwd"] as? String, "/Users/me/app")

        let shell = AgentAdapter.cursor(["hook_event_name": "afterShellExecution", "conversation_id": "c1", "command": "ls"])
        XCTAssertEqual(shell["tool_name"] as? String, "Bash")
        XCTAssertEqual((shell["tool_input"] as? [String: String])?["command"], "ls")

        XCTAssertEqual(AgentAdapter.cursor(["hook_event_name": "stop", "status": "error"])["hook_event_name"] as? String, "StopFailure")
        XCTAssertEqual(AgentAdapter.cursor(["hook_event_name": "stop", "status": "completed"])["hook_event_name"] as? String, "Stop")
    }

    func testAntigravityEventsMapToClaudeShape() {
        let tool = AgentAdapter.antigravity([
            "hook_event_name": "PostToolUse", "conversationId": "g1",
            "workspacePaths": ["file:///Users/me/data"],
            "toolCall": ["name": "run_command", "args": ["CommandLine": "pytest"]],
        ])
        XCTAssertEqual(tool["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(tool["session_id"] as? String, "g1")
        XCTAssertEqual(tool["cwd"] as? String, "/Users/me/data")
        XCTAssertEqual((tool["tool_input"] as? [String: String])?["command"], "pytest")

        let edit = AgentAdapter.antigravityTool(name: "replace_file_content", args: ["TargetFile": "/a/b.swift"])
        XCTAssertEqual(edit.0, "Edit")
        XCTAssertEqual(AgentAdapter.antigravity(["hook_event_name": "Stop", "error": "boom"])["hook_event_name"] as? String, "StopFailure")
        XCTAssertEqual(AgentAdapter.antigravity(["hook_event_name": "PreInvocation"])["hook_event_name"] as? String, "AgentActive")
    }

    @MainActor
    func testEditorSessionsFlowThroughStore() {
        let store = SessionStore()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        store.handle(HookEnvelope(agent: .antigravity, pid: nil, payload: ["hook_event_name": "PreInvocation", "conversationId": "g"]), at: t0)
        XCTAssertEqual(store.sessions["g"]?.state, .working)
        store.handle(HookEnvelope(agent: .cursor, pid: nil, payload: ["hook_event_name": "afterAgentResponse", "conversation_id": "c", "text": "Done!\nmore"]), at: t0)
        store.handle(HookEnvelope(agent: .cursor, pid: nil, payload: ["hook_event_name": "stop", "conversation_id": "c", "status": "completed"]), at: t0)
        XCTAssertEqual(store.sessions["c"]?.state, .finished)
        XCTAssertEqual(store.sessions["c"]?.lastMessage, "Done!")

        store.tick(at: t0.addingTimeInterval(SessionStore.ideQuietAfter + 1))
        XCTAssertTrue(store.sessions.isEmpty, "quiet editor sessions expire")
    }
}

final class SynthTests: XCTestCase {
    func testEveryCueRendersAudibleClippingFreeAudio() {
        for cue in SoundCue.allCases {
            let samples = Synth.render(Synth.notes(for: cue))
            XCTAssertGreaterThan(samples.count, Int(Synth.sampleRate * 0.4), "\(cue)")
            let peak = samples.map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.1, "\(cue) is audible")
            XCTAssertLessThan(peak, 1.0, "\(cue) never clips")
        }
    }
}
