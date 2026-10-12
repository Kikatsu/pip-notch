import AVFoundation
import SwiftUI
import UserNotifications

/// The first-run tour: what Pip is, what it shows, and a few choices, one step at a time.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, states, approve, agents, personality, setup, ready

        var tint: Color {
            switch self {
            case .welcome, .agents, .personality: Palette.cyan
            case .states: .white
            case .approve, .setup: Palette.amber
            case .ready: Palette.green
            }
        }

        /// `--onboarding-step <n>` opens the tour on a given step (for screenshots).
        static var launchStep: Step? {
            let args = CommandLine.arguments
            guard let i = args.firstIndex(of: "--onboarding-step"), i + 1 < args.count, let n = Int(args[i + 1]) else { return nil }
            return Step(rawValue: n)
        }
    }

    @ObservedObject var integrations: IntegrationsModel
    let finish: (_ playDemo: Bool) -> Void

    @State private var step: Step = Step.launchStep ?? .welcome
    @State private var forward = true
    @State private var openAtLogin = true
    @State private var loginError: String?

    var body: some View {
        ZStack {
            Color(white: 0.035).ignoresSafeArea()
            GlowBackground(tint: step.tint)

            VStack(spacing: 0) {
                ZStack {
                    content(for: step)
                        .id(step)
                        .transition(.asymmetric(
                            insertion: .offset(x: forward ? 60 : -60).combined(with: .opacity),
                            removal: .offset(x: forward ? -60 : 60).combined(with: .opacity)
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .frame(width: 780, height: 580)
    }

    // MARK: Steps

    @ViewBuilder
    private func content(for step: Step) -> some View {
        switch step {
        case .welcome:
            StepLayout(eyebrow: nil, title: "Meet ", highlight: "Pip.", tint: Palette.cyan,
                       subtitle: "Your notch has eyes. Pip keeps watch over your coding agents, so you can stop babysitting terminals.") {
                WelcomeStage()
            }
        case .states:
            StepLayout(eyebrow: "01 — At a glance", title: "It lives in your ", highlight: "notch.", tint: .white,
                       subtitle: "Working, needs you, error, done. One look at the top of your screen tells you how every agent is doing.") {
                VStack(spacing: 18) {
                    VideoCard(name: "onboarding-states")
                    MoodLegend()
                }
            }
        case .approve:
            StepLayout(eyebrow: "02 — Stay in flow", title: "Approve from the ", highlight: "notch.", tint: Palette.amber,
                       subtitle: "Allow commands, review plans and answer questions without leaving your editor. Risky commands are flagged.") {
                VStack(spacing: 18) {
                    VideoCard(name: "onboarding-approve")
                    HStack(spacing: 22) {
                        KeyHint(keys: Shortcut.allow.keys, label: "Allow")
                        KeyHint(keys: Shortcut.deny.keys, label: "Deny")
                        KeyHint(keys: Shortcut.togglePanel.keys, label: "Open the notch")
                    }
                }
            }
        case .agents:
            AgentsStep(integrations: integrations)
        case .personality:
            StepLayout(eyebrow: "04 — Personality", title: "Pick a ", highlight: "face.", tint: Palette.cyan,
                       subtitle: "Pip comes in four styles. You can change it any time in Settings → Appearance.") {
                PersonalityPicker()
            }
        case .setup:
            StepLayout(eyebrow: "05 — Preferences", title: "Make it ", highlight: "yours.", tint: Palette.amber, subtitle: nil) {
                SetupStep(openAtLogin: $openAtLogin, loginError: loginError)
            }
        case .ready:
            StepLayout(eyebrow: nil, title: "You're all ", highlight: "set.", tint: Palette.green,
                       subtitle: "Look up: Pip is in your notch. Hover over it any time, or press \(Shortcut.togglePanel.keys).") {
                ReadyStage()
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            ProgressDashes(count: Step.allCases.count, current: step.rawValue, tint: step.tint)
            Spacer()
            if step == .welcome {
                Button("Skip Tour") { finish(false) }
                    .buttonStyle(QuietButtonStyle())
            } else if step != .ready {
                Button("Back") { go(-1) }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut(.leftArrow, modifiers: [])
            }
            if step == .ready {
                Button("Play the Demo") { finish(true) }
                    .buttonStyle(QuietButtonStyle())
                Button("Start Using Pip") { finish(false) }
                    .buttonStyle(PillButtonStyle(tint: step.tint))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button(step == .welcome ? "Get Started" : "Continue") { go(1) }
                    .buttonStyle(PillButtonStyle(tint: step.tint))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 26)
        .padding(.top, 8)
    }

    private func go(_ delta: Int) {
        if step == .setup, delta > 0 {
            do {
                try LoginItem.set(openAtLogin)
                loginError = nil
            } catch {
                // Usually Pip running from outside /Applications. Say so once, then let them move on.
                if loginError == nil {
                    loginError = error.localizedDescription
                    return
                }
            }
        }
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        OnboardingSounds.shared.play(forward ? .whoosh : .whooshBack)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { step = next }
    }
}

// MARK: Layout

/// Visual on top, big headline below, like the promo video's title cards.
private struct StepLayout<Stage: View>: View {
    let eyebrow: String?
    let title: String
    let highlight: String
    let tint: Color
    let subtitle: String?
    @ViewBuilder let stage: () -> Stage

    @State private var shown = false

    var body: some View {
        VStack(spacing: 0) {
            stage()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 34)
                .padding(.horizontal, 40)

            VStack(spacing: 10) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(tint.opacity(0.9))
                }
                (Text(title).foregroundColor(.white) + Text(highlight).foregroundColor(tint))
                    .font(.system(size: 40, weight: .heavy))
                    .tracking(-1.2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 520)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 22)
            .padding(.bottom, 14)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 12)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.55).delay(0.12)) { shown = true }
        }
    }
}

