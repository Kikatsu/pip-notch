import Foundation
import Combine

/// Turns hook events into session state and decides the notch's mood.
@MainActor
final class SessionStore: ObservableObject {
    /// How long a finished turn keeps the "finished" mood before settling to idle.
    static let finishedDisplay: TimeInterval = 4
    /// How long an error keeps the "error" mood if nothing else happens.
    static let errorDisplay: TimeInterval = 60
    /// Sessions with no pid and no events for this long are dropped.
    static let staleAfter: TimeInterval = 3 * 60 * 60

    @Published private(set) var sessions: [String: AgentSession] = [:]
    @Published private(set) var approvals: [PendingApproval] = []
    @Published private(set) var now = Date()

    /// Called when a new approval arrives or a turn finishes, so the notch can open itself.
    var onAttention: ((Attention) -> Void)?

    enum Attention { case approval, finished }

    private var responders: [UUID: (ApprovalDecision) -> Void] = [:]
    private let isProcessAlive: (pid_t) -> Bool

    init(isProcessAlive: @escaping (pid_t) -> Bool = ProcessTree.isAlive) {
        self.isProcessAlive = isProcessAlive
    }

    // MARK: Derived state

    var mood: Mood {
        if !approvals.isEmpty { return .needsYou }
        if sessions.isEmpty { return .asleep }
        return sessions.values.map { mood(of: $0) }.min() ?? .idle
    }

    func mood(of session: AgentSession) -> Mood {
        let age = now.timeIntervalSince(session.stateChangedAt)
        switch session.state {
        case .needsInput: return .needsYou
        case .error: return age < Self.errorDisplay ? .error : .idle
        case .rateLimited: return .rateLimited
        case .finished: return age < Self.finishedDisplay ? .finished : .idle
        case .working: return .working
        case .idle: return .idle
        }
    }

    /// Sessions ordered most urgent first, then most recently active.
    var orderedSessions: [AgentSession] {
        sessions.values.sorted {
            let (a, b) = (mood(of: $0), mood(of: $1))
            return a == b ? $0.updatedAt > $1.updatedAt : a < b
        }
    }

    var workingCount: Int { sessions.values.filter { $0.state == .working }.count }

    // MARK: Events

    /// Applies one hook event. For blocking events, `reply` answers the waiting agent and the
    /// new approval's id is returned.
    @discardableResult
    func handle(_ event: HookEnvelope, at time: Date = Date(), reply: ((ApprovalDecision) -> Void)? = nil) -> UUID? {
        now = time
        if event.eventName == "SessionEnd" {
            endSession(event.sessionID)
            return nil
        }
        var createdApproval: UUID?

        var session = sessions[event.sessionID] ?? AgentSession(
            id: event.sessionID, agent: event.agent, cwd: event.cwd, pid: event.pid,
            env: event.env, stateChangedAt: time, updatedAt: time
        )
        if !event.cwd.isEmpty { session.cwd = event.cwd }
        if let pid = event.pid { session.pid = pid }
        if !event.env.isEmpty { session.env = event.env }
        session.updatedAt = time

        func set(_ state: SessionState) {
            if session.state != state { session.stateChangedAt = time }
            session.state = state
        }

        switch event.eventName {
        case "SessionStart":
            set(.idle)

        case "UserPromptSubmit":
            set(.working)
            session.turnStartedAt = time
            session.lastPrompt = event["prompt"].map(Self.firstLine)
            session.currentTool = nil
            session.errorText = nil

        case "PreToolUse":
            set(.working)
            if let tool = event["tool_name"] {
                session.currentTool = ToolSummary.label(tool: tool, input: event.payload["tool_input"] as? [String: Any] ?? [:])
            }

        case "PostToolUse", "PostToolUseFailure":
            set(.working)

        case "PermissionRequest":
            if let reply { createdApproval = addApproval(for: session, event: event, at: time, reply: reply) }

        case "Notification":
            switch event["notification_type"] {
            case "idle_prompt":
                if session.state != .finished { set(.idle) }
            case "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog":
                set(.needsInput)
            default:
                break
            }

        case "Stop":
            set(.finished)
            session.currentTool = nil
            session.lastMessage = event["last_assistant_message"].map(Self.firstLine)
            session.lastDuration = session.turnStartedAt.map { time.timeIntervalSince($0) }
            cancelApprovals(forSession: session.id)
            onAttention?(.finished)

        case "StopFailure":
            set(event["error"] == "rate_limit" ? .rateLimited : .error)
            session.currentTool = nil
            session.errorText = event["error_details"] ?? event["error"]
            cancelApprovals(forSession: session.id)

        default:
            break
        }
        sessions[session.id] = session
        return createdApproval
    }

    func resolve(_ id: UUID, with decision: ApprovalDecision) {
        responders.removeValue(forKey: id)?(decision)
        approvals.removeAll { $0.id == id }
    }

    /// The agent stopped waiting (Esc, crash, timeout): drop the card without answering.
    func approvalAbandoned(_ id: UUID) {
        responders.removeValue(forKey: id)
        approvals.removeAll { $0.id == id }
    }

    /// Advances time-based state: finished and error moods fade, dead sessions go away.
    func tick(at time: Date = Date()) {
        now = time
        for (id, session) in sessions {
            if let pid = session.pid {
                if !isProcessAlive(pid) { endSession(id) }
            } else if time.timeIntervalSince(session.updatedAt) > Self.staleAfter {
                endSession(id)
            }
        }
    }

    // MARK: Private

    private func addApproval(for session: AgentSession, event: HookEnvelope, at time: Date, reply: @escaping (ApprovalDecision) -> Void) -> UUID {
        let tool = event["tool_name"] ?? "Tool"
        let summary = ToolSummary.describe(tool: tool, input: event.payload["tool_input"] as? [String: Any] ?? [:])
        let approval = PendingApproval(
            id: UUID(), sessionID: session.id, agent: session.agent, projectName: session.projectName,
            toolName: tool, title: summary.title, detail: summary.detail, receivedAt: time
        )
        responders[approval.id] = reply
        approvals.append(approval)
        onAttention?(.approval)
        return approval.id
    }

    private func cancelApprovals(forSession id: String) {
        for approval in approvals where approval.sessionID == id {
            resolve(approval.id, with: .passthrough)
        }
    }

    private func endSession(_ id: String) {
        cancelApprovals(forSession: id)
        sessions.removeValue(forKey: id)
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(line.prefix(140))
    }
}
