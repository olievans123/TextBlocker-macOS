import SwiftUI

@main
struct TextBlockerApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}
