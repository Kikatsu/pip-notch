import Foundation

/// Plays two fake sessions through every mood, so the notch can be previewed without real agents.
@MainActor
enum DemoScript {
    static func run(on store: SessionStore) {
        let api = "demo-api", web = "demo-web"
        let steps: [(TimeInterval, String, [String: Any])] = [
            (0.0, api, ["hook_event_name": "SessionStart", "cwd": "/Users/demo/api-server"]),
            (0.0, web, ["hook_event_name": "SessionStart", "cwd": "/Users/demo/web-app"]),
            (0.4, api, ["hook_event_name": "UserPromptSubmit", "prompt": "Fix the failing auth tests"]),
            (0.6, web, ["hook_event_name": "UserPromptSubmit", "prompt": "Add a dark mode toggle"]),
            (1.0, api, ["hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": ["command": "npm test -- auth"]]),
            (1.2, web, ["hook_event_name": "PreToolUse", "tool_name": "Edit", "tool_input": ["file_path": "/Users/demo/web-app/src/Theme.tsx"]]),
            (5.0, web, ["hook_event_name": "Stop", "last_assistant_message": "Added a dark mode toggle to the header and saved the choice."]),
            (10.0, api, ["hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": ["command": "rm -rf dist && npm run build"]]),
            (22.0, api, ["hook_event_name": "StopFailure", "error": "server_error", "error_details": "API returned 500"]),
            (27.0, web, ["hook_event_name": "UserPromptSubmit", "prompt": "Now update the docs"]),
            (30.0, web, ["hook_event_name": "StopFailure", "error": "rate_limit", "error_details": "429 Too Many Requests"]),
            (35.0, api, ["hook_event_name": "SessionEnd"]),
            (35.0, web, ["hook_event_name": "SessionEnd"]),
        ]
        for (delay, session, fields) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                var payload = fields
                payload["session_id"] = session
                if payload["cwd"] == nil {
                    payload["cwd"] = session == api ? "/Users/demo/api-server" : "/Users/demo/web-app"
                }
                let event = HookEnvelope(agent: .claude, pid: nil, payload: payload)
                if event.isBlocking {
                    store.handle(event) { decision in NSLog("Pip demo: approval answered \(decision.rawValue)") }
                } else {
                    store.handle(event)
                }
            }
        }
    }
}
