// Speech priority (§5.15): danger > stairs > reply > guidance > narration.
// - A higher priority interrupts a lower one immediately.
// - Lower-priority lines (below stairs) are dropped, not queued, if they're older than ~3 s when their turn comes.
// - Narration (optional lines) is dropped at the brief detail level.
// - Talking (volume up) stops and clears everything below stairs, but never cuts a danger or stairs line.

public struct SpeechLine: Equatable {
    public var text: String
    public var priority: SpeechPriority
    public var createdAt: Double

    public init(text: String, priority: SpeechPriority, createdAt: Double) {
        self.text = text; self.priority = priority; self.createdAt = createdAt
    }
}

/// What the speaker should do with a line given to `SpeechPriorityQueue.enqueue`.
public enum SpeechDecision: Equatable {
    /// Nothing was playing: speak it now.
    case speakNow(SpeechLine)
    /// Stop the current line, then speak this one.
    case interrupt(SpeechLine)
    /// Waits for the current line to finish (`finished(now:)` returns it later, unless it goes stale).
    case queued
    /// Not spoken: duplicate of what's playing or waiting, or narration at the brief level.
    case dropped
}

/// Which voice speaks a line (§5.15): danger always through the synthesizer; with VoiceOver on, everything else
/// is posted as a VoiceOver announcement so two voices never overlap.
public enum SpeechChannel: Equatable { case synthesizer, voiceOverAnnouncement }

public func speechChannel(for priority: SpeechPriority, voiceOverRunning: Bool) -> SpeechChannel {
    priority == .danger || !voiceOverRunning ? .synthesizer : .voiceOverAnnouncement
}

public struct SpeechPriorityQueue {
    public private(set) var current: SpeechLine?
    private var pending: [SpeechLine] = []
    /// Narration is dropped at `.brief`.
    public var verbosity: Verbosity = .normal
    /// Seconds after which a waiting line below stairs is dropped.
    public var staleAfter: Double = 3

    public init() {}

    public init(verbosity: Verbosity, staleAfter: Double = 3) {
        self.verbosity = verbosity; self.staleAfter = staleAfter
    }

    /// Lines waiting behind `current`, highest priority first, oldest first within a priority.
    public var pendingLines: [SpeechLine] { pending }
    public var isSpeaking: Bool { current != nil }

    /// Returns true if the new line should interrupt what's playing.
    /// (Original path: with nothing playing the line waits in the queue until `next(now:)`. Prefer `enqueue`.)
    public mutating func push(_ line: SpeechLine) -> Bool {
        if let c = current, line.priority > c.priority { current = line; return true }
        insert(line)
        return false
    }

    /// Main path: speaks immediately when nothing is playing, interrupts a lower priority, otherwise queues.
    /// An interrupted stairs or reply line goes back to the front of its priority (stairs are announced only once;
    /// replies answer the user). Interrupted guidance and narration are dropped: they're re-derived anyway.
    public mutating func enqueue(_ line: SpeechLine) -> SpeechDecision {
        if line.priority == .narration && verbosity == .brief { return .dropped }
        if current?.text == line.text || pending.contains(where: { $0.text == line.text }) { return .dropped }
        guard let c = current else { current = line; return .speakNow(line) }
        if line.priority > c.priority {
            if c.priority == .stairs || c.priority == .reply {
                pending.insert(c, at: pending.firstIndex { $0.priority <= c.priority } ?? pending.count)
            }
            current = line
            return .interrupt(line)
        }
        if line.priority == .danger { pending.removeAll { $0.priority == .danger } }   // newest danger only
        insert(line)
        return .queued
    }

    /// Next line to speak after the current one finishes; drops stale lower-priority lines.
    public mutating func next(now: Double) -> SpeechLine? {
        pending.removeAll { $0.priority < .stairs && now - $0.createdAt > staleAfter }
        current = pending.isEmpty ? nil : pending.removeFirst()
        if current?.priority == .narration && verbosity == .brief { return next(now: now) }
        return current
    }

    /// The current line finished playing: same as `next(now:)`.
    public mutating func finished(now: Double) -> SpeechLine? { next(now: now) }

    /// Volume up (talk): drops everything below stairs. Returns true if the current line must be stopped now;
    /// false when nothing is playing or a danger / stairs line is playing (the talk beep waits for it).
    public mutating func holdForListening() -> Bool {
        pending.removeAll { $0.priority < .stairs }
        guard let c = current, c.priority < .stairs else { return false }
        current = nil
        return true
    }

    /// Drops waiting lines below `priority` (and the current line if it's below too).
    /// Returns true if the current line was removed (stop the speaker).
    @discardableResult
    public mutating func clear(below priority: SpeechPriority) -> Bool {
        pending.removeAll { $0.priority < priority }
        guard let c = current, c.priority < priority else { return false }
        current = nil
        return true
    }

    /// Speech was stopped from outside (e.g. `Effect.stopSpeech`): forget everything.
    public mutating func stopAll() {
        current = nil
        pending.removeAll()
    }

    /// Stable insert: after every waiting line of the same or higher priority.
    private mutating func insert(_ line: SpeechLine) {
        let i = pending.firstIndex { $0.priority < line.priority } ?? pending.count
        pending.insert(line, at: i)
    }
}
