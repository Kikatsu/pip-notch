import SwiftUI

/// The right ear of the compact notch: one glanceable mark for the current mood.
struct EarIndicator: View {
    let mood: Mood
    let workingCount: Int
    let sessionCount: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !mood.isAnimatedInEar)) { context in
            mark(t: context.date.timeIntervalSinceReferenceDate)
        }
    }

    @ViewBuilder
    private func mark(t: Double) -> some View {
        switch mood {
        case .working:
            HStack(spacing: 3) {
                if workingCount > 1 {
                    Text("\(workingCount)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.trailing, 1)
                }
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(.white)
                        .frame(width: 4, height: 4)
                        .opacity(0.25 + 0.75 * pulse(t, delay: Double(i) * 0.2))
                }
            }
        case .needsYou:
            let p = CGFloat((t * 0.85).truncatingRemainder(dividingBy: 1))
            ZStack {
                Circle().fill(Palette.amber).frame(width: 7, height: 7)
                    .scaleEffect(1 + 1.6 * p).opacity(Double(1 - p))
                Circle().fill(Palette.amber).frame(width: 7, height: 7)
            }
        case .error:
            Circle().fill(Palette.red).frame(width: 7, height: 7)
        case .rateLimited:
            Image(systemName: "hourglass")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.amber)
        case .finished:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Palette.green)
        case .idle:
            Text("\(sessionCount)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        case .asleep:
            EmptyView()
        }
    }

    private func pulse(_ t: Double, delay: Double) -> Double {
        (sin((t - delay) * 2 * .pi / 1.2) + 1) / 2
    }
}

private extension Mood {
    var isAnimatedInEar: Bool { self == .working || self == .needsYou }
}
