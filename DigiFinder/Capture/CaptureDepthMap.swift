import AVFoundation
import CoreVideo
import Foundation

/// Read-only view of a Float32 depth map (meters, landscape sensor grid) while its base address is locked.
/// AVFoundation gives no per-pixel confidence for LiDAR depth, so "low confidence" means: invalid or out of
/// the LiDAR range, or a flying pixel (mixed foreground/background at an edge) that disagrees with its neighbors.
struct CaptureDepthMap {
    static let minDepth: Float = 0.15
    static let maxDepth: Float = 6.0
    /// Relative jump to a neighbor that counts as disagreement.
    static let flyingPixelJump: Float = 0.15

    let width: Int
    let height: Int
    private let base: UnsafeRawPointer
    private let rowBytes: Int

    /// The same depth as `kCVPixelFormatType_DepthFloat32`, or nil if it can't be converted.
    static func float32(_ d: AVDepthData) -> AVDepthData? {
        if d.depthDataType == kCVPixelFormatType_DepthFloat32 { return d }
        guard d.availableDepthDataTypes.contains(kCVPixelFormatType_DepthFloat32) else { return nil }
        return d.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
    }

    /// Runs `body` with the map locked. `depth` must already be Float32 (see `float32(_:)`).
    static func read<T>(_ depth: AVDepthData, _ body: (CaptureDepthMap) -> T) -> T? {
        let pb = depth.depthDataMap
        guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferLockBaseAddress(pb, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let map = CaptureDepthMap(width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb),
                                  base: UnsafeRawPointer(base), rowBytes: CVPixelBufferGetBytesPerRow(pb))
        guard map.width > 0, map.height > 0 else { return nil }
        return body(map)
    }

    @inline(__always) func raw(_ u: Int, _ v: Int) -> Float {
        base.load(fromByteOffset: v * rowBytes + u * MemoryLayout<Float32>.stride, as: Float32.self)
    }

    @inline(__always) func contains(_ u: Int, _ v: Int) -> Bool { u >= 0 && v >= 0 && u < width && v < height }

    /// Depth in meters, nil if outside the map, not finite, or outside the usable range.
    @inline(__always) func depth(_ u: Int, _ v: Int) -> Float? {
        guard contains(u, v) else { return nil }
        let z = raw(u, v)
        return z.isFinite && z >= Self.minDepth && z <= Self.maxDepth ? z : nil
    }

    /// Depth only if the pixel agrees with at least two of its four neighbors `step` pixels away
    /// (neighbors outside the map count as agreeing; holes count as disagreeing).
    func confidentDepth(_ u: Int, _ v: Int, step: Int) -> Float? {
        guard let z = depth(u, v) else { return nil }
        let limit = Self.flyingPixelJump * z
        var disagree = 0
        @inline(__always) func check(_ x: Int, _ y: Int) {
            guard contains(x, y) else { return }
            let n = raw(x, y)
            if !n.isFinite || n < Self.minDepth || n > Self.maxDepth || abs(n - z) > limit { disagree += 1 }
        }
        check(u + step, v); check(u - step, v); check(u, v + step); check(u, v - step)
        return disagree >= 3 ? nil : z
    }

    /// Median of the valid depths in a (2r+1)² window, nil if fewer than `minCount` are valid.
    func medianDepth(_ u: Int, _ v: Int, radius r: Int, minCount: Int) -> Float? {
        var values: [Float] = []
        values.reserveCapacity((2 * r + 1) * (2 * r + 1))
        for y in (v - r)...(v + r) {
            for x in (u - r)...(u + r) { if let z = depth(x, y) { values.append(z) } }
        }
        guard values.count >= max(1, minCount) else { return nil }
        values.sort()
        return values[values.count / 2]
    }
}
