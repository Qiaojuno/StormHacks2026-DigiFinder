// Frozen contract (§3.3). Change requests go to CONTRACT_CHANGES.md.

/// YOLO detection, shared by Safety and Perception.
public struct Detection: Equatable {
    public var label: String
    public var confidence: Float
    public var box: NormRect
    public var trackID: Int?

    public init(label: String, confidence: Float, box: NormRect, trackID: Int? = nil) {
        self.label = label; self.confidence = confidence; self.box = box; self.trackID = trackID
    }
}

public struct AisleSign: Equatable {
    public var number: String?
    public var words: [String]
    public var clock: Int
    /// Meters to the sign (LiDAR, else estimated from the letter size); nil when unknown.
    public var distance: Float?

    public init(number: String? = nil, words: [String] = [], clock: Int, distance: Float? = nil) {
        self.number = number; self.words = words; self.clock = clock; self.distance = distance
    }
}


public struct PointedProduct: Equatable {
    public var text: String
    public var match: Double
    public var directionToTarget: String?
    /// "There's also a 680 gram one."
    public var alternative: String?

    public init(text: String, match: Double, directionToTarget: String? = nil, alternative: String? = nil) {
        self.text = text; self.match = match; self.directionToTarget = directionToTarget; self.alternative = alternative
    }
}

public struct StairsObservation: Equatable {
    public var up: Bool
    public var distance: Float
    public var steps: Int?
    public var more: Bool

    public init(up: Bool, distance: Float, steps: Int? = nil, more: Bool = false) {
        self.up = up; self.distance = distance; self.steps = steps; self.more = more
    }
}

public struct DoorObservation: Equatable {
    public var clock: Int
    public var distance: Float?
    public var label: DoorLabel

    public init(clock: Int, distance: Float? = nil, label: DoorLabel = .unknown) {
        self.clock = clock; self.distance = distance; self.label = label
    }
}

public enum DoorLabel: Equatable { case entrance, exit, unknown }

/// Danger steering (§5.3): the open direction as a clock position (11 / 1 = slightly left / right, never 12),
/// stop when nothing visible is open, unknown when the sides can't be seen.
public enum Steer: Equatable { case clock(Int), stop, unknown }

public enum DoorKind: String, Codable, Equatable { case automatic, revolving, push, pull, unknown }

/// From Gemini; x = horizontal center in the upright still, 0...1.
/// `clock` / `cartCorralClock` are filled by the runner from Stream B intrinsics before `.entrancePicked`
/// (nil = the session estimates them from a nominal field of view).
public struct EntrancePick: Codable, Equatable {
    public var x: Double
    public var kind: DoorKind
    public var cartCorralX: Double?
    public var note: String?
    public var clock: Int?
    public var cartCorralClock: Int?

    public init(x: Double, kind: DoorKind = .unknown, cartCorralX: Double? = nil, note: String? = nil,
                clock: Int? = nil, cartCorralClock: Int? = nil) {
        self.x = x; self.kind = kind; self.cartCorralX = cartCorralX; self.note = note
        self.clock = clock; self.cartCorralClock = cartCorralClock
    }
}

public enum PositioningHint: Equatable {
    case tiltUp, tiltDown, stepBack, moveCloser, slowDown, pointInFront, tooDark, phoneFlipped
}
