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
    private let store = SessionStore()
    private let server = SocketServer()
    private let integrations = IntegrationsModel()
    private lazy var settings = SettingsWindowController(integrations: integrations) { [weak self] in
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
            openSettings: { [weak self] in self?.openSettings() },
            runDemo: { [weak self] in self.map { DemoScript.run(on: $0.store) } },
            quit: { NSApp.terminate(nil) }
        )
        let notch = NotchWindowController(store: store, actions: actions)
        self.notch = notch
        store.onAttention = { [weak self] attention in
            self?.notch?.handle(attention)
            SoundPlayer.shared.play(attention.cue)
        }
        notch.show()
        setUpStatusItem()

        integrations.$connected
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak notch] connected in notch?.viewModel.anyAgentConnected = connected }
            .store(in: &subscriptions)
        integrations.refresh()

        if CommandLine.arguments.contains("--demo") {
            DemoScript.run(on: store)
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

    private func openSettings() {
        Log.ui.notice("Open Settings requested")
        notch?.collapse()
        settings.show()
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
