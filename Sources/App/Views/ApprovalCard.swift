import SwiftUI

/// The permission request at the front of the queue, answerable without leaving your app.
struct ApprovalCard: View {
    let approval: PendingApproval
    let position: Int
    let total: Int
    let actions: NotchActions

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(Palette.amber).frame(width: 7, height: 7)
                AgentBadge(agent: approval.agent)
                Text("\(approval.agent.displayName) · \(approval.projectName)")
                    .lineLimit(1)
                Spacer(minLength: 8)
                if total > 1 { Text("\(position) of \(total)") }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Palette.quiet)

            Text(approval.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)

            if !approval.detail.isEmpty {
                Text(approval.detail)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(4)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.faint))
            }

            HStack(spacing: 8) {
                PillButton(title: "Deny", prominent: false) { actions.resolve(approval.id, .deny) }
                PillButton(title: "Allow", prominent: true) { actions.resolve(approval.id, .allow) }
            }
            .padding(.top, 2)

            HStack {
                Button("Answer in terminal") { actions.resolve(approval.id, .passthrough) }
                Spacer()
                Button("Later") { actions.dismissApprovals() }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.quiet)
        }
    }
}

struct PillButton: View {
    let title: String
    let prominent: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(prominent ? Color.black : Color.white)
                .background(
                    Capsule().fill(prominent ? Color.white.opacity(hovering ? 0.85 : 1) : Color.white.opacity(hovering ? 0.2 : 0.13))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
