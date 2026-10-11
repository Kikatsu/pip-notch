import XCTest
@testable import Pip

final class MoreAgentsTests: XCTestCase {
    private let bridge = "/Users/me/Library/Application Support/Pip/bin/pip-bridge"

    func testCanonicalToolNames() {
        XCTAssertEqual(AgentAdapter.canonicalTool(name: "run_shell_command", input: ["command": "ls"]).0, "Bash")
        XCTAssertEqual(AgentAdapter.canonicalTool(name: "bash", input: ["command": "ls"]).1["command"] as? String, "ls")
        XCTAssertEqual(AgentAdapter.canonicalTool(name: "write_file", input: ["file_path": "/a"]).0, "Edit")
        XCTAssertEqual(AgentAdapter.canonicalTool(name: "edit", input: ["path": "/a"]).1["file_path"] as? String, "/a")
        XCTAssertEqual(AgentAdapter.canonicalTool(name: "read", input: ["filePath": "/a"]).0, "Read")
        XCTAssertEqual(AgentAdapter.canonicalTool(name: "Bash", input: ["command": "x"]).0, "Bash", "Claude's own names are kept")
        XCTAssertEqual(AgentAdapter.canonicalTool(name: "web_search", input: ["q": "x"]).0, "web_search")
    }

    func testGeminiEvents() {
        let after = AgentAdapter.gemini(["hook_event_name": "AfterAgent", "session_id": "g", "prompt_response": "Done"])
        XCTAssertEqual(after["hook_event_name"] as? String, "Stop")
        XCTAssertEqual(after["last_assistant_message"] as? String, "Done")
        let tool = AgentAdapter.gemini(["hook_event_name": "BeforeTool", "tool_name": "run_shell_command", "tool_input": ["command": "make"]])
        XCTAssertEqual(tool["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(tool["tool_name"] as? String, "Bash")
        let note = AgentAdapter.gemini(["hook_event_name": "Notification", "notification_type": "ToolPermission"])
        XCTAssertEqual(note["notification_type"] as? String, "agent_needs_input")
    }

    func testCopilotEvents() {
        let tool = AgentAdapter.copilot(["hook_event_name": "preToolUse", "sessionId": "c", "cwd": "/w", "toolName": "bash", "toolArgs": #"{"command":"npm test"}"#])
        XCTAssertEqual(tool["session_id"] as? String, "c")
        XCTAssertEqual(tool["tool_name"] as? String, "Bash")
        XCTAssertEqual((tool["tool_input"] as? [String: Any])?["command"] as? String, "npm test")
        XCTAssertEqual(AgentAdapter.copilot(["hook_event_name": "agentStop"])["hook_event_name"] as? String, "Stop")
        XCTAssertEqual(AgentAdapter.copilot(["hook_event_name": "notification", "notification_type": "permission_prompt"])["notification_type"] as? String, "agent_needs_input")
    }

    func testDroidPermissionPromptNeedsYou() {
        let note = AgentAdapter.droid(["hook_event_name": "Notification", "notification_type": "permission_prompt"])
        XCTAssertEqual(note["notification_type"] as? String, "agent_needs_input")
    }

    @MainActor
    func testOpenCodeAndPiFlowThroughStore() {
        let store = SessionStore()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        store.handle(HookEnvelope(agent: .opencode, pid: nil, payload: ["hook_event_name": "AgentActive", "session_id": "opencode-1", "cwd": "/w/site"]), at: t0)
        store.handle(HookEnvelope(agent: .opencode, pid: nil, payload: ["hook_event_name": "PreToolUse", "session_id": "opencode-1", "tool_name": "bash", "tool_input": ["command": "bun test"]]), at: t0)
        XCTAssertEqual(store.sessions["opencode-1"]?.currentTool, "Bash · bun test")
        store.handle(HookEnvelope(agent: .pi, pid: nil, payload: ["hook_event_name": "Stop", "session_id": "pi-9", "last_assistant_message": "All set"]), at: t0)
        XCTAssertEqual(store.sessions["pi-9"]?.lastMessage, "All set")
        XCTAssertEqual(store.sessions["pi-9"]?.state, .finished)
    }

    func testOwnedFilesInstallAndRemoveCompletely() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        for (agent, contents) in [(AgentKind.opencode, AgentPlugins.openCode), (.pi, AgentPlugins.pi), (.copilot, AgentPlugins.copilot)] {
            let url = dir.appendingPathComponent("\(agent.rawValue)/pip")
            let integration = AgentIntegration(agent: agent, configURL: url, format: .ownedFile(contents), detectPaths: [], note: nil)
            XCTAssertFalse(integration.isInstalled())
            try integration.install(bridgePath: bridge)
            XCTAssertTrue(integration.isInstalled(), "\(agent)")
            try integration.uninstall()
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "\(agent)")
        }
    }

    func testCopilotHooksFileIsValidAndNamesEachEvent() throws {
        let data = Data(AgentPlugins.copilot(bridgePath: bridge).utf8)
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(config["version"] as? Int, 1)
        let hooks = try XCTUnwrap(config["hooks"] as? [String: [[String: Any]]])
        XCTAssertEqual(hooks["agentStop"]?.first?["bash"] as? String, "\"\(bridge)\" copilot agentStop")
        XCTAssertNil(hooks["permissionRequest"], "Copilot's permissionRequest fires for auto-approved tools too; Pip stays out of it")
    }

    func testGeminiInstallUsesMillisecondTimeoutsAndNoAsync() {
        let gemini = AgentIntegration.all.first { $0.agent == .gemini }!
        let hooks = HookConfig.installing(gemini.format, agent: .gemini, bridgePath: bridge, into: [:])["hooks"] as! [String: Any]
        let handler = ((hooks["BeforeTool"] as! [[String: Any]])[0]["hooks"] as! [[String: Any]])[0]
        XCTAssertEqual(handler["timeout"] as? Int, 5000)
        XCTAssertNil(handler["async"])
    }

    /// Writes the generated plugin sources where a syntax check can read them.
    func testWritePluginSourcesForSyntaxCheck() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pip-plugin-check")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try AgentPlugins.openCode(bridgePath: bridge).write(to: dir.appendingPathComponent("pip.mjs"), atomically: true, encoding: .utf8)
        try AgentPlugins.pi(bridgePath: bridge).write(to: dir.appendingPathComponent("pip.mts"), atomically: true, encoding: .utf8)
    }
}
