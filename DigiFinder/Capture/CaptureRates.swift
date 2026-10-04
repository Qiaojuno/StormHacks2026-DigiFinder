import AVFoundation
import Foundation
import DigiFinderCore

/// Delivery caps for the two streams. Thermal hook (§5.16): YOLO/OCR slow down with Stream B, danger is throttled last.
struct CaptureRates: Equatable {
    /// Max frames per second yielded on `streamB` (consumers drop further through `bufferingNewest(1)`).
    var streamBFPS: Double
    /// Max depth frames per second passed to `onDepth` (safety lane).
    var depthFPS: Double

    static let full = CaptureRates(streamBFPS: 30, depthFPS: 30)

    /// Default caps per thermal level: Stream B first, depth only when critical.
    static func forThermal(_ level: ThermalLevel) -> CaptureRates {
        switch level {
        case .nominal: return full
        case .fair: return CaptureRates(streamBFPS: 24, depthFPS: 30)
        case .serious: return CaptureRates(streamBFPS: 12, depthFPS: 30)
        case .critical: return CaptureRates(streamBFPS: 5, depthFPS: 15)
        }
    }

    /// Component-wise minimum.
    func capped(by o: CaptureRates) -> CaptureRates {
        CaptureRates(streamBFPS: min(streamBFPS, o.streamBFPS), depthFPS: min(depthFPS, o.depthFPS))
    }

    /// Ordering for `ThermalLevel` (not Comparable in Core).
    static func severity(_ l: ThermalLevel) -> Int {
        switch l { case .nominal: return 0; case .fair: return 1; case .serious: return 2; case .critical: return 3 }
    }

    static func worse(_ a: ThermalLevel, _ b: ThermalLevel) -> ThermalLevel { severity(a) >= severity(b) ? a : b }

    /// Camera system pressure (heat, power, depth-module temperature) as a thermal level.
    static func level(_ p: AVCaptureDevice.SystemPressureState.Level) -> ThermalLevel {
        switch p {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        default: return .critical                    // .critical, .shutdown
        }
    }

    /// ProcessInfo thermal state as a thermal level (for callers without a SystemMonitor).
    static func level(_ s: ProcessInfo.ThermalState) -> ThermalLevel {
        switch s {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        default: return .critical
        }
    }
}
