import SwiftUI

enum CharacterStyle: String, CaseIterable, Identifiable {
    case livingNotch, blob, pixel, minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .livingNotch: "Living notch"
        case .blob: "Burrow blob"
        case .pixel: "Pixel bit"
        case .minimal: "Minimal"
        }
    }

    var subtitle: String {
        switch self {
        case .livingNotch: "The notch itself has eyes"
        case .blob: "A soft creature hanging from the notch"
        case .pixel: "An 8-bit sprite for terminal people"
        case .minimal: "No character, just a status dot"
        }
    }
}

/// The notch's character in the current mood. `large` is the expanded panel's size.
struct CharacterView: View {
    let mood: Mood
    var large = false
    /// Forces a style (settings previews); otherwise the user's choice is used.
    var style: CharacterStyle?
    /// Where the eyes look, -1...1 per axis.
    var gaze: CGSize = .zero
    var reaction: FaceState.Reaction?
    var reactionStart: Date = .distantPast

    @AppStorage(PipDefaults.character) private var storedStyle = CharacterStyle.livingNotch.rawValue

    private var resolvedStyle: CharacterStyle { style ?? CharacterStyle(rawValue: storedStyle) ?? .livingNotch }

    var body: some View {
        let style = resolvedStyle
        let reacting = reaction != nil && Date().timeIntervalSince(reactionStart) < (reaction?.duration ?? 0)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: mood == .asleep && !reacting && (style == .livingNotch || style == .minimal))) { context in
            Canvas { gc, size in
                let t = context.date.timeIntervalSinceReferenceDate
                let (mood, scale) = Self.react(mood, reaction, age: context.date.timeIntervalSince(reactionStart))
                if scale != CGSize(width: 1, height: 1) {
                    gc.translateBy(x: size.width / 2, y: size.height / 2)
                    gc.scaleBy(x: scale.width, y: scale.height)
                    gc.translateBy(x: -size.width / 2, y: -size.height / 2)
                }
                let reach: CGFloat = large ? 5 : 1.6
                gc.translateBy(x: gaze.width * reach, y: gaze.height * reach * 0.6)
                switch style {
                case .livingNotch:
                    EyeRenderer.draw(mood, time: t, in: &gc, size: size, eyeWidth: large ? 13 : 6, color: .white)
                case .blob:
                    BlobRenderer.draw(mood, time: t, in: &gc, size: size, large: large)
                case .pixel:
                    PixelRenderer.draw(mood, time: t, in: &gc, size: size, large: large)
                case .minimal:
                    MinimalRenderer.draw(mood, time: t, in: &gc, size: size, large: large)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(Palette.label(for: mood)))
    }

    /// The mood to draw while a reaction plays, and how to stretch the face.
    static func react(_ mood: Mood, _ reaction: FaceState.Reaction?, age: TimeInterval) -> (Mood, CGSize) {
        guard let reaction, age >= 0, age < reaction.duration else { return (mood, CGSize(width: 1, height: 1)) }
        let progress = age / reaction.duration
        let swell = CGFloat(sin(progress * .pi))
        switch reaction {
        case .hello:
            let pop = 1 + 0.18 * swell
            return (mood == .asleep ? .idle : mood, CGSize(width: pop, height: pop))
        case .poke:
            let wobble = CGFloat(sin(progress * .pi * 3)) * (1 - CGFloat(progress))
            return (.finished, CGSize(width: 1 + 0.16 * wobble, height: 1 - 0.2 * wobble))
        case .approve:
            return (.finished, CGSize(width: 1 + 0.08 * swell, height: 1 + 0.08 * swell))
        case .deny:
            return (.rateLimited, CGSize(width: 1 + 0.06 * swell, height: 1 - 0.1 * swell))
        }
    }

    /// Frame for the character in the expanded panel.
    static func largeSize(for style: CharacterStyle) -> CGSize {
        switch style {
        case .livingNotch, .minimal: CGSize(width: 96, height: 30)
        case .blob, .pixel: CGSize(width: 96, height: 58)
        }
    }
}

/// The notch's character wired to its live state: eyes follow the pointer, clicks get a reaction.
struct InteractiveFace: View {
    let mood: Mood
    var large = false
    @ObservedObject var face: FaceState

    var body: some View {
        CharacterView(mood: mood, large: large, gaze: face.gaze, reaction: face.reaction, reactionStart: face.reactionStart)
            .contentShape(Rectangle())
            .onTapGesture { face.react(.poke) }
            .help(large ? "Say hi" : "")
    }
}

