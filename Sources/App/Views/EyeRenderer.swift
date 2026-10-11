import SwiftUI

enum EyeRenderer {
    static func draw(_ mood: Mood, time t: Double, in gc: inout GraphicsContext, size: CGSize, eyeWidth w: CGFloat, color: Color, pupil: Color = .black) {
        let h = w * 1.4
        let cx = size.width / 2
        let cy = size.height / 2
        let spread = w * 1.15
        let fill = GraphicsContext.Shading.color(color)
        let stroke = StrokeStyle(lineWidth: max(1.5, w * 0.32), lineCap: .round, lineJoin: .round)
        let sides: [CGFloat] = [-1, 1]

        func oval(_ x: CGFloat, _ y: CGFloat, _ ow: CGFloat, _ oh: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: x - ow / 2, y: y - oh / 2, width: ow, height: oh))
        }

        switch mood {
        case .idle:
            let phase = t.truncatingRemainder(dividingBy: 4.6)
            let open: CGFloat = phase < 0.14 ? 0.12 : 1
            let look = CGFloat(sin(t * 0.45)) * w * 0.25
            for side in sides {
                gc.fill(oval(cx + side * spread + look, cy, w, h * open), with: fill)
            }

        case .working:
            let look = CGFloat(sin(t * 2.6)) * w * 0.55
            for side in sides {
                gc.fill(oval(cx + side * spread + look, cy + h * 0.05, w * 0.9, h * 0.8), with: fill)
            }

        case .needsYou:
            let bounce = -abs(CGFloat(sin(t * 4.2))) * h * 0.12
            for side in sides {
                let x = cx + side * spread * 1.1
                gc.fill(oval(x, cy + bounce, w * 1.15, h * 1.15), with: fill)
                gc.fill(oval(x, cy + bounce + h * 0.2, w * 0.5, w * 0.5), with: .color(pupil))
            }

        case .error:
            let jitter = t.truncatingRemainder(dividingBy: 2.2) < 0.5 ? CGFloat(sin(t * 48)) * w * 0.15 : 0
            let r = w * 0.5
            for side in sides {
                let x = cx + side * spread + jitter
                var cross = Path()
                cross.move(to: CGPoint(x: x - r, y: cy - r))
                cross.addLine(to: CGPoint(x: x + r, y: cy + r))
                cross.move(to: CGPoint(x: x + r, y: cy - r))
                cross.addLine(to: CGPoint(x: x - r, y: cy + r))
                gc.stroke(cross, with: fill, style: stroke)
            }

        case .rateLimited:
            let sway = CGFloat(sin(t * 0.8)) * w * 0.15
            for side in sides {
                let x = cx + side * spread + sway
                var lower = gc
                lower.clip(to: Path(CGRect(x: x - w, y: cy - h * 0.05, width: w * 2, height: h)))
                lower.fill(oval(x, cy, w, h), with: fill)
                var lid = Path()
                lid.move(to: CGPoint(x: x - w * 0.6, y: cy - h * 0.05))
                lid.addLine(to: CGPoint(x: x + w * 0.6, y: cy - h * 0.05))
                gc.stroke(lid, with: fill, style: stroke)
            }

        case .finished:
            let hop = -abs(CGFloat(sin(t * 5.0))) * h * 0.18
            for side in sides {
                let x = cx + side * spread
                var arc = Path()
                arc.move(to: CGPoint(x: x - w * 0.6, y: cy + h * 0.18 + hop))
                arc.addQuadCurve(to: CGPoint(x: x + w * 0.6, y: cy + h * 0.18 + hop), control: CGPoint(x: x, y: cy - h * 0.55 + hop))
                gc.stroke(arc, with: fill, style: stroke)
            }

        case .asleep:
            let alpha = 0.35 + 0.35 * (sin(t * 1.4) + 1) / 2
            for side in sides {
                let x = cx + side * spread
                var lid = Path()
                lid.move(to: CGPoint(x: x - w * 0.6, y: cy))
                lid.addQuadCurve(to: CGPoint(x: x + w * 0.6, y: cy), control: CGPoint(x: x, y: cy + h * 0.45))
                gc.stroke(lid, with: .color(color.opacity(alpha)), style: stroke)
            }
        }
    }
}

enum Palette {
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let red = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let green = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let quiet = Color(white: 0.64)
    static let faint = Color(white: 1, opacity: 0.08)

    static func label(for mood: Mood) -> String {
        switch mood {
        case .needsYou: "An agent needs you"
        case .error: "An agent hit an error"
        case .rateLimited: "Rate limit reached"
        case .finished: "An agent finished"
        case .working: "Agents working"
        case .idle: "Agents idle"
        case .asleep: "No agents running"
        }
    }

    static func color(for state: SessionState) -> Color {
        switch state {
        case .needsInput: amber
        case .error: red
        case .rateLimited: amber
        case .finished: green
        case .working: .white
        case .idle: quiet
        }
    }
}
