import Foundation
import DigiFinderCore

/// What the safety lane saw on its latest frame (debug overlay: corridor, steer lanes, TTC, stairs profile).
struct SafetyDebugSnapshot: Equatable {
    enum Source: String, Equatable {
        /// No depth frames and no fallback reading yet.
        case idle
        /// LiDAR depth frames.
        case lidar
        /// No depth: YOLO box growth (§5.3 fallback).
        case fallback
    }

    var source: Source = .idle
    /// Time of the latest reading (seconds, host clock for LiDAR frames, uptime for the fallback).
    var time: Double = 0

    // Danger corridor (§5.3).
    /// 5th-percentile distance of the corridor points (LiDAR), or a box-size estimate (fallback), meters.
    var corridorDistance: Float?
    var corridorPoints = 0
    /// Lateral offset of the nearest obstacle (meters, + right).
    var obstacleX: Float?
    /// m/s, positive = getting closer.
    var closingSpeed: Float?
    /// Seconds.
    var timeToContact: Float?
    var steer: Steer = .unknown
    /// The 2-frame emergency rule holds this frame.
    var emergency = false
    /// YOLO label of the nearest obstacle ("Obstacle" without a matching box).
    var label: String?
    /// The YOLO box that gave the label (Stream B, upright portrait, normalized).
    var labelBox: NormRect?
    /// The nearest obstacle's points projected into Stream B (at most 40).
    var obstaclePoints: [NormPoint] = []

    // Alerts.
    /// An alert was raised and the path hasn't cleared yet.
    var alertActive = false
    /// "Person ahead, steer left".
    var lastAlert: String?
    /// Frame capture → `feedback.danger` call, milliseconds (target < 50).
    var lastAlertLatencyMs: Double?
    /// Safety work per depth frame, milliseconds.
    var processingMs: Double?
    var shelfMode = false
    var rotationRate: Double = 0

    // Stairs (§5.4).
    /// Learned floor height (leveled y, meters, negative).
    var floorY: Float?
    /// This frame's stairs reading (before confirmation).
    var stairs: StairsObservation?
    /// The last announced observation.
    var lastStairsAnnounced: StairsObservation?
    /// Floor profile ahead (~2 Hz).
    var stairsProfile: [SafetyStairsProfileBin] = []

    var lines: [String] {
        func m(_ v: Float?) -> String { v.map { String(format: "%.2f m", $0) } ?? "–" }
        var out: [String] = []
        var corridor = "danger \(source.rawValue) · corridor \(m(corridorDistance))"
        if source == .lidar { corridor += " (\(corridorPoints) pts)" }
        if let x = obstacleX { corridor += String(format: " · x %+.2f", x) }
        out.append(corridor)
        let closing = closingSpeed.map { String(format: "%.2f m/s", $0) } ?? "–"
        let ttc = timeToContact.map { String(format: "%.1f s", $0) } ?? "–"
        out.append("closing \(closing) · TTC \(ttc) · steer \(steer)" + (emergency ? " · EMERGENCY" : ""))
        var alert = "label \(label ?? "–")" + (alertActive ? " · alert active" : "")
        if let lastAlert { alert += " · last \"\(lastAlert)\"" }
        if let ms = lastAlertLatencyMs { alert += String(format: " %.0f ms", ms) }
        out.append(alert)
        var state = "shelf mode \(shelfMode ? "on" : "off") · rot \(String(format: "%.1f", rotationRate)) rad/s"
        if let ms = processingMs { state += String(format: " · %.1f ms/frame", ms) }
        out.append(state)
        var stairsLine = "floor \(m(floorY)) · stairs "
        if let s = stairs {
            stairsLine += "\(s.up ? "up" : "down") \(s.steps.map(String.init) ?? "?")\(s.more ? "+" : "") at \(m(s.distance))"
        } else {
            stairsLine += "none"
        }
        stairsLine += " · profile \(stairsProfile.count) bins"
        out.append(stairsLine)
        return out
    }
}
