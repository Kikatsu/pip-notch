import AVFoundation

enum SoundCue: String, CaseIterable, Identifiable {
    case approval, finished, error, rateLimited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approval: "Needs You"
        case .finished: "Finished"
        case .error: "Error"
        case .rateLimited: "Rate Limit"
        }
    }

    var detail: String {
        switch self {
        case .approval: "An agent asks for approval or input"
        case .finished: "A task is done"
        case .error: "A turn fails"
        case .rateLimited: "You hit a usage limit"
        }
    }
}

/// A set of sounds for every cue. All but `system` are synthesized by Pip, so nothing needs a licence;
/// `system` uses the alert sounds that ship with macOS.
enum SoundPack: String, CaseIterable, Identifiable {
    case pip, soft, arcade, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pip: "Pip"
        case .soft: "Soft"
        case .arcade: "Arcade"
        case .system: "macOS"
        }
    }

    var detail: String {
        switch self {
        case .pip: "Bright bells and marimba"
        case .soft: "Quiet glass and wood"
        case .arcade: "8-bit blips"
        case .system: "Glass, Ping, Basso and Submarine"
        }
    }
}

/// Where each cue's sound comes from: a file the user chose, a macOS alert, or the synthesizer.
enum SoundLibrary {
    static let maxCustomDuration: TimeInterval = 15

    static var directory: URL { PipPaths.supportDirectory.appendingPathComponent("Sounds", isDirectory: true) }

    static func customKey(_ cue: SoundCue) -> String { "sound.custom.\(cue.rawValue)" }

    static var pack: SoundPack {
        SoundPack(rawValue: UserDefaults.standard.string(forKey: PipDefaults.soundPack) ?? "") ?? .pip
    }

    /// The user's own file for `cue`, if one was chosen and still exists.
    static func customURL(for cue: SoundCue, defaults: UserDefaults = .standard) -> URL? {
        guard let path = defaults.string(forKey: customKey(cue)), FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    static func systemURL(for cue: SoundCue) -> URL? {
        let name = switch cue {
        case .approval: "Ping"
        case .finished: "Glass"
        case .error: "Basso"
        case .rateLimited: "Submarine"
        }
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A file to play for `cue`, or nil to use the synthesizer.
    static func fileURL(for cue: SoundCue, pack: SoundPack = pack, defaults: UserDefaults = .standard) -> URL? {
        customURL(for: cue, defaults: defaults) ?? (pack == .system ? systemURL(for: cue) : nil)
    }

    /// Copies `source` into Pip's folder so the sound keeps working if the original moves.
    static func importFile(_ source: URL, for cue: SoundCue, defaults: UserDefaults = .standard) throws {
        let player = try AVAudioPlayer(contentsOf: source)
        guard player.duration > 0 else { throw SoundError.unreadable }
        guard player.duration <= maxCustomDuration else { throw SoundError.tooLong(player.duration) }

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        removeCustom(for: cue, defaults: defaults)
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent("\(cue.rawValue)-\(UUID().uuidString.prefix(8)).\(ext)")
        try fm.copyItem(at: source, to: destination)
        defaults.set(destination.path, forKey: customKey(cue))
    }

    static func removeCustom(for cue: SoundCue, defaults: UserDefaults = .standard) {
        if let url = customURL(for: cue, defaults: defaults), url.path.hasPrefix(directory.path) {
            try? FileManager.default.removeItem(at: url)
        }
        defaults.removeObject(forKey: customKey(cue))
    }

    enum SoundError: LocalizedError {
        case unreadable
        case tooLong(TimeInterval)

        var errorDescription: String? {
            switch self {
            case .unreadable: "That file isn't a sound Pip can play."
            case .tooLong(let seconds): "That sound is \(Int(seconds.rounded())) seconds long. Choose one under \(Int(maxCustomDuration)) seconds."
            }
        }
    }
}

/// Plays Pip's sounds: custom files and macOS alerts through AVAudioPlayer, synthesized cues
/// through a small AVAudioEngine that stops when quiet.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var filePlayer: AVAudioPlayer?
    private var lastPlayed: [SoundCue: Date] = [:]
    private var stopWork: DispatchWorkItem?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Plays `cue` if sounds and that cue are switched on. `preview` ignores both switches.
    func play(_ cue: SoundCue, preview: Bool = false, pack: SoundPack? = nil) {
        let defaults = UserDefaults.standard
        if !preview {
            guard defaults.bool(forKey: PipDefaults.soundsEnabled), defaults.bool(forKey: PipDefaults.soundKey(cue)) else { return }
            if let last = lastPlayed[cue], Date().timeIntervalSince(last) < 1.5 { return }
        }
        lastPlayed[cue] = Date()
        let volume = Float(defaults.double(forKey: PipDefaults.soundVolume))
        let pack = pack ?? SoundLibrary.pack

        if let url = SoundLibrary.fileURL(for: cue, pack: pack), playFile(url, volume: volume) { return }
        playSynth(cue, pack: pack == .system ? .pip : pack, volume: volume)
    }

    private func playFile(_ url: URL, volume: Float) -> Bool {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        player.volume = volume
        player.play()
        filePlayer = player
        return true
    }

    private func playSynth(_ cue: SoundCue, pack: SoundPack, volume: Float) {
        let key = "\(pack.rawValue).\(cue.rawValue)"
        if buffers[key] == nil { buffers[key] = Synth.buffer(for: cue, pack: pack, format: format) }
        guard let buffer = buffers[key] else { return }

        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            NSLog("Pip: audio engine failed to start: \(error)")
            return
        }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()

        // Stop the engine once quiet so Pip uses no audio resources while idle.
        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.player.stop()
            self?.engine.stop()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(buffer.frameLength) / Synth.sampleRate + 0.5, execute: work)
    }
}

