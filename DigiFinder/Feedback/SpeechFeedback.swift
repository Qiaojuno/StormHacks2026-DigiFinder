import AVFoundation
import Foundation
import UIKit
import DigiFinderCore

/// Speech output (§5.15): `AVSpeechSynthesizer` + Core's `SpeechPriorityQueue` + VoiceOver announcements.
/// - Higher priority interrupts lower at once; waiting lines below stairs are dropped after ~3 s.
/// - Danger always speaks through the synthesizer. With VoiceOver on, every other line is posted as a VoiceOver
///   announcement so two voices never overlap.
/// - While the mic is open (voice input), lines below stairs are held and replayed when it closes (if still fresh),
///   so the app never records its own speech.
/// Every method is callable from any thread; speech state lives on one serial queue.
final class SpeechFeedback: NSObject, FeedbackOutput, UIDebugSnapshotSource, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let haptics: HapticsService
    private let tones: ToneService
    private let synthesizer = AVSpeechSynthesizer()
    private let audio = FeedbackAudioSession.shared
    private let queue = DispatchQueue(label: "feedback.speech", qos: .userInitiated)

    // Confined to `queue`.
    private var lines = SpeechPriorityQueue()
    private var held: [SpeechLine] = []
    /// Done chimes waiting for a line: each plays when that line finishes (or when nothing more is playing).
    private var pendingChimes: [(tone: Tone, after: String?)] = []
    /// The most recent line given to `say` (queue), so a chime can follow exactly that line.
    private var lastSubmittedText: String?
    private var micOpen = false
    private var utterance: AVSpeechUtterance?
    private var announcement: String?
    private var announcementRetried = false
    private var token = 0
    private var voice: AVSpeechSynthesisVoice?
    private var voiceID: String?
    private var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    // Read from any thread.
    private let flags = NSLock()
    private var busy = false
    private var pendingSubmits = 0
    private var voiceOverOn = false
    private var observers: [NSObjectProtocol] = []

    init(haptics: HapticsService, tones: ToneService) {
        self.haptics = haptics
        self.tones = tones
        super.init()
        synthesizer.delegate = self
        voice = FeedbackVoicePicker.bestEnglishVoice()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in self?.refreshVoiceOver() })
        observers.append(center.addObserver(forName: UIAccessibility.announcementDidFinishNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let text = note.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String
            let ok = note.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? Bool ?? true
            self?.queue.async { self?.announcementFinished(text: text, successful: ok) }
        })
        refreshVoiceOver()
        audio.register(output: self)
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    // MARK: FeedbackOutput

    /// Includes VoiceOver announcements and lines handed to `say` but not yet processed.
    var isSpeaking: Bool {
        flags.lock()
        let b = busy || pendingSubmits > 0
        flags.unlock()
        return b || synthesizer.isSpeaking
    }

    /// Safety lane, any thread: vibrations FIRST (no hop) for a high threat, then stop speech, then the alert line
    /// at danger priority. Low threats (overhead) are spoken only.
    func danger(_ label: String, steer: Steer, distance: Float?, vibrate: Bool) {
        if vibrate { haptics.dangerPulse() }
        let line = SpeechLine(text: alertPhrase(label: label, steer: steer, distance: distance, inSteps: distanceInSteps),
                              priority: .danger, createdAt: Self.now())
        markSubmit()
        queue.async {
            if self.lines.clear(below: .stairs) { self.stopCurrentOutput() }
            self.held.removeAll()
            self.submit(line)
            self.unmarkSubmit()
        }
    }

    func say(_ text: String, _ p: SpeechPriority) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let line = SpeechLine(text: trimmed, priority: p, createdAt: Self.now())
        markSubmit()
        queue.async {
            self.lastSubmittedText = line.text
            self.submit(line)
            self.unmarkSubmit()
        }
    }

    /// Talk / stop: stops and clears everything below stairs. Never cuts a danger or stairs line (§5.10).
    func stopAll() {
        queue.async {
            self.lines.stopAll()
            self.stopCurrentOutput()
            self.held.removeAll()
            self.pendingChimes.removeAll()
            self.updateBusy()
        }
    }

    func stopSpeech() {
        queue.async {
            if self.lines.holdForListening() { self.stopCurrentOutput() }
            self.held.removeAll()
            self.pendingChimes.removeAll()
            self.updateBusy()
        }
    }

    /// The done chime follows the line said just before it ("Got it… Put it in your cart." + chime → "Next: milk."),
    /// even when more lines are queued behind; beeps and ticks play now.
    func chime(_ t: Tone) {
        queue.async {
            if t == .done && self.lines.current != nil {
                self.pendingChimes.append((t, self.lastSubmittedText))
            } else {
                self.tones.play(t)
            }
        }
    }

    /// The danger vibration only; speech is left alone. Any thread.
    func dangerPulse() { haptics.dangerPulse() }

    // MARK: Setup (§5.13)

    // Settings are read from the main thread: cached copies behind `flags`, never `queue.sync` (the speech queue can
    // be busy with slow audio-session work, which used to freeze the UI).
    private var cachedVerbosity: Verbosity = .normal
    private var cachedRate: Float = AVSpeechUtteranceDefaultSpeechRate
    private var cachedVoiceID: String?
    private var cachedQueueLines: [String] = []

    var verbosity: Verbosity {
        get { flags.lock(); defer { flags.unlock() }; return cachedVerbosity }
        set {
            flags.lock(); cachedVerbosity = newValue; flags.unlock()
            queue.async { self.lines.verbosity = newValue }
        }
    }

    var speechRate: Float {
        get { flags.lock(); defer { flags.unlock() }; return cachedRate }
        set {
            let r = min(max(newValue, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
            flags.lock(); cachedRate = r; flags.unlock()
            queue.async { self.rate = r }
        }
    }

    var voiceIdentifier: String? {
        get { flags.lock(); defer { flags.unlock() }; return cachedVoiceID }
        set {
            let v = newValue.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? FeedbackVoicePicker.bestEnglishVoice()
            flags.lock(); cachedVoiceID = newValue; flags.unlock()
            queue.async {
                self.voiceID = newValue
                self.voice = v
            }
        }
    }

    var tonesEnabled: Bool {
        get { tones.isEnabled }
        set { tones.isEnabled = newValue }
    }

    /// Distances in alerts as steps; read from the safety lane, so behind a lock.
    private let unitsLock = NSLock()
    private var stepsUnits = false
    var distanceInSteps: Bool {
        get { unitsLock.lock(); defer { unitsLock.unlock() }; return stepsUnits }
        set { unitsLock.lock(); stepsUnits = newValue; unitsLock.unlock() }
    }

    var dangerHapticsEnabled: Bool {
        get { haptics.isEnabled }
        set { haptics.isEnabled = newValue }
    }

    // MARK: Debug overlay

    /// Current and waiting lines, highest priority first.
    var debugSnapshot: UIDebugSnapshot {
        var s = UIDebugSnapshot()
        flags.lock(); s.speechQueue = cachedQueueLines; flags.unlock()
        return s
    }

    // MARK: Voice input coordination (FeedbackAudioSession)

    /// Waits until nothing is speaking, at most `maxWait` seconds.
    func waitUntilQuiet(maxWait: Double) async {
        let deadline = Self.now() + maxWait
        while isSpeaking && Self.now() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Mic open: guidance below stairs stops and new lines are held. Mic closed: fresh held lines play.
    func setMicOpen(_ open: Bool) {
        queue.sync {
            guard micOpen != open else { return }
            micOpen = open
            if open {
                if lines.holdForListening() { stopCurrentOutput() }
                held.removeAll()
            } else {
                let now = Self.now()
                let fresh = held.filter { $0.priority >= .stairs || now - $0.createdAt <= lines.staleAfter }
                held.removeAll()
                fresh.forEach(submit)
            }
            updateBusy()
        }
    }

    func playTone(_ t: Tone) async { await tones.playAndWait(t) }

    // MARK: Queue

    private func submit(_ line: SpeechLine) {
        defer { updateBusy() }
        if micOpen && line.priority < .stairs {
            held.removeAll { $0.text == line.text }
            held.append(line)
            return
        }
        switch lines.enqueue(line) {
        case .speakNow(let l): start(l)
        case .interrupt(let l): stopCurrentOutput(); start(l)
        case .queued, .dropped: break
        }
    }

    private func start(_ line: SpeechLine) {
        token += 1
        switch speechChannel(for: line.priority, voiceOverRunning: voiceOverRunning) {
        case .synthesizer:
            audio.prepareForSpeech(micOpen: micOpen)
            let u = AVSpeechUtterance(string: line.text)
            u.voice = voice
            u.rate = rate
            u.preUtteranceDelay = 0
            u.postUtteranceDelay = 0
            utterance = u
            announcement = nil
            synthesizer.speak(u)
        case .voiceOverAnnouncement:
            utterance = nil
            announcement = line.text
            announcementRetried = false
            post(line.text)
            // Fallback in case VoiceOver never reports the end (e.g. turned off mid-line).
            let t = token
            let words = Double(line.text.split(separator: " ").count)
            queue.asyncAfter(deadline: .now() + 1.5 + words * 0.4) { [weak self] in
                guard let self, self.token == t, self.announcement != nil else { return }
                self.lineFinished()
            }
        }
    }

    private func stopCurrentOutput() {
        if utterance != nil {
            utterance = nil
            synthesizer.stopSpeaking(at: .immediate)
        }
        announcement = nil     // a VoiceOver announcement can't be stopped; the next one replaces it
        token += 1
    }

    private func lineFinished() {
        utterance = nil
        announcement = nil
        let finishedText = lines.current?.text
        let due = pendingChimes.filter { $0.after == nil || $0.after == finishedText }
        if !due.isEmpty {
            due.forEach { tones.play($0.tone) }
            pendingChimes.removeAll { $0.after == nil || $0.after == finishedText }
        }
        if let next = lines.finished(now: Self.now()) {
            if micOpen && next.priority < .stairs {
                held.append(next)
                lines.clear(below: .stairs)
                if let n = lines.current { start(n) }
            } else {
                start(next)
            }
        }
        if lines.current == nil && !pendingChimes.isEmpty {     // its line was dropped or replaced
            pendingChimes.forEach { tones.play($0.tone) }
            pendingChimes.removeAll()
        }
        if lines.current == nil && !micOpen { audioSettled() }
        updateBusy()
    }

    private func audioSettled() {
        // After a danger line spoken during a recording, return to the speaking category.
        if audio.currentMode == .listening { audio.enterSpeaking() }
    }

    private func announcementFinished(text: String?, successful: Bool) {
        guard let current = announcement, text == nil || text == current else { return }
        if !successful && !announcementRetried {
            announcementRetried = true
            let t = token
            queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.token == t, self.announcement == current else { return }
                self.post(current)
            }
            return
        }
        lineFinished()
    }

    private func post(_ text: String) {
        Task { @MainActor in
            let attributed = NSAttributedString(string: text, attributes: [.accessibilitySpeechQueueAnnouncement: false])
            UIAccessibility.post(notification: .announcement, argument: attributed)
        }
    }

    private func updateBusy() {
        let b = lines.current != nil || utterance != nil || announcement != nil
        let shown = ([lines.current].compactMap { $0 } + lines.pendingLines).map { "[\($0.priority)] \($0.text)" }
        flags.lock(); busy = b; cachedQueueLines = shown; flags.unlock()
    }

    private func markSubmit() { flags.lock(); pendingSubmits += 1; flags.unlock() }
    private func unmarkSubmit() { flags.lock(); pendingSubmits -= 1; flags.unlock() }

    private var voiceOverRunning: Bool {
        flags.lock(); defer { flags.unlock() }
        return voiceOverOn
    }

    private func refreshVoiceOver() {
        Task { @MainActor [weak self] in
            let on = UIAccessibility.isVoiceOverRunning
            guard let self else { return }
            self.flags.withLock { self.voiceOverOn = on }
        }
    }

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        queue.async { if utterance === self.utterance { self.lineFinished() } }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        queue.async { if utterance === self.utterance { self.lineFinished() } }
    }
}
