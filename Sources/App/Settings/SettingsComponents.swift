import SwiftUI

extension View {
    /// The standard Settings surface: a softly outlined dark card.
    func settingsCard(padding: CGFloat = 16, highlighted: Bool = false) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SettingsTheme.card))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(highlighted ? SettingsTheme.accent : SettingsTheme.stroke, lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

/// Small uppercase label above a group, with an optional count.
struct SectionLabel: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(SettingsTheme.tertiary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SettingsTheme.tertiary)
            }
        }
    }
}

/// A round, tinted icon used at the start of rows.
struct RowIcon: View {
    let systemName: String
    let tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 32, height: 32)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.15)))
            .accessibilityHidden(true)
    }
}

/// Title + explanation, the left half of most rows.
struct RowText: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13.5, weight: .semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Pill-shaped button. `prominent` is the white primary style used for the one action that matters.
struct SettingsButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(prominent ? Color.black : destructive ? Palette.red : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(
                Capsule().fill(prominent ? Color.white : Color.white.opacity(configuration.isPressed ? 0.16 : 0.09))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

/// A selectable chip, for picking one of a few values.
struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.85))
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.07)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One key drawn like a physical keycap.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(SettingsTheme.cardRaised)
                    .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            )
    }
}

/// A thin separator between rows inside a card.
struct RowDivider: View {
    var body: some View {
        Rectangle().fill(SettingsTheme.stroke).frame(height: 1).padding(.vertical, 12)
    }
}

/// Lays children out left to right, wrapping to new lines, each at its natural width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var items: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.items.isEmpty {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
