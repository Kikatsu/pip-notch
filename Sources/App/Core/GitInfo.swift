import Foundation

/// Reads the current branch straight from `.git/HEAD`, without running git.
enum GitInfo {
    static func branch(at path: String) -> String? {
        var directory = URL(fileURLWithPath: path)
        let fm = FileManager.default
        for _ in 0..<40 {
            let dotGit = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                let gitDir = isDirectory.boolValue ? dotGit : worktreeGitDir(dotGit, relativeTo: directory)
                guard let gitDir, let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
                return parseHead(head)
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { return nil }
            directory = parent
        }
        return nil
    }

    /// "ref: refs/heads/main" → "main"; a detached HEAD → its short hash.
    static func parseHead(_ head: String) -> String? {
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: ") {
            let ref = line.dropFirst(5)
            return ref.hasPrefix("refs/heads/") ? String(ref.dropFirst(11)) : String(ref)
        }
        return line.isEmpty ? nil : String(line.prefix(7))
    }

    /// Worktrees and submodules have a `.git` file pointing at the real git directory.
    private static func worktreeGitDir(_ file: URL, relativeTo directory: URL) -> URL? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let line = text.split(separator: "\n").first, line.hasPrefix("gitdir: ") else { return nil }
        let path = String(line.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path).standardizedFileURL
    }
}
