# Claude Notes

## What This Project Is

Hive is a SwiftUI macOS menu bar app for launching and organizing terminal workspaces ("pods"). Each pod is a Ghostty terminal layout with multiple panes running Claude, Codex, Lazygit, shell, or custom commands. Pods are placed on numbered workspaces via yabai.

## Build and Test

```bash
swift build            # validate changes
swift test             # run test suite
.build/debug/Hive      # launch the app
```

After rebuilding, always kill the running Hive process before relaunching. The menu bar app runs as a persistent process.

## Key Architecture Decisions

- **Actors for services**: GhosttyService, YabaiService, PodLauncher, StateService, SessionService are all actors for thread safety
- **Deterministic terminal setup**: Each pane uses Ghostty's `initial input` surface configuration property rather than post-creation `input text`. This avoids timing races entirely
- **Hook script sourced, not pasted**: The telemetry hook lives at `~/.claude-pods/hive-hook.sh` and is sourced by each pane's initial input. Never paste multi-line scripts into interactive shells via `initial input`
- **Inline navigation**: The popover uses a NavigationMode enum to switch views inline. Never use `.sheet()` in a MenuBarExtra — it dismisses the popover
- **Snapshot-based persistence**: StateService saves snapshots with source and confidence metadata. UI saves are authoritative; telemetry saves are lower confidence

## Ghostty AppleScript API

The scripting dictionary (`sdef /Applications/Ghostty.app`) is the source of truth. Key patterns:

- `new tab in win with configuration cfg` returns the created `tab` object — use it directly, don't re-query `selected tab of win`
- `split terminal direction right with configuration cfg` returns the new `terminal` — each split gets its own surface configuration
- Surface configuration properties: `initial working directory`, `initial input`, `command`, `font size`, `environment variables`
- `initial working directory` works correctly for splits (each split respects its own config)
- `perform action "equalize_splits"` and `perform action "set_tab_title:<title>"` target a terminal

## Runtime Telemetry (Currently Disabled)

The background sync that reads telemetry events and updates processType on panes is disabled. It was overwriting configured pane types (claude/codex) with observed state (shell) when processes weren't running, corrupting pod definitions. Before re-enabling, the system needs to separate "configured processType" (what should launch) from "observed processType" (what's currently running).

## Important Constraints

- Keep the repository public-safe: no personal paths, usernames, secrets, or local machine details in tracked files
- Do not commit generated state, build output, or editor-specific files
- Preserve the Swift Package structure unless a change clearly improves maintainability
- Favor straightforward SwiftUI and Foundation code over unnecessary abstraction
- Update README.md if setup steps, requirements, or behavior change
