import Foundation

struct PodState: Codable, Sendable {
    var pods: [Pod]
}

enum SnapshotSource: String, Codable, Sendable {
    case ui
    case liveSync
    case recovery
    case manualCheckpoint
}

enum SnapshotConfidence: String, Codable, Sendable {
    case authoritative
    case high
    case low
}

struct PodSnapshot: Codable, Sendable {
    var id: String
    var createdAt: Date
    var source: SnapshotSource
    var confidence: SnapshotConfidence
    var pods: [Pod]
}

struct SnapshotManifest: Codable, Sendable {
    var lastSnapshotID: String? = nil
    var lastKnownGoodSnapshotID: String? = nil
}

actor StateService {
    private let stateDir: URL
    private let stateFile: URL
    private let snapshotsDir: URL
    private let manifestFile: URL

    init(baseDirectory: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        stateDir = baseDirectory ?? home.appendingPathComponent(".claude-pods")
        stateFile = stateDir.appendingPathComponent("state.json")
        snapshotsDir = stateDir.appendingPathComponent("snapshots")
        manifestFile = stateDir.appendingPathComponent("manifest.json")
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
        if FileManager.default.fileExists(atPath: stateFile.path) {
            do {
                let data = try Data(contentsOf: stateFile)
                let decoder = makeDecoder()
                let state = try decoder.decode(PodState.self, from: data)
                return state.pods.map { migratePod($0) }
            } catch {
                return try loadLastKnownGoodPods()
            }
        }

        return try loadLastKnownGoodPods()
    }

    func save(_ pods: [Pod]) throws {
        try saveSnapshot(
            pods,
            source: .ui,
            confidence: .authoritative,
            allowEmptyPromotion: true
        )
    }

    func saveCurrentStateOnly(_ pods: [Pod]) throws {
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try writeCurrentState(pods, createBackupCopy: false)
    }

    func saveLiveSync(_ pods: [Pod], confidence: SnapshotConfidence = .high) throws {
        try saveSnapshot(
            pods,
            source: .liveSync,
            confidence: confidence,
            allowEmptyPromotion: false
        )
    }

    func saveRecovery(_ pods: [Pod]) throws {
        try saveSnapshot(
            pods,
            source: .recovery,
            confidence: .authoritative,
            allowEmptyPromotion: false
        )
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

    private func saveSnapshot(
        _ pods: [Pod],
        source: SnapshotSource,
        confidence: SnapshotConfidence,
        allowEmptyPromotion: Bool
    ) throws {
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        let snapshot = PodSnapshot(
            id: UUID().uuidString.lowercased(),
            createdAt: Date(),
            source: source,
            confidence: confidence,
            pods: pods
        )

        try writeSnapshot(snapshot)

        var manifest = try loadManifest()
        manifest.lastSnapshotID = snapshot.id
        if !pods.isEmpty {
            manifest.lastKnownGoodSnapshotID = snapshot.id
        }
        try writeManifest(manifest)

        if !pods.isEmpty || allowEmptyPromotion {
            try writeCurrentState(pods, createBackupCopy: true)
        }
    }

    private func loadLastKnownGoodPods() throws -> [Pod] {
        let manifest = try loadManifest()
        guard let snapshotID = manifest.lastKnownGoodSnapshotID else {
            return []
        }

        let snapshotURL = snapshotsDir.appendingPathComponent("\(snapshotID).json")
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return []
        }

        let data = try Data(contentsOf: snapshotURL)
        let decoder = makeDecoder()
        let snapshot = try decoder.decode(PodSnapshot.self, from: data)
        return snapshot.pods.map { migratePod($0) }
    }

    private func loadManifest() throws -> SnapshotManifest {
        guard FileManager.default.fileExists(atPath: manifestFile.path) else {
            return SnapshotManifest()
        }

        let data = try Data(contentsOf: manifestFile)
        let decoder = makeDecoder()
        return try decoder.decode(SnapshotManifest.self, from: data)
    }

    private func writeManifest(_ manifest: SnapshotManifest) throws {
        let encoder = makeEncoder()
        let data = try encoder.encode(manifest)
        let tempFile = stateDir.appendingPathComponent("manifest.json.tmp")
        try data.write(to: tempFile, options: .atomic)

        if FileManager.default.fileExists(atPath: manifestFile.path) {
            try FileManager.default.removeItem(at: manifestFile)
        }
        try FileManager.default.moveItem(at: tempFile, to: manifestFile)
    }

    private func writeSnapshot(_ snapshot: PodSnapshot) throws {
        let encoder = makeEncoder()
        let data = try encoder.encode(snapshot)
        let snapshotURL = snapshotsDir.appendingPathComponent("\(snapshot.id).json")
        let tempURL = snapshotsDir.appendingPathComponent("\(snapshot.id).json.tmp")
        try data.write(to: tempURL, options: .atomic)

        if FileManager.default.fileExists(atPath: snapshotURL.path) {
            try FileManager.default.removeItem(at: snapshotURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: snapshotURL)
    }

    private func writeCurrentState(_ pods: [Pod], createBackupCopy: Bool) throws {
        if createBackupCopy && FileManager.default.fileExists(atPath: stateFile.path) {
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
}
