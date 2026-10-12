import XCTest
@testable import Pip

final class ZCodeHooksTests: XCTestCase {
    private let bridge = "/Users/me/Library/Application Support/Pip/bin/pip-bridge"
    private var format: AgentIntegration.Format { AgentIntegration.all.first { $0.agent == .zcode }!.format }

    func testUsesTheUserCLIConfig() {
        let zcode = AgentIntegration.all.first { $0.agent == .zcode }!
        XCTAssertTrue(zcode.configURL.path.hasSuffix("/.zcode/cli/config.json"))
    }

    func testEnablesHooksUnderEventsAndKeepsTheRestOfTheConfig() throws {
        let config: [String: Any] = ["mcpServers": ["fs": ["command": "npx"]]]
        let installed = HookConfig.installing(format, agent: .zcode, bridgePath: bridge, into: config)

        XCTAssertNotNil(installed["mcpServers"])
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        XCTAssertEqual(hooks["enabled"] as? Bool, true, "ZCode runs no hooks unless enabled")
        let events = try XCTUnwrap(hooks["events"] as? [String: Any])
        XCTAssertEqual(Set(events.keys), ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                          "PostToolUseFailure", "PermissionRequest", "Stop"])
        let permission = try XCTUnwrap((events["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])
        XCTAssertEqual(permission.first?["timeout"] as? Int, 600)
        XCTAssertNil(permission.first?["async"], "Approvals must wait for the answer")

        let removed = HookConfig.removing(format, from: installed)
        XCTAssertNil(removed["hooks"], "Nothing of Pip's is left behind")
        XCTAssertNotNil(removed["mcpServers"])
    }

    func testLeavesTheUsersOwnHooksAndSwitchOn() throws {
        let mine: [String: Any] = ["matcher": "Write|Edit", "hooks": [["type": "command", "command": "lint.sh"]]]
        let config: [String: Any] = ["hooks": ["enabled": true, "timeoutMs": 30000, "events": ["PreToolUse": [mine]]]]
        let installed = HookConfig.installing(format, agent: .zcode, bridgePath: bridge, into: config)
        let preToolUse = ((installed["hooks"] as? [String: Any])?["events"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        XCTAssertEqual(preToolUse?.count, 2)

        let removed = HookConfig.removing(format, from: installed)
        let hooks = try XCTUnwrap(removed["hooks"] as? [String: Any])
        XCTAssertEqual(hooks["enabled"] as? Bool, true)
        XCTAssertEqual(hooks["timeoutMs"] as? Int, 30000)
        let events = try XCTUnwrap(hooks["events"] as? [String: Any])
        XCTAssertEqual(Array(events.keys), ["PreToolUse"])
        XCTAssertEqual((events["PreToolUse"] as? [[String: Any]])?.count, 1)
    }
}
