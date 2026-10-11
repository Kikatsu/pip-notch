import AppKit

/// Brings the app hosting an agent session to the front.
enum TerminalJumper {
    static func focus(_ session: AgentSession) {
        if let bundleID = session.env["__CFBundleIdentifier"],
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
            return
        }
        var pid = session.pid
        for _ in 0..<16 {
            guard let current = pid, current > 1 else { return }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                app.activate()
                return
            }
            pid = ProcessTree.parent(of: current)
        }
    }
}
