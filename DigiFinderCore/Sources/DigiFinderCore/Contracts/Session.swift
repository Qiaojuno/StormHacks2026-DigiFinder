// Frozen contract (§3.3). Change requests go to CONTRACT_CHANGES.md.

/// Task phase (layer 2). Motion state (layer 1, Walking / Standing) is separate: `SessionEvent.motion(walking:)`,
/// read by the phases but never set by them; it alone decides obstacle alerts (Safety reads `MotionService.isWalking`).
/// Ask pending and the background / lost pause are overlays on `SessionState` that keep the phase.
public enum Step: Equatable {
    case idle, entrance, findAisle, inAisle, pick, confirm

    /// Short on-screen title.
    public var title: String {
        switch self {
        case .idle: return "Ready"
        case .entrance: return "Finding the entrance"
        case .findAisle: return "Finding the aisle"
        case .inAisle: return "In the aisle"
        case .pick: return "Pointing at the shelf"
        case .confirm: return "Checking the item"
        }
    }
}

/// Runtime semantics shared by `ShoppingSession`, the runner and the services:
/// - `.tick(t)`: a monotonic clock in seconds (e.g. `ProcessInfo.systemUptime`), sent every ~0.5 s. The first tick
///   only sets the reference; a gap longer than 5 s counts as 5 s. Time only arrives through `.tick`.
/// - `.talkPressed` doesn't say which button was pressed. The runner applies the screen rule first (§5.10):
///   the on-screen record button is ignored while walking.
/// - Recording (§5.10): `.talkPressed` (volume up / record button) only starts one and is ignored while recording;
///   `.donePressed` (volume down / the record button's stop) ends it and the transcript is routed; ignored when not
///   recording. No silence end, no time limit; only danger / stairs / backgrounding cancel a recording.
/// - The runner routes the transcript: a known command / destination / product → `.routed`; words the router can't
///   place → `.unmatched(text, noisy:)`; a question / unknown item → `.routed(.question / .unknownProduct)`. Those
///   three go to Gemini silently when online (`Effect.assist`), else take the offline path.
/// - An empty recording arrives as `.notUnderstood(noisy:)`;
///   a cancelled recording sends nothing.
/// - `.motion(yawDegrees:)`: heading in degrees that grows clockwise (turning right), the sense of
///   `clockPosition(degreesRight:)` (= `-MotionService.yawDegrees`). `steps` is the cumulative pedometer count.
/// - `.stairs`: at most two per staircase from Safety: the first confirmed sighting, then one at ≤ 1.2 m
///   ("Stairs, 1 meter ahead."); no second one when the first sighting is already that close. Stairs lines come from
///   the session as `.say(_, .stairs)`; danger lines only from `SafetyService` → `FeedbackOutput.danger`.
/// - `.danger(cutRecording: true)` → the session says "Say that again." (the user presses volume up to answer).
/// - Perception: `PointedProduct.match >= 0.9` (`MatchingThresholds.pointMatch`) = the goal ("Grab it."); `text == ""` = nothing readable at the
///   fingertip but the target is in view; `.pointed(nil)` = nothing readable and no target. `AisleSign.number == nil`
///   = a shelf or section label. `.aisleVerdict(nil, …)` = unsure. `.confirmed(nil, _)` = unclear (session timers
///   prompt). `.signs([])` / `.doors([])` once when they vanish. `.outside` on changes only (default inside).
///   Perception events come from its own queues, never the main thread.
/// - `.productLookedUp(Goal?)`: a goal with `category` = aisle found; without `category` (with `signWords`) =
///   word search; `nil` = nothing found (also sent on errors).
/// - `.shelfDistance(m)`: LiDAR meters to the shelf in front, sent in pointing mode (`StreamWork.hands`), ≤ 1 per ~2 s.
/// - `.motion(walking:)`: the motion state (Walking / Standing, `MotionStateTracker` hysteresis in the app's
///   `DeviceMotionService`). The same value Safety reads; the session never derives it from anything else.
/// - `.aisleEnd`: Safety saw the shelves stop on both sides (open space left and right) after walking between them.
///   Phase-agnostic; the session uses it only in InAisle after ≥ 5 steps since entering.
/// - `.placeClassified(_:)`: answer to `Effect.classifyPlace` (Gemini, 3 photos). nil = offline, not configured,
///   no camera or failed. Confidence below 0.7 is asked once more; then the store flow.
public enum SessionEvent: Equatable {
    /// Volume up / volume down / screen Talk button.
    case started, talkPressed, donePressed
    /// The runner routes transcripts; a cancelled recording sends nothing.
    case routed(Request), notUnderstood(noisy: Bool)
    /// Words the offline router couldn't place (sent to Gemini when online).
    case unmatched(String, noisy: Bool)
    /// Gemini's answer to `Effect.assist`: the line to speak, and an item to search for (resolved by the runner
    /// through the product search; a word-search goal when nothing resolves). nil / nil = failed or timed out.
    case assistAnswer(say: String?, find: Goal?)
    case productLookedUp(Goal?), surroundings(String)
    case outside(Bool), entrancePicked(EntrancePick?), doors([DoorObservation]), stairs(StairsObservation)
    case signs([AisleSign]), aisleVerdict(String?, evidence: [String]), arrivedAtAisle(clock: Int), arrivedAtDestination
    case pointed(PointedProduct?), confirmed(ProductInfo?, isGoal: Bool)
    case shelfDistance(Float)
    /// The shelves stopped on both sides (LiDAR): the end of an aisle.
    case aisleEnd
    /// Grocery store or anywhere else (Gemini, once at app open); nil = no answer.
    case placeClassified(PlaceAnswer?)
    case danger(cutRecording: Bool), dangerCleared
    /// After a danger alert: the way straight ahead is open for about `meters` (nil = beyond what LiDAR measures).
    /// Sent just before `.dangerCleared`, so the session says "Clear ahead" before the fresh prompt.
    case pathClear(meters: Float?)
    /// A recording ended without a transcript (cancelled: mic busy, interruption…). Silent; clears "recording".
    case recordingCancelled
    /// The goal item itself is in view (label text or its YOLO class): clock position and meters if known.
    case itemSeen(clock: Int, distance: Float?)
    /// Gemini item finder (online, while searching): the item isn't in this photo; a short hint where to look
    /// ("Coffee sign at 10 o'clock."). Spoken as guidance in Entrance / FindAisle / InAisle only, when it differs
    /// from the last hint and at most every ~8 s; dropped while the user talks, an answer is pending or stopped.
    case searchHint(String)
    /// On-device text reader (owner decision; YOLO has no wet-floor-sign class): "wet floor" / "caution" read while
    /// walking, at this clock position. One vibration + "Wet floor sign, N o'clock.", once per ~20 s.
    case wetFloorSign(clock: Int)
    /// Gemini item finder: a lot of people close around the user. "Lot of people around you, be careful." at most
    /// once per ~60 s; waits for an alert like other Gemini lines.
    case crowded
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

/// - `.listen`: wait until `FeedbackOutput.isSpeaking` is false (max ~3 s), then beep, then record until volume down.
///   `VoiceInput.listen` does the wait and the beep itself; the session never emits its own `.chime(.beep)`.
///   Only a talk press starts one (no auto-listen after questions).
/// - `.setTarget` always carries `candidates: []` from the session; the runner fills them from the database.
/// - `.classifyPlace`: once the camera runs and the phone is upright and still (max ~5 s), capture 3 stills ~0.7 s
///   apart and ask Gemini in one request whether this is a grocery store; answer with `.placeClassified` (nil on any
///   failure). Sent after `.started`, and once more when the confidence is low.
public enum Effect: Equatable {
    case say(String, SpeechPriority), stopSpeech, chime(Tone)
    case listen, finishListening, cancelListening
    case setWork(StreamWork), setTarget(Goal?, candidates: [ProductInfo], destination: Destination?)
    /// Anything unusual the user said (question, unknown item, unmatched words): transcript + one still + context
    /// to Gemini; answer with `.assistAnswer`. assist / pickEntrance capture their own still.
    case assist(String, context: AssistContext)
    case pickEntrance, lookupProduct(String), describeSurroundings
    /// Grocery store or not: 3 stills to Gemini (see above).
    case classifyPlace
    case remember(ProductInfo), markDone(Goal)
    /// The stream (owner decision): on = camera, danger, perception and prompts run; off = everything stops, danger
    /// included, and all speech is cut. Volume up / the record button turn it on; volume down / stop turn it off.
    case setStreaming(Bool)
    /// One danger vibration (no speech): the wet floor sign.
    case buzz
}
// "Recalculate" is session-internal: clear the last-spoken de-dupe and re-derive the prompt from the next observations.

public struct StreamWork: Equatable {
    public var text: TextLevel
    public var hands: Bool
    public var barcodes: Bool
    public var yoloFPS: Int
    // No task-phase flag here: obstacle alerts depend on the motion state only (§5.3).

