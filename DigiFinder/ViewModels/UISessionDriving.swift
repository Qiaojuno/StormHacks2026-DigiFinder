import Foundation
import DigiFinderCore

/// Runner features the UI needs beyond the frozen `SessionRunner` API (see CONTRACT_CHANGES.md, "SessionRunner: UI hooks").
/// Wave 3 makes `SessionRunner` conform. Until then the view models find no conformance and these actions do nothing.
@MainActor
protocol UISessionDriving: AnyObject {
    /// Typed text treated exactly like a finished transcript (debug panel / Simulator): route it and send
    /// `.routed(_)` or `.notUnderstood(noisy: false)`; if a recording is running, it ends with this text.
    func submitTypedRequest(_ text: String)
    /// Feeds an event to the session as if a service had produced it, then performs the effects.
    /// For `.danger`, also run the alert through `feedback.danger(_:steer:)` first, as the safety lane would.
    func inject(_ event: SessionEvent)
    /// Drag-to-hear: speak a screen element's text (`.reply` priority, replaces the previous screen line).
    func speakScreenText(_ text: String)
    /// First-launch / setup walkthrough: speak the lines in order (`.reply`); the session's opening prompt follows it.
    func speakWalkthrough(_ lines: [String])
    /// Apply setup settings: speech speed and voice, units, tones, danger haptics, detail level.
    func apply(settings: UISettings)
}

/// Status chip values, read from the environment by `AppViewModel`.
struct UIStatus: Equatable {
    var cameraAvailable = false
    var hasLiDAR = false
    var hasOfflineDatabase = false
    var isOnline = false
}
