import Foundation
import Testing
@testable import Hive

struct StateServiceTests {
    @Test
    func liveSyncEmptySnapshotDoesNotOverwriteCurrentState() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let service = StateService(baseDirectory: baseDirectory)
        let pods = [makePod(id: "pod-1")]

        try await service.save(pods)
        try await service.saveLiveSync([])

        let loaded = try await service.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "pod-1")
    }

    @Test
    func loadFallsBackToLastKnownGoodSnapshotWhenStateFileIsMissing() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let service = StateService(baseDirectory: baseDirectory)
        let pods = [makePod(id: "pod-1")]

        try await service.save(pods)
        try FileManager.default.removeItem(at: baseDirectory.appendingPathComponent("state.json"))

        let loaded = try await service.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "pod-1")
    }

    @Test
    func saveCurrentStateOnlyWritesStateWithoutCreatingSnapshots() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let service = StateService(baseDirectory: baseDirectory)
        let pods = [makePod(id: "pod-1")]

        try await service.saveCurrentStateOnly(pods)

        let stateFile = baseDirectory.appendingPathComponent("state.json")
        let backupFile = baseDirectory.appendingPathComponent("state.json.bak")
        let manifestFile = baseDirectory.appendingPathComponent("manifest.json")
        let snapshotsDir = baseDirectory.appendingPathComponent("snapshots")

        #expect(FileManager.default.fileExists(atPath: stateFile.path))
        #expect(!FileManager.default.fileExists(atPath: backupFile.path))
        #expect(!FileManager.default.fileExists(atPath: manifestFile.path))
        #expect(!FileManager.default.fileExists(atPath: snapshotsDir.path))

        let loaded = try await service.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "pod-1")
    }

    private func makePod(id: String) -> Pod {
        Pod(
            id: id,
            directory: "~/tmp/project",
            workspace: 1,
            mode: .standalone,
            windowGroup: id,
            panes: [
                PaneConfig(position: .left0, processType: .claude)
            ],
            createdAt: Date()
        )
    }
}
