import SwiftUI

/// Every live agent session, most urgent first. Click a row to jump to its terminal.
struct SessionListView: View {
    @ObservedObject var store: SessionStore
    let actions: NotchActions

    var body: some View {
        let sessions = store.orderedSessions
        if sessions.isEmpty {
            VStack(spacing: 4) {
                Text("No agents running")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Start Claude Code in any terminal and the notch wakes up.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.quiet)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        } else {
            VStack(spacing: 2) {
                ForEach(sessions.prefix(6)) { session in
                    SessionRow(
                        session: session,
                        now: store.now,
                        onTap: { actions.jump(session) },
                        onTerminate: { store.terminateSession(session.id) }
                    )
                }
                if sessions.count > 6 {
                    Text("+\(sessions.count - 6) more")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.quiet)
                        .padding(.top, 2)
                }

                let inactiveStates: Set<SessionState> = [.idle, .finished, .error]
                let hasInactive = sessions.contains { inactiveStates.contains($0.state) }
                if hasInactive {
                    Button(action: { store.clearInactiveSessions() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Clear inactive sessions")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(Palette.quiet)
                        .padding(.top, 4)
                        .padding(.bottom, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SessionRow: View {
    let session: AgentSession
    let now: Date
    let onTap: () -> Void
    var onTerminate: (() -> Void)? = nil
    @State private var hovering = false
    @State private var hoveringStop = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Palette.color(for: session.state))
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(session.projectName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            AgentBadge(agent: session.agent)
                            if let branch = session.branch {
                                Label(branch, systemImage: "arrow.triangle.branch")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Palette.quiet)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 120, alignment: .leading)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.quiet)
                                .lineLimit(1)
                        }
                        Text(statusLine)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.quiet)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hovering, session.state == .working, session.pid != nil, let onTerminate {
                Button(action: onTerminate) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(hoveringStop ? Palette.red : Palette.quiet)
                        .padding(.leading, 4)
                }
                .buttonStyle(.plain)
                .onHover { hoveringStop = $0 }
                .help("Stop process (SIGTERM)")
            } else if let elapsed {
                Text(elapsed)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.quiet)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Palette.faint : .clear))
        .onHover { hovering = $0 }
        .help("Go to this session")
    }

    /// "Claude Code", or "Claude Code · VS Code" when it runs inside an editor or a named terminal.
    private var subtitle: String {
        guard let host = session.host, host != session.agentName, !session.agent.isIDE else {
            return session.agentName
        }
        return "\(session.agentName) · \(host)"
    }

    private var statusLine: String {
        switch session.state {
        case .working: session.currentTool ?? session.lastPrompt.map { "Working on: \($0)" } ?? "Thinking…"
        case .needsInput: "Waiting for your answer"
        case .finished: session.lastMessage ?? "Finished"
        case .error: session.errorText.map { "Error: \($0)" } ?? "Error"
        case .rateLimited: "Rate limit reached"
        case .idle: session.lastMessage ?? "Idle"
        }
    }

    private var elapsed: String? {
        switch session.state {
        case .working:
            return session.turnStartedAt.map { Self.format(now.timeIntervalSince($0)) }
        case .finished, .idle:
            return session.lastDuration.map(Self.format)
        default:
            return nil
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
