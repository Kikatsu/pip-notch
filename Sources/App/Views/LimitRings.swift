import SwiftUI

/// Plan usage as rings: one per window, coloured by how close you are to the limit.
struct LimitRings: View {
    let limits: [UsageLimit]
    let now: Date

    var body: some View {
        HStack(spacing: 14) {
            ForEach(limits.prefix(4)) { limit in
                LimitRing(limit: limit, now: now)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }
}

struct LimitRing: View {
    let limit: UsageLimit
    let now: Date

    private var fraction: Double { min(max(limit.usedPercent / 100, 0), 1) }

    private var tint: Color {
        switch limit.usedPercent {
        case ..<60: Palette.green
        case ..<85: Palette.amber
        default: Palette.red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: fraction)
                Text("\(Int(limit.usedPercent.rounded()))")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(limit.provider == .claude ? "Claude" : limit.provider.displayName) \(limit.window.label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                Text(resetText)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.quiet)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(limit.provider.displayName) \(limit.window.label) limit, \(Int(limit.usedPercent.rounded())) percent used, \(resetText)")
    }

    private var resetText: String {
        guard let resets = limit.resetsAt else { return "used" }
        let seconds = max(0, Int(resets.timeIntervalSince(now)))
        let days = seconds / 86_400, hours = seconds / 3600 % 24, minutes = seconds / 60 % 60
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(max(minutes, 1))m"
    }
}
