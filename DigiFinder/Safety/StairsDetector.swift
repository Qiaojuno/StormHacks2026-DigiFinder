import Foundation
import DigiFinderCore

/// Floor profile → stairs notice (§5.4). LiDAR only, spoken only (never vibrates). Learns the floor height,
/// runs Core's `detectStairs`, confirms with YOLO "Stairs" (1 frame) or 3 frames alone, announces once per
/// staircase, then once more at ~1 m (LiDAR while visible, else the pedometer at ~0.7 m per step).
/// Safety lane only: the controller serializes calls.
final class StairsDetector {
    /// Lanyard swing makes the leveled profile unreliable: skip those frames (keeps the confirmation streak).
    static let maxRotation = 1.5
    static let yoloLabel = "stairs"
    static let yoloMinConfidence: Float = 0.3
    /// "Nearby": the YOLO box center sits in the middle of the image, where the profile looks.
    static let yoloBand = 0.2...0.8
    /// Debug profile refresh interval (seconds).
    static let profileInterval = 0.5

    private var floor = GeometryFloorTracker()
    /// Farther floor patch, used only until Core's 0.6–2 m patch is seen (often below the field of view on a
    /// chest lanyard with the phone upright).
    private var farFloor: Float?
    private var tracker = GeometryStairsTracker()
    private var lastSteps: Int?
    private var lastProfileTime = -Double.infinity
    /// Last time YOLO saw "Stairs" near the middle of the image.
    private var lastYoloStairs = -Double.infinity
    /// A down-staircase counts only if YOLO saw stairs within this many seconds.
    static let downNeedsYoloWithin = 1.0

    private(set) var floorY: Float?
    /// This frame's reading (before confirmation).
    private(set) var latest: StairsObservation?
    private(set) var profile: [SafetyStairsProfileBin] = []

    /// Returns an observation to announce via `.stairs`: the first sighting of a staircase, then the ~1 m update
    /// (distance ≤ 1.2 m). At most two per staircase.
    func process(_ pts: [Vec3], t: Double, steps: Int, rotationRate: Double, detections: [Detection]) -> StairsObservation? {
        let walked = lastSteps.map { max(steps - $0, 0) } ?? 0
        lastSteps = steps
        guard rotationRate.isFinite, abs(rotationRate) < Self.maxRotation else {
            return announce(tracker.walked(steps: walked, t: t))
        }
        floorY = learnFloor(pts)
        guard let fy = floorY else {
            latest = nil
            return announce(tracker.walked(steps: walked, t: t))
        }
        var obs = detectStairs(pts, floorY: fy)
        // Stairs going down are hard to see from chest height (the profile can't tell a drop from a floor it simply
        // doesn't see), so they're only announced when YOLO sees "Stairs" too.
        let yolo = Self.yoloSeesStairs(detections)
        if yolo { lastYoloStairs = t }
        if let o = obs, !o.up, t - lastYoloStairs > Self.downNeedsYoloWithin { obs = nil }
        latest = obs
        if t - lastProfileTime >= Self.profileInterval || t < lastProfileTime {
            lastProfileTime = t
            profile = Self.profile(pts, floorY: fy)
        }
        if let obs {
            return announce(tracker.update(obs, yoloStairs: yolo, t: t))
        }
        // The floor near the feet isn't visible on a chest lanyard: count down from the last LiDAR distance.
        _ = tracker.update(nil, yoloStairs: false, t: t)
        return announce(tracker.walked(steps: walked, t: t))
    }

    func reset() {
        tracker.reset()
        latest = nil
    }

    private func announce(_ a: GeometryStairsAnnouncement?) -> StairsObservation? {
        switch a {
        case let .first(o)?: return o
        case let .near(o)?: return o
        case nil: return nil
        }
    }

    private func learnFloor(_ pts: [Vec3]) -> Float? {
        if let f = floor.update(pts) { return f }
        guard let f = Self.farFloorY(pts) else { return farFloor }
        farFloor = farFloor.map { $0 + (f - $0) * floor.smoothing } ?? f
        return farFloor
    }

    /// Same flatness test as Core's `estimateFloorY`, on a patch 1.8–4 m ahead.
    private static func farFloorY(_ pts: [Vec3]) -> Float? {
        let ys = pts.filter { abs($0.x) < 0.6 && $0.z > 1.8 && $0.z < 4.0 && $0.y < -0.8 && $0.y.isFinite }.map(\.y).sorted()
        guard ys.count >= 30, ys[ys.count * 2 / 5] - ys[ys.count / 10] <= 0.05 else { return nil }
        return ys[ys.count / 4]
    }

    private static func yoloSeesStairs(_ detections: [Detection]) -> Bool {
        detections.contains {
            $0.label.lowercased() == yoloLabel && $0.confidence >= yoloMinConfidence && yoloBand.contains($0.box.midX)
        }
    }

    /// The profile `detectStairs` reads (|x| < 0.4, below the waist band, z 0.3–5 m, 10 cm bins, ≥ 8 points).
    static func profile(_ pts: [Vec3], floorY: Float) -> [SafetyStairsProfileBin] {
        var bins = [Int: [Float]]()
        for p in pts where abs(p.x) < 0.4 && p.y < -0.4 && p.z > 0.3 && p.z < 5 && p.y.isFinite {
            bins[Int(p.z / 0.1), default: []].append(p.y)
        }
        return bins.keys.sorted().compactMap { k -> SafetyStairsProfileBin? in
            guard let ys = bins[k], ys.count >= 8 else { return nil }
            let s = ys.sorted()
            return SafetyStairsProfileBin(z: Float(k) * 0.1, height: s[s.count / 2] - floorY, count: s.count)
        }
    }
}
