import AVFoundation
import Foundation
import DigiFinderCore

/// Tones generated in code: listening beep, done chime, scan tick. Plays in whatever audio session category is
/// current (speaking or listening). Thread-safe.
final class ToneService {
    /// Setup toggle "tones". The listening beep always plays (it tells the user the mic is open).
    var isEnabled: Bool {
        get { enabledLock.lock(); defer { enabledLock.unlock() }; return enabledCopy }
        set {
            enabledLock.lock(); enabledCopy = newValue; enabledLock.unlock()
            queue.async { self.enabled = newValue }
        }
    }
    /// Read from any thread without waiting on the tone queue.
    private let enabledLock = NSLock()
    private var enabledCopy = true

    private let queue = DispatchQueue(label: "feedback.tones")
    private var enabled = true
    private var players: [Tone: AVAudioPlayer] = [:]
    private var wavs: [Tone: Data] = [:]

    init() {
        for t in [Tone.beep, .done, .tick] { wavs[t] = FeedbackToneSynth.wav(for: t) }
    }

    func play(_ t: Tone) { play(t, completion: nil) }

    /// Calls `completion` (on a background queue) when the tone has finished.
    func play(_ t: Tone, completion: (() -> Void)?) {
        queue.async {
            guard self.enabled || t == .beep, let player = self.player(for: t) else {
                completion?()
                return
            }
            player.currentTime = 0
            player.play()
            if let completion {
                self.queue.asyncAfter(deadline: .now() + FeedbackToneSynth.duration(of: t) + 0.03) { completion() }
            }
        }
    }

    /// Async form used before recording (beep, then listen).
    func playAndWait(_ t: Tone) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            play(t) { c.resume() }
        }
    }

    private func player(for t: Tone) -> AVAudioPlayer? {
        if let p = players[t] { return p }
        guard let data = wavs[t], let p = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) else {
            return nil
        }
        p.volume = 1
        p.prepareToPlay()
        players[t] = p
        return p
    }
}
