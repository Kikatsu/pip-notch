import AppKit
import Combine
import SwiftUI

@main
struct PipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = SessionStore(
        hostName: { HostApps.label(env: $0.env, pid: $0.pid) },
        gitBranch: GitInfo.branch(at:)
    )
    private let server = SocketServer()
    private let integrations = IntegrationsModel()
    private let usage = UsageStore()
    private lazy var settings = SettingsWindowController(integrations: integrations, usage: usage) { [weak self] in
        self.map { DemoScript.run(on: $0.store) }
    }
    private var notch: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As a unit-test host, stay inert so a running Pip keeps its socket.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        PipDefaults.register()

        do {
            integrations.bridgePath = try BridgeInstaller.installBundledBridge()
        } catch {
            NSLog("Pip: could not install bridge: \(error)")
        }

        server.onEvent = { [weak self] envelope, connection in
            MainActor.assumeIsolated { self?.receive(envelope, connection) }
        }
        do {
            try server.start()
        } catch {
            NSLog("Pip: could not open socket at \(server.path): \(error)")
        }

        let actions = NotchActions(
            resolve: { [weak self] id, decision in self?.store.resolve(id, with: decision) },
            dismissApprovals: { [weak self] in
                guard let self, let notch = self.notch else { return }
                notch.viewModel.approvalsDismissed = true
                notch.collapse()
            },
            jump: { [weak self] session in
                self?.notch?.collapse()
                TerminalJumper.focus(session)
            },
            answerInTerminal: { [weak self] approval in self?.answerInTerminal(approval) },
            toggleMute: { Self.toggleMute() },
            openSettings: { [weak self] in self?.openSettings(fromNotch: true) },
            runDemo: { [weak self] in self.map { DemoScript.run(on: $0.store) } },
            quit: { NSApp.terminate(nil) }
        )
        let notch = NotchWindowController(store: store, usage: usage, actions: actions)
        self.notch = notch
        store.onAttention = { [weak self] attention, session in
            self?.attention(attention, session: session)
        }
        notch.show()
        setUpStatusItem()
        setUpShortcuts()

        integrations.$connected
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak notch] connected in notch?.viewModel.anyAgentConnected = connected }
            .store(in: &subscriptions)
        integrations.connectDetected()
        // New agents get installed while Pip runs; pick them up without a restart.
        let reconnect = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.integrations.connectDetected() }
        }
        RunLoop.main.add(reconnect, forMode: .common)

        UserDefaults.standard.register(defaults: [UsageStore.visibleKey: true])
        usage.refreshCodex()
        let usageTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.usage.refreshCodex()
                self?.usage.tick()
            }
        }
        RunLoop.main.add(usageTimer, forMode: .common)

        if CommandLine.arguments.contains("--demo") {
            DemoScript.run(on: store)
        }
        if CommandLine.arguments.contains("--demo-review") {
            DemoScript.runReview(on: store)
        }
        if CommandLine.arguments.contains("--settings") {
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        for approval in store.approvals {
            store.resolve(approval.id, with: .passthrough)
        }
        server.stop()
    }

    // MARK: Events

    private func receive(_ envelope: HookEnvelope, _ connection: BridgeConnection?) {
        // Claude Code's status line only carries plan limits; it isn't a session event.
        if envelope.eventName == "StatusLine" {
            if let limits = envelope.payload["rate_limits"] as? [String: Any] { usage.updateClaude(limits) }
            connection?.finish(nil)
            return
        }
        if envelope.agent == .codex, envelope.eventName == "Stop" { usage.refreshCodex() }
        Log.events.info("\(envelope.agent.rawValue, privacy: .public) \(envelope.eventName, privacy: .public) session=\(envelope.sessionID, privacy: .public)")
        guard let connection else {
            store.handle(envelope)
            return
        }
        let id = store.handle(envelope) { decision in connection.finish(decision) }
        guard let id else {
            connection.finish(nil)
            return
        }
        connection.watchForHangup { [weak self] in self?.store.approvalAbandoned(id) }
    }

    /// Approvals always surface. A finished turn stays quiet if you're already looking at
    /// the app it runs in: you saw it finish.
    private func attention(_ attention: SessionStore.Attention, session: AgentSession) {
        if attention == .finished,
           let host = HostApps.app(env: session.env, pid: session.pid),
           host.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier {
            return
        }
        notch?.handle(attention)
        SoundPlayer.shared.play(attention.cue)
    }

    private func answerInTerminal(_ approval: PendingApproval) {
        let session = store.sessions[approval.sessionID]
        store.resolve(approval.id, with: .passthrough)
        notch?.collapse()
        if let session { TerminalJumper.focus(session) }
    }

    private static func toggleMute() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: PipDefaults.soundsEnabled), forKey: PipDefaults.soundsEnabled)
    }

    // MARK: Shortcuts

    private func setUpShortcuts() {
        UserDefaults.standard.register(defaults: [HotKeyCenter.enabledKey: true])
        store.$approvals
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refreshShortcuts() } }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshShortcuts() }
            .store(in: &subscriptions)
        refreshShortcuts()
    }

    private func refreshShortcuts() {
        let enabled = UserDefaults.standard.bool(forKey: HotKeyCenter.enabledKey)
        let pending = !store.approvals.isEmpty
        for shortcut in Shortcut.allCases {
            let active = enabled && (!shortcut.onlyWhileApprovalPending || pending)
            HotKeyCenter.shared.set(shortcut, active: active) { [weak self] in self?.run(shortcut) }
        }
    }

    private func run(_ shortcut: Shortcut) {
        switch shortcut {
        case .togglePanel:
            notch?.toggle()
        case .allow, .deny:
            guard let approval = store.approvals.first else { return }
            if case .question = approval.kind {
                answerInTerminal(approval)
            } else if shortcut == .allow {
                store.resolve(approval.id, with: .allow)
            } else if case .plan = approval.kind {
                store.resolve(approval.id, with: .deny("The user wants to keep planning. Ask what they'd like to change."))
            } else {
                store.resolve(approval.id, with: .deny)
            }
        case .jump:
            guard let session = store.approvals.first.flatMap({ store.sessions[$0.sessionID] }) ?? store.orderedSessions.first else { return }
            notch?.collapse()
            TerminalJumper.focus(session)
        case .mute:
            Self.toggleMute()
        }
    }

    private func openSettings(fromNotch: Bool = false) {
        Log.ui.notice("Open Settings requested (from notch: \(fromNotch, privacy: .public))")
        let screen = fromNotch ? notch?.screen : nil
        notch?.collapse()
        settings.show(on: screen)
    }

    // MARK: Menu bar item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "eyes", accessibilityDescription: "Pip")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        integrations.refresh()
        menu.removeAllItems()
        let names = integrations.integrations.filter { integrations.connected.contains($0.agent) }.map(\.agent.displayName)
        let summary = names.isEmpty ? "No agents connected" : "Connected: " + names.joined(separator: ", ")
        menu.addItem(withTitle: summary, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Preview All States", action: #selector(menuDemo), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func menuSettings() { openSettings() }
    @objc private func menuDemo() { DemoScript.run(on: store) }
}

private extension SessionStore.Attention {
    var cue: SoundCue {
        switch self {
        case .approval, .needsInput: .approval
        case .finished: .finished
        case .error: .error
        case .rateLimited: .rateLimited
        }
    }
}
