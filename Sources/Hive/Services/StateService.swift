import Foundation

struct PodState: Codable, Sendable {
    var pods: [Pod]
}

actor StateService {
    private let stateDir: URL
    private let stateFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        stateDir = home.appendingPathComponent(".claude-pods")
        stateFile = stateDir.appendingPathComponent("state.json")
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        nonisolated(unsafe) let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = formatter.date(from: dateString) {
                return date
            }
            let basicFormatter = ISO8601DateFormatter()
            basicFormatter.formatOptions = [.withInternetDateTime]
            if let date = basicFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
        return decoder
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        nonisolated(unsafe) let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    func load() throws -> [Pod] {
        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            return []
        }
        let data = try Data(contentsOf: stateFile)
        let decoder = makeDecoder()
        let state = try decoder.decode(PodState.self, from: data)
        return state.pods.map { migratePod($0) }
    }

    func save(_ pods: [Pod]) throws {
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: stateFile.path) {
            let backupFile = stateDir.appendingPathComponent("state.json.bak")
            try? FileManager.default.removeItem(at: backupFile)
            try? FileManager.default.copyItem(at: stateFile, to: backupFile)
        }

        let encoder = makeEncoder()
        let state = PodState(pods: pods)
        let data = try encoder.encode(state)

        let tempFile = stateDir.appendingPathComponent("state.json.tmp")
        try data.write(to: tempFile, options: .atomic)

        if FileManager.default.fileExists(atPath: stateFile.path) {
            try FileManager.default.removeItem(at: stateFile)
        }
        try FileManager.default.moveItem(at: tempFile, to: stateFile)
    }

    private func migratePod(_ pod: Pod) -> Pod {
        if !pod.panes.isEmpty {
            return pod
        }

        var migrated = pod
        var panes: [PaneConfig] = []

        let count = pod.claudeCount ?? 1
        let sessions = pod.claudeSessions ?? []
        let leftPositions = PanePosition.leftPositions(count: count)

        for (i, position) in leftPositions.enumerated() {
            let sessionId = i < sessions.count && !sessions[i].isEmpty ? sessions[i] : nil
            panes.append(PaneConfig(position: position, processType: .claude, sessionId: sessionId))
        }

        if let mainCmd = pod.mainCmd, !mainCmd.isEmpty {
            panes.append(PaneConfig(position: .middle, processType: .custom, customCommand: mainCmd))
        } else {
            panes.append(PaneConfig(position: .middle, processType: .shell))
        }

        panes.append(PaneConfig(position: .rightTop, processType: .lazygit))
        panes.append(PaneConfig(position: .rightBottom, processType: .shell))

        migrated.panes = panes
        return migrated
    }
}
