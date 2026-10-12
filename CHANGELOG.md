# Changelog

All notable changes to Pip are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Pip uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

[Unreleased]: https://github.com/Kikatsu/pip-notch/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Kikatsu/pip-notch/releases/tag/v0.1.0
