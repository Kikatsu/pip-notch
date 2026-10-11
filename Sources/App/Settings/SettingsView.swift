import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var integrations: IntegrationsModel
    var runDemo: () -> Void = {}

    @AppStorage(PipDefaults.character) private var character = CharacterStyle.livingNotch.rawValue
    @AppStorage(PipDefaults.soundsEnabled) private var soundsEnabled = true
    @AppStorage(PipDefaults.soundVolume) private var volume = 0.6
    @State private var previewMood: Mood = .working
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                ForEach(integrations.integrations) { integration in
                    AgentRow(integration: integration, model: integrations)
                }
                if let error = integrations.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } header: {
                Text("Agents")
            } footer: {
                Text("Connecting adds Pip's hooks to that agent's config file and keeps a .pip-backup copy. Disconnecting removes only Pip's hooks.")
            }

            Section("Character") {
                HStack(spacing: 12) {
                    ForEach(CharacterStyle.allCases) { style in
                        CharacterCard(style: style, mood: previewMood, selected: style.rawValue == character) {
                            character = style.rawValue
                        }
                    }
                }
                .padding(.vertical, 4)
                Picker("Preview", selection: $previewMood) {
                    ForEach(Mood.previewOrder, id: \.self) { mood in
                        Text(mood.title).tag(mood)
                    }
                }
            }

            Section("Sounds") {
                Toggle("Play sounds", isOn: $soundsEnabled)
                LabeledContent("Volume") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $volume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                }
                .disabled(!soundsEnabled)
                ForEach(SoundCue.allCases) { cue in
                    SoundRow(cue: cue)
                        .disabled(!soundsEnabled)
                }
            }

            Section("General") {
                LabeledContent("Preview") {
                    Button("Play all states in the notch", action: runDemo)
                }
                LabeledContent("Pip") {
                    Button("Quit Pip") { NSApp.terminate(nil) }
                }
                Toggle("Open Pip at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            integrations.lastError = "Couldn't change Open at Login: \(error.localizedDescription)"
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 560, idealHeight: 720)
        .onAppear { integrations.refresh() }
    }
}

private struct AgentRow: View {
    let integration: AgentIntegration
    @ObservedObject var model: IntegrationsModel

    var body: some View {
        let connected = model.connected.contains(integration.agent)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(integration.agent.displayName).font(.headline)
                    Text(status(connected: connected))
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(connected ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15)))
                        .foregroundStyle(connected ? Color.green : Color.secondary)
                }
                Text(integration.configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                if let note = integration.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(connected ? "Disconnect" : "Connect") {
                model.setConnected(integration, !connected)
            }
        }
        .padding(.vertical, 2)
    }

    private func status(connected: Bool) -> String {
        if connected { return "Connected" }
        return integration.isDetected ? "Not connected" : "Not found on this Mac"
    }
}

private struct CharacterCard: View {
    let style: CharacterStyle
    let mood: Mood
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18)
                        .fill(Color.black)
                        .frame(width: 132, height: 76)
                    let size = CharacterView.largeSize(for: style)
                    CharacterView(mood: mood, large: true, style: style)
                        .frame(width: size.width, height: size.height)
                        .padding(.top, style == .livingNotch ? 22 : 8)
                }
                .frame(width: 132, height: 76)
                Text(style.title).font(.callout.weight(.semibold))
                Text(style.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct SoundRow: View {
    let cue: SoundCue
    @AppStorage private var enabled: Bool

    init(cue: SoundCue) {
        self.cue = cue
        _enabled = AppStorage(wrappedValue: true, PipDefaults.soundKey(cue))
    }

    var body: some View {
        HStack {
            Toggle(isOn: $enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cue.title)
                    Text(cue.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button {
                SoundPlayer.shared.play(cue, preview: true)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Play the \(cue.title) sound")
            .accessibilityLabel("Play \(cue.title) sound")
        }
    }
}

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

@MainActor
final class SettingsWindowController {
    /// Centres the window on the screen under the pointer: the one with the notch you just clicked,
    /// not necessarily the main display.
    private func place(_ window: NSWindow, on preferred: NSScreen?) {
        let pointer = NSEvent.mouseLocation
        let underPointer = NSScreen.screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(pointer) }
        guard let screen = preferred ?? underPointer ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        var frame = window.frame
        frame.size.height = min(frame.height, area.height - 40)
        frame.origin = CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        window.setFrame(frame, display: false)
    }

    private var window: NSWindow?
    private let integrations: IntegrationsModel
    private let runDemo: () -> Void

    init(integrations: IntegrationsModel, runDemo: @escaping () -> Void) {
        self.integrations = integrations
        self.runDemo = runDemo
    }

    /// Opens Settings, centred on `screen` (the notch's screen when opened from the notch).
    func show(on screen: NSScreen? = nil) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(integrations: integrations, runDemo: runDemo))
            let window = NSWindow(contentViewController: host)
            window.title = "Pip Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 720))
            self.window = window
        }
        if let window, !window.isVisible || screen != nil { place(window, on: screen) }
        integrations.refresh()
        Log.ui.notice("Settings window shown")
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // Activation can be refused while another app is frontmost; the window still comes forward.
        window?.orderFrontRegardless()
    }
}