/// Minimal: no character at all. One small dot whose colour and motion carry the mood.
enum MinimalRenderer {
    static func draw(_ mood: Mood, time t: Double, in gc: inout GraphicsContext, size: CGSize, large: Bool) {
        let r: CGFloat = large ? 5 : 3.5
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        func dot(_ radius: CGFloat, _ color: Color) {
            gc.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        }

        switch mood {
        case .asleep:
            break
        case .idle:
            dot(r, .white.opacity(0.35))
        case .working:
            dot(r, .white.opacity(0.45 + 0.55 * (sin(t * 3) + 1) / 2))
        case .needsYou:
            let p = CGFloat((t * 0.85).truncatingRemainder(dividingBy: 1))
            dot(r * (1 + 1.6 * p), Palette.amber.opacity(Double(1 - p) * 0.8))
            dot(r, Palette.amber)
        case .error:
            dot(r, Palette.red)
        case .rateLimited:
            dot(r, Palette.amber.opacity(0.6))
        case .finished:
            dot(r, Palette.green)
        }
    }
}

/// Option A: an orange creature hanging out of the notch, drawn in a 120 x 112 design space.
enum BlobRenderer {
    static let body = Color(red: 0.94, green: 0.54, blue: 0.29)
    static let ink = Color(red: 0.12, green: 0.11, blue: 0.09)

    static func draw(_ mood: Mood, time t: Double, in gc: inout GraphicsContext, size: CGSize, large: Bool) {
        let scale = min(size.height / 112, size.width / 120)
        var g = gc
        g.translateBy(x: size.width / 2 - 60 * scale, y: 0)
        g.scaleBy(x: scale, y: scale)

        var shrink: CGFloat = 1
        var opacity = 1.0
        switch mood {
        case .working:
            g.translateBy(x: 60, y: 0)
            g.scaleBy(x: 1, y: 1 + 0.035 * CGFloat(sin(t * 3)))
            g.translateBy(x: -60, y: 0)
        case .needsYou:
            g.translateBy(x: 60, y: 0)
            g.rotate(by: .degrees(5 * sin(t * 5.5)))
            g.translateBy(x: -60, y: 0)
        case .finished:
            g.translateBy(x: 0, y: abs(CGFloat(sin(t * 4.5))) * 9)
        case .error:
            let shaking = t.truncatingRemainder(dividingBy: 2.2) < 0.5
            g.translateBy(x: shaking ? CGFloat(sin(t * 46)) * 3 : 0, y: 0)
            opacity = 0.85
        case .rateLimited:
            g.translateBy(x: 60, y: 0)
            g.scaleBy(x: 1.03, y: 0.9)
            g.translateBy(x: -60, y: 0)
        case .asleep:
            shrink = 0.78
            opacity = 0.75
        case .idle:
            break
        }

        g.translateBy(x: 60, y: 0)
        g.scaleBy(x: shrink, y: shrink)
        g.translateBy(x: -60, y: 0)

        var shape = Path()
        shape.move(to: CGPoint(x: 20, y: 0))
        shape.addLine(to: CGPoint(x: 20, y: 48))
        shape.addCurve(to: CGPoint(x: 60, y: 98), control1: CGPoint(x: 20, y: 82), control2: CGPoint(x: 38, y: 98))
        shape.addCurve(to: CGPoint(x: 100, y: 48), control1: CGPoint(x: 82, y: 98), control2: CGPoint(x: 100, y: 82))
        shape.addLine(to: CGPoint(x: 100, y: 0))
        shape.closeSubpath()
        g.fill(shape, with: .color(body.opacity(opacity)))

        if large || mood != .asleep {
            for cx in [36.0, 84.0] {
                g.fill(Path(ellipseIn: CGRect(x: cx - 6, y: 66, width: 12, height: 9)), with: .color(Color(red: 0.76, green: 0.25, blue: 0.05).opacity(0.3)))
            }
        }

        var eyes = g
        eyes.translateBy(x: 0, y: 10)
        EyeRenderer.draw(mood, time: t, in: &eyes, size: CGSize(width: 120, height: 92), eyeWidth: 11, color: ink, pupil: .white)

        guard large else { return }
        switch mood {
        case .finished:
            let colors: [Color] = [Palette.amber, .blue, Palette.amber, .blue]
            for (i, point) in [CGPoint(x: 6, y: 60), CGPoint(x: 108, y: 50), CGPoint(x: 12, y: 96), CGPoint(x: 104, y: 92)].enumerated() {
                let phase = (t * 0.8 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                let rect = CGRect(x: point.x, y: point.y - phase * 14, width: 6, height: 9)
                gc.opacity = 1 - phase
                var piece = gc
                piece.translateBy(x: size.width / 2 - 60 * scale, y: 0)
                piece.scaleBy(x: scale, y: scale)
                piece.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(colors[i]))
                gc.opacity = 1
            }
        case .error:
            let phase = (t * 0.6).truncatingRemainder(dividingBy: 1)
            var puff = gc
            puff.translateBy(x: size.width / 2 - 60 * scale, y: 0)
            puff.scaleBy(x: scale, y: scale)
            puff.opacity = 0.6 * (1 - phase)
            puff.fill(Path(ellipseIn: CGRect(x: 102, y: 80 - phase * 16, width: 12, height: 12)), with: .color(.gray))
        case .needsYou:
            var mark = gc
            mark.translateBy(x: size.width / 2 + 52 * scale, y: 30 * scale)
            mark.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 7, height: 7)), with: .color(Palette.amber))
        default:
            break
        }
    }
}

