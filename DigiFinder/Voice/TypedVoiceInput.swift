import Foundation
import DigiFinderCore

/// Simulator / debug panel: typed requests stand in for speech. Same rules as `SpeechVoiceInput` (waits for speech
/// to end, holds guidance, beeps) but no microphone. `submit(_:)` resolves the pending listen with the text; text
/// submitted while not listening is kept for the next listen.
final class TypedVoiceInput: VoiceInput, VoiceInputControl, @unchecked Sendable {
    /// Typing is slower than talking: a listen waits at least this long.
    static let minimumWaitSeconds = 30.0

    private let lock = NSLock()
    private var listening = false
    private var continuation: CheckedContinuation<VoiceResult, Never>?
    private var pendingText: String?
    private var generation = 0

    var onPermissionDenied: (() -> Void)?
    var permissionDenied: Bool { false }
    var contextualStrings: [String] = []

    init() {}

    func requestPermissions() async -> Bool { true }

    var isListening: Bool {
        lock.lock(); defer { lock.unlock() }
        return listening
    }

    func listen(maxSeconds: Double) async -> VoiceResult {
        let gen: Int? = lock.withLock {
            guard !listening else { return nil }
            listening = true
            generation += 1
            return generation
        }
        guard let gen else { return .cancelled }

        let audio = FeedbackAudioSession.shared
        _ = await audio.beginListening(record: false)
        let result = await withCheckedContinuation { (c: CheckedContinuation<VoiceResult, Never>) in
            lock.lock()
            guard listening, generation == gen else {   // cancelled during the beep
                lock.unlock()
                c.resume(returning: .cancelled)
                return
            }
            if let text = pendingText {
                pendingText = nil
                lock.unlock()
                c.resume(returning: .text(text, noisy: false))
                return
            }
            continuation = c
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + max(maxSeconds, Self.minimumWaitSeconds)) { [weak self] in
                self?.resolve(.empty(noisy: false), generation: gen)
            }
        }
        lock.withLock { if generation == gen { listening = false } }
        audio.endListening()
        return result
    }

    /// Called by the debug panel with a typed request.
    func submit(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lock.lock()
        if continuation == nil {
            pendingText = t
            lock.unlock()
            return
        }
        let gen = generation
        lock.unlock()
        resolve(.text(t, noisy: false), generation: gen)
    }

    func finish() {
        lock.lock()
        let pending = continuation != nil
        let gen = generation
        lock.unlock()
        if pending { resolve(.empty(noisy: false), generation: gen) }
    }

    func cancel() {
        lock.lock()
        let gen = generation
        if continuation == nil, listening { generation += 1; listening = false }
        lock.unlock()
        resolve(.cancelled, generation: gen)
    }

    private func resolve(_ r: VoiceResult, generation gen: Int) {
        lock.lock()
        guard generation == gen, let c = continuation else { lock.unlock(); return }
        continuation = nil
        listening = false
        lock.unlock()
        c.resume(returning: r)
    }
}
