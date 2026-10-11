import SwiftUI

/// UI state for the notch: its size, whether it is open, and why.
@MainActor
final class NotchViewModel: ObservableObject {
    static let earWidth: CGFloat = 44
    static let expandedWidth: CGFloat = 500

    @Published var notchSize: CGSize
    @Published private(set) var isExpanded = false
    @Published var isHovering = false
    /// At least one agent has Pip's hooks installed.
    @Published var anyAgentConnected = false
    /// The black shape's frame in the window's top-left coordinate space, reported by the view.
    @Published var shapeFrame: CGRect = .zero

    /// The user chose "Later" on the current approvals; stay compact until a new one arrives.
    var approvalsDismissed = false
    var finishedPinnedUntil = Date.distantPast

    init(notchSize: CGSize) {
        self.notchSize = notchSize
    }

    func updateExpansion(store: SessionStore, now: Date = Date()) {
        let wantsApproval = !store.approvals.isEmpty && !approvalsDismissed
        let expanded = isHovering || wantsApproval || now < finishedPinnedUntil
        if expanded != isExpanded { isExpanded = expanded }
    }
}

/// Everything the notch views can ask the app to do.
struct NotchActions {
    var resolve: (UUID, ApprovalDecision) -> Void
    var dismissApprovals: () -> Void
    var jump: (AgentSession) -> Void
    var openSettings: () -> Void
    var runDemo: () -> Void
    var quit: () -> Void
}
