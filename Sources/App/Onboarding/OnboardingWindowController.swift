import AppKit
import SwiftUI

/// Shows the welcome tour on first launch, and again from Settings or the menu bar.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let completedKey = "onboarding.completed"
    /// The launch argument that shows the tour even after it's been finished (for screenshots).
    static let launchArgument = "--onboarding"

    static var shouldShowOnLaunch: Bool {
        !UserDefaults.standard.bool(forKey: completedKey) || CommandLine.arguments.contains(launchArgument)
            || CommandLine.arguments.contains("--onboarding-step")
    }

    private let integrations: IntegrationsModel
    /// Called once the tour closes, with whether the user asked to play the demo.
    private let onFinish: (_ playDemo: Bool) -> Void
    private var window: NSWindow?

    init(integrations: IntegrationsModel, onFinish: @escaping (_ playDemo: Bool) -> Void) {
        self.integrations = integrations
        self.onFinish = onFinish
    }

    func show(on screen: NSScreen?) {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let root = OnboardingView(integrations: integrations) { [weak self] playDemo in
            self?.close(playDemo: playDemo)
        }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Pip"
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let area = (screen ?? NSScreen.screens.first)?.visibleFrame {
            let size = window.frame.size
            window.setFrameOrigin(CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2 + area.height * 0.04))
        }
        self.window = window

        window.alphaValue = 0
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            window.animator().alphaValue = 1
        }
    }

    private func close(playDemo: Bool) {
        guard let window else { return }
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                window.close()
            }
        }
        onFinish(playDemo)
    }

    /// Closing with the red button counts as finishing; it shouldn't come back every launch.
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window = nil
    }
}
