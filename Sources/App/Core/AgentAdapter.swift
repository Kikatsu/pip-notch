import Foundation

/// Translates each agent's hook payload into the Claude-style shape `SessionStore` understands.
///
/// Besides Claude's own events, the store accepts two synthetic ones:
/// `AgentActive` (the agent is busy, with no detail) and `AgentMessage` (`text` = the agent's reply).
enum AgentAdapter {
    static func normalize(_ payload: [String: Any], agent: AgentKind) -> [String: Any] {
        switch agent {
        case .cursor: cursor(payload)
        case .antigravity: antigravity(payload)
        case .claude, .codex, .unknown: payload
        }
    }

    // MARK: Cursor (~/.cursor/hooks.json)

    static func cursor(_ p: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [
            "session_id": p["conversation_id"] as? String ?? p["session_id"] as? String ?? "cursor",
        ]
        if let root = (p["workspace_roots"] as? [String])?.first {
            out["cwd"] = path(root)
        } else if let cwd = p["cwd"] as? String {
            out["cwd"] = cwd
        }

        switch p["hook_event_name"] as? String ?? "" {
        case "sessionStart":
            out["hook_event_name"] = "SessionStart"
        case "sessionEnd":
            out["hook_event_name"] = "SessionEnd"
        case "beforeSubmitPrompt":
            out["hook_event_name"] = "UserPromptSubmit"
            out["prompt"] = p["prompt"]
        case "afterShellExecution":
            out["hook_event_name"] = "PreToolUse"
            out["tool_name"] = "Bash"
            out["tool_input"] = ["command": p["command"] as? String ?? ""]
        case "afterFileEdit":
            out["hook_event_name"] = "PreToolUse"
            out["tool_name"] = "Edit"
            out["tool_input"] = ["file_path": p["file_path"] as? String ?? ""]
        case "postToolUse":
            out["hook_event_name"] = "PreToolUse"
            out["tool_name"] = p["tool_name"] as? String ?? "Tool"
            out["tool_input"] = p["tool_input"] as? [String: Any] ?? [:]
        case "afterAgentResponse":
            out["hook_event_name"] = "AgentMessage"
            out["text"] = p["text"]
        case "stop":
            if p["status"] as? String == "error" {
                out["hook_event_name"] = "StopFailure"
                out["error"] = "error"
                out["error_details"] = "Cursor stopped with an error"
            } else {
                out["hook_event_name"] = "Stop"
            }
        default:
            out["hook_event_name"] = "AgentActive"
        }
        return out
    }

    // MARK: Antigravity (~/.gemini/config/hooks.json)

    /// Antigravity payloads are camelCase and carry no event name; pip-bridge injects
    /// `hook_event_name` from its command-line arguments.
    static func antigravity(_ p: [String: Any]) -> [String: Any] {
        let toolCall = p["toolCall"] as? [String: Any] ?? [:]
        let args = toolCall["args"] as? [String: Any] ?? [:]
        var out: [String: Any] = [
            "session_id": p["conversationId"] as? String ?? "antigravity",
        ]
        if let root = (p["workspacePaths"] as? [String])?.first {
            out["cwd"] = path(root)
        } else if let cwd = args["Cwd"] as? String {
            out["cwd"] = cwd
        }

        switch p["hook_event_name"] as? String ?? "" {
        case "PreToolUse", "PostToolUse":
            let (tool, input) = antigravityTool(name: toolCall["name"] as? String ?? "tool", args: args)
            out["hook_event_name"] = "PreToolUse"
            out["tool_name"] = tool
            out["tool_input"] = input
        case "Stop":
            if let error = p["error"] as? String, !error.isEmpty {
                out["hook_event_name"] = "StopFailure"
                out["error"] = "error"
                out["error_details"] = error
            } else {
                out["hook_event_name"] = "Stop"
            }
        default:
            out["hook_event_name"] = "AgentActive"
        }
        return out
    }

    static func antigravityTool(name: String, args: [String: Any]) -> (String, [String: Any]) {
        if name == "run_command" {
            return ("Bash", ["command": args["CommandLine"] as? String ?? ""])
        }
        let file = ["TargetFile", "AbsolutePath", "FilePath", "File"].lazy.compactMap { args[$0] as? String }.first
        if let file {
            let reading = name.contains("view") || name.contains("read")
            return (reading ? "Read" : "Edit", ["file_path": file])
        }
        return (name, args)
    }

    private static func path(_ value: String) -> String {
        value.hasPrefix("file://") ? (URL(string: value)?.path ?? value) : value
    }
}
