import Foundation

/// Errors thrown by the frame sources.
enum CaptureError: Error {
    /// No usable camera (Simulator, no back camera, or the session failed to configure).
    case unavailable
    /// The photo output returned no usable image.
    case stillFailed
    /// Camera permission is denied or restricted.
    case denied
    /// The session is not running, so there is nothing to capture from.
    case notRunning
    /// A still took too long (the session was interrupted or stopped mid-capture).
    case timeout
}
