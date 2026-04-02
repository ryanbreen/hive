import SwiftUI

@main
struct HiveApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("Hive", systemImage: "hexagon.fill") {
            MenuBarView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
