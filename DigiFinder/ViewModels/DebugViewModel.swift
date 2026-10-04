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
    let events = UIDebugEvent.allCases

    private(set) var previewImage: CGImage?
    private(set) var heatmapImage: CGImage?
    private(set) var captureLines: [String] = []
    private(set) var depthLine = ""
    private(set) var snapshot = UIDebugSnapshot()

    private let capture: FrameSource
    private let sources: [UIDebugSnapshotSource]
    private let driver: UISessionDriving
    private let onVolumeUp: () -> Void
    private let onVolumeDown: () -> Void

    init(capture: FrameSource, sources: [UIDebugSnapshotSource], driver: UISessionDriving,
         onVolumeUp: @escaping () -> Void, onVolumeDown: @escaping () -> Void) {
        self.capture = capture
        self.sources = sources
        self.driver = driver
        self.onVolumeUp = onVolumeUp
        self.onVolumeDown = onVolumeDown
    }

    // MARK: Panel intents

    func submitTyped() {
        let text = typedRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        driver.submitTypedRequest(text)
        lastAction = "Sent: “\(text)”"
        typedRequest = ""
    }

    func send(_ event: UIDebugEvent) {
        driver.inject(event.event)
        lastAction = "Sent: \(event.title)"
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
        capture.debugOverlayEnabled = visible
        if visible { refresh() }
    }

    /// Pulls fresh snapshots (call ~2 Hz while the overlay is visible).
    func refresh() {
        previewImage = capture.latestDebugImage
        heatmapImage = capture.latestDepthHeatmap
        captureLines = capture.debugInfo.lines
        depthLine = capture.latestDepthSummary?.line ?? "depth –"
        snapshot = sources.reduce(UIDebugSnapshot()) { $0.merged(with: $1.debugSnapshot) }
    }
}
