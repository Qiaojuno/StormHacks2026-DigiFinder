// Session state (§3.3). Owned by Flow/ and free to grow; the runner relies on `step`, `lastLine` and `isWalking`.
// Times are session seconds (`now`), advanced only by `.tick`.
//
// Two independent layers: the motion state (`isWalking`, only from `.motion`) and the task phase (`step`).
// Overlays keep the phase: `askPending` (Ask answer awaited) and `pause` (screen lock / lost track).

/// Why guidance is paused (overlay, the phase is kept).
public enum SessionPauseReason: Equatable { case lost, background }

/// Grocery store (signs, aisles) or anywhere else (`general`: home, office, campus, library, outdoors…): look around
/// for the item itself.
public enum SessionPlace: Equatable { case store, general }

/// Why the phase waits for Standing before Pick.
enum SessionPickReason: Equatable {
    /// The item was seen within reach while walking ("Stop. Coffee at 12 o'clock.").
    case item
    /// The shelf sign or the vote found the item's section ("Stop here. Turn to the shelf…").
    case shelf
}

public struct SessionState: Equatable {
    // Runner-facing
    /// Task phase (layer 2).
    public var step: Step = .idle
    /// Lines spoken by the latest event, joined (shown on screen).
    public var lastLine = ""
    /// Motion state (layer 1), only from `.motion(walking:)`.
    public var isWalking = false

    // Overlays (the phase is kept)
    /// An Ask answer is pending: speech prompts pause; motion and danger keep running.
    public var askPending = false
    public var pause: SessionPauseReason?
    /// "Shopping done" was said (the next goal starts a fresh count).
    public var finished = false

    // Goals
    public var goal: Goal?
    public var queue: [Goal] = []
    /// "Switch to milk, or add it?" awaiting an answer.
    public var pendingChoice: Goal?
    public var destination: Destination?
    public var foundCount = 0
    /// "What's next?" awaiting an answer.
    public var askingNext = false

    // Settings and environment
    public var online = false
    public var verbosity: Verbosity = .normal
    public var thermal: ThermalLevel = .nominal
    public var outside = false
    /// Setup: distances in steps instead of meters.
    public var distanceInSteps = false
    /// Gemini's answer (or the entrance: store); nil = not known (store flow).
    public var place: SessionPlace?
    /// Manual setting ("it's nearby" / Settings nearby mode → general, "store mode" → store): wins over `place`.
    public var placeOverride: SessionPlace?
    /// Last grocery-check answer (debug overlay): confidence, scene, how many times asked.
    public var placeConfidence: Double?
    public var placeScene = ""
    public var placeTries = 0
    /// The opening question waits for the place line ("You're in a grocery store.").
    var openingPending = false
    /// Last time the goal item was seen in view, and where (clock, meters).
    public var itemSeenAt: Double?
    public var itemClock: Int?
    public var itemDistance: Float?
    /// Gemini is configured (Secrets.plist); without it Ask and the entrance pick stay offline.
    public var onlineHelp = true

    // Talking
    public var isListening = false
    /// The stream is running (on at app open). Off after volume down / stop: nothing is checked, asked or spoken.
    public var streaming = true
    /// The place line, waiting for the request recorded with the first volume up to be handled.
    public var pendingPlaceLine: String?
    /// "Loading." was said for the current goal while the grocery check ran.
    public var loadingGoal = false
    /// OWNER DECISION: on-device item search (signs, aisle vote, pointing, label check) is commented out in the app;
    /// items are found only by Gemini. Off: every search is the Gemini-guided one (no sign prompts, vote or aisle end)
    /// and it ends when the item is within reach ahead. On restores the store flow (kept for when it comes back).
    public var onDeviceItemSearch = false
    /// When the current recording started (stuck-recording safety net).
    public var listenStartedAt: Double?
    /// Last flow prompt (for "repeat" and audio route changes).
    public var lastPrompt = ""

    // Clock and motion
    public var now: Double = 0
    public var stepStartedAt: Double = 0
    public var yaw: Double = 0
    public var steps = 0

    // Internal memory
    var lastTick: Double?
    var hasMotion = false
    /// Aisle (category key) the user stands in, for "Tea is in this aisle too."
    var currentAisle: String?
    /// Bumped whenever the target changes; held observations for an older target are dropped.
    var goalEpoch = 0
    var held: [SessionHeldEvent] = []
    /// Gemini handling something unusual the user said (`askPending` overlay).
    var assist: SessionAssist?
    /// The grocery check (`Effect.classifyPlace`) in progress.
    var placeCheck: SessionPlaceCheck?
    var placeDecidedAt: Double?
    /// Waiting for Standing before Pick, and the phase Pick returns to when the user walks on.
    var pendingPick: SessionPickReason?
    var pickReturn: Step = .inAisle
    /// After "Stop. Aisle 6 is at 9 o'clock.": the aisle's absolute bearing; walking toward it enters InAisle.
    var aisleBearing: Double?
    /// Shelf vote, a sub-state of FindAisle.
    var vote: SessionVote?
    var lookup: SessionLookup?
    var surroundingsSince: Double?
    var choiceAskedAt: Double?
    var askingNextAt: Double?
    var dangerSince: Double?
    /// Gemini answers and hints that arrived during an alert, played once it clears (owner decision). A new alert
    /// keeps them waiting. Newest hint only.
    var afterDanger: [SessionEvent] = []
    var wetFloorSignAt: Double?
    var crowdWarnedAt: Double?
    var work: StreamWork?
    var progress = SessionGoalProgress()
    var marks = SessionStepMarks()
    var entrance = SessionEntranceState()
    var stairs: SessionStairsMemory?
    var speech = SessionSpeechMemory()

