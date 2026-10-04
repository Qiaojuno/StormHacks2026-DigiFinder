// Wave 1 stub with the frozen API (§3.3). Wave 3 implements it: executes effects, turns service output into events.
import Foundation
import DigiFinderCore

@MainActor
final class SessionRunner {
    /// step, last spoken line, isWalking
    var onUpdate: ((Step, String, Bool) -> Void)?

    private let env: AppEnvironment
    private var session: ShoppingSession
    private var started = false

    init(env: AppEnvironment) {
        self.env = env
        session = ShoppingSession(catalog: env.catalog.aisles)
    }

    /// Idempotent.
    func start() {
        guard !started else { return }
        started = true
        perform(session.handle(.started))
    }

    func volumeUp() {}
    func volumeDown() {}
    func screenTalkPressed() {}

    private func perform(_ effects: [Effect]) {
        for effect in effects {
            if case .say(let text, let priority) = effect { env.feedback.say(text, priority) }
        }
        onUpdate?(session.state.step, session.state.lastLine, session.state.isWalking)
    }
}
