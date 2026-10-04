// Frozen contract (§3.3). Change requests go to CONTRACT_CHANGES.md.

public enum Verbosity: Int, Codable, Comparable {
    case brief = 0, normal, detailed
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public enum VoiceCommand: Equatable {
    case stop, thatsAll, repeatLast, lessDetail, moreDetail, whatsAround, outside(Bool), finishTalking
    /// Answers to "Switch to milk, or add it?"
    case switchGoal, addGoal
}

public enum Request: Equatable {
    case command(VoiceCommand), destination(Destination)
    case product(Goal, GoalChange)
    /// "coffee and milk" (queued)
    case products([Goal])
    /// Not in the offline database (§5.2).
    case unknownProduct(String, GoalChange)
    case question(String)
}
