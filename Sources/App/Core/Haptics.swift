import AppKit

/// Haptic feedback patterns supported by Pip.
enum HapticPattern: CaseIterable, Sendable, Equatable {
    case poke
    case allow
    case deny
    case attention
    case finished
    case selection

    /// The AppKit feedback patterns corresponding to this cue.
    var feedbackPatterns: [NSHapticFeedbackManager.FeedbackPattern] {
        switch self {
        case .poke:
            return [.levelChange]
        case .allow:
            return [.alignment]
        case .deny:
            return [.generic]
        case .attention:
            return [.generic, .alignment]
        case .finished:
            return [.alignment]
        case .selection:
            return [.alignment]
        }
    }
}

/// Plays tactile haptic feedback through the trackpad.
enum HapticFeedback {
    /// Plays the requested haptic pattern using the performer if haptics are enabled.
    @discardableResult
    static func play(
        _ pattern: HapticPattern,
        performer: NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard isEnabled(defaults: defaults) else { return false }
        for feedback in pattern.feedbackPatterns {
            performer.perform(feedback, performanceTime: .default)
        }
        return true
    }

    /// Whether haptic feedback is enabled in user preferences (default true).
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: PipDefaults.hapticsEnabled) == nil {
            return true
        }
        return defaults.bool(forKey: PipDefaults.hapticsEnabled)
    }
}
