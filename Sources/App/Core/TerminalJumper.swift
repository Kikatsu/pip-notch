import AppKit

/// Brings the exact terminal tab, pane or editor window running a session to the front,
/// falling back to just activating the app that hosts it.
@MainActor
enum TerminalJumper {
    static func focus(_ session: AgentSession) {
        let env = session.env

        if let pane = env["TMUX_PANE"], let tmux = env["TMUX"] {
            selectTmuxPane(pane, socket: tmux.split(separator: ",").first.map(String.init))
        }
        let host = hostApp(of: session)
        // Decide by where the session runs, not which agent it is: `agy` and `cursor-agent`
        // run in terminals and should jump to their tab, not open a folder.
        let inEditor = env["TERM_PROGRAM"] == "vscode" || host.map(HostApps.isEditor) == true
        if inEditor, openWorkspace(of: session) {
            return
        }
        if let id = env["ITERM_SESSION_ID"], focusITerm(sessionID: id) {
            return
        }
        if let windowID = env["KITTY_WINDOW_ID"], focusKitty(windowID: windowID) {
            host?.activate()
            return
        }
        if env["TERM_PROGRAM"] == "Apple_Terminal", let tty = session.pid.flatMap(ProcessTree.tty), focusTerminalApp(tty: tty) {
            return
        }
        if let pane = env["WEZTERM_PANE"] {
            focusWezTerm(pane: pane)
        }
        host?.activate()
    }

    /// Terminates a process using SIGTERM (or SIGKILL if force is true).
    @discardableResult
    static func terminateProcess(pid: pid_t, force: Bool = false) -> Bool {
        Darwin.kill(pid, force ? SIGKILL : SIGTERM) == 0
    }

    // MARK: Hosts

    /// The GUI app the session runs in: from the bundle id the terminal exported, else the process tree.
    static func hostApp(of session: AgentSession) -> NSRunningApplication? {
        HostApps.app(env: session.env, pid: session.pid)
    }

    /// Editors (Cursor, VS Code, Antigravity) focus the window that has the folder open.
    private static func openWorkspace(of session: AgentSession) -> Bool {
        guard !session.cwd.isEmpty, let app = hostApp(of: session), let appURL = app.bundleURL else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([URL(fileURLWithPath: session.cwd)], withApplicationAt: appURL, configuration: configuration)
        return true
    }

    // MARK: Terminals

    private static func focusITerm(sessionID: String) -> Bool {
        guard let uuid = sessionID.split(separator: ":").last else { return false }
        return runAppleScript("""
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is "\(uuid)" then
                            select w
                            select t
                            select s
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """)
    }

    private static func focusTerminalApp(tty: String) -> Bool {
        runAppleScript("""
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """)
    }

    private static func focusKitty(windowID: String) -> Bool {
        let candidates = [
            "/Applications/kitty.app/Contents/MacOS/kitty",
            "/opt/homebrew/bin/kitty",
            "/usr/local/bin/kitty"
        ]
        guard let kitty = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return false }
        run(kitty, ["@", "focus-window", "--match", "id:\(windowID)"])
        return true
    }

    private static func focusWezTerm(pane: String) {
        let candidates = [
            "/Applications/WezTerm.app/Contents/MacOS/wezterm",
            "/opt/homebrew/bin/wezterm",
            "/usr/local/bin/wezterm"
        ]
        guard let wezterm = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        run(wezterm, ["cli", "activate-pane", "--pane-id", pane])
    }

    private static func selectTmuxPane(_ pane: String, socket: String?) {
        let candidates = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        guard let tmux = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let target = socket.map { ["-S", $0] } ?? []
        run(tmux, target + ["select-window", "-t", pane, ";", "select-pane", "-t", pane])
    }

    // MARK: Helpers

    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("Pip: AppleScript failed: \(error)") }
        return result?.booleanValue ?? false
    }

    private static func run(_ path: String, _ arguments: [String]) {
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
    }
}

