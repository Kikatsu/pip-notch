import Foundation

/// One hook event as forwarded by pip-bridge.
struct HookEnvelope {
    let agent: AgentKind
    let pid: pid_t?
    let env: [String: String]
    let payload: [String: Any]

    var eventName: String { payload["hook_event_name"] as? String ?? "" }
    var sessionID: String { payload["session_id"] as? String ?? "\(agent.rawValue)-main" }
    var cwd: String { payload["cwd"] as? String ?? "" }
    var isBlocking: Bool { BridgeWire.blockingEvents.contains(eventName) }

    subscript(key: String) -> String? { payload[key] as? String }

    init(agent: AgentKind, pid: pid_t?, env: [String: String] = [:], payload: [String: Any], fallbackCwd: String? = nil) {
        self.agent = agent
        self.pid = pid
        self.env = env
        var normalized = AgentAdapter.normalize(payload, agent: agent)
        if (normalized["cwd"] as? String ?? "").isEmpty, let fallbackCwd, fallbackCwd != "/" {
            normalized["cwd"] = fallbackCwd
        }
        // Agents without session ids get one per process, so each run is its own row.
        if (normalized["session_id"] as? String ?? "").isEmpty {
            normalized["session_id"] = "\(agent.rawValue)-\(pid.map(String.init) ?? "main")"
        }
        self.payload = normalized
    }

    init?(data: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = object["payload"] as? [String: Any]
        else { return nil }
        let pid = (object["pid"] as? Int).map { pid_t($0) }
        self.init(
            agent: AgentKind(raw: object["agent"] as? String ?? ""),
            pid: pid.flatMap { $0 > 1 ? $0 : nil },
            env: object["env"] as? [String: String] ?? [:],
            payload: payload,
            fallbackCwd: object["cwd"] as? String
        )
    }
}
