import Foundation
import Combine
import Darwin

/// Turns hook events into session state and decides the notch's mood.
@MainActor
final class SessionStore: ObservableObject {
    /// How long a finished turn keeps the "finished" mood before settling to idle.
    static let finishedDisplay: TimeInterval = 4
    /// How long an error keeps the "error" mood if nothing else happens.
    static let errorDisplay: TimeInterval = 60
    /// Sessions with no pid and no events for this long are dropped.
    static let staleAfter: TimeInterval = 3 * 60 * 60
    /// Editor sessions (Cursor, Antigravity) send no end event; quiet ones are dropped after this.
    static let ideQuietAfter: TimeInterval = 30 * 60
    /// Events for a session that ended this recently are stragglers: each hook runs its own bridge
    /// process, so a quick session's SessionStart can arrive after its SessionEnd.
    static let endedGrace: TimeInterval = 5

    @Published private(set) var sessions: [String: AgentSession] = [:]
    @Published private(set) var approvals: [PendingApproval] = []
    @Published private(set) var now = Date()

    /// Called when a new approval arrives or a turn finishes, so the notch can open itself.
    var onAttention: ((Attention, AgentSession) -> Void)?
    /// Called when an approval is resolved, abandoned, or cancelled so external observers (e.g. notifications) can clean up.
    var onApprovalRemoved: ((UUID) -> Void)?

    enum Attention { case approval, needsInput, finished, error, rateLimited }

    static let inactiveStates: Set<SessionState> = [.idle, .finished, .error, .rateLimited]

    private var responders: [UUID: (ApprovalDecision) -> Void] = [:]
    private var recentlyEnded: [String: Date] = [:]
    private let isProcessAlive: (pid_t) -> Bool
    private let hostName: (HookEnvelope) -> String?
    private let gitBranch: (String) -> String?
    private let killProcess: (pid_t, Int32) -> Int32