/// Finds and names the app an agent runs in: a terminal, or an editor hosting an extension.
@MainActor
enum HostApps {
    static let editorBundleIDs: [String: String] = [
        "com.microsoft.VSCode": "VS Code",
        "com.microsoft.VSCodeInsiders": "VS Code Insiders",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
        "com.vscodium": "VSCodium",
        "dev.zed.Zed": "Zed",
        "com.google.antigravity": "Antigravity",
        "com.trae.app": "Trae",
        "dev.kiro.desktop": "Kiro",
    ]
    /// Desktop apps that run agents inside them (Claude Code in Claude, Codex in ChatGPT and Codex).
    static let agentAppBundleIDs: [String: String] = [
        "com.anthropic.claudefordesktop": "Claude",
        "com.openai.chat": "ChatGPT",
        "com.openai.codex": "Codex app",
        "com.anysphere.sand": "Grok Bot",
        "dev.cognition.devin": "Devin",
        "com.qoder.app": "Qoder",
        "com.qoder.work": "QoderWork",
        "com.qwen.work": "QwenWork",
        "com.deepseek.app": "DeepSeek",
        "com.zcode.app": "ZCode",
        "com.mimocode.app": "MiMoCode",
        "com.codebuddy.app": "CodeBuddy",
        "com.workbuddy.app": "WorkBuddy",
        "com.gajae.app": "Gajae",
    ]
    /// Dedicated terminal emulator applications.
    static let terminalBundleIDs: [String: String] = [
        "com.googlecode.iterm2": "iTerm2",
        "com.apple.Terminal": "Terminal",
        "com.github.wez.wezterm": "WezTerm",
        "net.kovidgoyal.kitty": "Kitty",
        "com.mitchellh.ghostty": "Ghostty",
        "org.alacritty": "Alacritty",
    ]
    static let grokBotBundleID = "com.anysphere.sand"
    static let editorNames: Set<String> = [
        "Code", "Visual Studio Code", "Cursor", "Windsurf", "VSCodium", "Zed", "Antigravity", "Trae", "Kiro",
        "Devin", "Qoder", "QoderWork", "DeepSeek", "ZCode",
    ]

    static func isEditor(_ app: NSRunningApplication) -> Bool {
        if let id = app.bundleIdentifier, editorBundleIDs[id] != nil { return true }
        return app.localizedName.map(editorNames.contains) ?? false
    }

    /// The GUI app hosting a session: from the bundle id its terminal or editor exported, else the process tree.
    static func app(env: [String: String], pid: pid_t?) -> NSRunningApplication? {
        if let bundleID = env["__CFBundleIdentifier"],
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app
        }
        var current = pid
        for _ in 0..<16 {
            guard let p = current, p > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: p), app.activationPolicy == .regular {
                return app
            }
            current = ProcessTree.parent(of: p)
        }
        return nil
    }

    /// A short display name, e.g. "VS Code", "Ghostty".
    static func label(env: [String: String], pid: pid_t?) -> String? {
        if let bundleID = env["__CFBundleIdentifier"], let name = editorBundleIDs[bundleID] ?? agentAppBundleIDs[bundleID] ?? terminalBundleIDs[bundleID] { return name }
        if let termProgram = env["TERM_PROGRAM"] {
            if termProgram == "ghostty" { return "Ghostty" }
            if termProgram == "Apple_Terminal" { return "Terminal" }
            if termProgram == "iTerm.app" { return "iTerm2" }
            if termProgram == "WezTerm" { return "WezTerm" }
        }
        if env["KITTY_WINDOW_ID"] != nil || env["TERM"] == "xterm-kitty" {
            return "Kitty"
        }
        if env["ALACRITTY_WINDOW_ID"] != nil || env["TERM"] == "alacritty" {
            return "Alacritty"
        }
        guard let app = app(env: env, pid: pid) else { return nil }
        if let id = app.bundleIdentifier, let name = editorBundleIDs[id] ?? agentAppBundleIDs[id] ?? terminalBundleIDs[id] { return name }
        return app.localizedName == "Code" ? "VS Code" : app.localizedName
    }
}
