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
        if session.agent.isIDE || env["TERM_PROGRAM"] == "vscode", openWorkspace(of: session) {
            return
        }
        if let id = env["ITERM_SESSION_ID"], focusITerm(sessionID: id) {
            return
        }
        if env["TERM_PROGRAM"] == "Apple_Terminal", let tty = session.pid.flatMap(ProcessTree.tty), focusTerminalApp(tty: tty) {
            return
        }
        if let pane = env["WEZTERM_PANE"] {
            run("/Applications/WezTerm.app/Contents/MacOS/wezterm", ["cli", "activate-pane", "--pane-id", pane])
        }
        hostApp(of: session)?.activate()
    }

    // MARK: Hosts

    /// The GUI app the session runs in: from the bundle id the terminal exported, else the process tree.
    static func hostApp(of session: AgentSession) -> NSRunningApplication? {
        if let bundleID = session.env["__CFBundleIdentifier"],
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app
        }
        var pid = session.pid
        for _ in 0..<16 {
            guard let current = pid, current > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            pid = ProcessTree.parent(of: current)
        }
        return nil
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