/// A slow, breathing glow from the top edge, tinted for the current step.
private struct GlowBackground: View {
    let tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let breathe = 0.85 + 0.15 * sin(t * 1.1)
            Canvas { gc, size in
                let center = CGPoint(x: size.width / 2 + CGFloat(sin(t * 0.35)) * 40, y: -40)
                let radius = size.width * 0.62 * breathe
                gc.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(Gradient(colors: [tint.opacity(0.22), tint.opacity(0.06), .clear]),
                                              center: center, startRadius: 0, endRadius: radius))
            }
        }
        .animation(.easeInOut(duration: 0.8), value: tint)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct ProgressDashes: View {
    let count: Int
    let current: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? tint : Color.white.opacity(index < current ? 0.4 : 0.15))
                    .frame(width: index == current ? 26 : 8, height: 4)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

private struct PillButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(Capsule().fill(tint == .white ? Color.white : tint))
            .shadow(color: tint.opacity(0.45), radius: configuration.isPressed ? 4 : 14, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.4 : 0.65))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Capsule())
    }
}

// MARK: Welcome

/// A notch drops in from the top of the window, opens its eyes and looks around.
private struct WelcomeStage: View {
    @State private var dropped = false
    @State private var awake = false
    @State private var reactionStart = Date.distantPast

