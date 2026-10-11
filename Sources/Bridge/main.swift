import Foundation

// pip-bridge <agent>
//
// Called by an agent hook. Reads the hook payload from stdin, forwards it to the Pip app,
// and for blocking events prints the decision JSON the agent expects. Every failure path
// exits 0 with no output, so the agent behaves exactly as if no hook were installed.

let agent = CommandLine.arguments.dropFirst().first ?? "claude"
let input = FileHandle.standardInput.readDataToEndOfFile()

guard let payload = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else { exit(0) }
let eventName = payload["hook_event_name"] as? String ?? ""
let blocking = BridgeWire.blockingEvents.contains(eventName)

let forwardedEnv = [
    "TERM_PROGRAM", "TERM_SESSION_ID", "ITERM_SESSION_ID", "TMUX", "TMUX_PANE",
    "__CFBundleIdentifier", "KITTY_WINDOW_ID", "WEZTERM_PANE",
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
    "payload": payload,
]
guard var line = try? JSONSerialization.data(withJSONObject: envelope) else { exit(0) }
line.append(0x0A)

let fd = SocketIO.connect(to: PipPaths.socketPath)
guard fd >= 0 else { exit(0) }
guard SocketIO.writeAll(fd, line), blocking else {
    close(fd)
    exit(0)
}

guard let reply = SocketIO.readLine(fd, timeout: BridgeWire.replyTimeout),
      let answer = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any],
      let decision = answer["decision"] as? String,
      decision == "allow" || decision == "deny"
else {
    close(fd)
    exit(0)
}
close(fd)

var decisionBody: [String: Any] = ["behavior": decision]
if decision == "deny" {
    decisionBody["message"] = answer["message"] as? String ?? "The user denied this from Pip."
}
let output: [String: Any] = [
    "hookSpecificOutput": ["hookEventName": eventName, "decision": decisionBody],
]
if let data = try? JSONSerialization.data(withJSONObject: output) {
    FileHandle.standardOutput.write(data)
}
exit(0)
