import Foundation

/// Live connection state for every supported agent.
@MainActor
final class IntegrationsModel: ObservableObject {
    let integrations = AgentIntegration.all
    @Published private(set) var connected: Set<AgentKind> = []
    @Published var lastError: String?
    var bridgePath: String?

    var anyConnected: Bool { !connected.isEmpty }

    func refresh() {
        connected = Set(integrations.filter { $0.isInstalled() }.map(\.agent))
    }

    func setConnected(_ integration: AgentIntegration, _ on: Bool) {
        lastError = nil
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
    }
}
