// Frozen contract (§3.3). Change requests go to CONTRACT_CHANGES.md.

public enum Step: Equatable {
    case idle, askingGoal, findingEntrance, findingSignage, walkingAisle, shelfVote
    case pointing, holdUpToCheck, findingDestination, asking, sessionDone, paused

    /// Short on-screen title.
    public var title: String {
        switch self {
        case .idle: return "Ready"
        case .askingGoal: return "What are you looking for?"
        case .findingEntrance: return "Finding the entrance"
        case .findingSignage: return "Finding signs"
        case .walkingAisle: return "Walking the aisle"
        case .shelfVote: return "Checking the aisle"
        case .pointing: return "Pointing at the shelf"
        case .holdUpToCheck: return "Checking the item"
        case .findingDestination: return "Finding the way"
        case .asking: return "Checking online"
        case .sessionDone: return "Shopping done"
        case .paused: return "Paused"
        }
    }
}

public enum SessionEvent: Equatable {
    /// Volume up / volume down / screen Talk button.
    case started, talkPressed, donePressed
    /// The runner routes transcripts; a cancelled recording sends nothing.
    case routed(Request), notUnderstood(noisy: Bool)
    case askAnswer(String?), productLookedUp(Goal?), surroundings(String)
    case outside(Bool), entrancePicked(EntrancePick?), doors([DoorObservation]), stairs(StairsObservation)
    case signs([AisleSign]), aisleVerdict(String?, evidence: [String]), arrivedAtAisle(clock: Int), arrivedAtDestination
    case pointed(PointedProduct?), confirmed(ProductInfo?, isGoal: Bool)
    case danger(cutRecording: Bool), dangerCleared
    /// ~2 Hz.
    case motion(yawDegrees: Double, steps: Int, walking: Bool)
    case positioning(PositioningHint)
    /// Time only arrives through .tick (seconds).
    case system(SystemEvent), tick(Double)
}

public enum SystemEvent: Equatable {
    case backgrounded, foregrounded, batteryLow(Int), thermal(ThermalLevel), audioRouteChanged
    /// online comes from NWPathMonitor.
    case cameraDenied, micDenied, online(Bool)
}

public enum ThermalLevel: Equatable { case nominal, fair, serious, critical }

public enum SpeechPriority: Int, Comparable {
    case narration = 0, guidance, reply, stairs, danger
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum Tone { case beep, done, tick }

public enum Effect: Equatable {
    case say(String, SpeechPriority), stopSpeech, chime(Tone)
    case listen(maxSeconds: Double), finishListening, cancelListening
    case setWork(StreamWork), setTarget(Goal?, candidates: [ProductInfo], destination: Destination?)
    /// ask / pickEntrance capture their own still.
    case ask(String), pickEntrance, lookupProduct(String), describeSurroundings
    case remember(ProductInfo), markDone(Goal)
}
// "Recalculate" is session-internal: clear the last-spoken de-dupe and re-derive the prompt from the next observations.

public struct StreamWork: Equatable {
    public var text: TextLevel
    public var hands: Bool
    public var barcodes: Bool
    public var yoloFPS: Int
    /// §5.3: at the shelf, static things and anything < 0.7 m never alert; no flipped check.
    public var shelfMode: Bool

    public enum TextLevel: Equatable { case off, fast, accurate }

    public init(text: TextLevel = .off, hands: Bool = false, barcodes: Bool = false, yoloFPS: Int = 10, shelfMode: Bool = false) {
        self.text = text; self.hands = hands; self.barcodes = barcodes; self.yoloFPS = yoloFPS; self.shelfMode = shelfMode
    }
}
