import AVFoundation
import XCTest
@testable import Pip

final class SoundPackTests: XCTestCase {
    func testEverySynthesizedPackRendersCleanAudio() {
        for pack in [SoundPack.pip, .soft, .arcade] {
            for cue in SoundCue.allCases {
                let samples = Synth.render(Synth.notes(for: cue, pack: pack))
                let peak = samples.map(abs).max() ?? 0
                XCTAssertGreaterThan(peak, 0.05, "\(pack) \(cue) is audible")
                XCTAssertLessThan(peak, 1.0, "\(pack) \(cue) never clips")
            }
        }
    }

    func testPacksSoundDifferent() {
        let pip = Synth.notes(for: .finished, pack: .pip).map(\.frequency)
        let arcade = Synth.notes(for: .finished, pack: .arcade).map(\.frequency)
        XCTAssertNotEqual(pip, arcade)
    }

    func testMacOSPackUsesSystemAlerts() {
        for cue in SoundCue.allCases {
            XCTAssertEqual(SoundLibrary.fileURL(for: cue, pack: .system, defaults: UserDefaults(suiteName: UUID().uuidString)!)?.deletingPathExtension().lastPathComponent,
                           SoundLibrary.systemURL(for: cue)?.deletingPathExtension().lastPathComponent)
        }
        XCTAssertNil(SoundLibrary.fileURL(for: .finished, pack: .pip, defaults: UserDefaults(suiteName: UUID().uuidString)!))
    }

    func testCustomSoundImportOverridesThePackAndCanBeRemoved() throws {
        let defaults = UserDefaults(suiteName: "pip.sound.\(UUID().uuidString)")!
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("beep-\(UUID().uuidString).wav")
        try Self.writeWav(to: source, seconds: 0.3)
        defer { try? FileManager.default.removeItem(at: source) }

        try SoundLibrary.importFile(source, for: .finished, defaults: defaults)
        let custom = try XCTUnwrap(SoundLibrary.fileURL(for: .finished, pack: .pip, defaults: defaults))
        XCTAssertTrue(custom.path.hasPrefix(SoundLibrary.directory.path), "a copy lives in Pip's folder")
        XCTAssertEqual(SoundLibrary.fileURL(for: .finished, pack: .system, defaults: defaults), custom, "custom beats the pack")

        SoundLibrary.removeCustom(for: .finished, defaults: defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path))
        XCTAssertNil(SoundLibrary.customURL(for: .finished, defaults: defaults))
    }

    func testRejectsLongAndInvalidFiles() throws {
        let defaults = UserDefaults(suiteName: "pip.sound.\(UUID().uuidString)")!
        let long = FileManager.default.temporaryDirectory.appendingPathComponent("long-\(UUID().uuidString).wav")
        try Self.writeWav(to: long, seconds: SoundLibrary.maxCustomDuration + 2)
        defer { try? FileManager.default.removeItem(at: long) }
        XCTAssertThrowsError(try SoundLibrary.importFile(long, for: .error, defaults: defaults))

        let text = FileManager.default.temporaryDirectory.appendingPathComponent("not-audio-\(UUID().uuidString).mp3")
        try Data("hello".utf8).write(to: text)
        defer { try? FileManager.default.removeItem(at: text) }
        XCTAssertThrowsError(try SoundLibrary.importFile(text, for: .error, defaults: defaults))
        XCTAssertNil(SoundLibrary.customURL(for: .error, defaults: defaults))
    }

    private static func writeWav(to url: URL, seconds: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(seconds * 22_050)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 0.1) * 0.3) }
        try file.write(from: buffer)
    }
}