    var body: some View {
        VStack {
            ZStack {
                Ellipse()
                    .fill(Palette.cyan.opacity(awake ? 0.35 : 0))
                    .frame(width: 320, height: 90)
                    .blur(radius: 40)
                    .offset(y: 50)
                HStack(spacing: 0) {
                    CharacterView(mood: awake ? .working : .asleep, large: true, style: .livingNotch,
                                  gaze: gaze, reaction: .hello, reactionStart: reactionStart)
                        .frame(width: 110, height: 70)
                }
                .frame(width: dropped ? 300 : 170, height: dropped ? 104 : 34)
                .background(NotchShape(topRadius: 10, bottomRadius: dropped ? 30 : 12).fill(Color.black))
                .overlay(
                    NotchShape(topRadius: 10, bottomRadius: dropped ? 30 : 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Palette.cyan.opacity(awake ? 0.4 : 0), radius: 30, y: 10)
            }
            .offset(y: dropped ? 0 : -140)

            VStack(spacing: 8) {
                ForEach(Array(Self.sessions.enumerated()), id: \.offset) { index, session in
                    SessionPill(project: session.0, agent: session.1, state: session.2, color: session.3)
                        .opacity(index < shownSessions ? 1 : 0)
                        .offset(y: index < shownSessions ? 0 : -16)
                }
            }
            .padding(.top, 26)
            Spacer()
        }
        .padding(.top, -34)
        .contentShape(Rectangle())
        // The eyes follow the pointer, like the real notch.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                gaze = CGSize(width: max(-1, min(1, (point.x - 350) / 220)), height: max(-1, min(1, (point.y - 20) / 160)))
            case .ended:
                gaze = .zero
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.72).delay(0.15)) { dropped = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                withAnimation(.easeOut(duration: 0.6)) { awake = true }
                reactionStart = Date()
            }
            for index in Self.sessions.indices {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(1.3 + Double(index) * 0.18)) {
                    shownSessions = index + 1
                }
            }
        }
        .task {
            await playSounds([(0.15, .whoosh), (0.85, .hello)]
                + Self.sessions.indices.map { (1.3 + Double($0) * 0.18, .blip($0 * 2)) })
        }
    }

    @State private var shownSessions = 0
    @State private var gaze: CGSize = .zero

    private static let sessions: [(String, String, String, Color)] = [
        ("web-app", "Claude Code", "Working", .white),
        ("api-server", "Codex", "Needs you", Palette.amber),
        ("docs", "Antigravity", "Done", Palette.green),
    ]
}

/// One row of the expanded notch's session list, as a sample.
private struct SessionPill: View {
    let project: String
    let agent: String
    let state: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 7, height: 7).shadow(color: color, radius: 4)
            Text(project).font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(agent).font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(state).font(.system(size: 11, weight: .medium)).foregroundStyle(color == .white ? .white.opacity(0.6) : color)
        }
        .padding(.horizontal, 14)
        .frame(width: 300, height: 34)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.07)))
    }
}

// MARK: States

private struct MoodLegend: View {
    private let moods: [(String, Color)] = [
        ("Working", .white), ("Needs you", Palette.amber), ("Error", Palette.red), ("Done", Palette.green),
    ]
    @State private var lit = 0

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(moods.enumerated()), id: \.offset) { index, mood in
                HStack(spacing: 7) {
                    Circle().fill(mood.1).frame(width: 7, height: 7)
                        .shadow(color: mood.1, radius: index == lit ? 5 : 0)
                    Text(mood.0).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(index == lit ? 0.12 : 0.05)))
                .foregroundStyle(.white.opacity(index == lit ? 1 : 0.6))
            }
        }
        .onReceive(Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.35)) { lit = (lit + 1) % moods.count }
        }
    }
}

// MARK: Approve

private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.15)))
            Text(label).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: Agents

private struct AgentsStep: View {
    @ObservedObject var integrations: IntegrationsModel
    @State private var revealed = 0

    private var found: [AgentIntegration] {
        integrations.integrations.filter { $0.isDetected || integrations.connected.contains($0.agent) }
    }

    private var subtitle: String {
        switch found.count {
        case 0: "No agents on this Mac yet. Install Claude Code, Codex or any of 32 supported agents, and Pip connects it automatically."
        case 1: "Pip found 1 agent and connected it. Your original config is backed up next to it."
        default: "Pip found \(found.count) agents and connected them. Your original configs are backed up next to them."
        }
    }

    var body: some View {
        StepLayout(eyebrow: "03 — Agents", title: "Already ", highlight: "connected.", tint: Palette.cyan, subtitle: subtitle) {
            if found.isEmpty {
                VideoCard(name: "onboarding-agents")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(Array(found.enumerated()), id: \.element.id) { index, integration in
                            AgentChip(integration: integration, model: integrations)
                                .opacity(index < revealed ? 1 : 0)
                                .scaleEffect(index < revealed ? 1 : 0.85)
                                .offset(y: index < revealed ? 0 : 10)
                        }
                    }
                    .padding(4)
                }
                .scrollIndicators(.never)
                .frame(maxWidth: 660)
            }
        }
        .onAppear {
            integrations.connectDetected()
            for index in 0..<max(found.count, 1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.25 + Double(index) * 0.09)) {
                    revealed = index + 1
                }
            }
        }
        .task {
            await playSounds(found.indices.prefix(8).map { (0.25 + Double($0) * 0.09, .blip($0)) })
        }
    }
}

