# Dispatch

Dispatch is a macOS menu bar launcher for running multiple agent terminals (Claude Code, Codex, OpenCode) with mixed tools, mixed directories, and auto-tiling.

## Features

- Menu bar UI (`Dispatch`) built with SwiftUI.
- Launch mixed tool batches in one run (for example: `4x Claude + 2x Codex`).
- Set different directories per launch row.
- Terminal backend support: `iTerm2` and `Terminal`.
- Select which displays are used for window tiling.
- Quick total windows input in the header, plus per-terminal counts.
- Visual layout picker (`Adaptive`, `Balanced`, `Wide`, `Dense`).
- Save and reuse named presets.
- Relaunch the last session.
- Close only windows launched by Dispatch.

## Requirements

- macOS 13+
- iTerm2 and/or Terminal installed
- Tool CLI installed and available in `PATH` (for example: `claude`, `codex`, `opencode`)
- Automation permission for controlling terminal apps (requested by macOS on first launch)

## Run

```bash
swift run
```

This starts Dispatch as a menu bar app.

## How Launch Works

For each launch row, Dispatch runs:

```bash
zsh -lc 'cd <row-directory> && exec <tool-command>'
```

It then tiles windows on the main display.

## Build a Distributable App

Build a signed app bundle and zipped artifact:

```bash
./scripts/package_app.sh
```

Artifacts:

- `dist/Dispatch.app`
- `dist/Dispatch-macos.zip`
