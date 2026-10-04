// Speech priority (§5.15): danger > stairs > reply > guidance > narration.

public struct SpeechLine: Equatable {
    public var text: String
    public var priority: SpeechPriority
    public var createdAt: Double

    public init(text: String, priority: SpeechPriority, createdAt: Double) {
        self.text = text; self.priority = priority; self.createdAt = createdAt
    }
}

public struct SpeechPriorityQueue {
    public private(set) var current: SpeechLine?
    private var pending: [SpeechLine] = []
    public init() {}

    /// Returns true if the new line should interrupt what's playing.
    public mutating func push(_ line: SpeechLine) -> Bool {
        if let c = current, line.priority > c.priority { current = line; return true }
        pending.append(line); pending.sort { $0.priority > $1.priority }
        return false
    }

    /// Next line to speak after the current one finishes; drops stale lower-priority lines.
    public mutating func next(now: Double) -> SpeechLine? {
        pending.removeAll { $0.priority < .stairs && now - $0.createdAt > 3 }
        current = pending.isEmpty ? nil : pending.removeFirst()
        return current
    }
}
