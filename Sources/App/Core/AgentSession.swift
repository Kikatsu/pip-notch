import Foundation

enum AgentKind: String, CaseIterable {
    case claude, codex, gemini, copilot, droid, opencode, pi, kiro, cursor, windsurf, antigravity, unknown

    init(raw: String) { self = AgentKind(rawValue: raw) ?? .unknown }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .gemini: "Gemini CLI"
        case .copilot: "Copilot CLI"
        case .droid: "Droid"
        case .opencode: "OpenCode"
        case .pi: "Pi"
        case .kiro: "Kiro CLI"
        case .cursor: "Cursor"
        case .windsurf: "Windsurf"
        case .antigravity: "Antigravity"
        case .unknown: "Agent"
        }
    }

    /// Editor-hosted agents: their process outlives sessions and they send no reliable end event.
    var isIDE: Bool { self == .cursor || self == .windsurf || self == .antigravity }
}

enum SessionState: Equatable {
    case idle, working, needsInput, error, rateLimited, finished
}

/// What the notch's face shows: the most urgent state across every session.
/// Lower raw value = more urgent, matching the spec's urgency table.
enum Mood: Int, Comparable {
    case needsYou = 1, error, rateLimited, finished, working, idle, asleep

    static func < (lhs: Mood, rhs: Mood) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var agent: AgentKind
    var cwd: String
    var pid: pid_t?
    var env: [String: String]
    /// The app the agent runs in, e.g. "VS Code" for the Claude Code extension, "Ghostty" for a CLI.
    var host: String?
    /// Current git branch of `cwd`, if it's a repository.
    var branch: String?
    var state: SessionState = .idle
    var stateChangedAt: Date
    var currentTool: String?
    var lastPrompt: String?
    var lastMessage: String?
    var errorText: String?
    var turnStartedAt: Date?
    var lastDuration: TimeInterval?
    var updatedAt: Date

    var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Unknown project" : name
    }
}

struct PendingApproval: Identifiable, Equatable {
    enum Kind: Equatable {
        /// A tool call to allow or deny.
        case tool
        /// Claude finished planning (ExitPlanMode): approve the plan or send it back with notes.
        case plan(markdown: String)
        /// The agent asked a question (AskUserQuestion): shown here, answered in the terminal.
        case question([Question])
    }

    struct Question: Equatable {
        let text: String
        let options: [String]
    }

    let id: UUID
    let sessionID: String
    let agent: AgentKind
    let projectName: String
    let toolName: String
    let title: String
    let detail: String
    let receivedAt: Date
    var kind: Kind = .tool
}

enum ApprovalDecision: Equatable {
    case allow
    /// Deny, optionally telling the agent why or what to do instead.
    case deny(String?)
    /// Let the agent ask in its own UI as if Pip weren't there.
    case passthrough

    static let deny = ApprovalDecision.deny(nil)

    var name: String {
        switch self {
        case .allow: "allow"
        case .deny: "deny"
        case .passthrough: "passthrough"
        }
    }
}

enum ToolSummary {
    /// A human title and the one detail worth showing for a tool call.
    static func describe(tool: String, input: [String: Any]) -> (title: String, detail: String) {
        func string(_ key: String) -> String { input[key] as? String ?? "" }
        switch tool {
        case "Bash": return ("Wants to run a command", string("command"))
        case "Edit", "MultiEdit": return ("Wants to edit a file", string("file_path"))
        case "Write": return ("Wants to write a file", string("file_path"))
        case "Read": return ("Wants to read a file", string("file_path"))
        case "NotebookEdit": return ("Wants to edit a notebook", string("notebook_path"))
        case "WebFetch": return ("Wants to fetch a page", string("url"))
        case "WebSearch": return ("Wants to search the web", string("query"))
        default:
            if let first = input.keys.sorted().lazy.compactMap({ input[$0] as? String }).first(where: { !$0.isEmpty }) {
                return ("Wants to use \(tool)", String(first.prefix(300)))
            }
            let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes])
            let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return ("Wants to use \(tool)", String(json.prefix(300)))
        }
    }

    /// Short label for a session row, e.g. "Bash · npm test".
    static func label(tool: String, input: [String: Any]) -> String {
        let detail = describe(tool: tool, input: input).detail
        let short = detail.split(separator: "\n").first.map(String.init) ?? ""
        if short.isEmpty { return tool }
        let file = tool == "Bash" ? short : URL(fileURLWithPath: short).lastPathComponent
        return "\(tool) · \(file.prefix(80))"
    }
}
