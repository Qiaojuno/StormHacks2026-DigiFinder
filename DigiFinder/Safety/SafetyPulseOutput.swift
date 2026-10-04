import Foundation

/// Local adapter until `FeedbackOutput` gains a vibration-only call (CONTRACT_CHANGES.md,
/// "FeedbackOutput: vibration-only danger repeat"). Alert step 5 (§5.3): still closing ~2 s after the alert →
/// the danger vibrations once more, with no speech. A feedback object that doesn't adopt this gets no repeat
/// (`feedback.danger` would speak the line again).
protocol SafetyPulseOutput: AnyObject {
    /// The danger vibration pattern only: no speech, and speech already playing is left alone. Callable from any thread.
    func dangerPulse()
}
