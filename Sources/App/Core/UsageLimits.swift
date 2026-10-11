import Foundation

/// One rate-limit window of one agent's plan, e.g. Claude's 5-hour window at 62%.
struct UsageLimit: Identifiable, Equatable {
    enum Window: String {
        case fiveHour, weekly, spend

        var label: String {
            switch self {
            case .fiveHour: "5h"
            case .weekly: "Week"
            case .spend: "Spend"
            }
        }
    }

    let provider: AgentKind
    let window: Window
    let usedPercent: Double
    let resetsAt: Date?

    var id: String { "\(provider.rawValue).\(window.rawValue)" }
}

/// Plan limits for the agents that expose them locally: Claude Code (through its status line)
/// and Codex (in its session logs). Windows disappear once they reset.
@MainActor
final class UsageStore: ObservableObject {
    static let displayKey = "limits.display"
    static let closedNotchKey = "limits.closedNotch"
    static let lowThreshold = 80.0

    enum Display: String, CaseIterable, Identifiable {
        case always, whenLow, never
        var id: String { rawValue }
        var title: String {
            switch self {
            case .always: "Always"
            case .whenLow: "When 80% or higher"
            case .never: "Never"
            }
        }
    }

    /// The limits to show under the user's display choice, fullest first.
    func shown(_ display: Display) -> [UsageLimit] {
        switch display {
        case .never: []
        case .whenLow: limits.filter { $0.usedPercent >= Self.lowThreshold }
        case .always: limits
        }
    }

    @Published private(set) var limits: [UsageLimit] = []
    private var claude: [UsageLimit] = []
    private var codex: [UsageLimit] = []
    private let codexHome: URL

    init(codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")) {
        self.codexHome = codexHome
    }

    /// `rate_limits` from Claude Code's status line input.
    func updateClaude(_ rateLimits: [String: Any], at now: Date = Date()) {
        claude = [("five_hour", UsageLimit.Window.fiveHour), ("seven_day", .weekly), ("spend_limit", .spend)].compactMap { key, window in
            guard let entry = rateLimits[key] as? [String: Any],
                  let used = (entry["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
            let resets = (entry["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return UsageLimit(provider: .claude, window: window, usedPercent: used, resetsAt: resets)
        }
        publish(now: now)
    }

    func refreshCodex(at now: Date = Date()) {
        codex = CodexUsage.latest(in: codexHome.appendingPathComponent("sessions"))
        publish(now: now)
    }

    func tick(at now: Date = Date()) { publish(now: now) }

    private func publish(now: Date) {
        let current = (claude + codex).filter { limit in limit.resetsAt.map { $0 > now } ?? true }
        if current != limits { limits = current }
    }
}

/// Reads the newest rate-limit snapshot Codex wrote to `~/.codex/sessions/**/rollout-*.jsonl`.
enum CodexUsage {
    static func latest(in sessions: URL, maxAge: TimeInterval = 8 * 24 * 3600) -> [UsageLimit] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sessions, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        var newest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  Date().timeIntervalSince(date) < maxAge else { continue }
            if newest.map({ date > $0.date }) ?? true { newest = (url, date) }
        }
        guard let file = newest else { return [] }
        return parse(tailOf: file.url, modified: file.date)
    }

    static func parse(tailOf url: URL, modified: Date) -> [UsageLimit] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }

        for line in text.split(separator: "\n").reversed() where line.contains("rate_limits") {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let limits = findRateLimits(in: object) else { continue }
            let observed = (object["timestamp"] as? String).flatMap(parseDate) ?? modified
            let parsed = parse(rateLimits: limits, observedAt: observed)
            if !parsed.isEmpty { return parsed }
        }
        return []
    }

    static func parse(rateLimits: [String: Any], observedAt: Date) -> [UsageLimit] {
        ["primary", "secondary"].compactMap { key in
            guard let entry = rateLimits[key] as? [String: Any],
                  let used = (entry["used_percent"] as? NSNumber)?.doubleValue else { return nil }
            let minutes = (entry["window_minutes"] as? NSNumber)?.doubleValue ?? (key == "primary" ? 300 : 10_080)
            var resets: Date?
            if let at = (entry["resets_at"] as? NSNumber)?.doubleValue {
                resets = Date(timeIntervalSince1970: at)
            } else if let seconds = (entry["resets_in_seconds"] as? NSNumber)?.doubleValue {
                resets = observedAt.addingTimeInterval(seconds)
            }
            return UsageLimit(provider: .codex, window: minutes <= 600 ? .fiveHour : .weekly, usedPercent: used, resetsAt: resets)
        }
    }

    private static func findRateLimits(in value: Any) -> [String: Any]? {
        guard let dict = value as? [String: Any] else { return nil }
        if let limits = dict["rate_limits"] as? [String: Any] { return limits }
        for child in dict.values {
            if let found = findRateLimits(in: child) { return found }
        }
        return nil
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// Installs `pip-bridge claude-statusline` as Claude Code's status line, keeping the user's
/// own status line (if any) so it can be run through and restored later.
enum ClaudeStatusLine {
    static var savedOriginalURL: URL { PipPaths.supportDirectory.appendingPathComponent("claude-statusline.json") }

    static func command(bridgePath: String) -> String { "\"\(bridgePath)\" claude-statusline" }

    static func isInstalled(settingsURL: URL, bridgePath: String) -> Bool {
        guard let settings = try? HookFile(url: settingsURL).read(),
              let line = settings["statusLine"] as? [String: Any] else { return false }
        return (line["command"] as? String) == command(bridgePath: bridgePath)
    }

    /// Returns the new settings and the user's previous status line, if it wasn't Pip's.
    static func installing(into settings: [String: Any], bridgePath: String) -> (settings: [String: Any], original: [String: Any]?) {
        var result = settings
        let current = settings["statusLine"] as? [String: Any]
        let original = current.flatMap { HookConfig.containsPip($0) ? nil : $0 }
        var line: [String: Any] = ["type": "command", "command": command(bridgePath: bridgePath)]
        if let padding = current?["padding"] { line["padding"] = padding }
        result["statusLine"] = line
        return (result, original)
    }

    static func removing(from settings: [String: Any], original: [String: Any]?) -> [String: Any] {
        guard let current = settings["statusLine"] as? [String: Any], HookConfig.containsPip(current) else { return settings }
        var result = settings
        result["statusLine"] = original
        return result
    }

    static func install(settingsURL: URL, bridgePath: String) throws {
        let file = HookFile(url: settingsURL)
        let (settings, original) = installing(into: try file.read(), bridgePath: bridgePath)
        if let original {
            let data = try JSONSerialization.data(withJSONObject: ["original": original], options: [.prettyPrinted])
            try FileManager.default.createDirectory(at: savedOriginalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: savedOriginalURL, options: .atomic)
        }
        try file.write(settings)
    }

    static func uninstall(settingsURL: URL) throws {
        let file = HookFile(url: settingsURL)
        let settings = try file.read()
        guard let current = settings["statusLine"] as? [String: Any], HookConfig.containsPip(current) else { return }
        let saved = (try? Data(contentsOf: savedOriginalURL)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        try file.write(removing(from: settings, original: saved?["original"] as? [String: Any]))
        try? FileManager.default.removeItem(at: savedOriginalURL)
    }
}
