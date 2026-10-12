import SwiftUI

/// Plan usage as rings in a strip that lines up with the session rows: equal columns, leading-aligned.
struct LimitStrip: View {
    let limits: [UsageLimit]
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            ForEach(limits.prefix(4)) { limit in
                LimitRing(limit: limit, now: now)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.faint))
    }
}

/// The fullest limit as a tiny ring and percentage, for the closed notch's right ear.
struct MiniLimitRing: View {
    let limit: UsageLimit

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(max(limit.usedPercent / 100, 0), 1))
                    .stroke(LimitRing.tint(for: limit.usedPercent), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 11, height: 11)
            Text("\(Int(limit.usedPercent.rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(limit.provider.displayName) \(limit.window.label) limit \(Int(limit.usedPercent.rounded())) percent")
    }
}

struct LimitRing: View {
    let limit: UsageLimit
    let now: Date

    private var fraction: Double { min(max(limit.usedPercent / 100, 0), 1) }

    private var tint: Color { Self.tint(for: limit.usedPercent) }

    static func tint(for percent: Double) -> Color {
        switch percent {
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
        LimitStrip.resetText(resetsAt: limit.resetsAt, now: now)
    }
}

extension LimitStrip {
    static func resetText(resetsAt: Date?, now: Date) -> String {
        guard let resets = resetsAt else { return "used" }
        let seconds = Int(resets.timeIntervalSince(now))
        if seconds <= 0 { return "resets now" }
        let days = seconds / 86_400, hours = seconds / 3600 % 24, minutes = seconds / 60 % 60
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(max(minutes, 1))m"
    }
}