private struct AgentChip: View {
    let integration: AgentIntegration
    @ObservedObject var model: IntegrationsModel

    var body: some View {
        let connected = model.connected.contains(integration.agent)
        let needsTrust = model.awaitingTrust.contains(integration.agent)
        HStack(spacing: 10) {
            AgentIcon(agent: integration.agent)
            Text(integration.agent.displayName)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            if needsTrust {
                Button(model.trusting ? "Trusting…" : "Trust") { model.trustCodexHooks() }
                    .controlSize(.small)
                    .disabled(model.trusting)
                    .help("\(integration.agent.displayName) skips Pip's hooks until you trust them.")
            } else if connected {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
            } else {
                Text("Off").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(needsTrust ? Palette.amber.opacity(0.6) : Color.white.opacity(0.08))
        )
    }
}

// MARK: Personality

private struct PersonalityPicker: View {
    @AppStorage(PipDefaults.character) private var character = CharacterStyle.livingNotch.rawValue
    @State private var mood: Mood = .working
    private let cycle: [Mood] = [.working, .needsYou, .finished, .error]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(CharacterStyle.allCases) { style in
                let selected = style.rawValue == character
                Button {
                    OnboardingSounds.shared.play(.style(style))
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { character = style.rawValue }
                } label: {
                    VStack(spacing: 12) {
                        ZStack(alignment: .top) {
                            LinearGradient(colors: [Color(white: 0.14), Color(white: 0.07)], startPoint: .top, endPoint: .bottom)
                            CharacterView(mood: mood, large: true, style: style)
                                .frame(width: 96, height: 58)
                                .frame(width: 140, height: 66)
                                .background(NotchShape(topRadius: 6, bottomRadius: 18).fill(Color.black))
                        }
                        .frame(width: 150, height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(selected ? Palette.cyan : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1)
                        )
                        .shadow(color: selected ? Palette.cyan.opacity(0.35) : .clear, radius: 16)
                        VStack(spacing: 3) {
                            Text(style.title).font(.system(size: 13, weight: .semibold))
                            Text(style.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .frame(width: 140)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .scaleEffect(selected ? 1.04 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .onReceive(Timer.publish(every: 1.8, on: .main, in: .common).autoconnect()) { _ in
            mood = cycle[((cycle.firstIndex(of: mood) ?? 0) + 1) % cycle.count]
        }
    }
}

// MARK: Setup

private struct SetupStep: View {
    @Binding var openAtLogin: Bool
    let loginError: String?
    @AppStorage(PipDefaults.soundsEnabled) private var sounds = true
    @AppStorage(PipDefaults.notificationsEnabled) private var notifications = true
    @AppStorage(NotchDisplay.key) private var display = NotchDisplay.automatic.rawValue
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 10) {
            SetupRow(icon: "power", tint: Palette.green, title: "Open at login",
                     detail: loginError ?? "Pip comes back on its own after a restart or shutdown.",
                     isError: loginError != nil) {
                Toggle("", isOn: $openAtLogin).labelsHidden().toggleStyle(.switch)
            }
            SetupRow(icon: "bell.badge.fill", tint: Palette.amber, title: "Notifications",
                     detail: "When an agent needs you and you're in another app.") {
                switch notificationStatus {
                case .authorized, .provisional:
                    Toggle("", isOn: $notifications).labelsHidden().toggleStyle(.switch)
                case .denied:
                    Button("Open Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                    .controlSize(.small)
                default:
                    Button("Allow") {
                        OnboardingSounds.shared.play(.click)
                        Task {
                            _ = try? await NotificationManager.shared.requestAuthorization()
                            await refreshNotificationStatus()
                        }
                    }
                    .controlSize(.small)
                }
            }
            SetupRow(icon: "speaker.wave.2.fill", tint: Palette.cyan, title: "Sounds",
                     detail: "A soft chime when an agent finishes or asks for something.") {
                Toggle("", isOn: $sounds).labelsHidden().toggleStyle(.switch)
            }
            if NSScreen.screens.count > 1 {
                SetupRow(icon: "display.2", tint: .white, title: "Show the notch on",
                         detail: "You have more than one display. Change this later in Settings → General.") {
                    Picker("", selection: $display) {
                        Text("Automatic").tag(NotchDisplay.automatic.rawValue)
                        Text("Primary display").tag(NotchDisplay.primary.rawValue)
                        Text("Display with the pointer").tag(NotchDisplay.followPointer.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
        }
        .frame(maxWidth: 560)
        .tint(Palette.green)
        .task { await refreshNotificationStatus() }
        .onChange(of: openAtLogin) { OnboardingSounds.shared.play(.click) }
        .onChange(of: notifications) { OnboardingSounds.shared.play(.click) }
        // Turning sounds off is silent, which is its own confirmation.
        .onChange(of: sounds) { OnboardingSounds.shared.play(.click) }
        .onChange(of: display) { OnboardingSounds.shared.play(.click) }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

private struct SetupRow<Control: View>: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    var isError = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint == .white ? Color.black : Color.black.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(isError ? Palette.red : .white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.07)))
    }
}

// MARK: Ready

/// The character cheers, with an arrow bobbing toward the real notch above.
private struct ReadyStage: View {
    @State private var reactionStart = Date.distantPast
    @State private var bob = false
    @State private var burst = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.up")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.green)
                .offset(y: bob ? -8 : 4)
                .opacity(0.9)
            ZStack {
                ForEach(0..<14, id: \.self) { index in
                    let angle = Double(index) / 14 * 2 * .pi
                    Circle()
                        .fill([Palette.green, Palette.cyan, Palette.amber][index % 3])
                        .frame(width: 6, height: 6)
                        .offset(x: burst ? cos(angle) * 170 : 0, y: burst ? sin(angle) * 80 : 0)
                        .opacity(burst ? 0 : 1)
                }
                CharacterView(mood: .finished, large: true, reaction: .approve, reactionStart: reactionStart)
                    .frame(width: 110, height: 70)
                    .frame(width: 300, height: 104)
                    .background(NotchShape(topRadius: 10, bottomRadius: 30).fill(Color.black))
                    .shadow(color: Palette.green.opacity(0.45), radius: 30, y: 10)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bob = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                reactionStart = Date()
                withAnimation(.easeOut(duration: 1.1)) { burst = true }
            }
        }
        .task {
            await playSounds([(0.3, .fanfare), (0.36, .pop), (0.47, .pop), (0.62, .pop)])
        }
    }
}

// MARK: Video

/// A muted, looping clip from the promo video in a rounded card.
private struct VideoCard: View {
    let name: String

    var body: some View {
        LoopingVideo(name: name)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.1)))
            .shadow(color: .black.opacity(0.6), radius: 24, y: 12)
            .frame(maxHeight: 250)
            .accessibilityHidden(true)
    }
}

private struct LoopingVideo: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> PlayerView {
        PlayerView(url: Bundle.main.url(forResource: name, withExtension: "mp4"))
    }

    func updateNSView(_ view: PlayerView, context: Context) {}

    static func dismantleNSView(_ view: PlayerView, coordinator: ()) {
        view.stop()
    }

    final class PlayerView: NSView {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?

        init(url: URL?) {
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            guard let url else { return }
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            layer = playerLayer
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }

        required init?(coder: NSCoder) { nil }

        func stop() {
            player.pause()
            looper?.disableLooping()
        }
    }
}

/// Plays each sound at its offset in seconds. Stops early when the step goes away and cancels the task.
@MainActor
private func playSounds(_ cues: [(TimeInterval, OnboardingSound)]) async {
    let start = Date()
    for (offset, sound) in cues.sorted(by: { $0.0 < $1.0 }) {
        let wait = offset - Date().timeIntervalSince(start)
        if wait > 0 {
            do { try await Task.sleep(for: .seconds(wait)) } catch { return }
        }
        OnboardingSounds.shared.play(sound)
    }
}
