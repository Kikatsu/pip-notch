# Pip

A macOS notch companion that shows what your AI coding agents are doing. The notch itself has eyes: they scan while agents work, widen when one needs your approval, cross out on errors and squint happily when a task finishes.

Works with Claude Code, Codex, Gemini CLI, Copilot CLI, Droid, OpenCode, Pi, Kiro CLI, Qoder CLI, Augment (`auggie`), Goose, Grok Build, Kimi Code, Mistral Vibe, Qwen Code, Cursor (app and `cursor-agent`), Windsurf and Antigravity (app and `agy`), including the Claude Code and Codex extensions inside VS Code, Cursor and other editors.

## Build and run

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project Pip.xcodeproj -scheme Pip -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Pip.app
```

Add `--args --demo` to `open` (or choose **Preview All States** from the menu bar eyes) to play fake sessions from every agent through every state. `--args --settings` opens Settings on launch.

Run the tests with:

```sh
xcodebuild -project Pip.xcodeproj -scheme Pip -derivedDataPath build/DerivedData test
```

## Connecting agents

Pip connects every agent it finds automatically, at launch and every minute after, so agents you install later are picked up too. It also repairs hooks that an agent update removed. Pressing **Disconnect** in Settings keeps that agent off, and **Connect agents automatically** turns the whole behaviour off. Open **Settings…** (General, Agents, Appearance, Sounds, Shortcuts) from the eyes icon in the menu bar or the ⚙ in the notch.

When connecting, Pip copies its `pip-bridge` helper to `~/Library/Application Support/Pip/bin/` and adds its hooks to that agent's config, saving the previous file as `<file>.pip-backup`. **Disconnect** removes only Pip's hooks.

| Agent | Config file | What Pip shows |
| --- | --- | --- |
| Claude Code | `~/.claude/settings.json` | Status, tools, approvals from the notch |
| Codex | `~/.codex/hooks.json` | Status, tools, approvals from the notch. Run `/hooks` in Codex once to trust Pip's hooks. |
| Gemini CLI | `~/.gemini/settings.json` | Status, tools, replies; "needs you" when a tool prompt is waiting |
| Copilot CLI | `~/.copilot/hooks/pip.json` (Pip's own file) | Status, tools; "needs you" on permission prompts |
| Droid | `~/.factory/hooks.json`, else `~/.factory/settings.json` | Status, tools; "needs you" on permission prompts |
| OpenCode | `~/.config/opencode/plugins/pip.js` (Pip's own plugin) | Status, tools; "needs you" on permission prompts |
| Pi | `~/.pi/agent/extensions/pip.ts` (Pip's own extension) | Status, tools, replies |
| Kiro CLI | `~/.kiro/hooks/pip.json` (Pip's own file, Kiro CLI 3+) | Status, tools, replies |
| Qoder CLI | `~/.qoder/settings.json` | Status, tools, approvals from the notch |
| Augment | `~/.augment/settings.json` | Status, tools and replies for `auggie` |
| Goose | `~/.agents/plugins/pip/` (Pip's own plugin) | Status, tools and replies |
| Cursor | `~/.cursor/hooks.json` | Status, tools and replies for the app, `cursor-agent` and Grok Bot's local agents (shown as "Grok Bot"). Approvals stay in the app. |
| Windsurf | `~/.codeium/windsurf/hooks.json` | Status, commands, edits and replies from Cascade |
| Antigravity | `~/.gemini/config/hooks.json` | Status and tools for the app and the `agy` CLI. Approvals stay in Antigravity. |

Not supported yet: Zed's own agent has no hooks, and Zed doesn't run Claude Code hooks for its Claude integration (Codex and Gemini in Zed work through their own hooks). Cline's hook format couldn't be confirmed.

The Claude Code and Codex editor extensions use the same hooks as their CLIs. Each session row shows where it runs ("Claude Code · VS Code", "Codex · Ghostty"), and clicking it opens that project's editor window.

Only Claude Code's and Codex's `PermissionRequest` hooks wait for you, because only they fire exactly when the agent would otherwise ask you. Everything else runs in the background. If Pip isn't running, the bridge exits at once with the agent's neutral answer, so agents behave as if no hook were installed.

**Any other agent** with Claude-style hooks works too: point its hooks at `"~/Library/Application Support/Pip/bin/pip-bridge" my-agent` (Settings → Agents → Other Agents has a Copy button). It shows up in the notch as "My-agent". Pip also accepts common field spellings such as `sessionId`, `working_dir` and `toolName`.

## Usage limits

The notch shows plan limits as rings (green, then amber from 60%, red from 85%) with the time until each resets:

- **Claude Code**: the 5-hour and weekly limits (and a spend limit behind a gateway). Claude Code only shares these with its status line, so Pip installs `pip-bridge claude-statusline` as the status line. If you already had one, Pip runs it unchanged and restores it when you turn this off; otherwise Claude Code shows a compact line such as `Opus 5.5 · 34% context · 5h 62% · week 88%`.
- **Codex**: the 5-hour and weekly limits, read from its local session logs in `~/.codex/sessions`.

Other agents don't expose their limits locally. Settings → General → Usage Limits chooses when to show them (always, only at 80% or higher, or never), can add the fullest limit as a small ring to the closed notch, and turns the Claude status line on or off.

## Characters and sounds

The character is interactive: its eyes follow your pointer as you approach the notch, it perks up (or wakes up) when the notch opens, giggles when you click its face, looks pleased when you allow a request and squints when you deny one.


Settings has three characters, **Living notch** (the notch has eyes), **Burrow blob** and **Pixel bit**, plus **Minimal**: no character, just a small status dot (white while working, pulsing amber when an agent needs you, red on errors, green when done) and a face-free panel.

Sounds come in four packs: **Pip** (bells and marimba), **Soft** (quiet glass and wood) and **Arcade** (8-bit blips) are synthesized by Pip itself, and **macOS** uses the alert sounds that ship with the system (Ping, Glass, Basso, Submarine). Any alert can use your own file instead (MP3, WAV, AIFF or M4A, up to 15 seconds); Pip keeps a copy in `~/Library/Application Support/Pip/Sounds`. Each alert can be switched off, and there's a master switch and a volume slider.

## Reviewing plans and questions

When Claude Code finishes planning, the plan appears in the notch. **Approve plan** lets it start; **Keep planning** sends it back, with your note if you typed one. When an agent asks you a question, the notch shows it with its options, and **Answer in terminal** takes you there.

A finished turn stays quiet (no popup, no sound) if you're already looking at the app it runs in. Session rows show the git branch.

## Keyboard shortcuts

Work from any app (Settings → Shortcuts can turn them off):

| Keys | Action |
| --- | --- |
| ⌃⌥Space | Open or close the notch |
| ⌃⌥↩ | Allow the request, or approve the plan |
| ⌃⌥⌫ | Deny the request, or keep planning |
| ⌃⌥J | Go to the session that needs you most |
| ⌃⌥M | Mute or unmute sounds |

⌃⌥↩ and ⌃⌥⌫ are only claimed while a request is waiting.

## Jumping to a session

Clicking a session focuses where it runs:

- iTerm2: the exact session (AppleScript)
- Terminal.app: the exact tab, by tty
- tmux: the pane, then its terminal
- WezTerm: the pane
- Cursor, VS Code, Antigravity: the window with the project open
- Anything else: the app

The first jump into iTerm2 or Terminal asks for Automation permission.

## How it fits together

```
Claude Code hook → pip-bridge (stdin JSON) → Unix socket → Pip.app
                                     ↖ allow / deny ↙
```

- `Sources/Bridge`: the helper that hooks call.
- `Sources/App/Core`: session state (`SessionStore`), per-agent payload adapters, socket server, hook installers, sounds, terminal jumping.
- `Sources/App/Settings`: the Settings window.
- `Sources/App/Notch`: the panel, notch geometry, hover tracking.
- `Sources/App/Views`: the notch shape, the three characters and the panel content.
