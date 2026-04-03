import Foundation

actor GhosttyService {
    private func runAppleScript(_ script: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw HiveError.ghosttyAutomationFailed(errMsg)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func shellEscape(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func expandedDirectory(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    func initialInput(dir: String, pane: PaneConfig?) -> String {
        let expandedDir = expandedDirectory(dir)
        var lines = ["cd -- \(shellEscape(expandedDir))"]
        if let cmd = pane?.launchCommand, !cmd.isEmpty {
            lines.append(cmd)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func paneConfig(dir: String, pane: PaneConfig?) -> String {
        let expandedDir = expandedDirectory(dir)
        let input = escape(initialInput(dir: dir, pane: pane))
        let escapedDir = escape(expandedDir)
        return "(new surface configuration from {initial working directory:\"\(escapedDir)\", initial input:\"\(input)\"})"
    }

    func launchPod(pod: Pod) async throws {
        let dir = pod.directory
        let leftPanes = pod.leftPanes
        let middle = pod.middlePane
        let rightPanes = pod.rightPanes

        var lines: [String] = []
        lines.append("tell application \"Ghostty\"")
        lines.append("  activate")

        // Each pane gets its own surface configuration with directory and command baked in
        let t0Pane = leftPanes.first
        lines.append("  set cfg0 to \(paneConfig(dir: dir, pane: t0Pane))")

        if pod.mode == .standalone {
            lines.append("  set win to (new window with configuration cfg0)")
            lines.append("  set baseTab to selected tab of win")
        } else {
            lines.append("  set win to front window")
            lines.append("  set newTab to (new tab in win with configuration cfg0)")
            lines.append("  set baseTab to newTab")
        }

        lines.append("  set t0 to focused terminal of baseTab")

        // Create per-pane configs and split — commands launch deterministically via initial input
        lines.append("  set cfgMid to \(paneConfig(dir: dir, pane: middle))")
        lines.append("  set midTerm to (split t0 direction right with configuration cfgMid)")

        let rightTop = rightPanes.count >= 1 ? rightPanes[0] : nil
        lines.append("  set cfgRT to \(paneConfig(dir: dir, pane: rightTop))")
        lines.append("  set rightTerm to (split midTerm direction right with configuration cfgRT)")

        if rightPanes.count >= 2 {
            lines.append("  set cfgRB to \(paneConfig(dir: dir, pane: rightPanes[1]))")
            lines.append("  set rightBottom to (split rightTerm direction down with configuration cfgRB)")
        }

        var leftTermNames: [String] = ["t0"]
        for i in 1..<leftPanes.count {
            let prevName = leftTermNames[i - 1]
            let newName = "left\(i)"
            lines.append("  set cfg\(newName) to \(paneConfig(dir: dir, pane: leftPanes[i]))")
            lines.append("  set \(newName) to (split \(prevName) direction down with configuration cfg\(newName))")
            leftTermNames.append(newName)
        }

        lines.append("  perform action \"equalize_splits\" on t0")

        let tabTitle = escape(URL(fileURLWithPath: pod.directory).lastPathComponent)
        lines.append("  perform action \"set_tab_title:\(tabTitle)\" on t0")

        lines.append("end tell")

        let script = lines.joined(separator: "\n")
        _ = try await runAppleScript(script)
    }

    func rebuildAll(pods: [Pod]) async throws {
        let sorted = pods.sorted { a, b in
            if a.workspace != b.workspace { return a.workspace < b.workspace }
            return a.createdAt < b.createdAt
        }

        let standalones = sorted.filter { $0.mode == .standalone }
        let tabs = sorted.filter { $0.mode == .tab }

        for pod in standalones {
            try await launchPod(pod: pod)
        }

        for pod in tabs {
            try await launchPod(pod: pod)
        }
    }

    func listWindows() async throws -> String {
        let script = """
        tell application "Ghostty"
            set output to ""
            repeat with win in windows
                set output to output & id of win & ":" & name of win & linefeed
            end repeat
            return output
        end tell
        """
        return try await runAppleScript(script)
    }

    func closeTerminal(terminalId: String) async throws {
        let script = """
        tell application "Ghostty"
            repeat with t in terminals
                if id of t is "\(escape(terminalId))" then
                    close t
                    return true
                end if
            end repeat
            return false
        end tell
        """
        _ = try await runAppleScript(script)
    }
}
