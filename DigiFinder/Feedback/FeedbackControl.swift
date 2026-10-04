import Foundation
import DigiFinderCore

/// Extra feedback controls beyond the frozen `FeedbackOutput` (see CONTRACT_CHANGES.md).
/// Use `(env.feedback as? FeedbackControl)` until the contract adopts them.
protocol FeedbackControl: AnyObject {
    /// Vibration only, no speech: the same danger is still ahead (re-alert without repeating the line).
    func dangerVibrationOnly()
    /// Narration is dropped at `.brief` (§5.15).
    var verbosity: Verbosity { get set }
    /// Setup: speech speed, `AVSpeechUtterance` rate (0...1, default `AVSpeechUtteranceDefaultSpeechRate`).
    var speechRate: Float { get set }
    /// Setup toggles.
    var tonesEnabled: Bool { get set }
    var dangerHapticsEnabled: Bool { get set }
}
