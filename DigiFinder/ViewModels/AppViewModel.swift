import Foundation
import Observation
import DigiFinderCore

@Observable @MainActor
final class AppViewModel {
    private(set) var stepTitle = "Ready"
    private(set) var lastMessage = ""
    private(set) var isWalking = false
    var showSetup = false
    var showDebug = false
    private let runner: SessionRunner

    init(env: AppEnvironment) {
        runner = SessionRunner(env: env)
        runner.onUpdate = { [weak self] step, message, walking in
            self?.stepTitle = step.title; self?.lastMessage = message; self?.isWalking = walking
        }
    }

    func onAppear()   { runner.start() }
    /// The runner applies the walking / recording rules (§5.10).
    func talkTapped() { runner.screenTalkPressed() }
    func volumeUp()   { runner.volumeUp() }
    func volumeDown() { runner.volumeDown() }
}
