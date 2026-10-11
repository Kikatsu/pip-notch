import SwiftUI

/// The whole notch: compact ears while agents run, a panel when hovered or when something needs you.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var store: SessionStore
    let actions: NotchActions

    private var spring: Animation { .spring(response: 0.38, dampingFraction: 0.8) }

    var body: some View {
        let expanded = viewModel.isExpanded
        let mood = store.mood
        let topRadius: CGFloat = expanded ? 12 : 6

        ZStack(alignment: .top) {
            if expanded {
                expandedContent(mood: mood)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if mood == .asleep {
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
                .opacity(!expanded && mood == .asleep ? 0 : 1)
        )
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: NotchFrameKey.self, value: proxy.frame(in: .named(Self.space)))
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(NotchFrameKey.self) { frame in
            MainActor.assumeIsolated { viewModel.shapeFrame = frame }
        }
        .animation(spring, value: expanded)
        .animation(spring, value: mood)
        .animation(spring, value: store.approvals.count)
        .environment(\.colorScheme, .dark)
    }

    private static let space = "pip.notch"

    // MARK: Compact

    private func compactContent(mood: Mood) -> some View {
        let height = viewModel.notchSize.height
        return HStack(spacing: 0) {
            FaceView(mood: mood, eyeWidth: 6)
                .frame(width: NotchViewModel.earWidth, height: height)
            Color.clear.frame(width: viewModel.notchSize.width, height: height)
            EarIndicator(mood: mood, workingCount: store.workingCount, sessionCount: store.sessions.count)
                .frame(width: NotchViewModel.earWidth, height: height)
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
                    settingsMenu
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: viewModel.notchSize.height)

            FaceView(mood: mood, eyeWidth: 13)
                .frame(width: 96, height: 30)

            if let approval = store.approvals.first {
                ApprovalCard(approval: approval, position: 1, total: store.approvals.count, actions: actions)
            } else {
                SessionListView(store: store, actions: actions)
            }

            if !viewModel.hooksInstalled {
                connectBanner
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .frame(width: NotchViewModel.expandedWidth)
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

    private var settingsMenu: some View {
        Menu {
            Button(viewModel.hooksInstalled ? "Disconnect Claude Code" : "Connect Claude Code", action: actions.toggleHooks)
            Button("Preview all states", action: actions.runDemo)
            Divider()
            Button("Quit Pip", action: actions.quit)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.quiet)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Pip settings")
    }

    private var connectBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Claude Code")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Adds Pip's hooks to ~/.claude/settings.json. A backup is kept.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.quiet)
            }
            Spacer(minLength: 8)
            PillButton(title: "Connect", prominent: true, action: actions.toggleHooks)
                .frame(width: 96)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.faint))
    }
}

private struct NotchFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