/// Option B: an 8-bit sprite on a 12 x 13 grid. Motion moves in whole steps, like an old game.
enum PixelRenderer {
    static let body = Color(red: 0.65, green: 0.55, blue: 0.98)
    static let ink = Color(red: 0.05, green: 0.07, blue: 0.09)
    static let green = Color(red: 0.29, green: 0.87, blue: 0.5)

    static func draw(_ mood: Mood, time t: Double, in gc: inout GraphicsContext, size: CGSize, large: Bool) {
        let u = floor(min(size.height / 13, size.width / 12) * 2) / 2
        let originX = (size.width - 12 * u) / 2
        let step = Int(t * 2.5)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var bodyRows: CGFloat = 7
        var opacity = 1.0

        switch mood {
        case .working: dy = step % 2 == 0 ? 0 : 0.5
        case .error: dx = t.truncatingRemainder(dividingBy: 2.2) < 0.6 ? (step % 2 == 0 ? -0.5 : 0.5) : 0
        case .finished: dy = Int(t * 2) % 3 == 0 ? 1 : 0
        case .asleep:
            bodyRows = 5
            opacity = 0.7
        default: break
        }

        func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
            gc.fill(Path(CGRect(x: originX + (x + dx) * u, y: (y + dy) * u, width: w * u, height: h * u)), with: .color(color))
        }

        // Body with a ghost-like fringe, and a shaded right edge for depth.
        px(2, 0, 8, bodyRows, body.opacity(opacity))
        for x in [2.0, 5.0, 8.0] { px(x, bodyRows, 2, 1, body.opacity(opacity)) }
        px(9, 0, 1, bodyRows, Color.black.opacity(0.2))

        let eyes: [CGFloat] = [4, 7]
        switch mood {
        case .idle:
            let blink = t.truncatingRemainder(dividingBy: 4) < 0.15
            for x in eyes { px(x, blink ? 3.5 : 3, 1, blink ? 0.5 : 2, ink) }
        case .working:
            let look: CGFloat = step % 4 < 2 ? -0.5 : 0.5
            for x in eyes { px(x + look, 4, 1, 1, ink) }
            if large, step % 2 == 0 { px(5, 9.5, 2, 1, green) }
        case .needsYou:
            for x in eyes {
                px(x, 2.5, 1, 2.5, ink)
                px(x, 2.5, 0.5, 0.5, .white)
            }
            if Int(t * 3) % 2 == 0 {
                px(10.5, 2, 1, 2.5, Palette.amber)
                px(10.5, 5, 1, 1, Palette.amber)
            }
        case .error:
            for x in eyes {
                px(x - 0.5, 3, 0.5, 0.5, ink); px(x + 0.5, 3, 0.5, 0.5, ink)
                px(x, 3.5, 0.5, 0.5, ink)
                px(x - 0.5, 4, 0.5, 0.5, ink); px(x + 0.5, 4, 0.5, 0.5, ink)
            }
            if large { px(10.5, 8 - CGFloat(step % 3), 1, 1, .gray) }
        case .rateLimited:
            for x in eyes { px(x - 0.5, 4, 2, 0.5, ink) }
            px(10.5, 1, 1, 1, Palette.amber)
        case .finished:
            for x in eyes {
                px(x - 0.5, 4, 0.5, 0.5, ink)
                px(x, 3.5, 0.5, 0.5, ink)
                px(x + 0.5, 4, 0.5, 0.5, ink)
            }
            if large, step % 2 == 0 {
                px(0, 4, 0.5, 1.5, green); px(-0.5, 4.5, 1.5, 0.5, green)
                px(11.5, 7, 0.5, 1.5, green); px(11, 7.5, 1.5, 0.5, green)
            }
        case .asleep:
            for x in eyes { px(x - 0.5, 3, 1.5, 0.5, ink) }
        }
    }
}
