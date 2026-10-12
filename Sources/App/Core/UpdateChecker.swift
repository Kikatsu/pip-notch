import Foundation

/// Asks GitHub once a day whether a newer Pip has been released. It only reads the public
/// release list; nothing about this Mac is sent. Pip's releases are marked pre-release, which
/// GitHub's /releases/latest skips, so this reads the list and picks the highest version.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let version: String
        let url: URL
    }

    static let enabledKey = "checkForUpdates"
    static let lastCheckKey = "lastUpdateCheck"
    static let notifiedVersionKey = "notifiedUpdateVersion"
    static let releasesURL = URL(string: "https://api.github.com/repos/Kikatsu/pip-notch/releases?per_page=20")!
    static let interval: TimeInterval = 24 * 60 * 60

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastError: String?

    /// Called once per newly found version, so the app can post a notification.
    var onNewVersion: ((Release) -> Void)?

    let currentVersion: String
    private let defaults: UserDefaults
    private var timer: Timer?

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        defaults: UserDefaults = .standard
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        defaults.register(defaults: [Self.enabledKey: true])
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
            if newValue { checkIfDue() } else { available = nil }
        }
    }

    /// Checks at launch (what was found last time isn't kept), then daily.
    func start() {
        if isEnabled { check() }
        let timer = Timer(timeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func checkIfDue() {
        guard isEnabled else { return }
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= Self.interval { check() }
    }

    func check() {
        guard !checking else { return }
        checking = true
        var request = URLRequest(url: Self.releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        Task {
            defer { checking = false }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                defaults.set(Date(), forKey: Self.lastCheckKey)
                lastError = nil
                apply(Self.newest(in: data, newerThan: currentVersion))
            } catch {
                lastError = "Couldn't reach GitHub"
            }
        }
    }

    private func apply(_ release: Release?) {
        available = release
        guard let release, defaults.string(forKey: Self.notifiedVersionKey) != release.version else { return }
        defaults.set(release.version, forKey: Self.notifiedVersionKey)
        onNewVersion?(release)
    }

    /// The highest non-draft release in a GitHub release list that is newer than `current`.
    nonisolated static func newest(in data: Data, newerThan current: String) -> Release? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        let releases: [Release] = list.compactMap { entry in
            guard entry["draft"] as? Bool != true,
                  let tag = entry["tag_name"] as? String,
                  let page = entry["html_url"] as? String,
                  let url = URL(string: page)
            else { return nil }
            return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, url: url)
        }
        return releases
            .filter { isVersion($0.version, newerThan: current) }
            .max { isVersion($1.version, newerThan: $0.version) }
    }

    /// Compares dotted numeric versions: 0.1.10 is newer than 0.1.9, and 0.2 equals 0.2.0.
    nonisolated static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = numbers(candidate), b = numbers(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private nonisolated static func numbers(_ version: String) -> [Int] {
        // "0.2.0-beta.1" compares as 0.2.0.
        let core = version.split(separator: "-").first.map(String.init) ?? version
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }
}
