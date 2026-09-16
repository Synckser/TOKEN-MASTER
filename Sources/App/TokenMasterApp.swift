import SwiftUI

@main
struct TokenMasterApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuView(store: store)
                .task { store.start() }
        } label: {
            Text(store.menuBarLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
