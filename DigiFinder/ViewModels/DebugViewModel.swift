import CoreGraphics
import Foundation
import Observation
import DigiFinderCore

/// Debug panel (typed requests + event buttons) and the judges' overlay (§6). UI state only:
/// injections go to the runner through `UISessionDriving`, images and values are read-only snapshots.
@Observable @MainActor
final class DebugViewModel {
    var typedRequest = ""
    /// Last action, shown under the panel ("Sent: Signs").
    private(set) var lastAction = ""
    /// False until the runner adopts `UISessionDriving` (Wave 3).
    let canInject: Bool
    let hasCaptureControl: Bool
    let events = UIDebugEvent.allCases

    private(set) var previewImage: CGImage?
    private(set) var heatmapImage: CGImage?
    private(set) var captureLines: [String] = []
    private(set) var depthLine = ""
    private(set) var snapshot = UIDebugSnapshot()

    private let capture: CaptureControl?
    private let sources: [UIDebugSnapshotSource]
    private let driver: UISessionDriving?
    private let onVolumeUp: () -> Void
    private let onVolumeDown: () -> Void

    init(capture: CaptureControl?, sources: [UIDebugSnapshotSource], driver: UISessionDriving?,
         onVolumeUp: @escaping () -> Void, onVolumeDown: @escaping () -> Void) {
        self.capture = capture
        self.sources = sources
        self.driver = driver
        self.onVolumeUp = onVolumeUp
        self.onVolumeDown = onVolumeDown
        canInject = driver != nil
        hasCaptureControl = capture != nil
    }

    // MARK: Panel intents

    func submitTyped() {
        let text = typedRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        driver?.submitTypedRequest(text)
        lastAction = canInject ? "Sent: “\(text)”" : "Runner can't take typed requests yet."
        typedRequest = ""
    }

    func send(_ event: UIDebugEvent) {
        driver?.inject(event.event)
        lastAction = canInject ? "Sent: \(event.title)" : "Runner can't take debug events yet."
    }

    func volumeUp() {
        onVolumeUp()
        lastAction = "Volume up"
    }

    func volumeDown() {
        onVolumeDown()
        lastAction = "Volume down"
    }

    // MARK: Overlay

    /// Turns the capture preview and heatmap rendering on while the overlay is visible.
    func setOverlayVisible(_ visible: Bool) {
        capture?.debugOverlayEnabled = visible
        if visible { refresh() }
    }

    /// Pulls fresh snapshots (call ~2 Hz while the overlay is visible).
    func refresh() {
        if let capture {
            previewImage = capture.latestDebugImage
            heatmapImage = capture.latestDepthHeatmap
            captureLines = capture.debugInfo.lines
            depthLine = capture.latestDepthSummary?.line ?? "depth –"
        } else {
            captureLines = ["Capture debug info unavailable."]
            depthLine = ""
        }
        snapshot = sources.reduce(UIDebugSnapshot()) { $0.merged(with: $1.debugSnapshot) }
    }
}
