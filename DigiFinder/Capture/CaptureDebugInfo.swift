import Foundation
import DigiFinderCore

/// Read-only capture status for the debug overlay (§6, M1 "Debug preview, heatmap, costs").
struct CaptureDebugInfo: Equatable {
    /// "LiDAR + ultra-wide", "ultra-wide", "wide", or why there is no camera.
    var backend = "none"
    var isRunning = false
    var interruption: String?
    /// Multi-cam only (nil for a single-camera session).
    var hardwareCost: Float?
    var systemPressureCost: Float?
    var streamBFormat = "–"
    var depthFormat = "–"
    var streamBFPS: Double = 0
    var depthFPS: Double = 0
    var droppedStreamB = 0
    var droppedDepth = 0
    /// Worse of the reported thermal level and the camera's own system pressure.
    var thermal: ThermalLevel = .nominal
    var rates = CaptureRates.full
    var lastError: String?

    /// nil when not a multi-cam session.
    var costsUnderLimit: Bool? {
        guard let h = hardwareCost, let s = systemPressureCost else { return nil }
        return h < 1 && s < 1
    }

    var lines: [String] {
        var out = ["\(backend) · \(isRunning ? "running" : "stopped")" + (interruption.map { " · interrupted: \($0)" } ?? "")]
        if let h = hardwareCost, let s = systemPressureCost {
            out.append(String(format: "cost hw %.2f · pressure %.2f", h, s) + (h < 1 && s < 1 ? "" : " · OVER 1.0"))
        }
        out.append("B \(streamBFormat) · \(String(format: "%.0f", streamBFPS)) fps · dropped \(droppedStreamB)")
        if depthFormat != "–" {
            out.append("A \(depthFormat) · \(String(format: "%.0f", depthFPS)) fps · dropped \(droppedDepth)")
        }
        out.append("thermal \(thermal) · caps B \(Int(rates.streamBFPS)) / A \(Int(rates.depthFPS)) fps")
        if let lastError { out.append("error: \(lastError)") }
        return out
    }
}
