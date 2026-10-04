import Foundation
import DigiFinderCore

/// What perception is looking for (from `setTarget`). `generation` changes on every `setTarget`.
struct PerceptionTarget {
    var goal: Goal?
    var candidates: [ProductInfo] = []
    var destination: Destination?
    var generation = 0

    /// Unknown item (no aisle): signs and labels are matched against the spoken words + `signWords` (§5.2).
    func isWordSearch(_ aisles: [String: AisleInfo]) -> Bool {
        guard let g = goal else { return false }
        guard let c = g.category else { return true }
        return aisles[c] == nil
    }
}
