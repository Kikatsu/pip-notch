# Pip

A macOS notch companion that shows what your AI coding agents are doing. The notch itself has eyes: they scan while agents work, widen when one needs your approval, cross out on errors and squint happily when a task finishes.

Phase 1 supports Claude Code. Codex, Cursor and others come next.

## Build and run

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
xcodebuild -project Pip.xcodeproj -scheme Pip -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Pip.app
```

Add `--args --demo` to `open` (or choose **Preview All States** from the menu bar eyes) to play two fake sessions through every state.

Run the tests with:

```sh
xcodebuild -project Pip.xcodeproj -scheme Pip -derivedDataPath build/DerivedData test
```

## Connecting Claude Code

Choose **Connect Claude Code** from the eyes icon in the menu bar or from the notch panel. Pip then:

1. copies its `pip-bridge` helper to `~/Library/Application Support/Pip/bin/`;
2. adds one hook per event to `~/.claude/settings.json`, keeping everything else, and saves the previous file as `settings.json.pip-backup`.

**Disconnect** removes only Pip's hooks. New Claude Code sessions pick up the change.

All hooks run in the background except `PermissionRequest`, which waits for your Allow or Deny in the notch. If Pip isn't running, the bridge exits immediately with no output, and Claude Code asks in the terminal as usual. "Answer in terminal" does the same on demand.

## How it fits together

```
Claude Code hook → pip-bridge (stdin JSON) → Unix socket → Pip.app
                                     ↖ allow / deny ↙
```

- `Sources/Bridge`: the helper that hooks call.
- `Sources/App/Core`: session state (`SessionStore`), socket server, settings installer.
- `Sources/App/Notch`: the panel, notch geometry, hover tracking.
- `Sources/App/Views`: the notch shape, the eyes (`FaceView`) and the panel content.
