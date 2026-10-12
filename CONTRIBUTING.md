# Contributing to Pip

Thanks for helping out! Pip is small, so most changes are quick to review. The most useful contributions right now are:

- **Reports from people who use the experimental agents.** Does it connect? Do the right states show up?
- Bug fixes, with a test that would have caught the bug.
- Support for new agents.

## Development setup

You'll need macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
git clone https://github.com/Kikatsu/pip-notch.git
cd pip-notch
xcodegen generate
open Pip.xcodeproj
```

`Pip.xcodeproj` is generated from `project.yml` and is git-ignored. **If you add, move or delete a file, run `xcodegen generate` again.** If you change project settings, edit `project.yml`, not the Xcode project.

### Build, run and test from the command line

```sh
# build and run (Debug)
xcodebuild -project Pip.xcodeproj -scheme Pip -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Pip.app --args --demo

# tests
xcodebuild -project Pip.xcodeproj -scheme Pip -derivedDataPath build/DerivedData test
```

`--demo` plays fake sessions from every agent through every state, so you can work on the UI without running a real agent. `--settings` opens Settings on launch.

### Talking to a running Pip by hand

The bridge reads one hook payload on stdin and forwards it to the app over the Unix socket. You can send events yourself:

```sh
BRIDGE=build/DerivedData/Build/Products/Debug/Pip.app/Contents/MacOS/pip-bridge
echo '{"hook_event_name":"SessionStart","session_id":"dev","cwd":"'"$PWD"'"}' | "$BRIDGE" claude
echo '{"hook_event_name":"PreToolUse","session_id":"dev","tool_name":"Bash","tool_input":{"command":"ls"}}' | "$BRIDGE" claude
```

Set `PIP_SOCKET=/tmp/pip-dev.sock` on both the app and the bridge to keep a development build away from your everyday Pip.

### Logs

```sh
log stream --predicate 'subsystem == "com.kikatsu.pip"' --level debug
```

## Adding a new agent

Using an existing agent with a similar hook format as a template (Windsurf is a good small example), the pieces are:

1. **`Sources/App/Core/AgentSession.swift`**: add a case to `AgentKind`, the name the bridge is called with in `init(raw:)` and its display name.
2. **`Sources/App/Core/AgentAdapter.swift`**: translate the agent's payload into Pip's Claude-style event (`hook_event_name`, `session_id`, `cwd`, `tool_name`, …).
3. **`Sources/App/Core/AgentIntegration.swift`**: describe where its config lives, which events to hook, how to detect it's installed, and the config format.
4. **`Sources/Bridge/main.swift`**: if the agent expects a specific "neutral" reply when Pip isn't running, add it.
5. **`Sources/App/Views/AgentBadge.swift`**: a two-letter badge and a colour.
6. **Tests** in `Tests/PipTests/`: at minimum, that installing and removing hooks round-trips the config file unchanged, and that a sample payload maps to the right state.
7. **README**: add a row to the agent table, marked *Experimental* until someone has checked it against a real install.

Please link the agent's hook documentation in your PR.

## Pull requests

- Keep each PR to one change. Small PRs get merged faster.
- Make sure `xcodebuild … test` passes. CI runs the same command.
- Match the style of the surrounding code: 4-space indentation, Swift API naming, and comments only where the *why* isn't obvious.
- Update the README if you change something users see.
- Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).

## Reporting bugs

Use the [issue templates](https://github.com/Kikatsu/pip-notch/issues/new/choose). For agent problems, include the agent's name and version, your macOS version, and the relevant part of the agent's hook config **with any tokens or keys removed**.

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
