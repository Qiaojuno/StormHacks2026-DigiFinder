import Foundation
import DigiFinderCore

/// Tracks YOLO boxes over time for the no-LiDAR fallback (§5.3): time to contact from box growth,
/// TTC ≈ Δt·h/Δh, for boxes in the middle 50% band. Compiles and runs; accuracy is not required.
/// Safety lane only: the controller serializes calls.
final class SafetyTracker {
    struct Threat: Equatable {
        var label: String
        var box: NormRect
        /// Seconds.
        var ttc: Double
    }

    /// Box center x must fall in the middle half of the image.
    static let band = 0.25...0.75
    static let minConfidence: Float = 0.3
    /// Height history kept per track (seconds).
    static let window: Double = 1
    /// Growth is measured over at least this span (seconds).
    static let minSpan: Double = 0.25
    static let matchIoU = 0.3
    /// Tracks not seen for this long are dropped (seconds).
    static let forget: Double = 0.6

    private struct Track {
        var key: Int
        var label: String
        var box: NormRect
        var samples: [(t: Double, h: Double)]
        var lastSeen: Double
    }

    private var tracks: [Track] = []
    private var nextKey = -1                 // generated keys are negative; YOLO track IDs are used as is
    private var lastInput: [Detection]?

    /// Feeds `detector.latest`. `fresh` is false when YOLO hasn't produced anything new since the last call
    /// (callers count consecutive frames only on fresh input). `threat`: the box closing in fastest.
    func update(_ detections: [Detection], t: Double) -> (threat: Threat?, fresh: Bool) {
        let fresh = detections != lastInput
        if fresh {
            lastInput = detections
            ingest(detections, t: t)
        }
        tracks.removeAll { t - $0.lastSeen > Self.forget || t < $0.lastSeen }
        var best: Threat?
        for tr in tracks {
            guard let last = tr.samples.last,
                  let first = tr.samples.first(where: { last.t - $0.t >= Self.minSpan }),
                  let ttc = Geometry.timeToContact(previousHeight: first.h, currentHeight: last.h, dt: last.t - first.t)
            else { continue }
            if best.map({ ttc < $0.ttc }) ?? true { best = Threat(label: tr.label, box: tr.box, ttc: ttc) }
        }
        return (best, fresh)
    }

    func reset() {
        tracks.removeAll()
        lastInput = nil
    }

    private func ingest(_ detections: [Detection], t: Double) {
        var updated = Set<Int>()
        for d in detections where d.confidence >= Self.minConfidence && Self.band.contains(d.box.midX) && d.box.height > 0 {
            let index: Int?
            if let id = d.trackID {
                index = tracks.firstIndex { $0.key == id }
            } else {
                index = tracks.indices
                    .filter { !updated.contains(tracks[$0].key) && tracks[$0].label == d.label && tracks[$0].box.iou(d.box) >= Self.matchIoU }
                    .max { tracks[$0].box.iou(d.box) < tracks[$1].box.iou(d.box) }
            }
            if let i = index {
                tracks[i].box = d.box
                tracks[i].lastSeen = t
                tracks[i].samples.append((t, d.box.height))
                tracks[i].samples.removeAll { t - $0.t > Self.window }
                updated.insert(tracks[i].key)
            } else {
                let key = d.trackID ?? nextKey
                if d.trackID == nil { nextKey -= 1 }
                tracks.append(Track(key: key, label: d.label, box: d.box, samples: [(t, d.box.height)], lastSeen: t))
                updated.insert(key)
            }
        }
    }
}
