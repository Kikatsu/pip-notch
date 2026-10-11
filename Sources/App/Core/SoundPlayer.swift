import AVFoundation

enum SoundCue: String, CaseIterable, Identifiable {
    case approval, finished, error, rateLimited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .approval: "Needs you"
        case .finished: "Finished"
        case .error: "Error"
        case .rateLimited: "Rate limit"
        }
    }

    var detail: String {
        switch self {
        case .approval: "Two rising bells when an agent asks for approval or input"
        case .finished: "A short sparkling arpeggio when a task is done"
        case .error: "A soft low double knock when a turn fails"
        case .rateLimited: "A gentle falling chime when you hit a usage limit"
        }
    }
}

/// Plays Pip's sounds. Every cue is synthesized here at launch, so there are no audio files
/// to license and the sound matches the notch's calm character.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    private lazy var buffers: [SoundCue: AVAudioPCMBuffer] = Dictionary(
        uniqueKeysWithValues: SoundCue.allCases.compactMap { cue in Synth.buffer(for: cue, format: format).map { (cue, $0) } }
    )
    private var lastPlayed: [SoundCue: Date] = [:]
    private var stopWork: DispatchWorkItem?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Plays `cue` if sounds and that cue are switched on. `preview` ignores both switches.
    func play(_ cue: SoundCue, preview: Bool = false) {
        let defaults = UserDefaults.standard
        if !preview {
            guard defaults.bool(forKey: PipDefaults.soundsEnabled), defaults.bool(forKey: PipDefaults.soundKey(cue)) else { return }
            if let last = lastPlayed[cue], Date().timeIntervalSince(last) < 1.5 { return }
        }
        lastPlayed[cue] = Date()
        guard let buffer = buffers[cue] else { return }

        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            NSLog("Pip: audio engine failed to start: \(error)")
            return
        }
        player.volume = Float(defaults.double(forKey: PipDefaults.soundVolume))
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

/// A tiny additive synthesizer: tuned partials with exponential decay, a short echo and a soft limiter.
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
        case bell, marimba, knock, glass

        /// (frequency ratio, relative amplitude)
        var partials: [(Double, Double)] {
            switch self {
            case .bell: [(1, 1), (2, 0.45), (2.76, 0.28), (5.4, 0.1), (8.93, 0.04)]
            case .marimba: [(1, 1), (4, 0.22), (9.9, 0.05)]
            case .knock: [(1, 1), (2.3, 0.35), (3.9, 0.12)]
            case .glass: [(1, 1), (2, 0.18), (3, 0.06)]
            }
        }

        var attack: Double { self == .glass ? 0.02 : 0.004 }
    }

    static func notes(for cue: SoundCue) -> [Note] {
        switch cue {
        case .approval:
            return [
                Note(start: 0, frequency: 659.25, duration: 1.0, amplitude: 0.42, timbre: .bell),
                Note(start: 0.16, frequency: 987.77, duration: 1.2, amplitude: 0.38, timbre: .bell),
            ]
        case .finished:
            return [523.25, 659.25, 783.99, 1046.5].enumerated().map { i, f in
                Note(start: Double(i) * 0.075, frequency: f, duration: i == 3 ? 1.3 : 0.7, amplitude: 0.3, timbre: .marimba)
            } + [Note(start: 0.3, frequency: 2093.0, duration: 1.1, amplitude: 0.07, timbre: .bell)]
        case .error:
            return [
                Note(start: 0, frequency: 220, duration: 0.35, amplitude: 0.55, timbre: .knock),
                Note(start: 0.14, frequency: 174.61, duration: 0.45, amplitude: 0.5, timbre: .knock),
            ]
        case .rateLimited:
            return [880, 739.99, 587.33].enumerated().map { i, f in
                Note(start: Double(i) * 0.13, frequency: f, duration: 0.9, amplitude: 0.22, timbre: .glass)
            }
        }
    }

    static func buffer(for cue: SoundCue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let samples = render(notes(for: cue))
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
            for (ratio, weight) in note.timbre.partials {
                let frequency = note.frequency * ratio
                guard frequency < sampleRate / 2 else { continue }
                // Higher partials ring shorter, as on a struck bar or bell.
                let tau = note.duration / 4 / sqrt(ratio)
                let step = 2 * Double.pi * frequency / sampleRate
                for n in 0..<length where first + n < out.count {
                    let t = Double(n) / sampleRate
                    let envelope = t < note.timbre.attack ? t / note.timbre.attack : exp(-(t - note.timbre.attack) / tau)
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

    static func soundKey(_ cue: SoundCue) -> String { "sound.\(cue.rawValue)" }

    static func register() {
        var values: [String: Any] = [
            character: CharacterStyle.livingNotch.rawValue,
            soundsEnabled: true,
            soundVolume: 0.6,
        ]
        for cue in SoundCue.allCases { values[soundKey(cue)] = true }
        UserDefaults.standard.register(defaults: values)
    }
}