/// A tiny additive synthesizer: tuned partials with an envelope, a short echo and a soft limiter.
enum Synth {
    static let sampleRate = 44_100.0

    struct Note {
        let start: Double
        let frequency: Double
        let duration: Double
        let amplitude: Double
        let timbre: Timbre
    }

    enum Timbre {
        case bell, marimba, knock, glass, chip

        /// (frequency ratio, relative amplitude)
        var partials: [(Double, Double)] {
            switch self {
            case .bell: [(1, 1), (2, 0.45), (2.76, 0.28), (5.4, 0.1), (8.93, 0.04)]
            case .marimba: [(1, 1), (4, 0.22), (9.9, 0.05)]
            case .knock: [(1, 1), (2.3, 0.35), (3.9, 0.12)]
            case .glass: [(1, 1), (2, 0.18), (3, 0.06)]
            // Odd harmonics approximate a square wave: the classic 8-bit voice.
            case .chip: [(1, 1), (3, 0.33), (5, 0.2), (7, 0.14), (9, 0.11)]
            }
        }

        var attack: Double { self == .glass ? 0.02 : self == .chip ? 0.002 : 0.004 }
        /// Chips hold at full level and stop; everything else rings out.
        var sustains: Bool { self == .chip }
    }

    static func notes(for cue: SoundCue, pack: SoundPack = .pip) -> [Note] {
        switch (pack, cue) {
        case (.pip, .approval), (.system, .approval):
            return [
                Note(start: 0, frequency: 659.25, duration: 1.0, amplitude: 0.42, timbre: .bell),
                Note(start: 0.16, frequency: 987.77, duration: 1.2, amplitude: 0.38, timbre: .bell),
            ]
        case (.pip, .finished), (.system, .finished):
            return [523.25, 659.25, 783.99, 1046.5].enumerated().map { i, f in
                Note(start: Double(i) * 0.075, frequency: f, duration: i == 3 ? 1.3 : 0.7, amplitude: 0.3, timbre: .marimba)
            } + [Note(start: 0.3, frequency: 2093.0, duration: 1.1, amplitude: 0.07, timbre: .bell)]
        case (.pip, .error), (.system, .error):
            return [
                Note(start: 0, frequency: 220, duration: 0.35, amplitude: 0.55, timbre: .knock),
                Note(start: 0.14, frequency: 174.61, duration: 0.45, amplitude: 0.5, timbre: .knock),
            ]
        case (.pip, .rateLimited), (.system, .rateLimited):
            return [880, 739.99, 587.33].enumerated().map { i, f in
                Note(start: Double(i) * 0.13, frequency: f, duration: 0.9, amplitude: 0.22, timbre: .glass)
            }

        case (.soft, .approval):
            return [
                Note(start: 0, frequency: 880, duration: 1.1, amplitude: 0.22, timbre: .glass),
                Note(start: 0.2, frequency: 1318.5, duration: 1.3, amplitude: 0.18, timbre: .glass),
            ]
        case (.soft, .finished):
            return [392, 493.88, 587.33].enumerated().map { i, f in
                Note(start: Double(i) * 0.11, frequency: f, duration: 0.8, amplitude: 0.26, timbre: .marimba)
            }
        case (.soft, .error):
            return [Note(start: 0, frequency: 196, duration: 0.5, amplitude: 0.4, timbre: .knock)]
        case (.soft, .rateLimited):
            return [
                Note(start: 0, frequency: 659.25, duration: 1.0, amplitude: 0.16, timbre: .glass),
                Note(start: 0.22, frequency: 523.25, duration: 1.2, amplitude: 0.16, timbre: .glass),
            ]

        case (.arcade, .approval):
            return [
                Note(start: 0, frequency: 1318.5, duration: 0.09, amplitude: 0.16, timbre: .chip),
                Note(start: 0.13, frequency: 1318.5, duration: 0.09, amplitude: 0.16, timbre: .chip),
            ]
        case (.arcade, .finished):
            return [523.25, 659.25, 783.99, 1046.5, 1318.5].enumerated().map { i, f in
                Note(start: Double(i) * 0.065, frequency: f, duration: i == 4 ? 0.26 : 0.07, amplitude: 0.15, timbre: .chip)
            }
        case (.arcade, .error):
            return [392, 329.63, 261.63].enumerated().map { i, f in
                Note(start: Double(i) * 0.1, frequency: f, duration: i == 2 ? 0.25 : 0.09, amplitude: 0.17, timbre: .chip)
            }
        case (.arcade, .rateLimited):
            return [
                Note(start: 0, frequency: 130.81, duration: 0.16, amplitude: 0.2, timbre: .chip),
                Note(start: 0.22, frequency: 130.81, duration: 0.3, amplitude: 0.2, timbre: .chip),
            ]
        }
    }

