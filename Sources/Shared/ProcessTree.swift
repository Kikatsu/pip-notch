import Foundation
import Darwin

/// Process-table lookups used to find the agent behind a hook and the terminal behind the agent.
enum ProcessTree {
    static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "timeout"]

    static func parent(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 1024)
        let n = proc_name(pid, &buffer, UInt32(buffer.count))
        return n > 0 ? String(cString: buffer) : ""
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// The first ancestor of `start` that is not a shell wrapper: the agent process itself.
    static func agentProcess(startingAt start: pid_t) -> pid_t {
        var pid = start
        for _ in 0..<5 {
            guard shells.contains(name(of: pid)), let up = parent(of: pid), up > 1 else { break }
            pid = up
        }
        return pid
    }
}
