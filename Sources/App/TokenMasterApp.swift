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

        Settings {
            SettingsView()
        }
    }
}
