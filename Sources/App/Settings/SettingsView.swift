import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, agents, appearance, sounds, shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .agents: "Agents"
        case .appearance: "Appearance"
        case .sounds: "Sounds"
        case .shortcuts: "Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .agents: "terminal"
        case .appearance: "eyes"
        case .sounds: "speaker.wave.2"
        case .shortcuts: "keyboard"
        }
    }

    /// `--settings-pane <name>` opens a specific tab (for screenshots and docs).
    static var launchPane: SettingsPane? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--settings-pane"), i + 1 < args.count else { return nil }
        return SettingsPane(rawValue: args[i + 1])
    }
}

/// A standard macOS preferences window: toolbar tabs, each hosting a grouped SwiftUI form.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let integrations: IntegrationsModel
    private let usage: UsageStore
    private let runDemo: () -> Void

    init(integrations: IntegrationsModel, usage: UsageStore, runDemo: @escaping () -> Void) {
        self.integrations = integrations
        self.usage = usage
        self.runDemo = runDemo
    }

    /// Opens Settings, centred on `screen` (the notch's screen when opened from the notch).
    func show(on screen: NSScreen? = nil) {
        if window == nil { window = makeWindow() }
        guard let window else { return }
        if !window.isVisible || screen != nil { place(window, on: screen) }
        integrations.connectDetected()
        Log.ui.notice("Settings window shown")
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // Activation can be refused while another app is frontmost; the window still comes forward.
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]

        for pane in SettingsPane.allCases {
            let host = NSHostingController(rootView: content(for: pane))
            host.sizingOptions = .preferredContentSize
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.icon, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        if let pane = SettingsPane.launchPane, let index = SettingsPane.allCases.firstIndex(of: pane) {
            tabs.selectedTabViewItemIndex = index
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func content(for pane: SettingsPane) -> AnyView {
        switch pane {
        case .general: AnyView(GeneralSettings(model: integrations, usage: usage, runDemo: runDemo))
        case .agents: AnyView(AgentSettings(model: integrations))
        case .appearance: AnyView(AppearanceSettings())
        case .sounds: AnyView(SoundSettings())
        case .shortcuts: AnyView(ShortcutSettings())
        }
    }

    /// Centres the window on the screen under the pointer: the one with the notch you just clicked,
    /// not necessarily the main display.
    private func place(_ window: NSWindow, on preferred: NSScreen?) {
        let pointer = NSEvent.mouseLocation
        let underPointer = NSScreen.screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(pointer) }
        guard let screen = preferred ?? underPointer ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        var frame = window.frame
        frame.origin = CGPoint(x: area.midX - frame.width / 2, y: area.maxY - frame.height - area.height * 0.12)
        window.setFrame(frame, display: false)
    }
}
