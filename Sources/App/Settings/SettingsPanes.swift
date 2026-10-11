import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

private let paneWidth: CGFloat = 540

// MARK: General

struct GeneralSettings: View {
    @ObservedObject var model: IntegrationsModel
    @ObservedObject var usage: UsageStore
    let runDemo: () -> Void
    @AppStorage(UsageStore.visibleKey) private var showLimits = true
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                LabeledContent("Preview") {
                    Button("Play Demo", action: runDemo)
                }
            } footer: {
                if let loginError {
                    Text(loginError).foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Show usage limits in the notch", isOn: $showLimits)
                Toggle("Read Claude Code limits", isOn: Binding(get: { model.claudeLimits }, set: { model.claudeLimits = $0 }))
                ForEach(usage.limits) { limit in
                    LabeledContent("\(limit.provider.displayName), \(limit.window == .fiveHour ? "5-hour" : limit.window == .weekly ? "weekly" : "spend") limit") {
                        Text("\(Int(limit.usedPercent.rounded()))% used")
                            .foregroundStyle(limit.usedPercent >= 85 ? .red : .secondary)
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Usage Limits")
            } footer: {
                Text(usage.limits.isEmpty
                     ? "Limits appear after Claude Code or Codex makes its next request. Claude's come from its status line (yours keeps working); Codex's from its local session logs."
                     : "Claude's limits come from its status line (yours keeps working); Codex's from its local session logs.")
            }

            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Helper") {
                    HStack {
                        Text(model.bridgePath.map(abbreviate) ?? "Not installed")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        if let path = model.bridgePath {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            }
                        }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit Pip") { NSApp.terminate(nil) }
                }
            } footer: {
                Text("Pip works entirely on this Mac. It has no accounts and sends nothing anywhere.")
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Agents

struct AgentSettings: View {
    @ObservedObject var model: IntegrationsModel
    @State private var copied = false

    private var customCommand: String {
        "\"\(model.bridgePath ?? "~/Library/Application Support/Pip/bin/pip-bridge")\" my-agent"
    }

    private var available: [AgentIntegration] {
        model.integrations.filter { $0.isDetected || model.connected.contains($0.agent) }
    }

    private var missing: [AgentIntegration] {
        model.integrations.filter { !$0.isDetected && !model.connected.contains($0.agent) }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Connect new agents automatically", isOn: Binding(get: { model.autoConnect }, set: { model.autoConnect = $0 }))
            } footer: {
                Text("Agents you turn off stay off.")
            }

            Section("On This Mac") {
                ForEach(available) { integration in
                    AgentRow(integration: integration, model: model)
                }
            }

            if !missing.isEmpty {
                Section {
                    ForEach(missing) { integration in
                        HStack(spacing: 10) {
                            AgentIcon(agent: integration.agent)
                            Text(integration.agent.displayName)
                            Spacer()
                            Text("Not installed").foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Not Installed")
                } footer: {
                    Text("Pip connects these when you install them.")
                }
            }

            Section {
                LabeledContent("Hook command") {
                    HStack {
                        Text(customCommand)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .textSelection(.enabled)
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(customCommand, forType: .string)
                            copied = true
                        }
                    }
                }
            } header: {
                Text("Other Agents")
            } footer: {
                Text("Using an agent that isn't listed? If it has Claude-style hooks, point them at this command and replace \"my-agent\" with its name. It shows up in the notch under that name.")
            }

            if let error = model.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: 600)
    }
}

private struct AgentRow: View {
    let integration: AgentIntegration
    @ObservedObject var model: IntegrationsModel

    var body: some View {
        let connected = model.connected.contains(integration.agent)
        Toggle(isOn: Binding(get: { connected }, set: { model.setConnected(integration, $0) })) {
            HStack(spacing: 10) {
                AgentIcon(agent: integration.agent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(integration.agent.displayName)
                    Text(integration.note ?? abbreviate(integration.configURL.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .help(integration.configURL.path)
    }
}

/// The agent's real app icon when it has an app, otherwise a terminal glyph.
struct AgentIcon: View {
    let agent: AgentKind

    private static let appPaths: [AgentKind: [String]] = [
        .claude: ["/Applications/Claude.app"],
        .codex: ["/Applications/Codex.app", "/Applications/ChatGPT.app"],
        .grok: ["/Applications/Grok.app"],
        .kimi: ["/Applications/Kimi.app"],
        .qwen: ["/Applications/Qwen.app"],
        .cursor: ["/Applications/Cursor.app"],
        .windsurf: ["/Applications/Windsurf.app"],
        .antigravity: ["/Applications/Antigravity.app"],
        .kiro: ["/Applications/Kiro.app"],
        .copilot: ["/Applications/Visual Studio Code.app"],
        .qoder: ["/Applications/Qoder.app"],
        .goose: ["/Applications/Goose.app"],
    ]

    var body: some View {
        if let path = Self.appPaths[agent]?.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "apple.terminal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(nsColor: .darkGray)))
                .accessibilityHidden(true)
        }
    }
}

// MARK: Appearance

struct AppearanceSettings: View {
    @AppStorage(PipDefaults.character) private var character = CharacterStyle.livingNotch.rawValue
    @State private var previewMood: Mood = .working

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(CharacterStyle.allCases) { style in
                        StyleThumbnail(style: style, mood: previewMood, selected: style.rawValue == character) {
                            character = style.rawValue
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 6)

                Picker("Preview", selection: $previewMood) {
                    ForEach(Mood.previewOrder, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Character")
            } footer: {
                Text(CharacterStyle(rawValue: character)?.subtitle ?? "")
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A thumbnail like the Light/Dark/Auto picker in System Settings.
private struct StyleThumbnail: View {
    let style: CharacterStyle
    let mood: Mood
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(red: 0.35, green: 0.42, blue: 0.55))
                    HStack(spacing: 0) {
                        CharacterView(mood: mood, style: style)
                            .frame(width: 30, height: 22)
                        Color.clear.frame(width: 28, height: 22)
                        EarIndicator(mood: mood, workingCount: 2, sessionCount: 2)
                            .scaleEffect(0.75)
                            .frame(width: 30, height: 22)
                    }
                    .padding(.horizontal, 4)
                    .background(NotchShape(topRadius: 4, bottomRadius: 7).fill(Color.black))
                }
                .frame(width: 96, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 3)
                        .padding(-4)
                )
                Text(style.title)
                    .font(.callout)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Sounds

struct SoundSettings: View {
    @AppStorage(PipDefaults.soundsEnabled) private var soundsEnabled = true
    @AppStorage(PipDefaults.soundVolume) private var volume = 0.6
    @AppStorage(PipDefaults.soundPack) private var pack = SoundPack.pip.rawValue
    @State private var importError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Play sounds", isOn: $soundsEnabled)
                Slider(value: $volume, in: 0...1) {
                    Text("Volume")
                } minimumValueLabel: {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .disabled(!soundsEnabled)
                Picker("Sound pack", selection: $pack) {
                    ForEach(SoundPack.allCases) { pack in
                        Text(pack.title).tag(pack.rawValue)
                    }
                }
                .disabled(!soundsEnabled)
                .onChange(of: pack) { _, value in
                    SoundPlayer.shared.play(.finished, preview: true, pack: SoundPack(rawValue: value))
                }
            } footer: {
                Text(SoundPack(rawValue: pack)?.detail ?? "")
            }

            Section {
                ForEach(SoundCue.allCases) { cue in
                    SoundCueRow(cue: cue, importError: $importError)
                }
            } header: {
                Text("Alerts")
            } footer: {
                if let importError {
                    Text(importError).foregroundStyle(.red)
                } else {
                    Text("Use your own sound for any alert: MP3, WAV, AIFF or M4A, up to \(Int(SoundLibrary.maxCustomDuration)) seconds.")
                }
            }
            .disabled(!soundsEnabled)
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SoundCueRow: View {
    let cue: SoundCue
    @Binding var importError: String?
    @AppStorage private var enabled: Bool
    @AppStorage private var customPath: String

    init(cue: SoundCue, importError: Binding<String?>) {
        self.cue = cue
        _importError = importError
        _enabled = AppStorage(wrappedValue: true, PipDefaults.soundKey(cue))
        _customPath = AppStorage(wrappedValue: "", SoundLibrary.customKey(cue))
    }

    private var hasCustom: Bool { !customPath.isEmpty && FileManager.default.fileExists(atPath: customPath) }

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                Button {
                    SoundPlayer.shared.play(cue, preview: true)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("Play")
                .accessibilityLabel("Play \(cue.title) sound")

                Menu(hasCustom ? "Custom" : "Pack Sound") {
                    Button("Choose File…", action: choose)
                    if hasCustom {
                        Button("Use Pack Sound") { SoundLibrary.removeCustom(for: cue) }
                    }
                }
                .fixedSize()

                Toggle(cue.title, isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(cue.title)
                Text(hasCustom ? URL(fileURLWithPath: customPath).lastPathComponent : cue.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose a sound for “\(cue.title)”"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SoundLibrary.importFile(url, for: cue)
            importError = nil
            SoundPlayer.shared.play(cue, preview: true)
        } catch {
            importError = error.localizedDescription
        }
    }
}

// MARK: Shortcuts

struct ShortcutSettings: View {
    @AppStorage(HotKeyCenter.enabledKey) private var enabled = true

    var body: some View {
        Form {
            Section {
                Toggle("Use keyboard shortcuts", isOn: $enabled)
            } footer: {
                Text("Allow and Deny only respond while a request is waiting.")
            }

            Section {
                ForEach(Shortcut.allCases) { shortcut in
                    LabeledContent(shortcut.title) {
                        Text(shortcut.keys)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Helpers

private func abbreviate(_ path: String) -> String {
    path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
}

extension Mood {
    static let previewOrder: [Mood] = [.working, .needsYou, .finished, .error, .rateLimited, .idle, .asleep]

    var title: String {
        switch self {
        case .needsYou: "Needs You"
        case .error: "Error"
        case .rateLimited: "Rate Limited"
        case .finished: "Finished"
        case .working: "Working"
        case .idle: "Idle"
        case .asleep: "Asleep"
        }
    }
}
