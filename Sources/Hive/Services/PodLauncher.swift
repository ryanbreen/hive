import Foundation

actor PodLauncher {
    private let ghostty = GhosttyService()
    private let yabai = YabaiService()

    func launch(pod: Pod) async throws {
        if pod.mode == .standalone {
            try await launchStandalone(pod: pod)
        } else {
            try await launchTab(pod: pod)
        }
    }

    private func launchStandalone(pod: Pod) async throws {
        try await ghostty.launchPod(pod: pod)
        try await Task.sleep(for: .milliseconds(300))

        if let win = try? await yabai.newestGhosttyWindow() {
            let currentSpace = try? await yabai.currentSpace()
            if currentSpace != pod.workspace {
                try await yabai.moveWindow(windowId: win.id, toSpace: pod.workspace)
            }
        }
    }

    private func launchTab(pod: Pod) async throws {
        try await yabai.focusSpace(pod.workspace)
        try await Task.sleep(for: .milliseconds(300))

        let windowsOnSpace = try await yabai.ghosttyWindowsOnSpace(pod.workspace)

        if windowsOnSpace.first != nil {
            let script = """
            tell application "System Events"
                tell process "Ghostty"
                    set frontmost to true
                end tell
            end tell
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            try await Task.sleep(for: .milliseconds(200))
        }

        try await ghostty.launchPod(pod: pod)
    }

    /// Rebuild all pods using Ghostty's native session restore.
    /// Creates all windows/tabs/panes in a single atomic call,
    /// then uses yabai to move windows to their target workspaces.
    func rebuildAllViaSession(pods: [Pod]) async throws {
        let session = GhosttySessionBuilder.buildSession(from: pods)
        let filePath = try GhosttySessionBuilder.writeSessionFile(session)

        // Snapshot existing Ghostty window IDs before restore so we can
        // identify newly-created windows afterward.
        let existingIds = Set((try? await yabai.ghosttyWindows())?.map(\.id) ?? [])

        _ = try await ghostty.restoreSession(filePath: filePath)

        // Build ordered list of target workspaces matching session window order.
        // GhosttySessionBuilder sorts pods by workspace then createdAt, so the
        // session windows appear in the same order.
        var windowOrder: [String] = []
        var groupWorkspaces: [String: Int] = [:]
        let sorted = pods.sorted { a, b in
            if a.workspace != b.workspace { return a.workspace < b.workspace }
            return a.createdAt < b.createdAt
        }
        for pod in sorted {
            if groupWorkspaces[pod.windowGroup] == nil {
                windowOrder.append(pod.windowGroup)
                groupWorkspaces[pod.windowGroup] = pod.workspace
            }
        }

        // Wait for Ghostty to finish creating windows.
        try await Task.sleep(for: .milliseconds(600))

        // New windows, sorted ascending by yabai ID (creation order).
        let allWindows = (try? await yabai.ghosttyWindows()) ?? []
        let newWindows = allWindows
            .filter { !existingIds.contains($0.id) }
            .sorted { $0.id < $1.id }

        // Move each new window to its target workspace in order.
        for (index, group) in windowOrder.enumerated() {
            guard index < newWindows.count else { break }
            guard let targetWorkspace = groupWorkspaces[group] else { continue }

            let win = newWindows[index]
            if win.space != targetWorkspace {
                try? await yabai.moveWindow(windowId: win.id, toSpace: targetWorkspace)
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func rebuildAll(pods: [Pod]) async throws {
        let sorted = pods.sorted { a, b in
            if a.workspace != b.workspace { return a.workspace < b.workspace }
            return a.createdAt < b.createdAt
        }

        let standalones = sorted.filter { $0.mode == .standalone }
        let tabs = sorted.filter { $0.mode == .tab }

        var windowGroupMap: [String: Int] = [:]

        for pod in standalones {
            try await ghostty.launchPod(pod: pod)
            try await Task.sleep(for: .milliseconds(300))

            if let win = try? await yabai.newestGhosttyWindow() {
                windowGroupMap[pod.id] = win.id
                let currentSpace = try? await yabai.currentSpace()
                if currentSpace != pod.workspace {
                    try await yabai.moveWindow(windowId: win.id, toSpace: pod.workspace)
                    try await Task.sleep(for: .milliseconds(200))
                }
            }
        }

        for pod in tabs {
            try await yabai.focusSpace(pod.workspace)
            try await Task.sleep(for: .milliseconds(300))

            if windowGroupMap[pod.windowGroup] != nil {
                let focusScript = """
                tell application "System Events"
                    tell process "Ghostty"
                        set frontmost to true
                    end tell
                end tell
                """
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", focusScript]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try process.run()
                process.waitUntilExit()
                try await Task.sleep(for: .milliseconds(200))
            }

            try await ghostty.launchPod(pod: pod)
            try await Task.sleep(for: .milliseconds(200))
        }
    }
}
