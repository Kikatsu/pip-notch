import XCTest
@testable import Pip

final class KiroWindsurfTests: XCTestCase {
    private let bridge = "/Users/me/Library/Application Support/Pip/bin/pip-bridge"

    func testWindsurfEventsMapToClaudeShape() {
        let command = AgentAdapter.windsurf([
            "agent_action_name": "post_run_command", "trajectory_id": "t1",
            "tool_info": ["command_line": "npm test", "cwd": "/w/app"],
        ])
        XCTAssertEqual(command["session_id"] as? String, "t1")
        XCTAssertEqual(command["cwd"] as? String, "/w/app")
        XCTAssertEqual(command["tool_name"] as? String, "Bash")
        let done = AgentAdapter.windsurf(["agent_action_name": "post_cascade_response", "trajectory_id": "t1", "tool_info": ["response": "Fixed it"]])
        XCTAssertEqual(done["hook_event_name"] as? String, "Stop")
        XCTAssertEqual(done["last_assistant_message"] as? String, "Fixed it")
    }

    func testWindsurfConfigKeepsUserHooksAndHidesPipOutput() {
        let windsurf = AgentIntegration.all.first { $0.agent == .windsurf }!
        let mine: [String: Any] = ["hooks": ["pre_run_command": [["command": "./guard.sh"]]]]
        let result = HookConfig.installing(windsurf.format, agent: .windsurf, bridgePath: bridge, into: mine)
        XCTAssertNil(result["version"], "Windsurf's file has no version key")
        let hooks = result["hooks"] as! [String: [[String: Any]]]
        XCTAssertEqual(hooks["pre_run_command"]?.count, 1, "Pip doesn't touch pre-hooks that can block")
        XCTAssertEqual(hooks["post_run_command"]?.first?["show_output"] as? Bool, false)
    }

    func testKiroHooksFileNamesEachTrigger() throws {
        let data = Data(AgentPlugins.kiro(bridgePath: bridge).utf8)
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(config["version"] as? String, "v1")
        let hooks = try XCTUnwrap(config["hooks"] as? [[String: Any]])
        XCTAssertEqual(hooks.map { $0["trigger"] as? String }, ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"])
        let action = try XCTUnwrap(hooks.last?["action"] as? [String: Any])
        XCTAssertEqual(action["command"] as? String, "\"\(bridge)\" kiro Stop")
    }

    func testKiroToolTagsAndResponse() {
        let tool = AgentAdapter.kiro(["hook_event_name": "PostToolUse", "tool_tags": ["tool_name": "execute_bash", "tool_input": ["command": "ls"]]])
        XCTAssertEqual(tool["hook_event_name"] as? String, "PreToolUse")
        XCTAssertEqual(tool["tool_name"] as? String, "execute_bash")
        let stop = AgentAdapter.kiro(["hook_event_name": "Stop", "assistant_response": "Done"])
        XCTAssertEqual(stop["last_assistant_message"] as? String, "Done")
    }

    func testMissingCwdAndSessionFallBackToTheBridge() throws {
        let line = #"{"v":1,"agent":"kiro","pid":4321,"cwd":"/Users/me/proj","env":{},"payload":{"hook_event_name":"Stop"}}"#
        let envelope = try XCTUnwrap(HookEnvelope(data: Data(line.utf8)))
        XCTAssertEqual(envelope.cwd, "/Users/me/proj")
        XCTAssertEqual(envelope.sessionID, "kiro-4321")
    }

    func testPayloadCwdWinsOverBridgeCwd() throws {
        let line = #"{"v":1,"agent":"claude","pid":1,"cwd":"/","env":{},"payload":{"hook_event_name":"Stop","session_id":"s","cwd":"/real"}}"#
        XCTAssertEqual(HookEnvelope(data: Data(line.utf8))?.cwd, "/real")
    }
}
