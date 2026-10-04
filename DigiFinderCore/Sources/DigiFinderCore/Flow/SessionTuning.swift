// Timings and thresholds for the shopping flow (§5). Seconds unless noted.

enum SessionTuning {
    // Listening (§5.10)
    /// No answer to "Switch to milk, or add it?" / "What's next?" (runner silence fallback).
    static let answerTimeout = 12.0

    /// A recording still "on" after this long is stuck (recordings end on silence within seconds): cleared.
    static let stuckRecording = 30.0

    // Clock
    /// Longest gap one tick may add (backgrounded time doesn't run the timers out).
    static let maxTickGap = 5.0

    // Replies
    /// Gemini assist: the still plus Gemini's ~6 s timeout; then the offline path.
    static let assistTimeout = 8.0
    static let lookupTimeout = 8.0
    static let surroundingsTimeout = 6.0
    /// Guidance stays quiet this long after a danger alert if no `.dangerCleared` arrives.
    static let dangerHold = 8.0

    // Item in view (global rule in every search phase)
    /// A sighting stays usable this long (the walking "Stop." waits for Standing within it).
    static let itemMemory = 5.0
    /// Within this distance (m) and at 11–1 o'clock the item is in reach: Pick (Standing) or "Stop." (Walking).
    static let reachMeters: Float = 1.2
    /// Not a store: "Turn slowly." repeat, and give up after this long with no sighting.
    static let nearbyPrompt = 15.0
    /// After "Stop and look around…": standing still this long (≈ two Gemini scans) → "Keep going."
    static let contextStill = 4.0
    /// Confirm (Gemini mode): "Pick it up and hold it out." again this often while nothing is held.
    static let holdReminder = 10.0
    /// Confirm (Gemini mode): walking this long without holding the item → back to the search, silently.
    static let confirmWalkAway = 4.0
    /// Still not stopped this long after asking → ask again.
    static let contextReask = 20.0
    static let nearbyGiveUp = 60.0
    /// Farther item directions: when the direction changes, else at most this often.
    static let itemInterval = 3.0
    /// Gemini search hints ("Coffee sign at 10 o'clock."): at most this often, and only when the text changed.
    static let searchHintInterval = 8.0
    /// No hint while the item itself was seen this recently (on-device or tracked).
    static let searchHintAfterSighting = 3.0

    // Grocery or not (Gemini, once at app open)
    /// No answer this long after asking → store flow. Covers the runner's good-photo wait (≤ 5 s), 3 stills ~0.7 s
    /// apart and Gemini's ~6 s timeout.
    static let placeTimeout = 14.0
    /// Below this confidence the answer counts as unsure: ask once more, then the store flow.
    static let placeMinConfidence = 0.7

    // Signage (§5.2, §5.7, §5.12)
    static let scanPrompt = 3.0
    static let outOfView = 10.0
    static let lostTrack = 30.0
    static let lostPause = 60.0
    static let directionInterval = 2.0
    static let otherSignsInterval = 6.0
    /// A target sign seen this recently overrides a conflicting vote.
    static let signOverride = 10.0

    // Aisle and shelf
    /// After "Stop. Aisle 6 is at 9 o'clock.": walking within this many degrees of the aisle's bearing enters it.
    static let aisleHeadingDegrees = 45.0
    /// Pick / Confirm with no match this long since entering the aisle → not found (§5.12).
    static let notFound = 90.0
    /// LiDAR aisle end counts only after this many steps in the aisle.
    static let minAisleSteps = 5
    /// Pedometer backup for the aisle end: this far (m) since entering the aisle.
    static let aisleEndBackupMeters: Float = 20
    /// Shelf vote: a side counts as checked after facing it this long, or this long ×2 after the prompt.
    static let voteFace = 4.0
    /// Facing a vote side = within this many degrees of it.
    static let voteFacingDegrees = 45.0
    /// Pointing match that means the goal ("Grab it.").
    static let pointMatch = MatchingThresholds.pointMatch
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