    public init() {}
}

/// An event that arrived while the user was talking or waiting for an answer; replayed afterwards.
struct SessionHeldEvent: Equatable {
    var event: SessionEvent
    var epoch: Int
    /// Dropped on replay if the target changed meanwhile.
    var goalBound: Bool
}

/// What was sent to Gemini, for the offline fallback.
struct SessionAssist: Equatable {
    var text: String
    var kind: AssistKind
    var change: GoalChange
    var noisy: Bool
    var startedAt: Double
}

/// Unknown item being looked up online (§5.2).
struct SessionLookup: Equatable {
    var words: String
    var change: GoalChange
    var startedAt: Double
}

/// The target's sign, remembered with its absolute bearing ("Coffee was aisle 6, at 6 o'clock behind you.").
struct SessionSignMemory: Equatable {
    var number: String?
    var words: [String]
    var bearing: Double
}

/// Memory scoped to the current goal or destination.
struct SessionGoalProgress: Equatable {
    /// Last sign, label or hand related to the goal (lost timers, §5.12).
    var evidenceAt: Double = 0
    var lostTrackAt: Double?
    var signMemory: SessionSignMemory?
    var lastTargetSignAt: Double?
    /// The out-of-view shelf vote runs once per goal.
    var voteDone = false
    /// First time in the right aisle (not-found timer, §5.12).
    var aisleEnteredAt: Double?
    var lastMatchAt: Double?
    var entryYaw: Double?
    var entrySteps: Int?
    var turnBackSteps: Int?
    var lastDestinationSignAt: Double?
    var aisleEndSaid = false
    /// Last Gemini search hint spoken for this goal, and when (de-dupe + rate limit).
    var lastSearchHint: String?
    var lastSearchHintAt: Double?

    init(evidenceAt: Double = 0) { self.evidenceAt = evidenceAt }
}

/// Flags and anchors reset on every step change.
struct SessionStepMarks: Equatable {
    var scanAnchor: Double = 0
    var scanPrompted = false
    var lastAnySignAt: Double?
    var lastDirectionAt: Double?
    var lastOtherSignsAt: Double?
    var unsureSaid = false
    var unclearStage = 0
    var unclearAnchor: Double = 0
    var lastPointCueAt: Double?
    var destinationSeen = false
    var destinationNotFoundSaid = false
    var noisyRetry = false
    var shelfDistanceSaid = false
    /// "Stop and look around. I need context." was said; waiting for the user to stand still.
    var contextAskedAt: Double?
    var contextStillSince: Double?

    init(anchor: Double = 0) { scanAnchor = anchor; unclearAnchor = anchor }
}

/// The grocery check: asked at app open, asked once more when the confidence is low.
struct SessionPlaceCheck: Equatable {
    var askedAt: Double
    var tries: Int
}

/// Shelf vote (§5.7) inside FindAisle: "Take two steps back." → Standing → face 9 o'clock → face 3 o'clock.
struct SessionVote: Equatable {
    enum Stage: Equatable { case stepBack, left, right }
    var stage: Stage = .stepBack
    var since: Double
    var baseYaw: Double
    var stepsAtPrompt: Int
    /// Walked (or stepped) since "Take two steps back."
    var moved = false
    /// Facing the side being checked since.
    var facingSince: Double?
}

/// Finding the entrance (§5.2, P1): Gemini pick online, door signs offline.
struct SessionEntranceState: Equatable {
    var online = false
    var tries = 0
    var lastPickAt: Double?
    var awaitingPick = false
    var waitingForTurn = false
    var yawAtFail: Double?
    /// Absolute bearing of the picked door, updated while tracking.
    var bearing: Double?
    var lastTrackedAt: Double?
    var pickAnnounced = false
    var lastDoorAt: Double?
    var sightingSaid = false
    var aheadSaid = false
    var noSignSaid = false
    var noDoorSaid = false

    init(online: Bool = false) { self.online = online }
}

/// One staircase, announced once (§5.4).
struct SessionStairsMemory: Equatable {
    var up: Bool
    var distance: Float
    var stepsAtObservation: Int
    var lastSeenAt: Double
    var nearSaid: Bool
}

struct SessionSpeechMemory: Equatable {
    /// De-dupe for repeated guidance; cleared by recalculate.
    var lastGuidance: String?
    var lastGuidanceAt: Double = 0
    var hintTimes: [String: Double] = [:]
    /// One-time notices already spoken (battery levels, denied permissions).
    var notices: Set<String> = []
}
