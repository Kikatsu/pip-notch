import AppKit
import Combine

/// Manages system sleep, screen lock, and power mode states to throttle or pause animations
/// and background loops when Pip is not visible or when power-saving is active.
@MainActor
final class PowerManager: ObservableObject {
    static let shared = PowerManager()

    /// True when the displays have slept (NSWorkspace.screensDidSleepNotification).
    @Published private(set) var isScreenSleeping = false

    /// True when the user session is inactive or the screen is locked (NSWorkspace.sessionDidResignActiveNotification).
    @Published private(set) var isScreenLocked = false

    /// True when Low Power Mode is enabled in macOS.
    @Published private(set) var isLowPowerModeEnabled: Bool

    /// True when Pip is idle (no active agent tasks running).
    @Published var isIdle: Bool = true

    /// Provider closure for reading low power mode state.
    private let lowPowerModeProvider: () -> Bool
    private var lowPowerModeOverride: Bool?

    /// Tokens to remove notification observers on deallocation.
    private var observers: [(NSObjectProtocol, NotificationCenter)] = []

    init(
        isIdle: Bool = true,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        lowPowerModeProvider: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.isIdle = isIdle
        self.lowPowerModeProvider = lowPowerModeProvider
        self.isLowPowerModeEnabled = lowPowerModeProvider()

        registerObservers(center: notificationCenter, workspaceCenter: workspaceNotificationCenter)
    }

    deinit {
        for (token, center) in observers {
            center.removeObserver(token)
        }
    }

    // MARK: - Throttling & Frame Interval

    /// True when screens are sleeping, screen is locked, or low power mode is active while idle.
    var shouldThrottleAnimation: Bool {
        isScreenSleeping || isScreenLocked || (isLowPowerModeEnabled && isIdle)
    }

    /// Target frame interval for animations:
    /// - `Double.infinity` (paused) when screens are sleeping.
    /// - `1.0 / 10.0` (10 FPS) when throttled (screen locked or low power mode while idle).
    /// - `1.0 / 30.0` (30 FPS) normally.
    var targetFrameInterval: Double {
        if isScreenSleeping {
            return .infinity
        }
        if shouldThrottleAnimation {
            return 1.0 / 10.0
        }
        return 1.0 / 30.0
    }

    // MARK: - State Mutators (Testing & Direct Control)

    func setScreenSleeping(_ sleeping: Bool) {
        isScreenSleeping = sleeping
    }

    func setScreenLocked(_ locked: Bool) {
        isScreenLocked = locked
    }

    func setLowPowerModeEnabled(_ enabled: Bool) {
        lowPowerModeOverride = enabled
        isLowPowerModeEnabled = enabled
    }

    func setIdle(_ idle: Bool) {
        isIdle = idle
    }

    func refreshPowerState() {
        isLowPowerModeEnabled = lowPowerModeOverride ?? lowPowerModeProvider()
    }

    // MARK: - Notification Observers

    private func registerObservers(center: NotificationCenter, workspaceCenter: NotificationCenter) {
        func observe(
            name: NSNotification.Name,
            primary: NotificationCenter,
            secondary: NotificationCenter?,
            action: @escaping @MainActor (PowerManager) -> Void
        ) {
            var centers = [primary]
            if let secondary, secondary !== primary {
                centers.append(secondary)
            }
            for c in centers {
                let token = c.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        action(self)
                    }
                }
                observers.append((token, c))
            }
        }

        // Screens sleep / wake
        observe(name: NSWorkspace.screensDidSleepNotification, primary: workspaceCenter, secondary: center) { manager in
            manager.setScreenSleeping(true)
        }
        observe(name: NSWorkspace.screensDidWakeNotification, primary: workspaceCenter, secondary: center) { manager in
            manager.setScreenSleeping(false)
        }

        // Session lock / unlock (resign active / become active)
        observe(name: NSWorkspace.sessionDidResignActiveNotification, primary: workspaceCenter, secondary: center) { manager in
            manager.setScreenLocked(true)
        }
        observe(name: NSWorkspace.sessionDidBecomeActiveNotification, primary: workspaceCenter, secondary: center) { manager in
            manager.setScreenLocked(false)
        }

        // Low power mode state changes
        observe(name: NSNotification.Name.NSProcessInfoPowerStateDidChange, primary: center, secondary: workspaceCenter) { manager in
            manager.refreshPowerState()
        }
    }
}
