import AVFoundation
import Foundation
import Speech
import DigiFinderCore

/// On-device `SFSpeechRecognizer` (§2 Audio and input, §5.10).
/// listen: permissions → wait for speech to end (max ~3 s) → hold guidance → `.playAndRecord` → beep → record.
/// Ends only on `finish()` (volume down): no silence end, no time limit; `cancel()` returns `.cancelled`.
/// A second `listen` while one is running returns `.cancelled` at once (a confused press never restarts it).
final class SpeechVoiceInput: VoiceInput, @unchecked Sendable {
    private enum Stop { case finish, cancel }

    private let lock = NSLock()
    private var listening = false
    private var stopRequest: Stop?
    private var recording: VoiceRecognitionSession?
    private var hints: [String] = []
    private var denied = false
    private var deniedHandler: (() -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    init() {}

    var isListening: Bool {
        lock.lock(); defer { lock.unlock() }
        return listening
    }

    var contextualStrings: [String] {
        get { lock.lock(); defer { lock.unlock() }; return hints }
        set {
            // Apple recommends short lists; keep the first 100 unique non-empty hints.
            var seen = Set<String>()
            let clean = newValue.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            lock.lock(); hints = Array(clean.prefix(100)); lock.unlock()
        }
    }

    var onPermissionDenied: (() -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return deniedHandler }
        set { lock.lock(); deniedHandler = newValue; lock.unlock() }
    }

    var permissionDenied: Bool {
        lock.lock(); defer { lock.unlock() }
        return denied
    }

    func requestPermissions() async -> Bool {
        let ok = await VoicePermissions.request()
        if !ok { reportDenied() }
        return ok
    }

    func listen() async -> VoiceResult {
        let began: Bool = lock.withLock {
            guard !listening else { return false }
            listening = true
            stopRequest = nil
            return true
        }
        guard began else { return .cancelled }
        defer {
            lock.withLock { listening = false; recording = nil; stopRequest = nil }
        }

        guard await VoicePermissions.request() else {
            reportDenied()
            return .empty(noisy: false)
        }
        guard let recognizer, recognizer.isAvailable else { return .empty(noisy: false) }
        if let early = earlyResult() { return early }

        let audio = FeedbackAudioSession.shared
        guard await audio.beginListening(record: true) else {
            audio.endListening()
            return .empty(noisy: false)
        }

        let session = VoiceRecognitionSession(recognizer: recognizer, contextualStrings: contextualStrings)
        let pending: Stop? = lock.withLock {
            recording = session
            return stopRequest
        }
        let result: VoiceResult
        switch pending {
        case .cancel?: result = .cancelled
        case .finish?: result = .empty(noisy: false)
        case nil: result = await session.run()
        }
        audio.endListening()
        return result
    }

    /// Volume down: ends the recording now. Ignored when not listening.
    func finish() {
        lock.lock()
        guard listening else { lock.unlock(); return }
        let r = recording
        if r == nil, stopRequest == nil { stopRequest = .finish }
        lock.unlock()
        r?.finish()
    }

    /// Danger or session end: `listen` returns `.cancelled`.
    func cancel() {
        lock.lock()
        guard listening else { lock.unlock(); return }
        let r = recording
        stopRequest = .cancel
        lock.unlock()
        r?.cancel()
    }

    private func earlyResult() -> VoiceResult? {
        lock.lock(); defer { lock.unlock() }
        switch stopRequest {
        case .cancel?: return .cancelled
        case .finish?: return .empty(noisy: false)
        case nil: return nil
        }
    }

    private func reportDenied() {
        lock.lock()
        denied = true
        let handler = deniedHandler
        lock.unlock()
        if let handler { DispatchQueue.main.async { handler() } }
    }
}
