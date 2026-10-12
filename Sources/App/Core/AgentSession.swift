import Foundation

enum AgentKind: String, CaseIterable {
    case claude, codex, zcode, gemini, antigravity, cursor, trae, opencode, mimocode, droid,
         devin, qoder, qoderwork, qwen, qwenwork, grok, kimi, deepseek, dsh, vibe,
         copilot, codebuddy, workbuddy, kiro, hermes, amp, pi, ohmypi, gajaecode,
         augment, goose, grokBot, windsurf, unknown

    init(raw: String) {
        let lower = raw.lowercased()
        switch lower {
        case "claude", "claude-code", "claudecode": self = .claude
        case "codex": self = .codex
        case "zcode", "z-code": self = .zcode
        case "gemini", "gemini-cli", "geminicli": self = .gemini
        case "antigravity", "antigravity-cli", "agy": self = .antigravity
        case "cursor", "cursor-agent": self = .cursor
        case "trae": self = .trae
        case "opencode", "open-code": self = .opencode
        case "mimocode", "mimo-code": self = .mimocode
        case "droid", "factory-droid": self = .droid
        case "devin": self = .devin
        case "qoder", "qoder-cli", "qodercn": self = .qoder
        case "qoderwork", "qoder-work": self = .qoderwork
        case "qwen", "qwen-code", "qwencode": self = .qwen
        case "qwenwork", "qwen-work": self = .qwenwork
        case "grok", "grok-build", "grokbuild": self = .grok
        case "kimi", "kimi-code", "kimicode": self = .kimi
        case "deepseek", "deepseek-cli", "codewhale": self = .deepseek
        case "dsh", "deepseek-harness", "deepseekharness": self = .dsh
        case "vibe", "mistral-vibe", "mistralvibe": self = .vibe
        case "copilot", "copilot-cli": self = .copilot
        case "codebuddy", "code-buddy": self = .codebuddy
        case "workbuddy", "work-buddy": self = .workbuddy
        case "kiro", "kiro-cli": self = .kiro
        case "hermes", "hermes-agent": self = .hermes
        case "amp": self = .amp
        case "pi", "pi-agent", "pi_agent": self = .pi
        case "ohmypi", "oh-my-pi": self = .ohmypi
        case "gajaecode", "gajae-code", "gajae": self = .gajaecode
        case "augment", "auggie": self = .augment
        case "goose": self = .goose
        case "grokbot", "grok-bot": self = .grokBot
        case "windsurf": self = .windsurf
        default: self = AgentKind(rawValue: raw) ?? .unknown
        }
    }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .zcode: "ZCode"
        case .gemini: "Gemini CLI"
        case .antigravity: "Antigravity CLI"
        case .cursor: "Cursor"
        case .trae: "Trae"
        case .opencode: "OpenCode"
        case .mimocode: "MiMoCode"
        case .droid: "Droid"
        case .devin: "Devin"
        case .qoder: "Qoder"
        case .qoderwork: "QoderWork"
        case .qwen: "Qwen"
        case .qwenwork: "QwenWork"
        case .grok: "Grok Build"
        case .kimi: "Kimi Code"
        case .deepseek: "DeepSeek"
        case .dsh: "DeepSeek Harness"
        case .vibe: "Mistral Vibe"
        case .copilot: "Copilot"
        case .codebuddy: "CodeBuddy"
        case .workbuddy: "WorkBuddy"
        case .kiro: "Kiro"
        case .hermes: "Hermes"
        case .amp: "Amp"
        case .pi: "Pi Agent"
        case .ohmypi: "Oh My Pi"
        case .gajaecode: "Gajae Code"
        case .augment: "Augment"
        case .goose: "Goose"
        case .grokBot: "Grok Bot"
        case .windsurf: "Windsurf"
        case .unknown: "Agent"
        }
    }

    /// Editor-hosted agents: their process outlives sessions and they send no reliable end event.
    var isIDE: Bool { self == .cursor || self == .grokBot || self == .windsurf || self == .antigravity || self == .trae }
}

enum SessionState: String, Hashable, CaseIterable {
    case idle, working, needsInput, error, rateLimited, finished

    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .needsInput: "Needs Input"
        case .error: "Error"
        case .rateLimited: "Rate Limited"
        case .finished: "Finished"
        }
    }
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
    /// For agents Pip doesn't know, the name their hook passed to pip-bridge.
    var customName: String?
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

    /// "Claude Code", or a custom agent's own name.
    var agentName: String {
        guard agent == .unknown, let customName, !customName.isEmpty else { return agent.displayName }
        return customName.prefix(1).uppercased() + customName.dropFirst()
    }

    var projectName: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? "Unknown project" : name
    }
}

struct CodeDiff: Equatable {
    let filePath: String
    let oldText: String?
    let newText: String?
    let diffText: String?

    init(filePath: String, oldText: String? = nil, newText: String? = nil, diffText: String? = nil) {
        self.filePath = filePath
        self.oldText = oldText
        self.newText = newText
        self.diffText = diffText
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
        var descriptions: [String: String] = [:]

        init(text: String, options: [String], descriptions: [String: String] = [:]) {
            self.text = text
            self.options = options
            self.descriptions = descriptions
        }
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
    /// Display name, which differs from `agent.displayName` for custom agents.
    var agentName: String?
    var risk: CommandRiskAssessment?
    var diff: CodeDiff?
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

    /// Extracts code diff or preview information from an edit or write tool input.
    static func extractDiff(tool: String, input: [String: Any]) -> CodeDiff? {
        let filePath = (input["file_path"] as? String)
            ?? (input["filePath"] as? String)
            ?? (input["path"] as? String)
            ?? (input["TargetFile"] as? String)
            ?? (input["absolute_path"] as? String)
            ?? (input["AbsolutePath"] as? String)
            ?? (input["file"] as? String)
            ?? ""

        // 1. Unified diff / patch
        if let diff = (input["patch"] as? String) ?? (input["diff"] as? String), !diff.isEmpty {
            return CodeDiff(filePath: filePath, oldText: nil, newText: nil, diffText: diff)
        }

        // 2. old_string / new_string
        if input["old_string"] != nil || input["new_string"] != nil {
            let old = input["old_string"] as? String
            let new = input["new_string"] as? String
            return CodeDiff(filePath: filePath, oldText: old, newText: new, diffText: nil)
        }

        // 3. TargetContent / ReplacementContent
        if input["TargetContent"] != nil || input["ReplacementContent"] != nil {
            let old = input["TargetContent"] as? String
            let new = input["ReplacementContent"] as? String
            return CodeDiff(filePath: filePath, oldText: old, newText: new, diffText: nil)
        }

        // 4. content / CodeContent
        if let content = (input["content"] as? String) ?? (input["CodeContent"] as? String) {
            return CodeDiff(filePath: filePath, oldText: nil, newText: content, diffText: nil)
        }

        // 5. old_text / new_text
        if input["old_text"] != nil || input["new_text"] != nil {
            let old = input["old_text"] as? String
            let new = input["new_text"] as? String
            return CodeDiff(filePath: filePath, oldText: old, newText: new, diffText: nil)
        }

        return nil
    }
}
