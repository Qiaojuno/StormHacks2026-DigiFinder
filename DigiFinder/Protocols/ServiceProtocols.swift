// Frozen app contracts (§3.3). Change requests go to CONTRACT_CHANGES.md.
import Foundation
import DigiFinderCore

protocol MotionService: AnyObject {
    /// CoreMotion gravity in the device frame (g units, pointing down).
    var gravity: SIMD3<Float> { get }
    var yawDegrees: Double { get }
    /// rad/s
    var rotationRate: Double { get }
    var isWalking: Bool { get }
    var steps: Int { get }
    func start()
}

/// Empty results if the model is missing.
protocol ObjectDetector: AnyObject {
    var latest: [Detection] { get }
    func detect(_ f: FrameB) -> [Detection]
}

/// Danger + stairs; calls feedback.danger itself (no main-thread hop).
protocol SafetyService: AnyObject {
    var onEvent: ((SessionEvent) -> Void)? { get set }
    func start()
    func setWork(_ w: StreamWork)
}

/// Signs, aisles, doors, pointing, confirmation, positioning, "What's around?".
protocol PerceptionService: AnyObject {
    var onEvent: ((SessionEvent) -> Void)? { get set }
    func start()
    func setWork(_ w: StreamWork)
    func setTarget(_ g: Goal?, candidates: [ProductInfo], destination: Destination?)
    func describeSurroundings() -> String
}

enum VoiceResult {
    case text(String, noisy: Bool), empty(noisy: Bool), cancelled
}

protocol VoiceInput: AnyObject {
    var isListening: Bool { get }
    func listen(maxSeconds: Double) async -> VoiceResult
    func finish()
    func cancel()
}

protocol FeedbackOutput: AnyObject {
    /// Vibrations first, stop speech, then the alert line; callable from any thread.
    func danger(_ label: String, steer: Steer)
    func say(_ text: String, _ p: SpeechPriority)
    func stopSpeech()
    func chime(_ t: Tone)
    /// Includes VoiceOver announcements; listening waits for false (§5.10).
    var isSpeaking: Bool { get }
}

protocol GeminiClient {
    func ask(_ question: String, still: Data) async throws -> String
    /// nil = no entrance visible.
    func pickEntrance(still: Data) async throws -> EntrancePick?
}

struct OnlineProduct {
    let info: ProductInfo
    let categoryTags: [String]
}

/// Open Food Facts.
protocol ProductLookupClient {
    func search(_ words: String) async throws -> [OnlineProduct]
}

protocol SystemMonitor: AnyObject {
    var onEvent: ((SystemEvent) -> Void)? { get set }
    var isOnline: Bool { get }
    func start()
}
