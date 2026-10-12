import AppKit
import XCTest
@testable import Pip

final class HapticsTests: XCTestCase {
    private final class MockPerformer: NSObject, NSHapticFeedbackPerformer {
        var calls: [(pattern: NSHapticFeedbackManager.FeedbackPattern, time: NSHapticFeedbackManager.PerformanceTime)] = []

        func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern, performanceTime: NSHapticFeedbackManager.PerformanceTime) {
            calls.append((pattern, performanceTime))
        }
    }

    func testHapticPatternMappings() {
        XCTAssertEqual(HapticPattern.allCases.count, 6)
        XCTAssertEqual(HapticPattern.poke.feedbackPatterns, [.levelChange])
        XCTAssertEqual(HapticPattern.allow.feedbackPatterns, [.alignment])
        XCTAssertEqual(HapticPattern.deny.feedbackPatterns, [.generic])
        XCTAssertEqual(HapticPattern.attention.feedbackPatterns, [.generic, .alignment])
        XCTAssertEqual(HapticPattern.finished.feedbackPatterns, [.alignment])
        XCTAssertEqual(HapticPattern.selection.feedbackPatterns, [.alignment])
    }

    func testDefaultPreferenceIsEnabled() {
        let defaults = UserDefaults(suiteName: "pip.haptics.test.\(UUID().uuidString)")!
        XCTAssertNil(defaults.object(forKey: PipDefaults.hapticsEnabled))
        XCTAssertTrue(HapticFeedback.isEnabled(defaults: defaults), "Haptics should default to enabled when unset")
    }

    func testPreferenceToggling() {
        let defaults = UserDefaults(suiteName: "pip.haptics.test.\(UUID().uuidString)")!

        defaults.set(false, forKey: PipDefaults.hapticsEnabled)
        XCTAssertFalse(HapticFeedback.isEnabled(defaults: defaults))

        defaults.set(true, forKey: PipDefaults.hapticsEnabled)
        XCTAssertTrue(HapticFeedback.isEnabled(defaults: defaults))
    }

    func testPipDefaultsRegistrationIncludesHaptics() {
        PipDefaults.register()
        XCTAssertTrue(UserDefaults.standard.bool(forKey: PipDefaults.hapticsEnabled))
    }

    func testPerformsFeedbackWhenEnabled() {
        let defaults = UserDefaults(suiteName: "pip.haptics.test.\(UUID().uuidString)")!
        let performer = MockPerformer()

        let playedPoke = HapticFeedback.play(.poke, performer: performer, defaults: defaults)
        XCTAssertTrue(playedPoke)
        XCTAssertEqual(performer.calls.count, 1)
        XCTAssertEqual(performer.calls[0].pattern, .levelChange)
        XCTAssertEqual(performer.calls[0].time, .default)

        performer.calls.removeAll()
        let playedAttention = HapticFeedback.play(.attention, performer: performer, defaults: defaults)
        XCTAssertTrue(playedAttention)
        XCTAssertEqual(performer.calls.count, 2)
        XCTAssertEqual(performer.calls[0].pattern, .generic)
        XCTAssertEqual(performer.calls[0].time, .default)
        XCTAssertEqual(performer.calls[1].pattern, .alignment)
        XCTAssertEqual(performer.calls[1].time, .default)

        performer.calls.removeAll()
        let playedAllow = HapticFeedback.play(.allow, performer: performer, defaults: defaults)
        XCTAssertTrue(playedAllow)
        XCTAssertEqual(performer.calls.map(\.pattern), [.alignment])

        performer.calls.removeAll()
        let playedDeny = HapticFeedback.play(.deny, performer: performer, defaults: defaults)
        XCTAssertTrue(playedDeny)
        XCTAssertEqual(performer.calls.map(\.pattern), [.generic])

        performer.calls.removeAll()
        let playedFinished = HapticFeedback.play(.finished, performer: performer, defaults: defaults)
        XCTAssertTrue(playedFinished)
        XCTAssertEqual(performer.calls.map(\.pattern), [.alignment])

        performer.calls.removeAll()
        let playedSelection = HapticFeedback.play(.selection, performer: performer, defaults: defaults)
        XCTAssertTrue(playedSelection)
        XCTAssertEqual(performer.calls.map(\.pattern), [.alignment])
    }

    func testSuppressesFeedbackWhenDisabled() {
        let defaults = UserDefaults(suiteName: "pip.haptics.test.\(UUID().uuidString)")!
        defaults.set(false, forKey: PipDefaults.hapticsEnabled)
        let performer = MockPerformer()

        for pattern in HapticPattern.allCases {
            let played = HapticFeedback.play(pattern, performer: performer, defaults: defaults)
            XCTAssertFalse(played)
        }

        XCTAssertTrue(performer.calls.isEmpty, "No feedback should be performed when haptics are disabled")
    }
}
