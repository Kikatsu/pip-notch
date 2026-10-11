import XCTest
@testable import Pip

final class MoreCLIsTests: XCTestCase {
    private let bridge = "/Users/me/Library/Application Support/Pip/bin/pip-bridge"

    func testTomlBlockKeepsUserContentAndRoundTrips() {
        let user = "model = \"kimi-k2\"\n\n[[hooks]]\nevent = \"Stop\"\ncommand = \"say done\"\n"
        let body = AgentPlugins.kimi(bridgePath: bridge)
        let installed = TomlBlock.installing(body, into: user)
        XCTAssertTrue(installed.hasPrefix(user), "user lines stay first and untouched")
        XCTAssertTrue(TomlBlock.contains(installed))
        XCTAssertEqual(TomlBlock.installing(body, into: installed), installed, "installing twice changes nothing")
        XCTAssertEqual(TomlBlock.removing(from: installed), user)
        XCTAssertEqual(TomlBlock.removing(from: TomlBlock.installing(body, into: "")), "")
    }

    func testKimiEntriesUseOnlyAllowedFieldsAndLiteralQuoting() {
        let body = AgentPlugins.kimi(bridgePath: bridge)
        for line in body.split(separator: "\n") where line.contains("=") {
            let key = line.split(separator: "=")[0].trimmingCharacters(in: .whitespaces)
            XCTAssertTrue(["event", "matcher", "command", "timeout"].contains(key), "Kimi rejects unknown field \(key)")
        }
        XCTAssertTrue(body.contains("command = '\"\(bridge)\" kimi'"))
    }

    func testVibeEntriesHaveUniqueNames() {
        let names = AgentPlugins.vibe(bridgePath: bridge).split(separator: "\n").filter { $0.hasPrefix("name =") }
        XCTAssertEqual(Set(names).count, 3)
    }

    func testTomlIntegrationOnDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)/hooks.toml")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "# my hooks\n".write(to: url, atomically: true, encoding: .utf8)
        let vibe = AgentIntegration(agent: .vibe, configURL: url, format: .tomlBlock(AgentPlugins.vibe(bridgePath:)), detectPaths: [], note: nil)
        try vibe.install(bridgePath: bridge)
        XCTAssertTrue(vibe.isInstalled(bridgePath: bridge))
        XCTAssertFalse(vibe.isInstalled(bridgePath: "/elsewhere/pip-bridge"), "a moved bridge counts as needing repair")
        try vibe.uninstall()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "# my hooks\n")
    }

    func testGrokCamelCasePayload() {
        let p = AgentAdapter.normalize(["hookEventName": "PreToolUse", "sessionId": "g1", "workspaceRoot": "/w", "toolName": "Bash", "toolInput": ["command": "ls"]], agent: .grok)
        XCTAssertEqual(p["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(p["session_id"] as? String, "g1")
        XCTAssertEqual(p["cwd"] as? String, "/w")
        XCTAssertEqual(p["tool_name"] as? String, "Bash")
    }

    func testVibeAndKimiEvents() {
        XCTAssertEqual(AgentAdapter.vibe(["hook_event_name": "post_agent"])["hook_event_name"] as? String, "Stop")
        XCTAssertEqual(AgentAdapter.vibe(["hook_event_name": "pre_tool", "tool_name": "bash", "tool_input": ["command": "ls"]])["tool_name"] as? String, "Bash")
        let kimi = AgentAdapter.observingPermissions(["hook_event_name": "PermissionRequest"])
        XCTAssertEqual(kimi["notification_type"] as? String, "agent_needs_input")
    }
}
