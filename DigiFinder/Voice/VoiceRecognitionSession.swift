import AVFoundation
import Foundation
import Speech

/// One recording: mic → `SFSpeechAudioBufferRecognitionRequest` (on-device when supported).
/// Ends on silence like Siri (owner decision): ~1.5 s after the last new word, or ~6 s if nothing is said.
/// `cancel()` ends with `.cancelled` (stop: volume down / the stop button, danger alert, stairs line, backgrounding).
/// `finish()` ends it now and keeps what was said (used by nothing user-facing today). Tracks the input level for
/// "It's noisy here".
/// The audio session must already be in `.playAndRecord` (FeedbackAudioSession.beginListening).
final class VoiceRecognitionSession: @unchecked Sendable {
    /// Silence after the last new word that ends the recording (s).
    static let silenceSeconds = 1.5
    /// Nothing said for this long: the recording ends empty (s).
    static let noSpeechSeconds = 6.0
    /// After endAudio, how long to wait for the final transcription.
    static let finalWaitSeconds = 1.2
    /// Noise floor (dBFS, 20th percentile of buffer levels) above which the room counts as noisy. Verify on device.
    static let noisyFloorDB: Float = -38

    private let recognizer: SFSpeechRecognizer
    private let contextualStrings: [String]
    private let queue = DispatchQueue(label: "voice.recognition")

    // Confined to `queue`.
    private let engine = AVAudioEngine()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<VoiceResult, Never>?
    private var tapInstalled = false
    private var stopping = false
    private var done = false
    private var bestText = ""
    private var timer: DispatchSourceTimer?
    private var startedAt: Double = 0
    private var lastWordAt: Double?

    // Written on the audio thread.
    private let levelLock = NSLock()
    private var levels: [Float] = []

    /// The words heard so far (screen caption), on the recognition queue.
    private let onPartial: ((String) -> Void)?

    init(recognizer: SFSpeechRecognizer, contextualStrings: [String], onPartial: ((String) -> Void)? = nil) {
        self.recognizer = recognizer
        self.contextualStrings = contextualStrings
        self.onPartial = onPartial
    }

    func run() async -> VoiceResult {
        await withCheckedContinuation { (c: CheckedContinuation<VoiceResult, Never>) in
            queue.async {
                // cancel() may already have run (danger alert before the recording started): never open the mic.
                if self.done { c.resume(returning: .cancelled); return }
                self.continuation = c
                self.start()
            }
        }
    }

    func finish() { queue.async { self.beginStopping() } }

    func cancel() {
        queue.async {
            guard !self.done else { return }
            self.task?.cancel()
            self.complete(.cancelled)
        }
    }

    // MARK: Private (queue)

    private func start() {
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = contextualStrings
        request.taskHint = .search
        request.addsPunctuation = false

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return complete(.empty(noisy: false)) }
        let request = self.request
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)
            self.record(level: Self.level(of: buffer))
        }
        tapInstalled = true
        engine.prepare()
        do { try engine.start() } catch { return complete(.empty(noisy: false)) }

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            self?.queue.async { self?.handle(text: text, isFinal: isFinal, failed: failed) }
        }

        startedAt = Self.now()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1)
        t.setEventHandler { [weak self] in self?.checkSilence() }
        t.resume()
        timer = t
    }

    /// Siri-style end: silence after speech, or nothing said at all.
    private func checkSilence() {
        guard !done, !stopping else { return }
        let now = Self.now()
        if let last = lastWordAt {
            if now - last >= Self.silenceSeconds { beginStopping() }
        } else if now - startedAt >= Self.noSpeechSeconds {
            beginStopping()
        }
    }

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard !done else { return }
        if let text, !text.isEmpty, text != bestText {
            bestText = text
            lastWordAt = Self.now()
            onPartial?(text)
        }
        // A final result before volume down (the recognizer ended on its own, or failed) ends the recording too.
        if isFinal || failed { complete(result()) }
    }

    private func beginStopping() {
        guard !done, !stopping else { return }
        stopping = true
        stopAudio()
        request.endAudio()
        queue.asyncAfter(deadline: .now() + Self.finalWaitSeconds) { [weak self] in
            guard let self, !self.done else { return }
            self.task?.finish()
            self.complete(self.result())
        }
    }

    private func result() -> VoiceResult {
        let text = bestText.trimmingCharacters(in: .whitespacesAndNewlines)
        let noisy = isNoisy()
        return text.isEmpty ? .empty(noisy: noisy) : .text(text, noisy: noisy)
    }

    private func complete(_ r: VoiceResult) {
        guard !done else { return }
        done = true
        timer?.cancel()
        timer = nil
        stopAudio()
        if !stopping { request.endAudio() }
        task = nil
        continuation?.resume(returning: r)
        continuation = nil
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func isNoisy() -> Bool {
        levelLock.lock()
        let l = levels.sorted()
        levelLock.unlock()
        guard l.count >= 5 else { return false }
        return l[l.count / 5] > Self.noisyFloorDB
    }

    private func record(level: Float) {
        levelLock.lock()
        if levels.count < 2_000 { levels.append(level) }
        levelLock.unlock()
    }

    private static func level(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return -160 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { let s = data[0][i]; sum += s * s }
        let rms = (sum / Float(n)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -160
    }
}
