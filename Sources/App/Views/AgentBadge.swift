import SwiftUI

/// A compact, colour-coded mark for each agent, so mixed sessions read at a glance.
struct AgentBadge: View {
    let agent: AgentKind

    var body: some View {
        Text(agent.initials)
            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
            .foregroundStyle(agent.tint)
            .frame(width: 20, height: 14)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(agent.tint.opacity(0.18)))
            .accessibilityLabel(agent.displayName)
    }
}

extension AgentKind {
    var initials: String {
        switch self {
        case .claude: "CC"
        case .codex: "CX"
        case .gemini: "GM"
        case .copilot: "CP"
        case .droid: "DR"
        case .opencode: "OC"
        case .pi: "PI"
        case .cursor: "CU"
        case .antigravity: "AG"
        case .unknown: "AI"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Color(red: 0.91, green: 0.55, blue: 0.40)
        case .codex: Color(red: 0.45, green: 0.80, blue: 0.70)
        case .gemini: Color(red: 0.49, green: 0.62, blue: 1.0)
        case .copilot: Color(red: 0.80, green: 0.80, blue: 0.86)
        case .droid: Color(red: 0.98, green: 0.69, blue: 0.30)
        case .opencode: Color(red: 0.95, green: 0.95, blue: 0.95)
        case .pi: Color(red: 0.86, green: 0.52, blue: 0.96)
        case .cursor: Color(red: 0.72, green: 0.85, blue: 1.0)
        case .antigravity: Color(red: 0.40, green: 0.78, blue: 1.0)
        case .unknown: Color(white: 0.7)
        }
    }
}
