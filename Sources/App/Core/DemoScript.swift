import Foundation

/// Plays fake sessions through every mood, so the notch can be previewed without real agents.
@MainActor
enum DemoScript {
    static func run(on store: SessionStore) {
        playEditorSessions(on: store)
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
            (16.0, web, ["hook_event_name": "PermissionRequest", "tool_name": "ExitPlanMode", "tool_input": ["plan": "## Dark mode docs\n1. Add a **Theming** page with screenshots\n2. Document the `prefers-color-scheme` fallback\n3. Link it from the README"]]),
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
                let event = HookEnvelope(agent: session == api ? .claude : .codex, pid: nil, payload: payload)
                if event.isBlocking {
                    store.handle(event) { decision in NSLog("Pip demo: approval answered \(decision.name)") }
                } else {
                    store.handle(event)
                }
            }
        }
    }

    /// Just a plan review and a question, for checking those cards.
    static func runReview(on store: SessionStore) {
        let plan = """
        # Dark Mode & Theming System

        ## Architecture Plan
        This implementation introduces dynamic theme switching with system appearance syncing.

        ### Tasks
        - [x] Configure theme color tokens
        - [ ] Add dark mode toggle in navigation header
        - [ ] Save user preference to local storage

        ```typescript
        export function useTheme() {
          const [theme, setTheme] = useState<'light' | 'dark'>('dark');
          return { theme, toggleTheme: () => setTheme(t => t === 'dark' ? 'light' : 'dark') };
        }
        ```

        | Setting | Default | Description |
        | --- | --- | --- |
        | Mode | Dark | High-contrast dark theme |
        | Sync | Enabled | Follows system macOS appearance |

        > Note: Verified contrast ratios comply with WCAG AAA standards.
        """
        store.handle(HookEnvelope(agent: .claude, pid: nil, payload: [
            "hook_event_name": "PermissionRequest", "session_id": "demo-plan", "cwd": "/Users/demo/web-app",
            "tool_name": "ExitPlanMode", "tool_input": ["plan": plan],
        ])) { NSLog("Pip demo: plan answered \($0.name)") }
        store.handle(HookEnvelope(agent: .claude, pid: nil, payload: [
            "hook_event_name": "PermissionRequest", "session_id": "demo-question", "cwd": "/Users/demo/api-server",
            "tool_name": "AskUserQuestion",
            "tool_input": [
                "questions": [
                    [
                        "question": "Which deployment target?",
                        "options": [
                            ["label": "Production"],
                            ["label": "Staging"],
                            ["label": "Local only"]
                        ]
                    ]
                ]
            ],
        ])) { NSLog("Pip demo: question answered \($0.name)") }
    }

    /// A Cursor and an Antigravity session, sent in each editor's own payload format.
    private static func playEditorSessions(on store: SessionStore) {
        let steps: [(TimeInterval, AgentKind, [String: Any])] = [
            (0.8, .cursor, ["hook_event_name": "beforeSubmitPrompt", "conversation_id": "demo-cursor",
                            "workspace_roots": ["/Users/demo/mobile-app"], "prompt": "Fix the login screen layout"]),
            (1.6, .cursor, ["hook_event_name": "afterFileEdit", "conversation_id": "demo-cursor",
                            "workspace_roots": ["/Users/demo/mobile-app"], "file_path": "/Users/demo/mobile-app/Login.swift"]),
            (1.4, .antigravity, ["hook_event_name": "PreInvocation", "conversationId": "demo-agy",
                                 "workspacePaths": ["/Users/demo/data-pipeline"]]),
            (2.2, .antigravity, ["hook_event_name": "PostToolUse", "conversationId": "demo-agy",
                                 "workspacePaths": ["/Users/demo/data-pipeline"],
                                 "toolCall": ["name": "run_command", "args": ["CommandLine": "pytest -q"]]]),
            (14.0, .cursor, ["hook_event_name": "afterAgentResponse", "conversation_id": "demo-cursor",
                             "text": "Login screen now centers on small iPhones."]),
            (14.2, .cursor, ["hook_event_name": "stop", "conversation_id": "demo-cursor", "status": "completed"]),
            (18.0, .antigravity, ["hook_event_name": "Stop", "conversationId": "demo-agy", "fullyIdle": true]),
            (35.0, .cursor, ["hook_event_name": "sessionEnd", "conversation_id": "demo-cursor"]),
            (35.0, .antigravity, ["hook_event_name": "Stop", "conversationId": "demo-agy"]),
        ]
        for (delay, agent, payload) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                store.handle(HookEnvelope(agent: agent, pid: nil, payload: payload))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 36) {
            store.handle(HookEnvelope(agent: .claude, pid: nil, payload: ["hook_event_name": "SessionEnd", "session_id": "demo-agy"]))
        }
    }
}
