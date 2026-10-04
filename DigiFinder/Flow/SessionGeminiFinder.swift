import Foundation
import DigiFinderCore

/// Gemini-assisted item finding (owner decision). While a search runs (stream on, a goal, phase Entrance / FindAisle /
/// InAisle, no Ask pending), Gemini is asked about every ~2 s whether the goal is in the latest Stream B frame
/// (upright, ~1024 px, JPEG 0.7). Found → Perception tracks the box frame to frame and reports `.itemSeen` like an
/// on-device sighting (the on-device item finder keeps running; whichever sees it first reports). While tracking,
/// Gemini is asked again every ~4 s, and at once when tracking is lost. Not found → its hint goes to the session as
/// `.searchHint` (the session de-dupes and rate-limits it). HTTP 429 / 503 / errors back off to ~5 s (never spoken). Offline: no request.
///
/// One request in flight at a time; a search change (goal, phase, stop) cancels the loop and drops late answers.
@MainActor
final class SessionGeminiFinder {
    static let searchInterval = 2.0
    /// Owner decision: Gemini every ~2 s, also while tracking.
    static let trackingInterval = 2.0
    static let backoffInterval = 5.0
    /// Never ask again sooner than this after the previous request started (tracking lost right away).
    static let minSpacing = 1.0
    /// 640 px answers in ~1.6 s vs ~4–9 s at 1024 px (measured with gemini-3.8-flash), so a ~2 s rhythm holds.
    nonisolated static let photoWidth = 640

    /// What the loop is searching for; a change restarts it.
    struct Search: Equatable {
        var goal: Goal
        var step: Step
    }

    /// Session events (hints) on the main actor.
    var onEvent: ((SessionEvent) -> Void)?
    /// Debug overlay line, readable from any thread.
    let status = SessionGeminiFinderStatus()

    private let gemini: GeminiClient
    private let perception: PerceptionService
    private let system: SystemMonitor
    private var search: Search?
    private var task: Task<Void, Never>?
    private var generation = 0

    init(gemini: GeminiClient, perception: PerceptionService, system: SystemMonitor) {
        self.gemini = gemini
        self.perception = perception
        self.system = system
    }

    /// nil = not searching. Same search → nothing changes. A new goal or the end of the search also drops the
    /// tracked box; a phase change within the search keeps it and asks again at once.
    func update(_ new: Search?) {
        guard new != search else { return }
        let old = search
        search = new
        generation += 1
        task?.cancel()
        task = nil
        if new?.goal != old?.goal, old != nil { perception.trackTarget(nil) }
        status.set(active: new != nil)
        guard let new else { return }
        let generation = self.generation
        task = Task { [weak self] in await self?.run(new.goal, generation: generation) }
    }

    /// The camera flipped: drop the answer in flight (its photo was the old way up) and scan again now.
    func restart() {
        guard let s = search else { return }
        search = nil
        update(s)
    }

    private func current(_ generation: Int) -> Bool { !Task.isCancelled && generation == self.generation }

    private func run(_ goal: Goal, generation: Int) async {
        let description = Self.describe(goal)
        let perception = self.perception
        let gemini = self.gemini
        while current(generation) {
            let began = ProcessInfo.processInfo.systemUptime
            var interval = Self.searchInterval
            if system.isOnline, let photo = await Self.photo(perception) {
                guard current(generation) else { return }
                status.sent()
                do {
                    let finding = try await gemini.findItem(description, image: photo.jpeg)
                    guard current(generation) else { return }
                    interval = apply(finding)
                } catch {
                    guard current(generation) else { return }
                    // HTTP 429 / 503 "high demand", timeouts, bad answers: back off, keep the loop, say nothing.
                    status.failed(error)
                    interval = Self.backoffInterval
                }
            }
            // Wait for the next round; tracking lost asks again early (not while backing off).
            let wasTracking = perception.isTrackingTarget
            while current(generation) {
                let t = ProcessInfo.processInfo.systemUptime
                if t - began >= interval { break }
                if wasTracking, interval < Self.backoffInterval, t - began >= Self.minSpacing,
                   !perception.isTrackingTarget { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    /// Found → track the box (Perception reports the sightings); not found → stop tracking, pass the hint on.
    private func apply(_ finding: ItemFinding?) -> Double {
        status.answer(finding)
        if finding?.crowded == true { onEvent?(.crowded) }            // the session rate-limits the warning
        if let f = finding, f.found, let box = f.box {
            perception.trackTarget(box)
            return Self.trackingInterval
        }
        if perception.isTrackingTarget { perception.trackTarget(nil) }      // Gemini corrects the tracker
        if let hint = finding?.hint, !hint.isEmpty { onEvent?(.searchHint(hint)) }
        return Self.searchInterval
    }

    /// Latest frame → upright JPEG, encoded off the main thread.
    private static func photo(_ perception: PerceptionService) async -> (jpeg: Data, frameTime: Double)? {
        nonisolated(unsafe) let perception = perception
        return await withCheckedContinuation { (c: CheckedContinuation<(jpeg: Data, frameTime: Double)?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                c.resume(returning: perception.latestUprightJPEG(maxWidth: photoWidth))
            }
        }
    }

    /// The goal in words for the prompt: brand, variant, product, form; household objects say so.
    static func describe(_ g: Goal) -> String {
        var words: [String] = []
        if let b = g.brand { words.append(b) }
        words += g.variant
        words.append(g.product)
        var text = words.joined(separator: " ")
        if let f = g.form, !f.isEmpty { text += ", \(f)" }
        if g.category == nil, g.visualClass != nil { text += " (a household object)" }
        return text
    }
}

/// Debug overlay values for the item finder, safe from any thread.
final class SessionGeminiFinderStatus: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false
    private var requests = 0
    private var last = "–"

    func set(active on: Bool) { lock.withLock { active = on } }
    func sent() { lock.withLock { requests += 1 } }

    func answer(_ f: ItemFinding?) {
        let text: String
        if let f {
            let c = String(format: "%.2f", f.confidence)
            text = f.found ? "found \(c) \"\(f.description)\"" : "not found \(c)" + (f.hint.isEmpty ? "" : " · hint \"\(f.hint)\"")
        } else {
            text = "no answer"
        }
        lock.withLock { last = text }
    }

    func failed(_ error: Error) {
        let e = NetworkError.from(error)
        let text: String
        if case .http(let code) = e { text = "error HTTP \(code)" } else { text = "error \(e)" }
        lock.withLock { last = text }
    }

    func line(tracking: Bool) -> String {
        lock.withLock {
            "Gemini finder \(active ? "on" : "off") · \(last) · requests \(requests) · tracking \(tracking ? "on" : "off")"
        }
    }
}
