# Changelog

All notable changes to Pip are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Pip uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-10-12

### Added

- Prebuilt download on GitHub Releases (universal, Apple Silicon and Intel).

### Fixed

- Amp: hooks now go to Amp's global `~/.config/amp/settings.json`. `~/.amp/settings.json` is a per-project file, so Amp never loaded them.
- DeepSeek Harness: dsh never reads `~/.dsh/settings.json`, so its hooks never ran. Pip now mounts dsh's own Claude-hooks bridge from `~/.dsh/cordis.patch.yml` and points it at `~/.dsh/pip-hooks.json`. Approvals stay in dsh, which has no approval hook.
- ZCode (Z.ai's GLM agent): hooks now go to `~/.zcode/cli/config.json` under `hooks.events` with `hooks.enabled` turned on. ZCode runs hooks only from there, so they never ran before.
- A second copy of Pip no longer takes over the socket and leaves a dead one behind when it quits, which made the notch show nothing while agents were working. A duplicate now quits on launch, and Pip rebinds its socket within 5 seconds if the file is deleted or replaced.
- Events that arrive just after a session ends (each hook runs its own bridge process) no longer bring the session back as a ghost.

### Tested against real installs

- DeepSeek Harness 0.2.0-rc.2, Pi 0.73, Copilot CLI 1.0.95, OpenCode 1.19, Qwen Code 0.25, CodeBuddy 2.164 and Droid 0.238 deliver their events to Pip.
- Kiro CLI 2.29 doesn't read `~/.kiro/hooks/`, so Pip's Kiro hooks don't load yet.

## [0.1.0] - 2026-10-12

First public beta.

### Added

- Living-notch companion with four states: working, needs you, error and done.
- Support for 32 agents. Claude Code, Codex, Antigravity CLI and Cursor are tested; the rest are experimental.
- Automatic agent connection and hook repair, with backups of the original configs.
- Approve or deny requests from the notch, with risky commands flagged.
- Plan review with Markdown rendering and feedback chips; interactive agent questions.
- Usage-limit rings for Claude Code and Codex.
- Four personalities: Living notch, Burrow blob, Pixel bit and Minimal.
- Four sound packs plus custom alert sounds.
- Global keyboard shortcuts and precise jumping to terminal sessions and editor windows.
- Native Settings window.
- A warning in Settings, the menu bar and a notification when Codex hasn't trusted Pip's hooks yet, which used to leave the notch silently empty.
- A **Trust in Codex** button in Settings → Agents that trusts Pip's own hooks through Codex's app server, without opening `/hooks`.

[Unreleased]: https://github.com/Kikatsu/pip-notch/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kikatsu/pip-notch/releases/tag/v0.1.0
