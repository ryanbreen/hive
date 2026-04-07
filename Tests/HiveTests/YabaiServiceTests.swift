import Foundation
import Testing
@testable import Hive

struct YabaiServiceTests {
    @Test
    func resolvesHomebrewYabaiWhenLaunchdPathOmitsIt() async throws {
        let path = YabaiService.locateExecutablePath(
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            fileExists: { candidate in
                candidate == "/opt/homebrew/bin/yabai"
            }
        )

        #expect(path == "/opt/homebrew/bin/yabai")
    }

    @Test
    func prefersYabaiFoundOnPath() async throws {
        let path = YabaiService.locateExecutablePath(
            environment: ["PATH": "/tmp/custom:/usr/bin:/bin"],
            fileExists: { candidate in
                candidate == "/tmp/custom/yabai"
            }
        )

        #expect(path == "/tmp/custom/yabai")
    }
}
