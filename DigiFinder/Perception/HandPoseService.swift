import Foundation
import Vision
import DigiFinderCore

/// Hand pose on Stream B → pointed spot (§9 Pointing). One instance per queue (the request is reused).
final class HandPoseService {
    let request: VNDetectHumanHandPoseRequest
    /// Extension factor k for tip + (tip − DIP) · k.
    var extend = 1.5
    var minConfidence: Float = 0.3

    init() {
        request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
    }

    /// Pointing finger from the last `perform` that included `request`, or nil.
    func result() -> PerceptionHandPoint? {
        guard let hand = request.results?.first,
              let tip = try? hand.recognizedPoint(.indexTip), tip.confidence > minConfidence,
              let dip = try? hand.recognizedPoint(.indexDIP), dip.confidence > minConfidence else { return nil }
        let t = Geometry.fromVision(NormPoint(x: Double(tip.location.x), y: Double(tip.location.y)))
        let d = Geometry.fromVision(NormPoint(x: Double(dip.location.x), y: Double(dip.location.y)))
        let s = Geometry.pointedSpot(tip: t, dip: d, extend: extend)
        return PerceptionHandPoint(tip: t, dip: d, spot: NormPoint(x: min(max(s.x, 0), 1), y: min(max(s.y, 0), 1)))
    }
}
