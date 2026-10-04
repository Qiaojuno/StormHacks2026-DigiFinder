import AppIntents
import Foundation

/// "Hey Siri, open DigiFinder" (§9 Siri intent). Opening the app is enough: MainView.onAppear → runner.start()
/// (idempotent) asks "What are you looking for? Press volume up to tell me." and waits for volume up.
struct OpenAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Shopping"
    static let description = IntentDescription("Opens DigiFinder and asks what you are looking for.")
    static let openAppWhenRun: Bool = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult { .result() }
}
