import AppKit
import ServiceManagement
import SwiftUI

// MARK: Agents

struct AgentsPane: View {
    @ObservedObject var model: IntegrationsModel

    private var connected: [AgentIntegration] { model.integrations.filter { model.connected.contains($0.agent) } }
    private var found: [AgentIntegration] { model.integrations.filter { !model.connected.contains($0.agent) && $0.isDetected } }
    private var missing: [AgentIntegration] { model.integrations.filter { !model.connected.contains($0.agent) && !$0.isDetected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 14) {
                RowIcon(systemName: "bolt.fill", tint: SettingsTheme.accent)
                RowText(
                    title: "Connect agents automatically",
                    detail: "Pip connects every agent it finds, including ones you install later. Disconnecting one keeps it off."
                )
                Spacer(minLength: 12)
                Toggle("Connect agents automatically", isOn: Binding(get: { model.autoConnect }, set: { model.autoConnect = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .settingsCard()

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.red)
            }

            if !connected.isEmpty { group("Connected", connected) }
            if !found.isEmpty { group("Found on this Mac", found) }

            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "Not installed", count: missing.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(missing) { integration in
                            HStack(spacing: 8) {
                                AgentBadge(agent: integration.agent)
                                Text(integration.agent.displayName)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(SettingsTheme.secondary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(SettingsTheme.stroke))
                            .help("Install \(integration.agent.displayName) and Pip connects it automatically")
                        }
                    }
                    Text("Install any of these and Pip connects it on its own.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(SettingsTheme.tertiary)
                }
            }

            Text("Connecting adds Pip's hooks to the agent's settings (a .pip-backup copy is kept) or installs a small Pip plugin file. Claude Code and Codex hooks also cover their VS Code and Cursor extensions.")
                .font(.system(size: 11.5))
                .foregroundStyle(SettingsTheme.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func group(_ title: String, _ items: [AgentIntegration]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: title, count: items.count)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(items) { integration in
                    AgentTile(integration: integration, model: model)
                }
            }
        }
    }
}

private struct AgentTile: View {
    let integration: AgentIntegration
    @ObservedObject var model: IntegrationsModel

    var body: some View {
        let connected = model.connected.contains(integration.agent)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AgentBadge(agent: integration.agent)
                Text(integration.agent.displayName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Circle().fill(connected ? Palette.green : SettingsTheme.tertiary).frame(width: 6, height: 6)
                    Text(connected ? "On" : "Off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(connected ? Palette.green : SettingsTheme.secondary)
                }
            }
            if let note = integration.note {
                Text(note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(SettingsTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(alignment: .center) {
                Text(integration.configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(SettingsTheme.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(integration.configURL.path)
                Spacer(minLength: 8)
                Button(connected ? "Disconnect" : "Connect") {
                    model.setConnected(integration, !connected)
                }
                .buttonStyle(SettingsButtonStyle(prominent: !connected))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .settingsCard(padding: 14)
    }
}

// MARK: Character

struct CharacterPane: View {
    @AppStorage(PipDefaults.character) private var character = CharacterStyle.livingNotch.rawValue
    /// nil cycles through every mood.
    @State private var pinnedMood: Mood?

    private var style: CharacterStyle { CharacterStyle(rawValue: character) ?? .livingNotch }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            TimelineView(.periodic(from: .now, by: 2.2)) { context in
                let cycle = Int(context.date.timeIntervalSinceReferenceDate / 2.2) % Mood.previewOrder.count
                CharacterStage(style: style, mood: pinnedMood ?? Mood.previewOrder[cycle], cycling: pinnedMood == nil)
            }

            FlowLayout(spacing: 6) {
                Chip(title: "All moods", selected: pinnedMood == nil) { pinnedMood = nil }
                ForEach(Mood.previewOrder, id: \.self) { mood in
                    Chip(title: mood.title, selected: pinnedMood == mood) { pinnedMood = mood }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "Style")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(CharacterStyle.allCases) { option in
                        StyleTile(style: option, selected: option == style) { character = option.rawValue }
                    }
                }
            }
        }
    }
}

/// A slice of a MacBook screen with the notch, at twice its real size.
private struct CharacterStage: View {
    let style: CharacterStyle
    let mood: Mood
    let cycling: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.17, green: 0.18, blue: 0.21))
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 28)
            HStack(spacing: 0) {
                CharacterView(mood: mood, style: style)
                    .frame(width: NotchViewModel.earWidth, height: 32)
                Color.clear.frame(width: 120, height: 32)
                EarIndicator(mood: mood, workingCount: 2, sessionCount: 2)
                    .frame(width: NotchViewModel.earWidth, height: 32)
            }
            .padding(.horizontal, 6)
            .background(NotchShape(topRadius: 6, bottomRadius: 10).fill(Color.black))
            .scaleEffect(2, anchor: .top)
            .animation(.spring(response: 0.38, dampingFraction: 0.8), value: mood)

