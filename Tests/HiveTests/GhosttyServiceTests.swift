import Foundation
import Testing
@testable import Hive

struct GhosttyServiceTests {
    @Test
    func initialInputForShellPaneStartsInRequestedDirectory() async throws {
        let service = GhosttyService()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let input = await service.initialInput(dir: "~/tmp/project", pane: nil)

        #expect(input == "cd -- '\(home)/tmp/project'\n")
    }

    @Test
    func initialInputForCommandPaneChangesDirectoryBeforeLaunchingProcess() async throws {
        let service = GhosttyService()
        let pane = PaneConfig(position: .left0, processType: .codex, sessionId: "session-123")
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let input = await service.initialInput(dir: "~/tmp/project", pane: pane)

        #expect(input.hasPrefix("cd -- '\(home)/tmp/project'\n"))
        #expect(input.hasSuffix("codex resume session-123\n"))
    }

    @Test
    func initialInputEscapesSingleQuotesInPath() async throws {
        let service = GhosttyService()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let input = await service.initialInput(dir: "~/tmp/it's-real", pane: nil)

        #expect(input.contains("cd -- '\(home)/tmp/it'\\''s-real'\n"))
    }
}
