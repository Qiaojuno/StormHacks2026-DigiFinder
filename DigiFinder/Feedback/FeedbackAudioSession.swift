import AVFoundation
import Foundation
import DigiFinderCore

/// The one owner of the app's `AVAudioSession` category (§9 Audio session).
/// Speaking: `.playback` / `.spokenAudio`. Listening: `.playAndRecord` with the speaker as output and the built-in mic.
/// Never record while speaking: `beginListening` waits for speech to end, holds guidance lines, switches category,
/// then beeps; the recorder starts after the beep. Thread-safe.
final class FeedbackAudioSession {
    static let shared = FeedbackAudioSession()

    enum Mode { case none, speaking, listening }

    private let lock = NSLock()
    private var mode: Mode = .none
    private var active = false
    private weak var output: SpeechFeedback?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: nil) { [weak self] note in
            guard let self else { return }
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began {
                self.lock.lock(); self.active = false; self.lock.unlock()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                            queue: nil) { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.active = false; self.mode = .none; self.lock.unlock()
        })
    }

    /// The speech output registers itself so voice input can wait for it, hold it and beep through it.
    func register(output: SpeechFeedback) {
        lock.lock(); self.output = output; lock.unlock()
    }

    var currentOutput: SpeechFeedback? {
        lock.lock(); defer { lock.unlock() }
        return output
    }

    var currentMode: Mode {
        lock.lock(); defer { lock.unlock() }
        return mode
    }

    /// Before a synthesizer line. Keeps `.playAndRecord` while the mic is open (a danger line during a recording).
    func prepareForSpeech(micOpen: Bool) {
        lock.lock(); defer { lock.unlock() }
        if micOpen && mode == .listening {
            activateLocked()
            return
        }
        guard mode != .speaking || !active else { return }
        setSpeakingLocked()
    }

    /// Switches to `.playback` now (used after a recording when nothing is speaking).
    func enterSpeaking() {
        lock.lock(); defer { lock.unlock() }
        guard mode != .speaking || !active else { return }
        setSpeakingLocked()
    }

    /// Stop speech → beep → listen (§2). Waits up to `maxWait` s for the current line (danger and stairs are never
    /// cut), drops guidance below stairs, switches to `.playAndRecord` when `record` is true, then plays the beep and
    /// returns after it. Returns false if the category could not be set (no recording possible).
    func beginListening(record: Bool, maxWait: Double = 3) async -> Bool {
        let output = currentOutput
        if let output { await output.waitUntilQuiet(maxWait: maxWait) }
        // Category / activation changes can block for a second or more: never on the caller's (often main) thread.
        let ok: Bool = await onSwitchQueue {
            output?.setMicOpen(true)
            return record ? self.enterListening() : true
        }
        if let output { await output.playTone(.beep) }
        if !ok { await onSwitchQueue { output?.setMicOpen(false) } }
        return ok
    }

    /// After a recording: re-opens speech output (held lines play) and goes back to `.playback` if nothing speaks.
    /// Returns at once; the switch runs on the same serial queue as `beginListening`, so the order is kept.
    func endListening() {
        let output = currentOutput
        switchQueue.async {
            output?.setMicOpen(false)
            if !(output?.isSpeaking ?? false) { self.enterSpeaking() }
        }
    }

    /// Serial queue for speak ↔ listen switches (AVAudioSession calls are slow and must not block the UI).
    private let switchQueue = DispatchQueue(label: "feedback.audio.switch", qos: .userInitiated)

    private func onSwitchQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { (c: CheckedContinuation<T, Never>) in
            switchQueue.async { c.resume(returning: work()) }
        }
    }

    private func enterListening() -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            // iOS mutes haptics while recording by default; danger must still vibrate mid-sentence (§5.3, §5.17).
            try? s.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try s.setActive(true)
            mode = .listening
            active = true
            return true
        } catch {
            return false
        }
    }

    private func setSpeakingLocked() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try s.setActive(true)
            mode = .speaking
            active = true
        } catch {
            active = false
        }
    }

    private func activateLocked() {
        guard !active else { return }
        active = (try? AVAudioSession.sharedInstance().setActive(true)) != nil
    }
}
