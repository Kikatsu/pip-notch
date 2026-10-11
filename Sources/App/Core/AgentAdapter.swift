import Foundation

/// Translates each agent's hook payload into the Claude-style shape `SessionStore` understands.
///
/// Besides Claude's own events, the store accepts two synthetic ones:
/// `AgentActive` (the agent is busy, with no detail) and `AgentMessage` (`text` = the agent's reply).
enum AgentAdapter {
    static func normalize(_ payload: [String: Any], agent: AgentKind) -> [String: Any] {
        switch agent {
        case .claude, .codex, .unknown: payload
        case .cursor: cursor(payload)
        case .antigravity: antigravity(payload)
        case .gemini: gemini(payload)
        case .copilot: copilot(payload)
        case .droid: droid(payload)
        // Pip's own OpenCode plugin and Pi extension already send Claude-shaped events.
        case .opencode, .pi: canonicalizingTool(payload)
        }
    }

    // MARK: Shared tool naming

    /// Maps each agent's tool names onto the few Pip knows how to describe (Bash, Edit, Read).
    static func canonicalTool(name: String, input: [String: Any]) -> (String, [String: Any]) {
        func string(_ keys: [String]) -> String? { keys.lazy.compactMap { input[$0] as? String }.first }
        let lower = name.lowercased()
        let shell = ["bash", "shell", "run_shell_command", "run_command", "execute", "exec", "terminal", "powershell"]
        if shell.contains(lower), let command = string(["command", "cmd", "CommandLine", "script"]) {
            return ("Bash", ["command": command])
        }
        let path = string(["file_path", "filePath", "path", "absolute_path", "TargetFile", "AbsolutePath", "file"])
        if let path {
            if ["read", "read_file", "view", "view_file", "cat", "read_many_files"].contains(lower) {
                return ("Read", ["file_path": path])
            }
            if ["edit", "write", "write_file", "replace", "apply_patch", "patch", "create", "str_replace", "multiedit", "multi_edit"].contains(lower) {
                return ("Edit", ["file_path": path])
            }
        }
        return (name, input)
    }

    private static func canonicalizingTool(_ payload: [String: Any]) -> [String: Any] {
        guard let name = payload["tool_name"] as? String else { return payload }
        var out = payload
        let mapped = canonicalTool(name: name, input: payload["tool_input"] as? [String: Any] ?? [:])
        out["tool_name"] = mapped.0
        out["tool_input"] = mapped.1
        return out
    }

    // MARK: Gemini CLI (~/.gemini/settings.json)

    static func gemini(_ p: [String: Any]) -> [String: Any] {
        var out = p
        switch p["hook_event_name"] as? String ?? "" {
        case "BeforeAgent":
            out["hook_event_name"] = "UserPromptSubmit"
        case "AfterAgent":
            out["hook_event_name"] = "Stop"
            out["last_assistant_message"] = p["prompt_response"]
        case "BeforeTool":
            out["hook_event_name"] = "PreToolUse"
        case "AfterTool":
            out["hook_event_name"] = "PostToolUse"
        case "Notification":
            // Gemini's only notification is "ToolPermission": it is waiting for you in the terminal.
            out["notification_type"] = "agent_needs_input"
        case "SessionStart", "SessionEnd":
            break
        default:
            out["hook_event_name"] = "AgentActive"
        }
        return canonicalizingTool(out)
    }

    // MARK: GitHub Copilot CLI (~/.copilot/hooks/pip.json)

    /// Copilot's camelCase payloads carry no event name; pip-bridge injects it from its arguments.
    static func copilot(_ p: [String: Any]) -> [String: Any] {
        var out: [String: Any] = ["session_id": p["sessionId"] as? String ?? "copilot"]
        out["cwd"] = p["cwd"]
        switch p["hook_event_name"] as? String ?? "" {
        case "sessionStart":
            out["hook_event_name"] = "SessionStart"
        case "sessionEnd":
            out["hook_event_name"] = "SessionEnd"
        case "userPromptSubmitted":
            out["hook_event_name"] = "UserPromptSubmit"
            out["prompt"] = p["prompt"]
        case "preToolUse", "postToolUse":
            var args = p["toolArgs"] as? [String: Any] ?? [:]
            if let text = p["toolArgs"] as? String,
               let parsed = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] {
                args = parsed
            }
            out["hook_event_name"] = "PreToolUse"
            out["tool_name"] = p["toolName"] as? String ?? "tool"
            out["tool_input"] = args
        case "agentStop":
            out["hook_event_name"] = "Stop"
        case "errorOccurred":
            out["hook_event_name"] = "StopFailure"
            out["error"] = "error"
            out["error_details"] = (p["error"] as? String) ?? (p["error"] as? [String: Any])?["message"] as? String ?? "Copilot hit an error"
        case "notification":
            out["hook_event_name"] = "Notification"
            switch p["notification_type"] as? String {
            case "permission_prompt", "elicitation_dialog": out["notification_type"] = "agent_needs_input"
            case "agent_idle": out["notification_type"] = "idle_prompt"
            default: out["notification_type"] = p["notification_type"]
            }
        default:
            out["hook_event_name"] = "AgentActive"
        }
        return canonicalizingTool(out)
    }

    // MARK: Factory Droid (~/.factory)

    /// Droid speaks Claude's format but has no PermissionRequest hook: its permission
    /// prompts arrive as notifications, answered in the terminal.
    static func droid(_ p: [String: Any]) -> [String: Any] {
        var out = p
        if p["hook_event_name"] as? String == "Notification", p["notification_type"] as? String == "permission_prompt" {
            out["notification_type"] = "agent_needs_input"
        }
        return canonicalizingTool(out)
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
        let mapped = canonicalTool(name: name, input: args)
        if mapped.0 != name { return mapped }
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
