// Timings and thresholds for the shopping flow (§5). Seconds unless noted.

enum SessionTuning {
    // Listening (§5.10)
    static let talkSeconds = 10.0
    static let autoListenSeconds = 5.0
    /// Speech before the beep plus routing time; a recording with no answer after this is treated as over.
    static let listenSlack = 8.0
    /// No answer to "Switch to milk, or add it?" / "What's next?" (runner silence fallback).
    static let answerTimeout = 12.0

    // Clock
    /// Longest gap one tick may add (backgrounded time doesn't run the timers out).
    static let maxTickGap = 5.0

    // Replies
    static let askTimeout = 6.0
    static let lookupTimeout = 8.0
    static let surroundingsTimeout = 6.0
    /// Guidance stays quiet this long after a danger alert if no `.dangerCleared` arrives.
    static let dangerHold = 8.0

    // Signage (§5.2, §5.7, §5.12)
    static let scanPrompt = 3.0
    static let outOfView = 10.0
    static let voteFace = 4.0
    static let lostTrack = 30.0
    static let lostPause = 60.0
    static let directionInterval = 2.0
    static let otherSignsInterval = 6.0
    /// A target sign seen this recently overrides a conflicting vote.
    static let signOverride = 10.0

    // Aisle and shelf
    static let turnFallback = 6.0
    static let turnDoneDegrees = 30.0
    static let shelfCue = 4.0
    static let notFound = 90.0
    static let turnBackDegrees = 150.0
    static let minAisleSteps = 5
    static let pointMatch = 0.8
    static let nearMiss = 0.5
    static let pointCueInterval = 1.0
    static let pointRepeat = 4.0
    static let unclearTurn = 4.0
    static let unclearFarther = 8.0

    // Destinations (§5.6)
    static let destinationNotFound = 45.0
    static let defaultDestinations: [Destination: [String]] = [
        .customerService: ["customer service", "information", "service desk", "help"],
        .checkout: ["checkout", "self checkout", "express", "lane", "cash"],
    ]

    // Entrance (§5.2)
    /// Portrait horizontal field of view of the 0.5× still, used until intrinsics reach the session.
    static let stillHorizontalFOV = 92.0
    static let entranceAnnounceMeters: Float = 8
    static let pickInterval = 5.0
    static let pickTimeout = 10.0
    static let maxPicks = 6
    static let reaskTurnDegrees = 60.0
    static let doorLost = 5.0
    static let doorTrackDegrees = 30.0
    static let noDoor = 30.0

    // Stairs (§5.4)
    static let stairsNearMeters: Float = 1.2
    static let stairsForget = 15.0
    static let stepLengthMeters: Float = 0.7

    // Positioning (§5.8)
    static let hintInterval = 8.0
    static let darkInterval = 20.0
    static let flippedInterval = 30.0

    static let maxHeld = 8
}
