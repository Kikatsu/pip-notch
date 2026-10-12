import AppKit
import Combine
import SwiftUI
import UserNotifications

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

        NotificationManager.shared.store = store
        NotificationManager.shared.onResolve = { [weak self] id, decision in self?.resolve(id, decision) }
        NotificationManager.shared.sessionLookup = { [weak self] sessionID in self?.store.sessions[sessionID] }
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        Task {
            _ = try? await NotificationManager.shared.requestAuthorization()
        }

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
            resolve: { [weak self] id, decision in self?.resolve(id, decision) },
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
        store.onApprovalRemoved = { id in
            NotificationManager.shared.removeApprovalNotification(for: id)
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

        UserDefaults.standard.register(defaults: [
            UsageStore.displayKey: UsageStore.Display.always.rawValue,
            UsageStore.closedNotchKey: false,
        ])
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

    /// Bundle id of the app hosting each agent process, cached because walking the process tree per event is wasteful.
    private var hostBundleIDs: [pid_t: String] = [:]

    private func hostBundleID(_ envelope: HookEnvelope) -> String? {
        if let id = envelope.env["__CFBundleIdentifier"] { return id }
        guard let pid = envelope.pid else { return nil }
        if let cached = hostBundleIDs[pid] { return cached }
        let id = HostApps.app(env: envelope.env, pid: pid)?.bundleIdentifier ?? ""
        hostBundleIDs[pid] = id
        return id
    }

    private func receive(_ incoming: HookEnvelope, _ connection: BridgeConnection?) {
        var envelope = incoming
        if envelope.agent == .cursor, hostBundleID(envelope) == HostApps.grokBotBundleID {
            envelope.agent = .grokBot
        }
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
        let host = HostApps.app(env: session.env, pid: session.pid)
        let hostIsFrontmost = host != nil && host?.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier

        if attention == .finished, hostIsFrontmost {
            return
        }
        notch?.handle(attention)
        SoundPlayer.shared.play(attention.cue)
        switch attention {
        case .approval, .needsInput:
            HapticFeedback.play(.attention)
        case .finished:
            HapticFeedback.play(.finished)
        case .error, .rateLimited:
            break
        }

        if NotificationManager.shared.isEnabled, !hostIsFrontmost {
            switch attention {
            case .approval:
                if let approval = store.approvals.last(where: { $0.sessionID == session.id }) {
                    NotificationManager.shared.postApprovalNotification(for: approval)
                }
            case .needsInput:
                NotificationManager.shared.postNeedsInputNotification(for: session)
            case .finished:
                NotificationManager.shared.postFinishedNotification(for: session)
            default:
                break
            }
        }
    }

    /// Answers a request and lets the character react to it.
    private func resolve(_ id: UUID, _ decision: ApprovalDecision) {
        store.resolve(id, with: decision)
        NotificationManager.shared.removeApprovalNotification(for: id)
        switch decision {
        case .allow: notch?.viewModel.face.react(.approve)
        case .deny: notch?.viewModel.face.react(.deny)
        case .passthrough: break
        }
        HapticFeedback.play(decision == .allow ? .allow : .deny)
    }

    private func answerInTerminal(_ approval: PendingApproval) {
        let session = store.sessions[approval.sessionID]
        store.resolve(approval.id, with: .passthrough)
        NotificationManager.shared.removeApprovalNotification(for: approval.id)
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
            guard let approval = notch?.viewModel.currentApproval(in: store) ?? store.approvals.first else { return }
            if case .question(let questions) = approval.kind {
                if shortcut == .allow, let firstOption = questions.first?.options.first {
                    resolve(approval.id, .deny("User selected: \(firstOption)"))
                } else {
                    answerInTerminal(approval)
                }
            } else if shortcut == .allow {
                resolve(approval.id, .allow)
            } else if case .plan = approval.kind {
                resolve(approval.id, .deny("The user wants to keep planning. Ask what they'd like to change."))
            } else {
                resolve(approval.id, .deny)
            }
        case .jump:
            let selectedApproval = notch?.viewModel.currentApproval(in: store) ?? store.approvals.first
            guard let session = selectedApproval.flatMap({ store.sessions[$0.sessionID] }) ?? store.orderedSessions.first else { return }
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

        let toggleItem = NSMenuItem(title: "Toggle Notch", action: #selector(menuToggleNotch), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.control, .option]
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let names = integrations.integrations.filter { integrations.connected.contains($0.agent) }.map(\.agent.displayName)
        let summary = names.isEmpty ? "No agents connected" : "Connected: " + names.joined(separator: ", ")
        let headerItem = NSMenuItem(title: summary, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let sessions = store.orderedSessions
        if !sessions.isEmpty {
            let sessionsMenu = NSMenu()
            for session in sessions {
                let stateDesc = session.state == .working ? "Working" : (session.state == .needsInput ? "Needs Input" : session.state.rawValue.capitalized)
                let title = "\(session.projectName) · \(session.agentName) (\(stateDesc))"
                let item = NSMenuItem(title: title, action: #selector(menuJumpToSession(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = session.id
                sessionsMenu.addItem(item)
            }
            let sessionsItem = NSMenuItem(title: "Active Sessions (\(sessions.count))", action: nil, keyEquivalent: "")
            sessionsItem.submenu = sessionsMenu
            menu.addItem(sessionsItem)
        }

        let inactiveStates: Set<SessionState> = [.idle, .finished, .error]
        let hasInactive = store.sessions.values.contains { inactiveStates.contains($0.state) }
        if hasInactive {
            let clearItem = NSMenuItem(title: "Clear Inactive Sessions", action: #selector(menuClearInactive), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        menu.addItem(.separator())

        let soundsEnabled = UserDefaults.standard.bool(forKey: PipDefaults.soundsEnabled)
        let muteItem = NSMenuItem(title: soundsEnabled ? "Mute Sounds" : "Unmute Sounds", action: #selector(menuToggleMute), keyEquivalent: "m")
        muteItem.keyEquivalentModifierMask = [.control, .option]
        muteItem.target = self
        menu.addItem(muteItem)

        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Preview All States", action: #selector(menuDemo), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func menuToggleNotch() { notch?.toggle() }
    @objc private func menuToggleMute() { Self.toggleMute() }
    @objc private func menuClearInactive() { store.clearInactiveSessions() }
    @objc private func menuJumpToSession(_ sender: NSMenuItem) {
        if let sessionID = sender.representedObject as? String, let session = store.sessions[sessionID] {
            TerminalJumper.focus(session)
        }
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
