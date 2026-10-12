import SwiftUI

/// The whole notch: compact ears while agents run, a panel when hovered or when something needs you.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var store: SessionStore
    @ObservedObject var usage: UsageStore
    let actions: NotchActions
    @AppStorage(UsageStore.displayKey) private var limitDisplay = UsageStore.Display.always.rawValue
    @AppStorage(UsageStore.closedNotchKey) private var limitsInClosedNotch = false

    private var shownLimits: [UsageLimit] { usage.shown(UsageStore.Display(rawValue: limitDisplay) ?? .always) }
    /// The fullest limit, when the user wants it in the closed notch.
    private var earLimit: UsageLimit? {
        limitsInClosedNotch ? shownLimits.max { $0.usedPercent < $1.usedPercent } : nil
    }
    @AppStorage(PipDefaults.character) private var character = CharacterStyle.livingNotch.rawValue

    private var spring: Animation { .spring(response: 0.38, dampingFraction: 0.8) }

    var body: some View {
        let expanded = viewModel.isExpanded
        let mood = store.mood
        let topRadius: CGFloat = expanded ? 12 : 6

        ZStack(alignment: .top) {
            if expanded {
                expandedContent(mood: mood)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if mood == .asleep, earLimit == nil {
                Color.clear.frame(width: viewModel.notchSize.width, height: viewModel.notchSize.height)
            } else {
                compactContent(mood: mood)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, topRadius)
        .background(
            NotchShape(topRadius: topRadius, bottomRadius: expanded ? 26 : 10)
                .fill(Color.black)
                .opacity(!expanded && mood == .asleep && earLimit == nil ? 0 : 1)
        )
        .background(
            // Reports the black shape's frame so the controller knows where the pointer counts as inside.
            // (A preference key here never updated past its first value inside NSHostingView.)
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(Self.space))
                Color.clear
                    .onAppear { viewModel.shapeFrame = frame }
                    .onChange(of: frame) { _, newFrame in viewModel.shapeFrame = newFrame }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: Self.space)
        .animation(spring, value: expanded)
        .animation(spring, value: mood)
        .animation(spring, value: store.approvals.count)
        .environment(\.colorScheme, .dark)
    }

    private static let space = "pip.notch"

    // MARK: Compact

    private func compactContent(mood: Mood) -> some View {
        let height = viewModel.notchSize.height
        let limit = earLimit
        // Both ears grow together when the limit ring is shown, so the notch stays centred.
        let ear = NotchViewModel.earWidth + (limit == nil ? 0 : 40)
        return HStack(spacing: 0) {
            InteractiveFace(mood: mood, face: viewModel.face)
                .frame(width: ear, height: height)
            Color.clear.frame(width: viewModel.notchSize.width, height: height)
            HStack(spacing: 7) {
                if let limit { MiniLimitRing(limit: limit) }
                if mood != .asleep {
                    EarIndicator(mood: mood, workingCount: store.workingCount, sessionCount: store.sessions.count)
                }
            }
            .frame(width: ear, height: height)
        }
    }

    // MARK: Expanded

    private func expandedContent(mood: Mood) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                Text(summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.quiet)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: viewModel.notchSize.width)
                HStack {
                    Spacer()
                    settingsButton
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: viewModel.notchSize.height)

            let style = CharacterStyle(rawValue: character) ?? .livingNotch
            // Minimal keeps the open panel purely informational: no face above the content.
            if style != .minimal {
                let face = CharacterView.largeSize(for: style)
                InteractiveFace(mood: mood, large: true, face: viewModel.face)
                    .frame(width: face.width, height: face.height)
            }

            if !shownLimits.isEmpty, store.approvals.isEmpty {
                LimitStrip(limits: shownLimits, now: store.now)
            }

            if !store.approvals.isEmpty {
                let safeIndex = min(max(0, viewModel.selectedApprovalIndex), store.approvals.count - 1)
                let approval = store.approvals[safeIndex]
                ApprovalCard(
                    approval: approval,
                    position: safeIndex + 1,
                    total: store.approvals.count,
                    actions: actions,
                    onPrevious: store.approvals.count > 1 ? {
                        viewModel.selectedApprovalIndex = (safeIndex - 1 + store.approvals.count) % store.approvals.count
                        HapticFeedback.play(.selection)
                    } : nil,
                    onNext: store.approvals.count > 1 ? {
                        viewModel.selectedApprovalIndex = (safeIndex + 1) % store.approvals.count
                        HapticFeedback.play(.selection)
                    } : nil
                )
            } else {
                SessionListView(store: store, actions: actions)
            }

            if !viewModel.anyAgentConnected {
                connectBanner
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .frame(width: NotchViewModel.expandedWidth)
        .onChange(of: store.approvals.count) { _, count in
            if count == 0 {
                viewModel.selectedApprovalIndex = 0
            } else if viewModel.selectedApprovalIndex >= count {
                viewModel.selectedApprovalIndex = count - 1
            }
        }
    }

    private var summary: String {
        let needs = store.approvals.count + store.sessions.values.filter { $0.state == .needsInput }.count
        let working = store.workingCount
        var parts: [String] = []
        if needs > 0 { parts.append("\(needs) need\(needs == 1 ? "s" : "") you") }
        if working > 0 { parts.append("\(working) working") }
        if parts.isEmpty { return store.sessions.isEmpty ? "Pip" : "All quiet" }
        return parts.joined(separator: " · ")
    }

    /// A plain button, not a menu: menus popped from a non-activating panel close as soon as they open.
    private var settingsButton: some View {
        HStack(spacing: 2) {
            MuteButton(action: actions.toggleMute)
            SettingsGearButton(action: actions.openSettings)
        }
    }

    private var connectBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect your agents")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Claude Code, Codex, Cursor and Antigravity")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.quiet)
            }
            Spacer(minLength: 8)
            PillButton(title: "Set up", prominent: true, action: actions.openSettings)
                .frame(width: 96)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.faint))
    }
}


private struct MuteButton: View {
    let action: () -> Void
    @AppStorage(PipDefaults.soundsEnabled) private var soundsEnabled = true
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: soundsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(hovering ? Color.white : Palette.quiet)
                .frame(width: 30, height: 24)
                .background(Circle().fill(hovering ? Palette.faint : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(soundsEnabled ? "Mute sounds (⌃⌥M)" : "Unmute sounds (⌃⌥M)")
        .accessibilityLabel(soundsEnabled ? "Mute sounds" : "Unmute sounds")
    }
}

private struct SettingsGearButton: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(hovering ? Color.white : Palette.quiet)
                .frame(width: 30, height: 24)
                .background(Circle().fill(hovering ? Palette.faint : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Pip Settings")
        .accessibilityLabel("Pip Settings")
    }
}
