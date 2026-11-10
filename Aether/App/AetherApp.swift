import SwiftUI

@main
struct AetherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var runtime = AppRuntime.shared

    var body: some Scene {
        MenuBarExtra("Aether", systemImage: "sparkle") {
            Button("Show Aether") { runtime.showPanel() }
            Button("New Conversation") { runtime.store?.newConversation(); runtime.showPanel() }
                .keyboardShortcut("n")
            Divider()
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Aether") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        Settings {
            SettingsView(runtime: runtime)
                .preferredColorScheme(runtime.settings.colorScheme)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") { runtime.store?.newConversation(); runtime.showPanel() }
                    .keyboardShortcut("n")
            }
        }
    }
}