    public enum TextLevel: Equatable { case off, fast, accurate }

    public init(text: TextLevel = .off, hands: Bool = false, barcodes: Bool = false, yoloFPS: Int = 10) {
        self.text = text; self.hands = hands; self.barcodes = barcodes; self.yoloFPS = yoloFPS
    }
}

/// Gemini's grocery check (app open).
public struct PlaceAnswer: Equatable {
    public var grocery: Bool
    /// 0...1; below 0.7 counts as no answer (one retry).
    public var confidence: Double
    /// 2–4 words: "home kitchen", "university library", "supermarket aisle".
    public var scene: String

    public init(grocery: Bool, confidence: Double, scene: String = "") {
        self.grocery = grocery; self.confidence = confidence; self.scene = scene
    }
}

/// Short context sent with `Effect.assist`.
public struct AssistContext: Equatable {
    /// true = grocery store, false = anywhere else (`general`), nil = unknown.
    public var store: Bool?
    /// Spoken name of the current goal or destination.
    public var goal: String?
    public var phase: Step
    /// What the transcript was: a question, an unknown item, or unmatched words.
    public var kind: AssistKind

    public init(store: Bool? = nil, goal: String? = nil, phase: Step = .idle, kind: AssistKind = .question) {
        self.store = store; self.goal = goal; self.phase = phase; self.kind = kind
    }
}

public enum AssistKind: Equatable { case question, unknownItem, unmatched }
