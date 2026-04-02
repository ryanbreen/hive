# Repository Guidelines

This repository is intended to be safe for public hosting.

## Core Rules

- Do not commit generated build output, local editor settings, session state, or machine-specific configuration.
- Do not add absolute paths, usernames, hostnames, API keys, tokens, or copied local environment details to tracked files.
- Prefer small, reviewable changes that preserve the existing Swift Package layout.
- Keep documentation aligned with behavior when changing app capabilities or external dependencies.

## Project Context

- `Hive` is a macOS menu bar app built with SwiftUI and Swift Package Manager.
- The app manages terminal "pods" and integrates with Ghostty, yabai, and local Claude/Codex session discovery.
- Local runtime state belongs on the user's machine and must not be checked into git.

## Development Expectations

- Validate changes with `swift build` when practical.
- If behavior depends on external tools, document the dependency in `README.md`.
- Treat privacy and portability as first-class concerns for any new config or persistence.
