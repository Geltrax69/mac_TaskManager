import SwiftUI

@main
struct MacCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(before: .toolbar) {
                Button("Find in Processes") {
                    NotificationCenter.default.post(name: .focusProcessSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let focusProcessSearch = Notification.Name("com.geltrax.maccleaner.focusProcessSearch")
}
