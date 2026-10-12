import XCTest
@testable import Pip

@MainActor
final class OnboardingSoundsTests: XCTestCase {
    private var allSounds: [OnboardingSound] {
        [.whoosh, .whooshBack, .hello, .click, .pop, .fanfare]
            + (0..<10).map { OnboardingSound.blip($0) }
            + CharacterStyle.allCases.map { OnboardingSound.style($0) }
    }

    func testEverySoundIsAudibleAndNeverClips() {
        for sound in allSounds {
            let samples = OnboardingSounds.samples(for: sound)
            XCTAssertFalse(samples.isEmpty, "\(sound)")
            XCTAssertLessThan(Double(samples.count) / Synth.sampleRate, 3, "\(sound) runs too long")
            XCTAssertTrue(samples.allSatisfy(\.isFinite), "\(sound)")
            let peak = samples.map(abs).max() ?? 0
            XCTAssertGreaterThan(peak, 0.05, "\(sound) is too quiet")
            XCTAssertLessThan(peak, 0.95, "\(sound) clips")
            XCTAssertLessThan(abs(samples.last ?? 0), 0.01, "\(sound) ends with a click")
        }
    }
}
