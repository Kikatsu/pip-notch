import AppKit
import SwiftUI

/// Owns the notch panel: places it on the notched screen, tracks the pointer, opens and closes it.
@MainActor
final class NotchWindowController {
    private static let windowSize = CGSize(width: 760, height: 600)
    private static let hoverOpenDelay: TimeInterval = 0.12
    private static let hoverCloseDelay: TimeInterval = 0.6
    /// After a click inside the notch, stay open this long even if the pointer drifts out.
    private static let clickHold: TimeInterval = 1.5

    let viewModel: NotchViewModel
    private let store: SessionStore
    private let panel: NotchPanel
    private var geometry: NotchGeometry?
    private var pointerTimer: Timer?
    private var tickTimer: Timer?
    private var insideSince: Date?
    private var outsideSince: Date?
    /// A menu opened from the notch is showing; its items sit outside the black shape.
    private var menuOpen = false
    private var holdOpenUntil = Date.distantPast
    private var clickMonitor: Any?

    init(store: SessionStore, usage: UsageStore, actions: NotchActions) {
        self.store = store
        let screen = NotchGeometry.preferredScreen()
        geometry = screen.map(NotchGeometry.init)
        viewModel = NotchViewModel(notchSize: geometry?.notchSize ?? CGSize(width: 180, height: 32))
        panel = NotchPanel(contentRect: CGRect(origin: .zero, size: Self.windowSize))

        let root = NotchRootView(viewModel: viewModel, store: store, usage: usage, actions: actions)
        let host = FirstMouseHostingView(rootView: root)
        host.frame = CGRect(origin: .zero, size: Self.windowSize)
        panel.contentView = host

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeOnScreen() }
        }
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.viewModel.isExpanded else { return }
                self.menuOpen = true
            }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.menuOpen else { return }
                self.menuOpen = false
                self.holdOpenUntil = Date().addingTimeInterval(Self.clickHold)
            }
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window === self.panel {
                    self.holdOpenUntil = Date().addingTimeInterval(Self.clickHold)
                }
            }
            return event
        }
    }

    func show() {
        placeOnScreen()
        panel.orderFrontRegardless()

        pointerTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackPointer() }
        }
        tickTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.store.tick()
                self.viewModel.updateExpansion(store: self.store)
            }
        }
        for timer in [pointerTimer, tickTimer].compactMap({ $0 }) {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func placeOnScreen() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let geometry = NotchGeometry(screen: screen)
        self.geometry = geometry
        viewModel.notchSize = geometry.notchSize
        let size = Self.windowSize
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    func handle(_ attention: SessionStore.Attention) {
        switch attention {
        case .approval, .needsInput:
            viewModel.approvalsDismissed = false
        case .finished:
            viewModel.finishedPinnedUntil = Date().addingTimeInterval(SessionStore.finishedDisplay)
        case .error, .rateLimited:
            break
        }
        viewModel.updateExpansion(store: store)
    }

    /// Opens the panel from the keyboard (it stays a few seconds, longer if the pointer moves in),
    /// or closes it if it's open.
    func toggle() {
        if viewModel.isExpanded {
            viewModel.approvalsDismissed = !store.approvals.isEmpty
            collapse()
        } else {
            viewModel.approvalsDismissed = false
            viewModel.isHovering = true
            holdOpenUntil = Date().addingTimeInterval(5)
            viewModel.updateExpansion(store: store)
        }
    }

    /// The screen the notch is on.
    var screen: NSScreen? { panel.screen ?? geometry?.screen }

    /// Closes the panel right away (e.g. when a settings window opens).
    func collapse() {
        menuOpen = false
        holdOpenUntil = .distantPast
        viewModel.isHovering = false
        viewModel.updateExpansion(store: store)
    }

    /// The pointer is polled rather than tracked with events because the panel ignores
    /// mouse events whenever the pointer is outside the black shape, so clicks pass through.
    private func trackPointer() {
        let now = Date()
        let pointer = NSEvent.mouseLocation
        let inside = interactiveRect().contains(pointer)
        panel.ignoresMouseEvents = !inside
        let held = menuOpen || now < holdOpenUntil

        if inside {
            outsideSince = nil
            let since = insideSince ?? now
            insideSince = since
            if !viewModel.isHovering, now.timeIntervalSince(since) >= Self.hoverOpenDelay {
                Log.ui.notice("Hover: open")
                viewModel.isHovering = true
            }
        } else {
            insideSince = nil
            if viewModel.isHovering, !held {
                let since = outsideSince ?? now
                outsideSince = since
                if now.timeIntervalSince(since) >= Self.hoverCloseDelay {
                    Log.ui.notice("Hover: close (pointer left) pointer=\(String(describing: pointer), privacy: .public) rect=\(String(describing: self.interactiveRect()), privacy: .public) shape=\(String(describing: self.viewModel.shapeFrame), privacy: .public)")
                    viewModel.isHovering = false
                    outsideSince = nil
                }
            }
        }
        viewModel.updateExpansion(store: store, now: now)
    }

    private func interactiveRect() -> CGRect {
        let frame = panel.frame
        let shape = viewModel.shapeFrame
        var rect = CGRect(x: frame.minX + shape.minX, y: frame.maxY - shape.maxY, width: shape.width, height: shape.height)
        if let notch = geometry?.notchRect {
            rect = rect.isEmpty ? notch : rect.union(notch)
        }
        return rect.insetBy(dx: -4, dy: -4)
    }
}