            VStack {
                Spacer()
                HStack {
                    Text(mood.title)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                    if cycling {
                        Text("cycling through moods")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    Spacer()
                    Text(style.title)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.65))
                }
                .padding(14)
            }
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(SettingsTheme.stroke))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.title) preview, \(mood.title)")
    }
}

private struct StyleTile: View {
    let style: CharacterStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black)
                    CharacterView(mood: .working, style: style)
                        .frame(width: 44, height: 32)
                }
                .frame(width: 64, height: 42)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title).font(.system(size: 13.5, weight: .semibold))
                    Text(style.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(SettingsTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? SettingsTheme.accent : SettingsTheme.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsCard(padding: 12, highlighted: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Sounds

struct SoundsPane: View {
    @AppStorage(PipDefaults.soundsEnabled) private var soundsEnabled = true
    @AppStorage(PipDefaults.soundVolume) private var volume = 0.6

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    RowIcon(systemName: soundsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill", tint: .white)
                    RowText(title: "Play sounds", detail: "Mute any time with ⌃⌥M or the speaker in the notch.")
                    Spacer(minLength: 12)
                    Toggle("Play sounds", isOn: $soundsEnabled).toggleStyle(.switch).labelsHidden()
                }
                RowDivider()
                HStack(spacing: 12) {
                    Text("Volume").font(.system(size: 13)).frame(width: 60, alignment: .leading)
                    Image(systemName: "speaker.fill").foregroundStyle(SettingsTheme.tertiary)
                    Slider(value: $volume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(SettingsTheme.tertiary)
                }
                .disabled(!soundsEnabled)
                .opacity(soundsEnabled ? 1 : 0.4)
            }
            .settingsCard()

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "When to play")
                VStack(spacing: 0) {
                    ForEach(Array(SoundCue.allCases.enumerated()), id: \.element) { index, cue in
                        if index > 0 { RowDivider() }
                        SoundCueRow(cue: cue)
                    }
                }
                .settingsCard()
                .disabled(!soundsEnabled)
                .opacity(soundsEnabled ? 1 : 0.4)
            }
        }
    }
}

private struct SoundCueRow: View {
    let cue: SoundCue
    @AppStorage private var enabled: Bool

    init(cue: SoundCue) {
        self.cue = cue
        _enabled = AppStorage(wrappedValue: true, PipDefaults.soundKey(cue))
    }

    var body: some View {
        HStack(spacing: 14) {
            RowIcon(systemName: cue.icon, tint: cue.tint)
            RowText(title: cue.title, detail: cue.detail)
            Spacer(minLength: 12)
            Button {
                SoundPlayer.shared.play(cue, preview: true)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.09)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Play the \(cue.title) sound")
            .accessibilityLabel("Play \(cue.title) sound")
            Toggle(cue.title, isOn: $enabled).toggleStyle(.switch).labelsHidden()
        }
    }
}

private extension SoundCue {
    var icon: String {
        switch self {
        case .approval: "bell.fill"
        case .finished: "sparkles"
        case .error: "xmark"
        case .rateLimited: "hourglass"
        }
    }

