import AppKit
import ServiceManagement
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
    private var notch: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var bridgePath: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // As a unit-test host, stay inert so a running Pip keeps its socket.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }
        do {
            bridgePath = try BridgeInstaller.installBundledBridge()
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
                notch.viewModel.isHovering = false
                notch.viewModel.updateExpansion(store: self.store)
            },
            jump: { TerminalJumper.focus($0) },
            toggleHooks: { [weak self] in self?.toggleHooks() },
            runDemo: { [weak self] in self.map { DemoScript.run(on: $0.store) } },
            quit: { NSApp.terminate(nil) }
        )
        let notch = NotchWindowController(store: store, actions: actions)
        self.notch = notch
        notch.show()
        setUpStatusItem()
        refreshHookStatus()

        if CommandLine.arguments.contains("--demo") {
            DemoScript.run(on: store)
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

    // MARK: Claude Code hooks

    private var installer: HookInstaller? {
        bridgePath.map { HookInstaller(settingsURL: HookInstaller.claudeSettingsURL, bridgePath: $0) }
    }

    private func refreshHookStatus() {
        notch?.viewModel.hooksInstalled = installer?.isInstalled() ?? false
    }

    private func toggleHooks() {
        guard let installer else {
            showAlert("Pip couldn't set up its helper", "The bundled pip-bridge tool is missing. Try reinstalling Pip.")
            return
        }
        do {
            if installer.isInstalled() {
                try installer.uninstall()
            } else {
                try installer.install()
            }
        } catch {
            showAlert("Couldn't update Claude Code settings", error.localizedDescription)
        }
        refreshHookStatus()
    }

    private func showAlert(_ title: String, _ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
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
        refreshHookStatus()
        menu.removeAllItems()
        let connected = notch?.viewModel.hooksInstalled ?? false
        menu.addItem(withTitle: connected ? "Claude Code connected" : "Claude Code not connected", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(withTitle: connected ? "Disconnect Claude Code" : "Connect Claude Code", action: #selector(menuToggleHooks), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Preview All States", action: #selector(menuDemo), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(menuToggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func menuToggleHooks() { toggleHooks() }
    @objc private func menuDemo() { DemoScript.run(on: store) }

    @objc private func menuToggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert("Couldn't change Open at Login", error.localizedDescription)
        }
    }
}
