import Foundation

enum CommandRiskLevel: String, Comparable, CaseIterable {
    case safe
    case caution
    case dangerous

    private var rank: Int {
        switch self {
        case .safe: return 0
        case .caution: return 1
        case .dangerous: return 2
        }
    }

    static func < (lhs: CommandRiskLevel, rhs: CommandRiskLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

struct CommandRiskAssessment: Equatable {
    let level: CommandRiskLevel
    let reason: String
    let matchedPattern: String

    init(level: CommandRiskLevel, reason: String, matchedPattern: String) {
        self.level = level
        self.reason = reason
        self.matchedPattern = matchedPattern
    }

    static let safe = CommandRiskAssessment(
        level: .safe,
        reason: "No high-risk shell patterns detected",
        matchedPattern: ""
    )
}

enum CommandSafety {
    private struct Rule {
        let level: CommandRiskLevel
        let matchedPattern: String
        let reason: String
        let regex: NSRegularExpression

        init(level: CommandRiskLevel, matchedPattern: String, reason: String, pattern: String) {
            self.level = level
            self.matchedPattern = matchedPattern
            self.reason = reason
            // Pre-compile regex with case-insensitivity
            self.regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }

    private static let dangerousRules: [Rule] = [
        // Destructive deletions
        Rule(
            level: .dangerous,
            matchedPattern: "rm -r /",
            reason: "Deletes files from root directory recursively",
            pattern: #"\brm\s+-[a-zA-Z]*r[a-zA-Z]*\s+/(?:\s|$|\*)"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "rm -rf",
            reason: "Forceful recursive directory deletion",
            pattern: #"\brm\s+(?:-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*|-[a-zA-Z]*r[a-zA-Z]*\s+-[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*\s+-[a-zA-Z]*r[a-zA-Z]*|--recursive\s+--force|--force\s+--recursive)\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "rmdir /s",
            reason: "Recursively removes directory tree",
            pattern: #"\brmdir\s+([^\n]*\s+)?(?:/s|-s)\b"#
        ),

        // Remote pipe execution (checked before bare sudo so piped installers are correctly classified)
        Rule(
            level: .dangerous,
            matchedPattern: "curl .* | (sh|bash|zsh)",
            reason: "Downloads and immediately executes remote script without verification",
            pattern: #"\bcurl\b[^|\n]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh)\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "wget .* | (sh|bash|zsh)",
            reason: "Downloads and immediately executes remote script without verification",
            pattern: #"\bwget\b[^|\n]*\|\s*(?:sudo\s+)?(?:sh|bash|zsh)\b"#
        ),

        // Privilege escalation
        Rule(
            level: .dangerous,
            matchedPattern: "chmod -R 777",
            reason: "Recursively grants world read, write, and execute permissions (777)",
            pattern: #"\bchmod\s+[^\n]*-[a-zA-Z]*r[a-zA-Z]*\s+[^\n]*777\b|\bchmod\s+[^\n]*777\s+[^\n]*-[a-zA-Z]*r[a-zA-Z]*\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "chmod 777",
            reason: "Grants full world read, write, and execute permissions (777)",
            pattern: #"\bchmod\s+[^\n]*\b777\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "chown -R",
            reason: "Recursively modifies file and directory ownership",
            pattern: #"\bchown\s+[^\n]*-[a-zA-Z]*r[a-zA-Z]*\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "sudo",
            reason: "Executes command with superuser (root) privileges",
            pattern: #"\bsudo\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "doas",
            reason: "Executes command with elevated administrative privileges",
            pattern: #"\bdoas\b"#
        ),

        // Git destruction
        Rule(
            level: .dangerous,
            matchedPattern: "git push .*--force",
            reason: "Force-pushes to remote repository, potentially overwriting history",
            pattern: #"\bgit\s+push\b[^\n]*(?:\s+|^)(?:--force|-f|--force-with-lease)\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "git reset --hard",
            reason: "Hard reset discards uncommitted work and resets branch history",
            pattern: #"\bgit\s+reset\b[^\n]*--hard\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "git clean -fdx",
            reason: "Forcefully removes untracked and ignored files",
            pattern: #"\bgit\s+clean\b[^\n]*(?:-[a-zA-Z]*[fdx]{2,}|--force)"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "git checkout -f",
            reason: "Force checkout discards local modifications in working tree",
            pattern: #"\bgit\s+checkout\b[^\n]*(?:\s+|^)(?:-f|--force)\b"#
        ),

        // Filesystem / storage destruction
        Rule(
            level: .dangerous,
            matchedPattern: "diskutil eraseDisk",
            reason: "Erases and reformats entire physical storage disk",
            pattern: #"\bdiskutil\s+eraseDisk\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "mkfs",
            reason: "Formats filesystem, destroying existing partition data",
            pattern: #"\bmkfs(?:\.[a-zA-Z0-9_-]+)?\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "dd if=",
            reason: "Direct block device write can overwrite disks or partitions",
            pattern: #"\bdd\b[^\n]*\bif="#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "> /dev/sd",
            reason: "Direct output redirection to raw storage device can corrupt disk",
            pattern: #">\s*/dev/sd[a-zA-Z0-9]*\b"#
        ),

        // Dangerous kill
        Rule(
            level: .dangerous,
            matchedPattern: "kill -9 -1",
            reason: "Forcefully kills all processes accessible by current user",
            pattern: #"\bkill\s+(?:-9|-kill)\s+-1\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "killall -9",
            reason: "Forcefully terminates all matching processes with SIGKILL",
            pattern: #"\bkillall\s+(?:-9|-kill)\b"#
        ),

        // Sensitive credential exposure
        Rule(
            level: .dangerous,
            matchedPattern: "cat ~/.ssh/id_",
            reason: "Exposes private SSH encryption keys",
            pattern: #"\bcat\b[^\n]*(?:~|\$HOME|/Users/[^/\s]+|/home/[^/\s]+)?/?\.ssh/id_[a-zA-Z0-9_-]*"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "cat ~/.aws/credentials",
            reason: "Exposes AWS secret access keys and credentials",
            pattern: #"\bcat\b[^\n]*(?:~|\$HOME|/Users/[^/\s]+|/home/[^/\s]+)?/?\.aws/credentials\b"#
        ),
        Rule(
            level: .dangerous,
            matchedPattern: "security find-generic-password",
            reason: "Reads sensitive stored passwords from macOS Keychain",
            pattern: #"\bsecurity\s+find-generic-password\b"#
        )
    ]

    private static let cautionRules: [Rule] = [
        Rule(
            level: .caution,
            matchedPattern: "npm publish",
            reason: "Publishes package to npm registry",
            pattern: #"\bnpm\s+publish\b"#
        ),
        Rule(
            level: .caution,
            matchedPattern: "docker system prune -a -f",
            reason: "Removes all unused Docker containers, networks, and images without prompt",
            pattern: #"\bdocker\s+system\s+prune\b[^\n]*(?:-a.*-f|-f.*-a|-[a-zA-Z]*af|-[a-zA-Z]*fa|--all.*--force|--force.*--all)"#
        ),
        Rule(
            level: .caution,
            matchedPattern: "pip install --upgrade pip",
            reason: "Modifies global pip package installer",
            pattern: #"(?:python[0-9.]*\s+-m\s+)?pip[0-9]*\s+install\b[^\n]*(?:--upgrade|-u)\b[^\n]*\bpip\b"#
        )
    ]

    static func analyze(command: String) -> CommandRiskAssessment {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .safe }

        // Normalize escaped line breaks so multiline pipelines can be matched accurately
        let normalized = trimmed.replacingOccurrences(of: "\\\n", with: " ")
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)

        // Evaluate dangerous rules first
        for rule in dangerousRules {
            if rule.regex.firstMatch(in: normalized, options: [], range: range) != nil {
                return CommandRiskAssessment(
                    level: .dangerous,
                    reason: rule.reason,
                    matchedPattern: rule.matchedPattern
                )
            }
        }

        // Evaluate caution rules next
        for rule in cautionRules {
            if rule.regex.firstMatch(in: normalized, options: [], range: range) != nil {
                return CommandRiskAssessment(
                    level: .caution,
                    reason: rule.reason,
                    matchedPattern: rule.matchedPattern
                )
            }
        }

        return .safe
    }
}
