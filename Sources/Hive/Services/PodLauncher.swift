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
