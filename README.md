# Hive

Hive is a macOS menu bar app for launching and organizing terminal "pods" across workspaces. A pod is a preconfigured Ghostty terminal layout (window or tab) with multiple panes, each running a specific process like Claude, Codex, Lazygit, or a custom command.

Built with SwiftUI and Swift Package Manager. No external Swift dependencies.

## Status

Early-stage. The repository is public-safe by design: no personal paths, secrets, or machine-specific state in tracked files.

## Requirements

- macOS 15+
- Swift 6 toolchain
- [Ghostty](https://ghostty.org/) terminal
- [yabai](https://github.com/koekeishiya/yabai) window manager

Terminal automation requires Accessibility and Automation permissions for AppleScript control of Ghostty.

## Build and Run

```bash
swift build
.build/debug/Hive
```

The app installs as a menu bar icon (hexagon). It has no dock icon or main window.

## Install

Install a bundled copy to `/Applications/Utilities/Hive.app` and register a per-user LaunchAgent so Hive starts automatically when you log in:

```bash
./Scripts/install.sh
```

What the installer does:
- builds the release binary with SwiftPM
- creates a minimal macOS app bundle with `LSUIElement` enabled
- copies the bundle to `/Applications/Utilities/Hive.app`
- writes `~/Library/LaunchAgents/com.hive.Hive.plist`
- loads the LaunchAgent immediately so the menu bar app starts now and on future logins

Notes:
- Writing to `/Applications/Utilities` may require an admin-capable shell. If needed, run the installer with `sudo`; the script still installs the LaunchAgent for the invoking macOS user, not for `root`. You can also override the destination with `INSTALL_DIR=/some/writable/path ./Scripts/install.sh`.
- The bundle includes an Apple Events usage string because Hive automates Ghostty through AppleScript.
- To reload startup manually: `launchctl kickstart -k gui/$(id -u)/com.hive.Hive`
- To remove startup: `launchctl bootout gui/$(id -u)/com.hive.Hive && rm ~/Library/LaunchAgents/com.hive.Hive.plist`
- To remove the installed app: `rm -rf /Applications/Utilities/Hive.app`

## Features

### Pod Management
- Create, edit, and delete pods via the menu bar popover
- Group pods by workspace (1-9)
- Two launch modes: standalone (new window) or tab (new tab in existing window)
- Rebuild All to relaunch every pod after a reboot or crash
- Rebuild 1-2 to relaunch only workspaces 1 and 2 during restore debugging
- Automatic backups start paused on launch and can be re-enabled manually from the popover header once the workspace state looks correct
- The menu bar icon shows backup state: yellow with a pause badge when paused, green center dot when backups are enabled

### Pane Layout
Each pod has a three-column layout:
- **Left column**: 1-8 panes, typically Claude or Codex sessions
- **Middle**: single pane for a custom command (e.g. SSH, dev server) or shell
- **Right column**: top pane (typically Lazygit) and bottom pane (shell)

### Ghostty Integration
Hive uses Ghostty's native AppleScript API to create windows, tabs, and splits. Each pane gets its own surface configuration with:
- `initial working directory` — sets the pane's cwd at creation time
- `initial input` — deterministic command injection without timing races

No keystroke simulation. No clipboard abuse. Commands are delivered through Ghostty's own scripting dictionary.

### Session Discovery and Resume
- Discovers recent Claude sessions from `~/.claude/projects/`
- Discovers recent Codex sessions from `~/.codex/sessions/` (last 7 days)
- Automatically matches sessions to panes and resumes them on launch
- Claude: `claude --resume <id>`, Codex: `codex resume <id>`

### Workspace Switching
Uses yabai to place pods on the correct workspace:
- Standalone pods: creates window, then moves it to the target workspace
- Tab pods: focuses the target workspace first, then creates the tab

### Quick Navigation
- Number keys (1-9) to jump to a workspace section
- `/` to search pods by name or directory
- Collapsible workspace sections

## Architecture

```
Sources/Hive/
  HiveApp.swift              # Entry point, MenuBarExtra setup
  Models/
    Pod.swift                # Pod, PaneConfig, ProcessType, PanePosition, PodMode
    AppState.swift           # Observable state, session refresh, persistence triggers
  Services/
    GhosttyService.swift     # AppleScript generation, hook script management
    YabaiService.swift       # Workspace queries and window placement
    PodLauncher.swift        # Orchestrates Ghostty + yabai for pod launch
    StateService.swift       # JSON persistence with snapshot history
    SessionService.swift     # Claude/Codex session discovery
    RuntimeTelemetryService.swift  # Event ingestion (currently disabled)
  Views/
    MenuBarView.swift        # Main popover UI
    PodCardView.swift        # Individual pod display with launch button
    PodEditorView.swift      # Create/edit form
    PodLayoutView.swift      # Color-coded mini layout preview
    DirectoryField.swift     # Tab-completion directory picker
```

## Local State

Pod definitions and runtime state live on the local machine, never in the repository.

- `~/.claude-pods/state.json` — pod definitions
- `~/.claude-pods/snapshots/` — historical state snapshots for recovery
- `~/.claude-pods/manifest.json` — tracks last-known-good snapshot
- `~/.claude-pods/hive-hook.sh` — telemetry hook sourced by each pane
- `~/.claude-pods/runtime-events.jsonl` — telemetry events from running panes

Session discovery reads from (but never writes to):
- `~/.claude/projects/`
- `~/.codex/sessions/`

## Privacy

- No build output, editor config, or session state in git
- No absolute paths, usernames, hostnames, API keys, or tokens in tracked files
- All local state paths use `~/` expansion at runtime
