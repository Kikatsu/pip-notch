import Foundation

/// Live connection state for every supported agent, plus automatic connection of new ones.
@MainActor
final class IntegrationsModel: ObservableObject {
    static let autoConnectKey = "agents.autoConnect"
    /// Agents the user disconnected by hand; auto-connect leaves them alone.
    static let optedOutKey = "agents.optedOut"
    /// Read Claude Code's plan limits by wrapping its status line.
    static let claudeLimitsKey = "limits.claude"

    let integrations: [AgentIntegration]
    @Published private(set) var connected: Set<AgentKind> = []
    /// Agents Pip connected or repaired on its own since launch, shown in Settings.
    @Published private(set) var autoConnected: Set<AgentKind> = []
    @Published var lastError: String?
    var bridgePath: String?

    private let defaults: UserDefaults

    init(integrations: [AgentIntegration] = AgentIntegration.all, defaults: UserDefaults = .standard) {
        self.integrations = integrations
        self.defaults = defaults
        defaults.register(defaults: [Self.autoConnectKey: true, Self.claudeLimitsKey: true])
    }

    var anyConnected: Bool { !connected.isEmpty }

    var autoConnect: Bool {
        get { defaults.bool(forKey: Self.autoConnectKey) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.autoConnectKey)
            if newValue { connectDetected() }
        }
    }

    var claudeLimits: Bool {
        get { defaults.bool(forKey: Self.claudeLimitsKey) }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: Self.claudeLimitsKey)
            syncClaudeStatusLine()
        }
    }

    private var claudeIntegration: AgentIntegration? { integrations.first { $0.agent == .claude } }

    /// Keeps Pip's status line installed exactly while Claude Code is connected and limits are on.
    func syncClaudeStatusLine() {
        guard let claude = claudeIntegration else { return }
        let wanted = claudeLimits && connected.contains(.claude)
        do {
            if wanted, let bridgePath {
                if !ClaudeStatusLine.isInstalled(settingsURL: claude.configURL, bridgePath: bridgePath) {
                    try ClaudeStatusLine.install(settingsURL: claude.configURL, bridgePath: bridgePath)
                    Log.ui.notice("Installed Claude status line for limits")
                }
            } else {
                try ClaudeStatusLine.uninstall(settingsURL: claude.configURL)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private var optedOut: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.optedOutKey) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Self.optedOutKey) }
    }

    func refresh() {
        connected = Set(integrations.filter { $0.isInstalled() }.map(\.agent))
    }

    /// A manual Connect or Disconnect. Disconnecting opts the agent out of auto-connect.
    func setConnected(_ integration: AgentIntegration, _ on: Bool) {
        lastError = nil
        if on {
            optedOut.remove(integration.agent.rawValue)
        } else {
            optedOut.insert(integration.agent.rawValue)
            autoConnected.remove(integration.agent)
        }
        do {
            if on {
                guard let bridgePath else {
                    lastError = "Pip's helper tool is missing. Try reinstalling Pip."
                    return
                }
                try integration.install(bridgePath: bridgePath)
            } else {
                try integration.uninstall()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
        if integration.agent == .claude { syncClaudeStatusLine() }
    }

    /// Connects every agent found on this Mac that the user hasn't opted out of, and repairs
    /// connections whose hooks went missing or point at an old copy of the bridge.
    /// Cheap enough to run on a timer: it only reads small config files.
    func connectDetected() {
        guard autoConnect, let bridgePath else {
            refresh()
            return
        }
        let skip = optedOut
        for integration in integrations where integration.isDetected && !skip.contains(integration.agent.rawValue) {
            guard !integration.isInstalled(bridgePath: bridgePath) else { continue }
            do {
                try integration.install(bridgePath: bridgePath)
                autoConnected.insert(integration.agent)
                Log.ui.notice("Auto-connected \(integration.agent.rawValue, privacy: .public)")
            } catch {
                // A config that isn't valid JSON is the user's to fix; don't retry it noisily.
                Log.ui.error("Auto-connect \(integration.agent.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        refresh()
        syncClaudeStatusLine()
    }
}
