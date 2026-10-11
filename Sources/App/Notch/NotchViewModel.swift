import SwiftUI

/// UI state for the notch: its size, whether it is open, and why.
@MainActor
final class NotchViewModel: ObservableObject {
    static let earWidth: CGFloat = 44
    static let expandedWidth: CGFloat = 500

    @Published var notchSize: CGSize
    @Published private(set) var isExpanded = false {
        didSet { if isExpanded, !oldValue { face.react(.hello) } }
    }
    let face = FaceState()
    @Published var isHovering = false
    /// At least one agent has Pip's hooks installed.
    @Published var anyAgentConnected = false
    /// The black shape's frame in the window's top-left coordinate space, reported by the view.
    @Published var shapeFrame: CGRect = .zero {
        didSet { Log.ui.debug("shape frame \(String(describing: self.shapeFrame), privacy: .public)") }
    }

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

/// Live state for the character's little interactions: where it looks and how it just reacted.
/// Kept apart from the view model so pointer tracking only redraws the face.
@MainActor
final class FaceState: ObservableObject {
    enum Reaction {
        /// The notch opened: perk up (and wake up if asleep).
        case hello
        /// The face was clicked: giggle and squish.
        case poke
        /// A request was allowed or a plan approved.
        case approve
        /// A request was denied.
        case deny

        var duration: Double {
            switch self {
            case .hello: 0.7
            case .poke: 0.9
            case .approve: 1.3
            case .deny: 1.0
            }
        }
    }

    /// Where the eyes look, each axis -1...1 (x right, y down).
    @Published var gaze: CGSize = .zero
    @Published private(set) var reaction: Reaction?
    @Published private(set) var reactionStart = Date.distantPast

    func react(_ reaction: Reaction) {
        self.reaction = reaction
        reactionStart = Date()
    }
}

/// Everything the notch views can ask the app to do.
struct NotchActions {
    var resolve: (UUID, ApprovalDecision) -> Void
    var dismissApprovals: () -> Void
    var jump: (AgentSession) -> Void
    var answerInTerminal: (PendingApproval) -> Void
    var toggleMute: () -> Void
    var openSettings: () -> Void
    var runDemo: () -> Void
    var quit: () -> Void
}
