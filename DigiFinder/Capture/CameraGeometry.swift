import AVFoundation
import CoreGraphics
import CoreVideo
import simd
import DigiFinderCore

/// Depth → 3D → Stream B pixel (§2, §9). Camera space follows the landscape sensor:
/// +x along buffer columns, +y along buffer rows, +z forward. Lenses are treated as co-located.
enum CameraGeometry {
    /// Intrinsics `K` given at `reference` size, rescaled to an image of `size` (e.g. the depth map).
    static func scale(_ K: simd_float3x3, from reference: CGSize, to size: CGSize) -> simd_float3x3 {
        guard reference.width > 0, reference.height > 0 else { return K }
        let sx = Float(size.width / reference.width), sy = Float(size.height / reference.height)
        var k = K
        k[0][0] *= sx; k[2][0] *= sx
        k[1][1] *= sy; k[2][1] *= sy
        return k
    }

    /// Depth-map intrinsics from the frame's calibration data, scaled to the depth map size.
    static func intrinsics(of depth: AVDepthData) -> simd_float3x3? {
        guard let cal = depth.cameraCalibrationData else { return nil }
        let map = depth.depthDataMap
        let size = CGSize(width: CVPixelBufferGetWidth(map), height: CVPixelBufferGetHeight(map))
        return scale(cal.intrinsicMatrix, from: cal.intrinsicMatrixReferenceDimensions, to: size)
    }

    /// Depth pixel (u, v) at depth z (meters) → camera-space point.
    static func unproject(u: Float, v: Float, z: Float, K: simd_float3x3) -> SIMD3<Float> {
        SIMD3((u - K[2][0]) * z / K[0][0], (v - K[2][1]) * z / K[1][1], z)
    }

    /// Camera-space point (before leveling) → Stream B sensor pixel. nil if behind the camera.
    static func projectToStreamB(_ p: SIMD3<Float>, KB: simd_float3x3) -> CGPoint? {
        guard p.z > 0.01 else { return nil }
        return CGPoint(x: CGFloat(KB[0][0] * p.x / p.z + KB[2][0]), y: CGFloat(KB[1][1] * p.y / p.z + KB[2][1]))
    }

    /// Camera-space point → Stream B upright-portrait normalized point (contract space).
    /// `width`/`height`: Stream B buffer size in sensor pixels. nil if outside the frame.
    static func streamBPoint(_ p: SIMD3<Float>, KB: simd_float3x3, width: Int, height: Int) -> NormPoint? {
        guard let px = projectToStreamB(p, KB: KB), width > 0, height > 0 else { return nil }
        let n = Geometry.fromSensorPixels((x: Double(px.x), y: Double(px.y)), width: Double(width), height: Double(height))
        guard (0...1).contains(n.x), (0...1).contains(n.y) else { return nil }
        return n
    }

    /// Camera axes in the CoreMotion device frame (+x right of the portrait screen, +y top, +z out of the screen).
    /// Back camera: camera +x = device −y, camera +y = device −x, camera +z = device −z.
    static func cameraToDevice(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(-p.y, -p.x, -p.z) }

    static func deviceToCamera(_ d: SIMD3<Float>) -> SIMD3<Float> { SIMD3(-d.y, -d.x, -d.z) }

    struct LevelBasis {
        var right: SIMD3<Float>
        var up: SIMD3<Float>
        var forward: SIMD3<Float>
    }

    /// Leveling basis in the device frame from CoreMotion gravity (pointing down). Forward is the back camera's
    /// direction flattened onto the floor plane.
    static func levelBasis(gravity g: SIMD3<Float>) -> LevelBasis {
        let gl = simd_length(g)
        let up = gl > 0.1 ? -g / gl : SIMD3<Float>(0, 1, 0)
        var fwd = SIMD3<Float>(0, 0, -1)
        fwd -= simd_dot(fwd, up) * up
        if simd_length(fwd) < 1e-3 {                                  // camera pointing straight down or up
            let top = SIMD3<Float>(0, 1, 0)
            fwd = top - simd_dot(top, up) * up
        }
        fwd = simd_normalize(fwd)
        return LevelBasis(right: simd_normalize(simd_cross(fwd, up)), up: up, forward: fwd)
    }

    /// Camera-space point → leveled contract point (+x right, +y up, +z forward, meters from the phone).
    static func level(_ p: SIMD3<Float>, _ b: LevelBasis) -> Vec3 {
        let d = cameraToDevice(p)
        return Vec3(x: simd_dot(d, b.right), y: simd_dot(d, b.up), z: simd_dot(d, b.forward))
    }

    /// Inverse of `level`, e.g. to project a leveled obstacle point into Stream B.
    static func unlevel(_ v: Vec3, _ b: LevelBasis) -> SIMD3<Float> {
        deviceToCamera(b.right * v.x + b.up * v.y + b.forward * v.z)
    }

    static func mat3(_ K: simd_float3x3) -> Mat3 {
        Mat3(m: [K[0][0], K[1][0], K[2][0], K[0][1], K[1][1], K[2][1], K[0][2], K[1][2], K[2][2]])
    }

    static func simdMatrix(_ m: Mat3) -> simd_float3x3 {
        simd_float3x3(rows: [SIMD3(m.m[0], m.m[1], m.m[2]), SIMD3(m.m[3], m.m[4], m.m[5]), SIMD3(m.m[6], m.m[7], m.m[8])])
    }
}
