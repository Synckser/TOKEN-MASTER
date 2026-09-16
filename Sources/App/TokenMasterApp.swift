import SwiftUI

@main
struct TokenMasterApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
                .task { store.refresh(); store.updateHealthAndAdvice() }
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("TOKEN MASTER — Optimize", id: "optimizer") {
            OptimizerView(store: store)
        }
        .defaultSize(width: 480, height: 660)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView()
        }
    }
}
