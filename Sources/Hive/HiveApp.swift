import SwiftUI

@main
struct HiveApp: App {
    @State private var appState = AppState()

    init() {
        GhosttyService.ensureHookScript()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            BackupStatusMenuBarLabel(backupMode: appState.backupMode)
        }
        .menuBarExtraStyle(.window)
    }
}
