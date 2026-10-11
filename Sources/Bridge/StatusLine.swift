import Foundation

/// `pip-bridge claude-statusline`: Claude Code's status line command.
///
/// Claude Code only shares its plan's usage limits with the status line, so Pip installs this
/// as the status line. It forwards the limits to Pip, then prints either the user's original
/// status line (run with the same input, so it behaves exactly as before) or a compact default.
func runClaudeStatusLine(input: Data) -> Never {
    let status = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] ?? [:]
    forwardLimits(status)

    if let original = originalStatusLineCommand(), let output = run(original, input: input) {
        FileHandle.standardOutput.write(output)
    } else {
        FileHandle.standardOutput.write(Data(defaultLine(status).utf8))
    }
    exit(0)
}

/// The status line the user had before Pip, saved by the app when it installed this one.
private func originalStatusLineCommand() -> String? {
    let url = PipPaths.supportDirectory.appendingPathComponent("claude-statusline.json")
    guard let data = try? Data(contentsOf: url),
          let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let original = saved["original"] as? [String: Any],
          let command = original["command"] as? String, !command.isEmpty
    else { return nil }
    return command
}

private func forwardLimits(_ status: [String: Any]) {
    guard let limits = status["rate_limits"] as? [String: Any], !limits.isEmpty else { return }
    let workspace = status["workspace"] as? [String: Any]
    var payload: [String: Any] = ["hook_event_name": "StatusLine", "rate_limits": limits]
    payload["session_id"] = status["session_id"]
    payload["cwd"] = workspace?["current_dir"] ?? status["cwd"]
    let envelope: [String: Any] = ["v": BridgeWire.version, "agent": "claude", "payload": payload]
    guard var line = try? JSONSerialization.data(withJSONObject: envelope) else { return }
    line.append(0x0A)
    let fd = SocketIO.connect(to: PipPaths.socketPath)
    guard fd >= 0 else { return }
    SocketIO.writeAll(fd, line)
    close(fd)
}

/// Runs the user's original status line with the same stdin; nil if it fails or hangs.
private func run(_ command: String, input: Data) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    let stdin = Pipe(), stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    stdin.fileHandleForWriting.write(input)
    try? stdin.fileHandleForWriting.close()
    DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if process.isRunning { process.terminate() } }
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? output : nil
}

/// "Opus 5.5 · 34% context · 5h 23% · week 41%"
func defaultLine(_ status: [String: Any]) -> String {
    var parts: [String] = []
    if let model = (status["model"] as? [String: Any])?["display_name"] as? String { parts.append(model) }
    if let used = ((status["context_window"] as? [String: Any])?["used_percentage"] as? NSNumber)?.doubleValue {
        parts.append("\(Int(used.rounded()))% context")
    }
    let limits = status["rate_limits"] as? [String: Any] ?? [:]
    for (key, label) in [("five_hour", "5h"), ("seven_day", "week")] {
        if let used = ((limits[key] as? [String: Any])?["used_percentage"] as? NSNumber)?.doubleValue {
            parts.append("\(label) \(Int(used.rounded()))%")
        }
    }
    return parts.joined(separator: " · ")
}