    var tint: Color {
        switch self {
        case .approval: Palette.amber
        case .finished: Palette.green
        case .error: Palette.red
        case .rateLimited: Color(red: 0.55, green: 0.65, blue: 1)
        }
    }
}

// MARK: Shortcuts

struct ShortcutsPane: View {
    @AppStorage(HotKeyCenter.enabledKey) private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                RowIcon(systemName: "keyboard", tint: .white)
                RowText(title: "Keyboard shortcuts", detail: "Allow and Deny only take over their keys while a request is waiting.")
                Spacer(minLength: 12)
                Toggle("Keyboard shortcuts", isOn: $enabled).toggleStyle(.switch).labelsHidden()
            }
            .settingsCard()

            VStack(spacing: 0) {
                ForEach(Array(Shortcut.allCases.enumerated()), id: \.element) { index, shortcut in
                    if index > 0 { RowDivider() }
                    HStack(spacing: 12) {
                        Text(shortcut.title).font(.system(size: 13))
                        Spacer(minLength: 12)
                        HStack(spacing: 5) {
                            ForEach(shortcut.keyTokens, id: \.self) { Keycap(label: $0) }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(shortcut.keys)
                    }
                }
            }
            .settingsCard()
            .opacity(enabled ? 1 : 0.4)
        }
    }
}

// MARK: General

struct GeneralPane: View {
    @ObservedObject var model: IntegrationsModel
    let runDemo: () -> Void
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    RowIcon(systemName: "power", tint: Palette.green)
                    RowText(title: "Open Pip at login", detail: loginError ?? "Keep the notch alive after a restart.")
                    Spacer(minLength: 12)
                    Toggle("Open Pip at login", isOn: $openAtLogin).toggleStyle(.switch).labelsHidden()
                }
                RowDivider()
                HStack(spacing: 14) {
                    RowIcon(systemName: "play.rectangle.fill", tint: SettingsTheme.accent)
                    RowText(title: "Preview every state", detail: "Plays fake sessions from several agents through the notch.")
                    Spacer(minLength: 12)
                    Button("Play demo", action: runDemo).buttonStyle(SettingsButtonStyle())
                }
            }
            .settingsCard()
            .onChange(of: openAtLogin) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    loginError = nil
                } catch {
                    loginError = "Couldn't change this: \(error.localizedDescription)"
                    openAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "About")
                VStack(spacing: 0) {
                    HStack {
                        Text("Version").font(.system(size: 13))
                        Spacer()
                        Text(version).font(.system(size: 13, design: .monospaced)).foregroundStyle(SettingsTheme.secondary)
                    }
                    RowDivider()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Helper").font(.system(size: 13))
                            Text(model.bridgePath.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? "Not installed")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SettingsTheme.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if let path = model.bridgePath {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                            .buttonStyle(SettingsButtonStyle())
                        }
                    }
                    RowDivider()
                    HStack {
                        Text("Everything stays on this Mac: no accounts, no cloud, no tracking.")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsTheme.secondary)
                        Spacer()
                    }
                }
                .settingsCard()
            }

            HStack {
                Spacer()
                Button("Quit Pip") { NSApp.terminate(nil) }
                    .buttonStyle(SettingsButtonStyle(destructive: true))
            }
        }
    }
}

// MARK: Shared extensions

extension Mood {
    static let previewOrder: [Mood] = [.working, .needsYou, .finished, .error, .rateLimited, .idle, .asleep]

    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .error: "Error"
        case .rateLimited: "Rate limited"
        case .finished: "Finished"
        case .working: "Working"
        case .idle: "Idle"
        case .asleep: "Asleep"
        }
    }
}

extension Shortcut {
    /// The keys one by one, for drawing keycaps.
    var keyTokens: [String] {
        let last: String
        switch self {
        case .togglePanel: last = "Space"
        case .allow: last = "↩"
        case .deny: last = "⌫"
        case .jump: last = "J"
        case .mute: last = "M"
        }
        return ["⌃", "⌥", last]
    }
}
