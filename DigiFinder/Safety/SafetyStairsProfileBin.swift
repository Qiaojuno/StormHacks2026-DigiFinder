import Foundation

/// One 10 cm bin of the floor profile ahead (§5.4), for the debug overlay.
struct SafetyStairsProfileBin: Equatable {
    /// Start of the bin, meters ahead.
    var z: Float
    /// Median height relative to the learned floor, meters (+ above the floor).
    var height: Float
    /// Points in the bin.
    var count: Int
}
