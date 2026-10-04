import Foundation
import DigiFinderCore

/// No LiDAR (§2 Fallback): distances from box size and growth; accuracy is not required.
/// Fallback devices deliver no depth frames; if one ever arrives it is read like LiDAR depth.
struct EstimatedDepthProvider: DepthProvider {
    /// Typical real heights (meters) of OIV7 labels, for the box-size estimate.
    static let typicalHeights: [String: Float] = [
        "Person": 1.7, "Man": 1.75, "Woman": 1.65, "Boy": 1.3, "Girl": 1.3, "Door": 2.05, "Shelf": 1.8,
        "Cart": 1.05, "Chair": 0.9, "Table": 0.75, "Refrigerator": 1.8, "Stairs": 1.0, "Box": 0.4,
    ]

    /// Vertical field of view of the upright Stream B image (ultra-wide ≈ 100°, wide ≈ 70°).
    let verticalFOVDegrees: Float
    private let measured: LiDARDepthProvider

    init(calibration: CaptureCalibration? = nil, verticalFOVDegrees: Float = 100) {
        self.verticalFOVDegrees = verticalFOVDegrees
        measured = LiDARDepthProvider(calibration: calibration)
    }

    func points(_ f: DepthFrame, gravity: SIMD3<Float>) -> [Vec3] { measured.points(f, gravity: gravity) }

    func distance(at p: NormPoint, _ f: DepthFrame) -> Float? { measured.distance(at: p, f) }

    /// Pinhole estimate from a detection's box height: d ≈ H / (2 · h · tan(vFOV / 2)). nil for unknown labels.
    func distance(for detection: Detection) -> Float? {
        guard let height = Self.typicalHeights[detection.label] else { return nil }
        let h = Float(detection.box.height)
        guard h > 0.01 else { return nil }
        return height / (2 * h * tan(verticalFOVDegrees * .pi / 360))
    }

    /// Time to contact (seconds) from box growth between two sightings: Δt / (h₁ / h₀ − 1). nil if not approaching.
    static func timeToContact(previousHeight h0: Double, currentHeight h1: Double, interval dt: Double) -> Double? {
        guard h0 > 0, h1 > h0, dt > 0 else { return nil }
        return dt / (h1 / h0 - 1)
    }
}
