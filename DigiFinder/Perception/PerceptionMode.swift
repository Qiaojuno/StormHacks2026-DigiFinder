import Foundation
import DigiFinderCore

/// What Stream B analysis does now, derived from `StreamWork` (§3.6).
enum PerceptionMode: String, Equatable {
    /// YOLO only (+ doors / outside / positioning from what's already known).
    case idle
    /// Text `.fast`: signs, section signs, destinations, aisle vote, arrival, door text.
    case signs
    /// Hands on: hand pose + text near the fingertip + memory hint.
    case pointing
    /// Text `.accurate`: full-res stills of the held item + passive barcode, ~2/s.
    case holdUp

    init(_ w: StreamWork) {
        if w.text == .accurate { self = .holdUp } else if w.hands { self = .pointing } else if w.text == .fast { self = .signs } else { self = .idle }
    }
}
