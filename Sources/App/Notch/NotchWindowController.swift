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
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.placeOnScreen()
                self.viewModel.updateExpansion(store: self.store)
            }
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
            MainActor.assumeIsolated {
                guard let self, !PowerManager.shared.isScreenSleeping else { return }
                self.trackPointer()
            }
        }
        tickTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !PowerManager.shared.isScreenSleeping else { return }
                self.store.tick()
                self.viewModel.updateExpansion(store: self.store)
                PowerManager.shared.isIdle = (self.store.mood == .idle || self.store.mood == .asleep)
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
        PowerManager.shared.isIdle = (store.mood == .idle || store.mood == .asleep)
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
        guard !PowerManager.shared.isScreenSleeping else { return }
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
        followPointer(pointer)
    }

    /// Points the character's eyes at the pointer, easing so they glide rather than jump.
    /// Far away (or over another screen) they drift back to the middle.
    private func followPointer(_ pointer: CGPoint) {
        let frame = panel.frame
        let shape = viewModel.shapeFrame
        guard shape.width > 0 else { return }
        let faceX: CGFloat, faceY: CGFloat
        if viewModel.isExpanded {
            faceX = frame.minX + shape.midX
            faceY = frame.maxY - (viewModel.notchSize.height + 30)
        } else {
            faceX = frame.minX + shape.minX + 6 + NotchViewModel.earWidth / 2
            faceY = frame.maxY - viewModel.notchSize.height / 2
        }
        let dx = pointer.x - faceX, dy = faceY - pointer.y
        let distance = hypot(dx, dy)
        var target = CGSize.zero
        if distance < 700, panel.screen?.frame.contains(pointer) ?? false {
            target = CGSize(width: max(-1, min(1, dx / 220)), height: max(-1, min(1, dy / 160)))
        }
        let current = viewModel.face.gaze
        let next = CGSize(width: current.width + (target.width - current.width) * 0.3,
                          height: current.height + (target.height - current.height) * 0.3)
        if abs(next.width - current.width) > 0.01 || abs(next.height - current.height) > 0.01 {
            viewModel.face.gaze = next
        } else if target == .zero && (current.width != 0 || current.height != 0) {
            viewModel.face.gaze = .zero
        }
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
