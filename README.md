# Hive

Hive is a macOS menu bar app for launching and organizing terminal "pods" across workspaces.

It is built with SwiftUI and Swift Package Manager. The app creates repeatable terminal layouts, launches configured commands, and can reconnect pods to locally discovered Claude and Codex sessions.

## Status

This project is early-stage. The repository is being prepared for public development, so the tracked files are intentionally limited to source, documentation, and portable project metadata.

## Requirements

- macOS 15 or newer
- Swift 6 toolchain / Xcode with Swift 6 support
- [Ghostty](https://ghostty.org/) for terminal window and tab management
- [`yabai`](https://github.com/koekeishiya/yabai) for workspace and window placement

Depending on your macOS security settings, terminal automation may also require the usual Accessibility and Automation permissions for AppleScript-driven control.

## Build

```bash
swift build
```

## Run

```bash
swift run Hive
```

## What Hive Manages

- Pods grouped by workspace
- Per-pane process types such as Claude, Codex, Lazygit, shell, or custom commands
- Ghostty window and tab layouts
- Re-association with recent local Claude and Codex sessions

## Local State

Hive stores its runtime state on the local machine. That state is not part of the repository and should not be committed.

Current local state locations used by the app:

- `~/.claude-pods/state.json`
- `~/.claude/projects/...`
- `~/.codex/sessions/...`

These locations are runtime inputs only. They are intentionally excluded from version control.

## Privacy and Public Repo Hygiene

- Do not commit build output such as `.build/`
- Do not commit machine-specific settings or editor metadata
- Do not add absolute file system paths, usernames, or secrets to tracked files

## Repository Layout

```text
Package.swift
Sources/Hive/
  Models/
  Services/
  Views/
```

## Development Notes

- Use `swift build` as the baseline validation step.
- Update this README when external dependencies or setup steps change.
- Keep generated files and personal environment details out of git.
