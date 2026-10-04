import AVFoundation
import CoreGraphics
import Foundation
import simd
import DigiFinderCore

/// LiDAR depth → leveled 3D points and point distances (§2, §9 Unproject and project). Thread-safe (no mutable state).
struct LiDARDepthProvider: DepthProvider {
    /// Samples per row for `points` (a 320×240 map → stride 2 → ~160×120 points).
    static let sampleColumns = 160
    /// Horizontal field of view of the 1× camera the LiDAR depth is registered to; only used without calibration data.
    static let nominalDepthFOVDegrees: Float = 69
    /// Without Stream B intrinsics: the 0.5× ultra-wide sees about twice the 1× field of view (13 mm vs 26 mm).
    static let nominalStreamBZoom: Double = 2

    private let calibration: CaptureCalibration?

    /// `calibration`: Stream B intrinsics from the frame source (`CaptureFactory` wires it), used by `distance(at:)`.
    init(calibration: CaptureCalibration? = nil) {
        self.calibration = calibration
    }

    /// Leveled points (+x right, +y up, +z forward, meters) with low-confidence pixels dropped.
    func points(_ f: DepthFrame, gravity: SIMD3<Float>) -> [Vec3] {
        guard let depth = CaptureDepthMap.float32(f.depth) else { return [] }
        let basis = CameraGeometry.levelBasis(gravity: gravity)
        return CaptureDepthMap.read(depth) { map -> [Vec3] in
            let K = Self.intrinsics(depth, map)
            let step = max(1, map.width / Self.sampleColumns)
            var out: [Vec3] = []
            out.reserveCapacity((map.width / step + 1) * (map.height / step + 1))
            var v = step / 2
            while v < map.height {
                var u = step / 2
                while u < map.width {
                    if let z = map.confidentDepth(u, v, step: step) {
                        out.append(CameraGeometry.level(CameraGeometry.unproject(u: Float(u), v: Float(v), z: z, K: K), basis))
                    }
                    u += step
                }
                v += step
            }
            return out
        } ?? []
    }

    /// Distance in meters (along the viewing ray) at a point of Stream B's upright portrait image, the app's only
    /// camera image. Uses the median of a 5×5 depth window; nil outside the LiDAR field of view or without depth.
    func distance(at p: NormPoint, _ f: DepthFrame) -> Float? {
        guard let depth = CaptureDepthMap.float32(f.depth) else { return nil }
        let streamB = calibration?.streamB
        let result: Float?? = CaptureDepthMap.read(depth) { map -> Float? in
            let K = Self.intrinsics(depth, map)
            let px: CGPoint
            if let b = streamB,
               let q = CameraGeometry.depthPixel(forStreamB: p, KB: b.intrinsics, widthB: b.width, heightB: b.height, KD: K) {
                px = q
            } else {
                let s = Geometry.toSensorPixels(p, width: 1, height: 1)
                px = CGPoint(x: ((s.x - 0.5) * Self.nominalStreamBZoom + 0.5) * Double(map.width),
                             y: ((s.y - 0.5) * Self.nominalStreamBZoom + 0.5) * Double(map.height))
            }
            guard px.x.isFinite, px.y.isFinite, px.x >= 0, px.y >= 0,
                  px.x < CGFloat(map.width), px.y < CGFloat(map.height) else { return nil }
            guard let z = map.medianDepth(Int(px.x), Int(px.y), radius: 2, minCount: 5) else { return nil }
            return CameraGeometry.range(u: Float(px.x), v: Float(px.y), z: z, K: K)
        }
        return result ?? nil
    }

    private static func intrinsics(_ depth: AVDepthData, _ map: CaptureDepthMap) -> simd_float3x3 {
        CameraGeometry.intrinsics(of: depth)
            ?? CameraGeometry.nominalIntrinsics(width: map.width, height: map.height, horizontalFOVDegrees: nominalDepthFOVDegrees)
    }
}
