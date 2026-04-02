# Claude Notes

## What This Project Is

`Hive` is a SwiftUI macOS menu bar app for launching and organizing terminal workspaces ("pods").

## Important Constraints

- Keep the repository public-safe: no personal paths, usernames, secrets, or local machine details in tracked files.
- Do not commit generated state, build output, or editor-specific files.
- Preserve the Swift Package structure unless a change clearly improves maintainability.

## Useful Context

- The app currently depends on Ghostty and yabai for terminal and window management.
- It also discovers local Claude and Codex sessions from user-specific directories at runtime.
- User data is local application state, not repository data.

## When Editing

- Update `README.md` if setup steps, requirements, or behavior change.
- Favor straightforward SwiftUI and Foundation code over unnecessary abstraction.
- Run `swift build` after meaningful code or package changes when possible.
