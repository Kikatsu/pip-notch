import XCTest
@testable import Pip

@MainActor
final class UsageLimitsTests: XCTestCase {
    func testClaudeStatusLineLimits() {
        let store = UsageStore(codexHome: URL(fileURLWithPath: "/nonexistent"))
        let now = Date(timeIntervalSince1970: 1_000_000)
        store.updateClaude([
            "five_hour": ["used_percentage": 23.5, "resets_at": 1_003_600],
            "seven_day": ["used_percentage": 41.2, "resets_at": 1_500_000],
        ], at: now)
        XCTAssertEqual(store.limits.map(\.window), [.fiveHour, .weekly])
        XCTAssertEqual(store.limits.first?.usedPercent, 23.5)

        store.tick(at: Date(timeIntervalSince1970: 1_004_000))
        XCTAssertEqual(store.limits.map(\.window), [.weekly], "a window disappears once it resets")
    }

    func testCodexSessionLogLimits() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let day = home.appendingPathComponent("sessions/2026/10/12")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let lines = [
            #"{"timestamp":"2026-10-12T10:00:00.000Z","type":"event_msg","payload":{"type":"user_message"}}"#,
            #"{"timestamp":"2026-10-12T10:00:05.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_in_seconds":3600},"secondary":{"used_percent":55.5,"window_minutes":10080,"resets_at":1791800000}}}}"#,
        ]
        try lines.joined(separator: "\n").write(to: day.appendingPathComponent("rollout-x.jsonl"), atomically: true, encoding: .utf8)

        let store = UsageStore(codexHome: home)
        store.refreshCodex(at: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(store.limits.count, 2)
        let five = try XCTUnwrap(store.limits.first { $0.window == .fiveHour })
        XCTAssertEqual(five.provider, .codex)
        XCTAssertEqual(five.usedPercent, 12)
        XCTAssertEqual(five.resetsAt, ISO8601DateFormatter().date(from: "2026-10-12T11:00:05Z"))
        XCTAssertEqual(store.limits.first { $0.window == .weekly }?.usedPercent, 55.5)
    }

    func testStatusLineInstallKeepsAndRestoresTheUsersOwn() {
        let bridge = "/Applications/Pip.app/pip-bridge"
        let mine: [String: Any] = ["model": "opus", "statusLine": ["type": "command", "command": "~/my-line.sh", "padding": 1]]
        let (installed, original) = ClaudeStatusLine.installing(into: mine, bridgePath: bridge)
        let line = installed["statusLine"] as? [String: Any]
        XCTAssertEqual(line?["command"] as? String, "\"\(bridge)\" claude-statusline")
        XCTAssertEqual(line?["padding"] as? Int, 1)
        XCTAssertEqual(original?["command"] as? String, "~/my-line.sh")

        let reinstalled = ClaudeStatusLine.installing(into: installed, bridgePath: bridge)
        XCTAssertNil(reinstalled.original, "Pip never saves its own line as the user's")

        let restored = ClaudeStatusLine.removing(from: installed, original: original)
        XCTAssertEqual(NSDictionary(dictionary: restored), NSDictionary(dictionary: mine))
        XCTAssertNil(ClaudeStatusLine.removing(from: ClaudeStatusLine.installing(into: [:], bridgePath: bridge).settings, original: nil)["statusLine"])
    }

    func testGenericAgentAliases() {
        let payload = AgentAdapter.generic(["event": "PreToolUse", "sessionId": "x", "working_dir": "/w", "toolName": "shell", "toolArgs": ["command": "ls"]])
        XCTAssertEqual(payload["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(payload["session_id"] as? String, "x")
        XCTAssertEqual(payload["cwd"] as? String, "/w")
        XCTAssertEqual(payload["tool_name"] as? String, "Bash")
    }

    func testCustomAgentKeepsItsName() throws {
        let line = #"{"v":1,"agent":"my-agent","pid":7,"env":{},"payload":{"hook_event_name":"Stop","session_id":"s","cwd":"/w"}}"#
        let envelope = try XCTUnwrap(HookEnvelope(data: Data(line.utf8)))
        let store = SessionStore()
        store.handle(envelope)
        XCTAssertEqual(store.sessions["s"]?.agentName, "My-agent")
    }

    func testAugmentAndGoose() {
        let augment = AgentAdapter.augment(["hook_event_name": "Stop", "conversation_id": "c", "workspace_roots": ["/w"], "agent_stop_cause": "error"])
        XCTAssertEqual(augment["hook_event_name"] as? String, "StopFailure")
        XCTAssertEqual(augment["session_id"] as? String, "c")
        let goose = AgentAdapter.goose(["event": "UserPromptSubmit", "session_id": "g", "working_dir": "/w", "message": "hi"])
        XCTAssertEqual(goose["hook_event_name"] as? String, "UserPromptSubmit")
        XCTAssertEqual(goose["prompt"] as? String, "hi")
        XCTAssertEqual(goose["cwd"] as? String, "/w")
    }

    func testGooseInstallsBothPluginFilesAndRemovesThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let hooks = root.appendingPathComponent("pip/hooks/hooks.json")
        let manifest = root.appendingPathComponent("pip/plugin.json")
        let goose = AgentIntegration(agent: .goose, configURL: hooks, format: .ownedFile(AgentPlugins.goose(bridgePath:)),
                                     detectPaths: [], note: nil, extraFiles: [(manifest, AgentPlugins.gooseManifest(bridgePath:))])
        try goose.install(bridgePath: "/b/pip-bridge")
        XCTAssertTrue(goose.isInstalled())
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)))
        try goose.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: hooks.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
    }
}
