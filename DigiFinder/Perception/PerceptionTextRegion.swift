import Foundation
import DigiFinderCore

/// One recognized text line in contract space (upright portrait, normalized, origin top-left).
struct PerceptionTextRegion: Equatable {
    var text: String
    var confidence: Float
    var box: NormRect
}
