import AVFoundation
import Foundation
import Speech

/// One recording: mic → `SFSpeechAudioBufferRecognitionRequest` (on-device when supported).
/// Ends on `finish()` (volume down), ~1.5 s without new words after speech started, no speech within the grace
/// period, or `maxSeconds`. `cancel()` ends with `.cancelled`. Tracks the input level for "It's noisy here".
/// The audio session must already be in `.playAndRecord` (FeedbackAudioSession.beginListening).
final class VoiceRecognitionSession: @unchecked Sendable {
    /// Silence after the last new word that ends the recording.
    static let silenceSeconds = 1.5
    /// Give up when nothing was said for this long (capped by maxSeconds).
    static let noSpeechSeconds = 6.0
    /// After endAudio, how long to wait for the final transcription.
    static let finalWaitSeconds = 1.2
    /// Noise floor (dBFS, 20th percentile of buffer levels) above which the room counts as noisy. Verify on device.
    static let noisyFloorDB: Float = -38

    private let recognizer: SFSpeechRecognizer
    private let contextualStrings: [String]
    private let maxSeconds: Double
    private let queue = DispatchQueue(label: "voice.recognition")

    // Confined to `queue`.
    private let engine = AVAudioEngine()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?
    private var timer: DispatchSourceTimer?
    private var continuation: CheckedContinuation<VoiceResult, Never>?
    private var tapInstalled = false
    private var stopping = false
    private var done = false
    private var bestText = ""
    private var startedAt: Double = 0
    private var lastWordAt: Double?

    // Written on the audio thread.
    private let levelLock = NSLock()
    private var levels: [Float] = []

    init(recognizer: SFSpeechRecognizer, contextualStrings: [String], maxSeconds: Double) {
        self.recognizer = recognizer
        self.contextualStrings = contextualStrings
        self.maxSeconds = max(1, maxSeconds)
    }

    func run() async -> VoiceResult {
        await withCheckedContinuation { (c: CheckedContinuation<VoiceResult, Never>) in
            queue.async {
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
            request.append(buffer)
            self?.record(level: Self.level(of: buffer))
        }
        tapInstalled = true
        engine.prepare()
        do { try engine.start() } catch { return complete(.empty(noisy: false)) }

        startedAt = Self.now()
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            self?.queue.async { self?.handle(text: text, isFinal: isFinal, failed: failed) }
        }

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1)
        t.setEventHandler { [weak self] in self?.checkTime() }
        t.resume()
        timer = t
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard !done else { return }
        if let text, !text.isEmpty, text != bestText {
            bestText = text
            lastWordAt = Self.now()
        }
        if isFinal || failed { complete(result()) }
    }

    private func checkTime() {
        guard !done, !stopping else { return }
        let now = Self.now()
        let elapsed = now - startedAt
        if elapsed >= maxSeconds { return beginStopping() }
        if let last = lastWordAt {
            if now - last >= Self.silenceSeconds { beginStopping() }
        } else if elapsed >= min(Self.noSpeechSeconds, maxSeconds) {
            beginStopping()
        }
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

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}
