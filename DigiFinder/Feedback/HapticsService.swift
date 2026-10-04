import AudioToolbox
import CoreHaptics
import Foundation

/// Core Haptics danger pattern: 3 strong ~150 ms pulses ~100 ms apart. Danger only (§2 Feedback channels).
/// Callable from any thread (the safety lane); the engine is kept running so a pulse starts in a few ms.
/// Devices without Core Haptics fall back to the system vibration.
final class HapticsService {
    /// Setup toggle "danger haptics" (default on).
    var isEnabled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return enabled }
        set { lock.lock(); enabled = newValue; lock.unlock() }
    }

    let supportsHaptics: Bool

    private let lock = NSLock()
    private var enabled = true
    private var engine: CHHapticEngine?
    private var engineRunning = false
    private var pattern: CHHapticPattern?

    init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        guard supportsHaptics else { return }
        pattern = Self.makeDangerPattern()
        guard let engine = try? CHHapticEngine() else { return }
        engine.playsHapticsOnly = true
        engine.isAutoShutdownEnabled = false
        engine.stoppedHandler = { [weak self] _ in
            guard let self else { return }
            self.lock.lock(); self.engineRunning = false; self.lock.unlock()
        }
        engine.resetHandler = { [weak self] in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            self.engineRunning = (try? self.engine?.start()) != nil
        }
        self.engine = engine
        engineRunning = (try? engine.start()) != nil
    }

    /// The danger vibration. Returns at once; never touches the main thread.
    func dangerPulse() {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return }
        guard let engine, let pattern else {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            return
        }
        do {
            if !engineRunning {
                try engine.start()
                engineRunning = true
            }
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            engineRunning = false
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    private static func makeDangerPattern() -> CHHapticPattern? {
        // Owner decision: one vibration in every place.
        let event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                                               CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)],
                                  relativeTime: 0, duration: 0.3)
        return try? CHHapticPattern(events: [event], parameters: [])
    }
}