    static func buffer(for cue: SoundCue, pack: SoundPack = .pip, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let samples = render(notes(for: cue, pack: pack))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, sample) in samples.enumerated() { channel[i] = sample }
        return buffer
    }

    static func render(_ notes: [Note]) -> [Float] {
        let end = (notes.map { $0.start + $0.duration }.max() ?? 0) + 0.35
        var out = [Double](repeating: 0, count: Int(end * sampleRate))

        for note in notes {
            let first = Int(note.start * sampleRate)
            let length = Int(note.duration * sampleRate)
            let release = 0.012
            for (ratio, weight) in note.timbre.partials {
                let frequency = note.frequency * ratio
                guard frequency < sampleRate / 2 else { continue }
                // Higher partials ring shorter, as on a struck bar or bell.
                let tau = note.duration / 4 / sqrt(ratio)
                let step = 2 * Double.pi * frequency / sampleRate
                for n in 0..<length where first + n < out.count {
                    let t = Double(n) / sampleRate
                    let envelope: Double
                    if t < note.timbre.attack {
                        envelope = t / note.timbre.attack
                    } else if note.timbre.sustains {
                        envelope = min(1, (note.duration - t) / release)
                    } else {
                        envelope = exp(-(t - note.timbre.attack) / tau)
                    }
                    out[first + n] += note.amplitude * weight * envelope * sin(step * Double(n))
                }
            }
        }

        // Two quiet echoes give a sense of space without a reverb unit.
        let dry = out
        for (delay, gain) in [(0.083, 0.16), (0.149, 0.09)] {
            let offset = Int(delay * sampleRate)
            for i in offset..<out.count { out[i] += dry[i - offset] * gain }
        }

        let fadeOut = Int(0.02 * sampleRate)
        return out.enumerated().map { i, sample in
            let fade = i > out.count - fadeOut ? Double(out.count - i) / Double(fadeOut) : 1
            return Float(tanh(sample * 1.1) * fade)
        }
    }
}

enum PipDefaults {
    static let character = "character"
    static let soundsEnabled = "soundsEnabled"
    static let soundVolume = "soundVolume"
    static let soundPack = "soundPack"
    static let hapticsEnabled = "hapticsEnabled"
    static let notificationsEnabled = "notificationsEnabled"

    static func soundKey(_ cue: SoundCue) -> String { "sound.\(cue.rawValue)" }

    static func register() {
        var values: [String: Any] = [
            character: CharacterStyle.livingNotch.rawValue,
            soundsEnabled: true,
            soundVolume: 0.6,
            soundPack: SoundPack.pip.rawValue,
            hapticsEnabled: true,
            notificationsEnabled: true,
        ]
        for cue in SoundCue.allCases { values[soundKey(cue)] = true }
        UserDefaults.standard.register(defaults: values)
    }
}
