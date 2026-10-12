import AVFoundation

/// Little sounds for the welcome tour, synthesized like the rest of Pip's sounds so nothing needs a licence.
/// They follow the Sounds switch and volume, so turning sounds off in the tour silences the rest of it.
enum OnboardingSound: Hashable {
    /// Moving to the next step.
    case whoosh
    /// Moving back a step: the same air, lower and shorter.
    case whooshBack
    /// The notch opens its eyes.
    case hello
    /// A row or chip lands; `index` climbs a pentatonic scale so a run of them sounds like a phrase.
    case blip(Int)
    /// Picking a personality: each one has its own voice.
    case style(CharacterStyle)
    /// A switch or button in the tour.
    case click
    /// Confetti.
    case pop
    /// The last step.
    case fanfare
}

@MainActor
final class OnboardingSounds {
    static let shared = OnboardingSounds()

    private let engine = AVAudioEngine()
    /// A few voices, so a blip doesn't cut off the whoosh it lands on.
    private let voices = (0..<4).map { _ in AVAudioPlayerNode() }
    private var nextVoice = 0
    private let format = AVAudioFormat(standardFormatWithSampleRate: Synth.sampleRate, channels: 1)!
    private var buffers: [OnboardingSound: AVAudioPCMBuffer] = [:]
    private var stopWork: DispatchWorkItem?

    private init() {
        for voice in voices {
            engine.attach(voice)
            engine.connect(voice, to: engine.mainMixerNode, format: format)
        }
    }

    func play(_ sound: OnboardingSound) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: PipDefaults.soundsEnabled) else { return }
        if buffers[sound] == nil { buffers[sound] = makeBuffer(Self.samples(for: sound)) }
        guard let buffer = buffers[sound] else { return }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            NSLog("Pip: audio engine failed to start: \(error)")
            return
        }
        let voice = voices[nextVoice]
        nextVoice = (nextVoice + 1) % voices.count
        voice.volume = Float(defaults.double(forKey: PipDefaults.soundVolume))
        voice.scheduleBuffer(buffer, at: nil, options: .interrupts)
        voice.play()

        stopWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.voices.forEach { $0.stop() }
            self.engine.stop()
        }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, sample) in samples.enumerated() { channel[i] = sample }
        return buffer
    }

    // MARK: Sound design

    /// C major pentatonic from C6 up, for runs of blips.
    private static let scale: [Double] = [1046.5, 1174.66, 1318.51, 1567.98, 1760.0, 2093.0, 2349.32, 2637.02]

    static func samples(for sound: OnboardingSound) -> [Float] {
        typealias Note = Synth.Note
        switch sound {
        case .whoosh:
            return noiseSweep(duration: 0.42, from: 350, to: 2600, gain: 0.22)
        case .whooshBack:
            return noiseSweep(duration: 0.32, from: 1800, to: 300, gain: 0.18)
        case .hello:
            return Synth.render([
                Note(start: 0, frequency: 783.99, duration: 0.9, amplitude: 0.26, timbre: .bell),
                Note(start: 0.11, frequency: 1174.66, duration: 1.1, amplitude: 0.24, timbre: .bell),
                Note(start: 0.22, frequency: 1567.98, duration: 1.2, amplitude: 0.1, timbre: .glass),
            ])
        case .blip(let index):
            let frequency = scale[min(max(index, 0), scale.count - 1)]
            return Synth.render([Note(start: 0, frequency: frequency, duration: 0.35, amplitude: 0.16, timbre: .marimba)])
        case .style(let style):
            switch style {
            case .livingNotch:
                return Synth.render([
                    Note(start: 0, frequency: 1318.51, duration: 0.8, amplitude: 0.2, timbre: .bell),
                    Note(start: 0.08, frequency: 1975.53, duration: 0.9, amplitude: 0.14, timbre: .bell),
                ])
            case .blob:
                return boing()
            case .pixel:
                return Synth.render([
                    Note(start: 0, frequency: 987.77, duration: 0.06, amplitude: 0.13, timbre: .chip),
                    Note(start: 0.07, frequency: 1318.51, duration: 0.12, amplitude: 0.13, timbre: .chip),
                ])
            case .minimal:
                return Synth.render([Note(start: 0, frequency: 1760, duration: 0.5, amplitude: 0.16, timbre: .glass)])
            }
        case .click:
            return click()
        case .pop:
            return pop()
        case .fanfare:
            let arpeggio = [523.25, 659.25, 783.99, 1046.5, 1318.51].enumerated().map { i, f in
                Note(start: Double(i) * 0.07, frequency: f, duration: i == 4 ? 1.4 : 0.6, amplitude: 0.24, timbre: .marimba)
            }
            let shimmer = [2093.0, 2637.02, 3135.96].enumerated().map { i, f in
                Note(start: 0.36 + Double(i) * 0.09, frequency: f, duration: 1.2, amplitude: 0.06, timbre: .bell)
            }
            return Synth.render(arpeggio + shimmer)
        }
    }

    /// Air through a band-pass filter whose centre glides, swelling in and out.
    private static func noiseSweep(duration: Double, from start: Double, to end: Double, gain: Double) -> [Float] {
        let rate = Synth.sampleRate
        let count = Int(duration * rate)
        var seed: UInt32 = 0x9E37_79B9
        var low = 0.0, band = 0.0
        return (0..<count).map { n in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            let progress = Double(n) / Double(count)
            // Exponential glide sounds even to the ear.
            let centre = start * pow(end / start, progress)
            let f = 2 * sin(Double.pi * centre / rate)
            let q = 0.6
            low += f * band
            let high = noise - low - q * band
            band += f * high
            let envelope = pow(sin(Double.pi * progress), 1.6)
            return Float(tanh(band * gain * envelope * 2.2))
        }
    }

    /// A soft, rubbery drop in pitch for the blob.
    private static func boing() -> [Float] {
        let rate = Synth.sampleRate
        let duration = 0.32
        var phase = 0.0
        return (0..<Int(duration * rate)).map { n in
            let t = Double(n) / rate
            let frequency = 180 + 260 * exp(-t * 14) + 18 * sin(t * 2 * .pi * 11) * exp(-t * 6)
            phase += 2 * .pi * frequency / rate
            let fadeOut = min(1, (duration - t) / 0.04)
            let envelope = min(1, t / 0.005) * exp(-t * 9) * fadeOut
            return Float(0.32 * envelope * (sin(phase) + 0.2 * sin(2 * phase)))
        }
    }

    /// A bubble: a sine that falls fast in pitch.
    private static func pop() -> [Float] {
        let rate = Synth.sampleRate
        var phase = 0.0
        return (0..<Int(0.09 * rate)).map { n in
            let t = Double(n) / rate
            phase += 2 * .pi * (420 + 900 * exp(-t * 60)) / rate
            return Float(0.18 * min(1, t / 0.002) * exp(-t * 45) * sin(phase))
        }
    }

    /// A tiny tick, like a physical switch.
    private static func click() -> [Float] {
        let rate = Synth.sampleRate
        var seed: UInt32 = 0x1234_5678
        return (0..<Int(0.035 * rate)).map { n in
            let t = Double(n) / rate
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            let tone = sin(2 * .pi * 2400 * t) * exp(-t * 180)
            return Float(0.2 * (tone * 0.7 + noise * exp(-t * 900) * 0.5))
        }
    }
}
