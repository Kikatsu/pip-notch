import Darwin
import Foundation

/// Codex only runs hooks the user has reviewed in `/hooks`. Each approval is a `trusted_hash`
/// under `[hooks.state]` in `~/.codex/config.toml`; untrusted hooks are skipped without any error.
///
/// Pip never trusts hooks on its own. The Settings button asks Codex's app server to trust
/// Pip's hooks, the same request `/hooks` makes, and only for hooks that run Pip's bridge.
enum CodexHookTrust {
    enum Failure: LocalizedError {
        case codexUnavailable
        case server(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .codexUnavailable: "Couldn't start Codex. Run /hooks in Codex and trust Pip's hooks instead."
            case .server(let message): "Codex refused: \(message)"
            case .timedOut: "Codex didn't answer in time. Run /hooks in Codex and trust Pip's hooks instead."
            }
        }
    }

    static func hasTrustedHooks(configTOML: String?) -> Bool {
        guard let configTOML else { return false }
        return configTOML.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Either `trusted_hash = "…"` under a table header or an inline `{ trusted_hash = "…" }`.
            return !trimmed.hasPrefix("#") && trimmed.contains("trusted_hash")
        }
    }

    /// The full `hooks.state` table to write, from a `hooks/list` result.
    ///
    /// Pip's untrusted hooks get their current hash. Every other hook keeps exactly the state it
    /// has now (trusted ones their hash, disabled ones `enabled = false`), so the write leaves the
    /// user's own decisions alone whether Codex merges or replaces the table.
    static func trustState(hooksList result: [String: Any], bridgePath: String) -> (state: [String: Any], newlyTrusted: Int) {
        var state: [String: Any] = [:]
        var newlyTrusted = 0
        for entry in result["data"] as? [[String: Any]] ?? [] {
            for hook in entry["hooks"] as? [[String: Any]] ?? [] {
                guard let key = hook["key"] as? String, let hash = hook["currentHash"] as? String else { continue }
                let status = hook["trustStatus"] as? String
                if status == "managed" { continue }
                let isPip = (hook["command"] as? String)?.contains(bridgePath) ?? false
                var hookState: [String: Any] = [:]
                if status == "trusted" {
                    hookState["trusted_hash"] = hash
                } else if isPip {
                    hookState["trusted_hash"] = hash
                    newlyTrusted += 1
                }
                if hook["enabled"] as? Bool == false { hookState["enabled"] = false }
                if !hookState.isEmpty { state[key] = hookState }
            }
        }
        return (state, newlyTrusted)
    }

    /// Asks Codex to trust Pip's hooks. Returns how many were newly trusted. Blocks; call off the main thread.
    static func trustPipHooks(bridgePath: String, timeout: TimeInterval = 20) throws -> Int {
        let client = try AppServerClient(timeout: timeout)
        defer { client.close() }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        _ = try client.request("initialize", ["clientInfo": ["name": "pip", "title": "Pip", "version": version]])
        try client.notify("initialized")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let listed = try client.request("hooks/list", ["cwds": [home]])
        let (state, newlyTrusted) = trustState(hooksList: listed, bridgePath: bridgePath)
        guard newlyTrusted > 0 else { return 0 }
        _ = try client.request("config/batchWrite", [
            "edits": [["keyPath": "hooks.state", "mergeStrategy": "upsert", "value": state]],
            "reloadUserConfig": true,
        ])
        return newlyTrusted
    }
}

/// A short-lived `codex app-server` speaking line-delimited JSON-RPC over stdio.
private final class AppServerClient {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextID = 0

    init(timeout: TimeInterval) throws {
        // A login shell finds `codex` (and the `node` it needs) on the user's PATH, which a GUI app doesn't inherit.
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec codex app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // If Codex exits early, writing must fail with EPIPE rather than kill Pip with SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try process.run() } catch { throw CodexHookTrust.Failure.codexUnavailable }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [process] in
            if process.isRunning { process.terminate() }
        }
    }

    func notify(_ method: String) throws {
        try send(["method": method])
    }

    func request(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        let id = nextID
        nextID += 1
        try send(["id": id, "method": method, "params": params])
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[buffer.startIndex..<newline])
                buffer = Data(buffer[buffer.index(after: newline)...])
                guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                      message["id"] as? Int == id else { continue }
                if let error = message["error"] as? [String: Any] {
                    throw CodexHookTrust.Failure.server(error["message"] as? String ?? "unknown error")
                }
                return message["result"] as? [String: Any] ?? [:]
            }
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty {
                throw process.isRunning || process.terminationReason == .uncaughtSignal
                    ? CodexHookTrust.Failure.timedOut : CodexHookTrust.Failure.codexUnavailable
            }
            buffer.append(chunk)
        }
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        do { try input.fileHandleForWriting.write(contentsOf: data) } catch { throw CodexHookTrust.Failure.codexUnavailable }
    }
}
