// Session state (§3.3). Owned by Flow/ and free to grow; the runner relies on `step`, `lastLine` and `isWalking`.
// Times are session seconds (`now`), advanced only by `.tick`.

/// Why guidance is paused (`Step.paused`).
public enum SessionPauseReason: Equatable { case lost, background }

public struct SessionState: Equatable {
    // Runner-facing
    public var step: Step = .idle
    /// Lines spoken by the latest event, joined (shown on screen).
    public var lastLine = ""
    public var isWalking = false

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

    // Talking
    public var isListening = false
    /// Last flow prompt (for "repeat" and audio route changes).
    public var lastPrompt = ""
    /// Step to resume after `.asking` or `.paused`.
    public var resumeStep: Step?
    public var pauseReason: SessionPauseReason?

    // Clock and motion
    public var now: Double = 0
    public var stepStartedAt: Double = 0
    public var yaw: Double = 0
    public var steps = 0

    // Internal memory
    var lastTick: Double?
    var hasMotion = false
    var listenDeadline: Double?
    /// Aisle (category key) the user stands in, for "Tea is in this aisle too."
    var currentAisle: String?
    /// Bumped whenever the target changes; held observations for an older target are dropped.
    var goalEpoch = 0
    var held: [SessionHeldEvent] = []
    var askStartedAt: Double?
    var lookup: SessionLookup?
    var surroundingsSince: Double?
    var choiceAskedAt: Double?
    var askingNextAt: Double?
    var dangerSince: Double?
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
    var voteStage = 0
    var turnBearing: Double?
    var turnDueAt: Double?
    var shelfCueAt: Double?
    var unclearStage = 0
    var unclearAnchor: Double = 0
    var lastPointCueAt: Double?
    var destinationSeen = false
    var destinationNotFoundSaid = false
    var noisyRetry = false

    init(anchor: Double = 0) { scanAnchor = anchor; unclearAnchor = anchor }
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
