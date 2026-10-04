import Foundation
import DigiFinderCore

/// Index finger from hand pose, in contract space. `spot` = tip + (tip − DIP) · k (§5.2, §9 Pointing).
struct PerceptionHandPoint: Equatable {
    var tip: NormPoint
    var dip: NormPoint
    var spot: NormPoint
}
