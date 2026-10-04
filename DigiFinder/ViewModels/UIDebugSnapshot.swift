import CoreGraphics
import Foundation
import DigiFinderCore

/// One recognized text region on the 0.5× frame (upright portrait, normalized, origin top-left).
struct UIDebugTextBox: Equatable {
    var text: String
    var box: NormRect
}

/// Safety and Perception values for the judges' debug overlay (§6). Every field is optional;
/// several sources are merged (first non-empty value wins).
struct UIDebugSnapshot {
    /// Upright 0.5× frame the boxes refer to (optional; without it the boxes are drawn on a blank frame).
    var preview: CGImage?
    var detections: [Detection] = []
    var textBoxes: [UIDebugTextBox] = []
    var handPoint: NormPoint?
    /// Danger corridor: nearest distance (m), point count, closing speed (m/s), time to contact (s).
    var corridorNearest: Float?
    var corridorPoints: Int?
    var closingSpeed: Float?
    var timeToContact: Double?
    var steer: Steer?
    var leftLaneClear: Bool?
    var rightLaneClear: Bool?
    var stairs: StairsObservation?
    /// Pending speech lines, highest priority first.
    var speechQueue: [String] = []
    /// Free-form lines (costs, rates, timers).
    var notes: [String] = []

    func merged(with o: UIDebugSnapshot) -> UIDebugSnapshot {
        var m = self
        m.preview = preview ?? o.preview
        if m.detections.isEmpty { m.detections = o.detections }
        if m.textBoxes.isEmpty { m.textBoxes = o.textBoxes }
        m.handPoint = handPoint ?? o.handPoint
        m.corridorNearest = corridorNearest ?? o.corridorNearest
        m.corridorPoints = corridorPoints ?? o.corridorPoints
        m.closingSpeed = closingSpeed ?? o.closingSpeed
        m.timeToContact = timeToContact ?? o.timeToContact
        m.steer = steer ?? o.steer
        m.leftLaneClear = leftLaneClear ?? o.leftLaneClear
        m.rightLaneClear = rightLaneClear ?? o.rightLaneClear
        m.stairs = stairs ?? o.stairs
        if m.speechQueue.isEmpty { m.speechQueue = o.speechQueue }
        m.notes += o.notes
        return m
    }

    /// Safety lines for the overlay.
    var safetyLines: [String] {
        func m(_ v: Float?) -> String { v.map { String(format: "%.2f m", $0) } ?? "–" }
        var out = ["corridor nearest \(m(corridorNearest)) · points \(corridorPoints.map(String.init) ?? "–")"]
        let closing = closingSpeed.map { String(format: "%.2f m/s", $0) } ?? "–"
        let ttc = timeToContact.map { String(format: "%.1f s", $0) } ?? "–"
        out.append("closing \(closing) · TTC \(ttc)")
        func lane(_ b: Bool?) -> String { b.map { $0 ? "clear" : "blocked" } ?? "–" }
        out.append("steer \(steer.map { "\($0)" } ?? "–") · left \(lane(leftLaneClear)) · right \(lane(rightLaneClear))")
        if let s = stairs {
            out.append("stairs \(s.up ? "up" : "down") \(String(format: "%.1f m", s.distance))"
                       + (s.steps.map { " · \($0) steps" } ?? "") + (s.more ? " · more" : ""))
        } else {
            out.append("stairs –")
        }
        return out
    }

    /// Perception lines for the overlay.
    var perceptionLines: [String] {
        var out: [String] = []
        let yolo = detections.prefix(6).map { "\($0.label) \(Int($0.confidence * 100))%" }.joined(separator: ", ")
        out.append("YOLO \(detections.count)" + (yolo.isEmpty ? "" : ": \(yolo)"))
        let text = textBoxes.prefix(6).map(\.text).joined(separator: " | ")
        out.append("OCR \(textBoxes.count)" + (text.isEmpty ? "" : ": \(text)"))
        out.append("hand " + (handPoint.map { String(format: "%.2f, %.2f", $0.x, $0.y) } ?? "–"))
        return out
    }
}

/// Wave 3: the runner, `SafetyService` or `PerceptionService` adopt this to feed the debug overlay.
/// Read about twice a second on the main thread; must be safe to call from any thread and cheap.
protocol UIDebugSnapshotSource: AnyObject {
    var debugSnapshot: UIDebugSnapshot { get }
}
