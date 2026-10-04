import AppIntents
import Foundation

/// Siri phrases with no setup (§9 Siri intent). Every phrase must contain the app name.
struct VoiceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenAppIntent(),
                    phrases: ["Open \(.applicationName)",
                              "Start shopping with \(.applicationName)",
                              "Start \(.applicationName)"],
                    shortTitle: "Start Shopping",
                    systemImageName: "cart")
    }
}
