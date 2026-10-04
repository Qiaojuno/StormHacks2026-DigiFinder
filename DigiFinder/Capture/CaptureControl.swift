import CoreGraphics
import Foundation
import DigiFinderCore

/// Extra controls every Capture frame source offers beyond `FrameSource` (local adapter until the contract grows;
/// see CONTRACT_CHANGES.md). Use `(env.frames as? CaptureControl)`.
protocol CaptureControl: AnyObject {
    /// Called (on an arbitrary queue) when `capabilities` change after `start()`: permission answered,
    /// session configured, or configuration failed.
    var onCapabilitiesChange: ((CaptureCapabilities) -> Void)? { get set }

    /// Thermal hook: lowers Stream B first, depth only when critical (§5.16). Callable from any thread.
    func setThermalLevel(_ level: ThermalLevel)
    /// Explicit caps from other modules (combined with the thermal caps by minimum). Callable from any thread.
    func setRates(_ rates: CaptureRates)
    /// Effective caps now.
    var rates: CaptureRates { get }

    /// Another Stream B subscription (bufferingNewest(1)). `streamB` itself supports one consumer only.
    func makeStreamB() -> AsyncStream<FrameB>

    // Debug overlay (read-only snapshots, safe from any thread).
    var debugInfo: CaptureDebugInfo { get }
    var latestDepthSummary: CaptureDepthSummary? { get }
    /// Upright 1× preview (~2 Hz) while `debugOverlayEnabled`.
    var latestDebugImage: CGImage? { get }
    /// Upright depth heatmap (red near, blue far, black invalid; ~2 Hz) while `debugOverlayEnabled`.
    var latestDepthHeatmap: CGImage? { get }
    /// Turns on the preview and heatmap rendering (off by default to save power).
    var debugOverlayEnabled: Bool { get set }
}
