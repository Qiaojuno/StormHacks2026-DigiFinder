// Shopping flow state machine (§5): (state, event) -> (state, [Effect]). Pure: no clock, no I/O.
// Wave 1 stub: only start-up is wired so the app is usable. Wave 2 (Core-session) implements the flow.

/// Session state. Owned by Flow/ and free to grow; the runner relies on `step`, `lastLine` and `isWalking`.
public struct SessionState: Equatable {
    public var step: Step = .idle
    /// Step to resume after talking, asking, danger or a "What's around?" answer.
    public var resumeStep: Step?
    public var goal: Goal?
    public var queue: [Goal] = []
    /// "Switch to milk, or add it?" awaiting an answer.
    public var pendingChoice: Goal?
    public var destination: Destination?
    public var online = false
    public var verbosity: Verbosity = .normal
    /// Last line spoken (shown on screen; "repeat").
    public var lastLine = ""
    public var isWalking = false
    public var foundCount = 0
    /// Seconds, from the latest .tick.
    public var now: Double = 0
    public var stepStartedAt: Double = 0

    public init() {}
}

public struct ShoppingSession {
    public private(set) var state = SessionState()
    let catalog: [String: AisleInfo]

    public init(catalog: [String: AisleInfo]) { self.catalog = catalog }

    public mutating func handle(_ e: SessionEvent) -> [Effect] {
        switch e {
        case .started:
            state.step = .askingGoal
            state.stepStartedAt = state.now
            state.lastLine = "What are you looking for?"
            return [.say(state.lastLine, .guidance), .listen(maxSeconds: 10)]
        case .tick(let t):
            state.now = t
            return []
        case .motion(_, _, let walking):
            state.isWalking = walking
            return []
        case .system(.online(let online)):
            state.online = online
            return []
        default:
            return []
        }
    }
}