    init(
        isProcessAlive: @escaping (pid_t) -> Bool = ProcessTree.isAlive,
        hostName: @escaping (HookEnvelope) -> String? = { _ in nil },
        gitBranch: @escaping (String) -> String? = { _ in nil },
        killProcess: @escaping (pid_t, Int32) -> Int32 = Darwin.kill
    ) {
        self.isProcessAlive = isProcessAlive
        self.hostName = hostName
        self.gitBranch = gitBranch
        self.killProcess = killProcess
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

    var hasInactiveSessions: Bool {
        sessions.values.contains { Self.inactiveStates.contains($0.state) }
    }

    // MARK: Events

    /// Applies one hook event. For blocking events, `reply` answers the waiting agent and the
    /// new approval's id is returned.
    @discardableResult
    func handle(_ event: HookEnvelope, at time: Date = Date(), reply: ((ApprovalDecision) -> Void)? = nil) -> UUID? {
        now = time
        if event.eventName == "SessionEnd" {
            endSession(event.sessionID)
            recentlyEnded[event.sessionID] = time
            return nil
        }
        // Drop stragglers so they don't bring an ended session back. Blocking events still go
        // through, since the agent is waiting for an answer.
        if reply == nil, let ended = recentlyEnded[event.sessionID], time.timeIntervalSince(ended) < Self.endedGrace {
            return nil
        }
        var createdApproval: UUID?

        let isNew = sessions[event.sessionID] == nil
        var session = sessions[event.sessionID] ?? AgentSession(
            id: event.sessionID, agent: event.agent, cwd: event.cwd, pid: event.pid,
            env: event.env, host: hostName(event), stateChangedAt: time, updatedAt: time
        )
        if !event.cwd.isEmpty { session.cwd = event.cwd }
        if event.agent == .unknown { session.customName = event.rawAgent }
        // Branches change between turns; re-read only at turn boundaries, not on every tool call.
        if isNew || ["SessionStart", "UserPromptSubmit", "Stop"].contains(event.eventName) {
            session.branch = session.cwd.isEmpty ? nil : gitBranch(session.cwd)
        }
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
            session.lastMessage = nil
            session.currentTool = nil
            session.errorText = nil

        case "AgentActive":
            if session.state != .working {
                session.turnStartedAt = time
                session.lastMessage = nil
                session.errorText = nil
            }
            set(.working)

        case "AgentMessage":
            session.lastMessage = event["text"].map(Self.firstLine) ?? session.lastMessage

        case "PreToolUse":
            if session.state != .working, session.turnStartedAt == nil || session.state == .finished {
                session.turnStartedAt = time
            }
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
                if session.state != .needsInput { onAttention?(.needsInput, session) }
                set(.needsInput)
            default:
                break
            }

        case "Stop":
            set(.finished)
            session.currentTool = nil
            session.lastMessage = event["last_assistant_message"].map(Self.firstLine) ?? session.lastMessage
            session.lastDuration = session.turnStartedAt.map { time.timeIntervalSince($0) }
            cancelApprovals(forSession: session.id)
            onAttention?(.finished, session)

        case "StopFailure":
            let limited = event["error"] == "rate_limit"
            set(limited ? .rateLimited : .error)
            session.currentTool = nil
            session.errorText = event["error_details"] ?? event["error"]
            cancelApprovals(forSession: session.id)
            onAttention?(limited ? .rateLimited : .error, session)

        default:
            break
        }
        sessions[session.id] = session
        return createdApproval
    }

    func resolve(_ id: UUID, with decision: ApprovalDecision) {
        Log.events.info("Approval \(decision.name, privacy: .public)")
        responders.removeValue(forKey: id)?(decision)
        approvals.removeAll { $0.id == id }
        onApprovalRemoved?(id)
    }

    /// The agent stopped waiting (Esc, crash, timeout): drop the card without answering.
    func approvalAbandoned(_ id: UUID) {
        responders.removeValue(forKey: id)
        approvals.removeAll { $0.id == id }
        onApprovalRemoved?(id)
    }

    /// Advances time-based state: finished and error moods fade, dead sessions go away.
    func tick(at time: Date = Date()) {
        now = time
        recentlyEnded = recentlyEnded.filter { time.timeIntervalSince($0.value) < Self.endedGrace }
        for (id, session) in sessions {
            let quiet = time.timeIntervalSince(session.updatedAt)
            if let pid = session.pid, !isProcessAlive(pid) {
                // Keep showing a finished turn until finishedDisplay elapses, even if the process exited promptly.
                if session.state == .finished, time.timeIntervalSince(session.stateChangedAt) < Self.finishedDisplay {
                    continue
                }
                endSession(id)
            } else if session.agent.isIDE, quiet > Self.ideQuietAfter {
                endSession(id)
            } else if session.pid == nil, quiet > Self.staleAfter {
                endSession(id)
            }
        }
    }

    /// Terminates the agent's process using SIGTERM and marks the session as finished.
    func terminateSession(_ id: String) {
        guard var session = sessions[id] else { return }
        if let pid = session.pid {
            _ = killProcess(pid, SIGTERM)
        }
        cancelApprovals(forSession: id)
        session.state = .finished
        session.currentTool = nil
        session.stateChangedAt = now
        session.updatedAt = now
        sessions[id] = session
    }

    /// Removes all sessions currently in inactive states (.idle, .finished, .error, .rateLimited).
    func clearInactiveSessions() {
        let inactiveIDs = sessions.values
            .filter { Self.inactiveStates.contains($0.state) }
            .map(\.id)
        for id in inactiveIDs {
            endSession(id)
        }
    }

    // MARK: Private

    private func addApproval(for session: AgentSession, event: HookEnvelope, at time: Date, reply: @escaping (ApprovalDecision) -> Void) -> UUID {
        let tool = event["tool_name"] ?? "Tool"
        let summary = ToolSummary.describe(tool: tool, input: event.payload["tool_input"] as? [String: Any] ?? [:])
        let input = event.payload["tool_input"] as? [String: Any] ?? [:]
        var approval = PendingApproval(
            id: UUID(), sessionID: session.id, agent: session.agent, projectName: session.projectName,
            toolName: tool, title: summary.title, detail: summary.detail, receivedAt: time
        )
        approval.agentName = session.agentName
        if isPlanTool(tool: tool, input: input) {
            let markdown = (input["plan"] as? String) ?? (input["plan_markdown"] as? String) ?? (input["markdown"] as? String) ?? ""
            approval = PendingApproval(
                id: approval.id, sessionID: session.id, agent: session.agent, projectName: session.projectName,
                toolName: tool, title: "Plan ready for review", detail: "", receivedAt: time,
                kind: .plan(markdown: markdown)
            )
            approval.agentName = session.agentName
        } else if let questions = extractQuestions(tool: tool, input: input) {
            let primaryQuestion = questions.first?.text
            let title = (primaryQuestion != nil && !primaryQuestion!.isEmpty) ? primaryQuestion! : "Has a question for you"
            approval = PendingApproval(
                id: approval.id, sessionID: session.id, agent: session.agent, projectName: session.projectName,
                toolName: tool, title: title, detail: "", receivedAt: time,
                kind: .question(questions)
            )
            approval.agentName = session.agentName
        }
        if isShellTool(tool: tool) {
            let command = (input["command"] as? String)
                ?? (input["cmd"] as? String)
                ?? (input["CommandLine"] as? String)
                ?? (input["script"] as? String)
                ?? event["command"]
                ?? summary.detail
            approval.risk = CommandSafety.analyze(command: command)
        }
        approval.diff = ToolSummary.extractDiff(tool: tool, input: input)
        responders[approval.id] = reply
        approvals.append(approval)
        onAttention?(.approval, session)
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

    private func isShellTool(tool: String) -> Bool {
        let lower = tool.lowercased()
        let shellTools = ["bash", "shell", "run_shell_command", "run_command", "execute", "exec", "terminal", "powershell", "sh", "zsh"]
        return tool == "Bash" || shellTools.contains(lower)
    }

    private func isPlanTool(tool: String, input: [String: Any]) -> Bool {
        if tool == "ExitPlanMode" { return true }
        if ["ReviewPlan", "SubmitPlan", "plan_mode"].contains(tool) { return true }
        if input["plan"] is String || input["plan_markdown"] is String { return true }
        return false
    }

    private func extractQuestions(tool: String, input: [String: Any]) -> [PendingApproval.Question]? {
        let lower = tool.lowercased()
        let isQuestionTool = lower.contains("question") || lower.contains("ask") || lower.contains("input") || tool == "request_user_input"

        // Format 1: input["questions"] is an array
        if let rawQuestions = input["questions"] as? [[String: Any]], !rawQuestions.isEmpty {
            let parsed = rawQuestions.map { item -> PendingApproval.Question in
                let text = item["question"] as? String ?? item["title"] as? String ?? item["text"] as? String ?? ""
                var options: [String] = []
                var descriptions: [String: String] = [:]

                if let stringOptions = item["options"] as? [String] {
                    options = stringOptions
                } else if let dictOptions = item["options"] as? [[String: Any]] {
                    for opt in dictOptions {
                        let label = opt["label"] as? String ?? opt["title"] as? String ?? opt["text"] as? String ?? opt["value"] as? String ?? ""
                        if !label.isEmpty {
                            options.append(label)
                            if let desc = opt["description"] as? String ?? opt["detail"] as? String {
                                descriptions[label] = desc
                            }
                        }
                    }
                } else if let choices = item["choices"] as? [String] {
                    options = choices
                }
                return PendingApproval.Question(text: text, options: options, descriptions: descriptions)
            }
            return parsed
        }

        // Format 2: direct "question" in input, or "prompt" when it's a question tool or choices are present
        let questionText: String? = {
            if let q = input["question"] as? String, !q.isEmpty {
                return q
            }
            if let p = input["prompt"] as? String, !p.isEmpty, (isQuestionTool || input["options"] != nil || input["choices"] != nil) {
                return p
            }
            return nil
        }()
        if let questionText {
            var options: [String] = []
            var descriptions: [String: String] = [:]

            if let stringOptions = input["options"] as? [String] {
                options = stringOptions
            } else if let dictOptions = input["options"] as? [[String: Any]] {
                for opt in dictOptions {
                    let label = opt["label"] as? String ?? opt["title"] as? String ?? opt["text"] as? String ?? opt["value"] as? String ?? ""
                    if !label.isEmpty {
                        options.append(label)
                        if let desc = opt["description"] as? String ?? opt["detail"] as? String {
                            descriptions[label] = desc
                        }
                    }
                }
            } else if let choices = input["choices"] as? [String] {
                options = choices
            }
            return [PendingApproval.Question(text: questionText, options: options, descriptions: descriptions)]
        }

        // Format 3: question tool without options
        if isQuestionTool {
            let text = input["message"] as? String ?? input["detail"] as? String ?? "Has a question for you"
            return [PendingApproval.Question(text: text, options: [])]
        }

        return nil
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return String(line.prefix(140))
    }
}
