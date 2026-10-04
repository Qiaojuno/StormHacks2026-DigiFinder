import AVFoundation
import CoreVideo
import Foundation
import simd
import DigiFinderCore

/// Projects depth-camera points into Stream B (the 0.5× image YOLO runs on), lenses treated as co-located (§2).
/// Uses the live Stream B intrinsics when the frame source shares them, else the depth intrinsics with the nominal
/// 2× field-of-view ratio `LiDARDepthProvider` also assumes.
///
/// Local adapter: Stream B intrinsics are read from `CaptureSessionSource.calibration` until `CaptureControl`
/// exposes them (CONTRACT_CHANGES.md, "CaptureControl: Stream B calibration for Safety labels").
enum SafetyStreamBLens {
    case calibrated(K: simd_float3x3, width: Int, height: Int)
    case nominal(depthK: simd_float3x3, width: Int, height: Int, zoom: Double)

    /// The shared calibration of a camera-backed frame source, if any (look it up once).
    static func calibration(of frames: FrameSource) -> CaptureCalibration? {
        (frames as? CaptureSessionSource)?.calibration
    }

    static func make(calibration: CaptureCalibration?, depth: AVDepthData) -> SafetyStreamBLens? {
        if let b = calibration?.streamB {
            return .calibrated(K: b.intrinsics, width: b.width, height: b.height)
        }
        let map = depth.depthDataMap
        let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map)
        guard w > 0, h > 0 else { return nil }
        let K = CameraGeometry.intrinsics(of: depth)
            ?? CameraGeometry.nominalIntrinsics(width: w, height: h,
                                                horizontalFOVDegrees: LiDARDepthProvider.nominalDepthFOVDegrees)
        return .nominal(depthK: K, width: w, height: h, zoom: LiDARDepthProvider.nominalStreamBZoom)
    }

    /// Camera-space point (before leveling) → Stream B upright-portrait normalized point; nil outside the image.
    func project(_ p: SIMD3<Float>) -> NormPoint? {
        switch self {
        case let .calibrated(K, width, height):
            return CameraGeometry.streamBPoint(p, KB: K, width: width, height: height)
        case let .nominal(K, width, height, zoom):
            // Depth-map pixel, then the 1× sensor position scaled into the ~2× wider Stream B sensor.
            guard zoom > 0, let px = CameraGeometry.projectToStreamB(p, KB: K) else { return nil }
            let sx = (Double(px.x) / Double(width) - 0.5) / zoom + 0.5
            let sy = (Double(px.y) / Double(height) - 0.5) / zoom + 0.5
            let n = Geometry.fromSensorPixels((x: sx, y: sy), width: 1, height: 1)
            guard (0...1).contains(n.x), (0...1).contains(n.y) else { return nil }
            return n
        }
    }
}
