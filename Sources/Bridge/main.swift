import Foundation

// pip-bridge <agent> [event]
//
// Called by an agent hook. Reads the hook payload from stdin, forwards it to the Pip app,
// and for blocking events prints the decision JSON the agent expects. `event` names the
// hook for agents whose payload doesn't (Antigravity, Copilot, Kiro).
//
// Every failure path still prints the agent's neutral answer (nothing for most agents,
// `{}` for Cursor, Antigravity and Gemini CLI), so the agent behaves as if no hook were installed.

let arguments = Array(CommandLine.arguments.dropFirst())
let agent = arguments.first ?? "claude"
let input = FileHandle.standardInput.readDataToEndOfFile()
if agent == "claude-statusline" { runClaudeStatusLine(input: input) }
var payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
if arguments.count > 1, payload?["hook_event_name"] == nil {
    payload?["hook_event_name"] = arguments[1]
}
let eventName = payload?["hook_event_name"] as? String ?? (arguments.count > 1 ? arguments[1] : "")

/// The answer that changes nothing, for agents that require one.
let neutralOutput: String? = {
    switch agent {
    case "cursor": eventName == "beforeSubmitPrompt" ? #"{"continue":true}"# : "{}"
    case "antigravity", "gemini": "{}"
    default: nil
    }
}()

func finish(_ output: String? = nil) -> Never {
    if let text = output ?? neutralOutput {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
    exit(0)
}

guard let payload else { finish() }
let blocking = BridgeWire.blockingEvents.contains(eventName) && ["claude", "codex", "qoder"].contains(agent)

let forwardedEnv = [
    "TERM_PROGRAM", "TERM_SESSION_ID", "ITERM_SESSION_ID", "TMUX", "TMUX_PANE",
    "__CFBundleIdentifier", "KITTY_WINDOW_ID", "WEZTERM_PANE", "VSCODE_PID", "CLAUDE_CODE_ENTRYPOINT",
]
var env: [String: String] = [:]
for key in forwardedEnv {
    if let value = ProcessInfo.processInfo.environment[key] { env[key] = value }
}

let envelope: [String: Any] = [
    "v": BridgeWire.version,
    "agent": agent,
    "pid": Int(ProcessTree.agentProcess(startingAt: getppid())),
    "env": env,
    // The hook runs in the agent's working directory; used when the payload has no cwd.
    "cwd": FileManager.default.currentDirectoryPath,
    "payload": payload,
]
guard var line = try? JSONSerialization.data(withJSONObject: envelope) else { finish() }
line.append(0x0A)

let fd = SocketIO.connect(to: PipPaths.socketPath)
guard fd >= 0 else { finish() }
guard SocketIO.writeAll(fd, line), blocking else {
    close(fd)
    finish()
}

guard let reply = SocketIO.readLine(fd, timeout: BridgeWire.replyTimeout),
      let answer = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any],
      let decision = answer["decision"] as? String,
      decision == "allow" || decision == "deny"
else {
    close(fd)
    finish()
}
close(fd)

var decisionBody: [String: Any] = ["behavior": decision]
if decision == "deny" {
    decisionBody["message"] = answer["message"] as? String ?? "The user denied this from Pip."
}
let output: [String: Any] = [
    "hookSpecificOutput": ["hookEventName": eventName, "decision": decisionBody],
]
let data = (try? JSONSerialization.data(withJSONObject: output)) ?? Data()
finish(String(data: data, encoding: .utf8))
