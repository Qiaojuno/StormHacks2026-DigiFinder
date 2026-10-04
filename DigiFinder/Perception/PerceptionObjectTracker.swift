import Foundation
import DigiFinderCore

/// Frame-to-frame IoU tracker: same label + overlapping box keeps its track ID, so each object votes once (§5.7)
/// and the safety lane can follow a box over time.
struct PerceptionObjectTracker {
    var minIoU = 0.3
    /// Tracks unseen for longer than this are dropped (seconds).
    var maxAge = 1.0

    private struct Track { var id: Int; var label: String; var box: NormRect; var lastSeen: Double }
    private var tracks: [Track] = []
    private var nextID = 1

    mutating func update(_ detections: [Detection], time t: Double) -> [Detection] {
        tracks.removeAll { t - $0.lastSeen > maxAge || t < $0.lastSeen - 5 }
        var used = Set<Int>()
        var out: [Detection] = []
        for d in detections.sorted(by: { $0.confidence > $1.confidence }) {
            var best: (index: Int, iou: Double)?
            for (i, tr) in tracks.enumerated() where !used.contains(i) && tr.label == d.label {
                let iou = tr.box.iou(d.box)
                if iou >= minIoU, iou > (best?.iou ?? 0) { best = (i, iou) }
            }
            var tracked = d
            if let b = best {
                used.insert(b.index)
                tracks[b.index].box = d.box
                tracks[b.index].lastSeen = t
                tracked.trackID = tracks[b.index].id
            } else {
                tracks.append(Track(id: nextID, label: d.label, box: d.box, lastSeen: t))
                used.insert(tracks.count - 1)
                tracked.trackID = nextID
                nextID += 1
            }
            out.append(tracked)
        }
        return out
    }
}
