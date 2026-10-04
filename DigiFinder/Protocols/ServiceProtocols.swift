// App contracts (§3.3). Change requests go to CONTRACT_CHANGES.md.
import Foundation
import DigiFinderCore

protocol MotionService: AnyObject {
    /// CoreMotion gravity in the device frame (g units, pointing down).
    var gravity: SIMD3<Float> { get }
    /// Back-camera heading around vertical, degrees, counterclockwise positive (CoreMotion sign), -180...180,
    /// arbitrary zero. Core dead reckoning and `SessionEvent.motion` take `-yawDegrees` (clockwise).
    var yawDegrees: Double { get }
    /// Magnitude of the gyro vector, rad/s.
    var rotationRate: Double { get }
    var isWalking: Bool { get }
    /// Cumulative pedometer steps since `start()`.
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
    /// Called on the safety lane (the capture depth queue, or Safety's own queue for the no-LiDAR fallback);
    /// the handler hops to the main actor itself.
    var onEvent: ((SessionEvent) -> Void)? { get set }
    /// Idempotent. Chains onto `FrameSource.onDepth`: start it after `PerceptionService.start()` so its work runs first.
    func start()
    func setWork(_ w: StreamWork)
    /// The stream (owner decision): false = no danger or stairs checks at all until true again. Any thread.
    func setActive(_ on: Bool)
    /// Alert sensitivity by place (owner decision): store = sensitive, general = calm. Any thread.
    func setProfile(_ p: ThreatProfile)
    /// Debug overlay (§6): corridor, steer, TTC, stairs profile. Thread-safe copy; poll at ~2–5 Hz.
    var debugSnapshot: SafetyDebugSnapshot { get }
}

/// Signs, aisles, doors, pointing, confirmation, positioning, "What's around?".
/// Events are sent from Perception's own queues, never the main thread (semantics: `SessionEvent` docs).
protocol PerceptionService: AnyObject {
    var onEvent: ((SessionEvent) -> Void)? { get set }
    func start()
    func setWork(_ w: StreamWork)
    func setTarget(_ g: Goal?, candidates: [ProductInfo], destination: Destination?)
    /// Blocking (runs Vision); call off the main thread.
    func describeSurroundings() -> String
    /// The stream (owner decision): false = frames are dropped, nothing is checked or reported. Any thread.
    func setActive(_ on: Bool)
    /// Saves the last confirmed held-item label crop to `ProductMemory` (§5.14).
    func remember(_ p: ProductInfo)
    /// Debug overlay (§6): YOLO boxes, OCR regions, hand point. Thread-safe copy.
    var debugSnapshot: PerceptionDebugSnapshot { get }

    // Gemini item finder (owner decision): the runner asks Gemini about the latest frame; Perception tracks the box.
    /// The latest Stream B frame (≤ ~1 s old) turned upright (flip setting applied), JPEG ≤ `maxWidth` px wide,
    /// quality ~0.7, and its time (`systemUptime`). nil while stopped or without a fresh frame. Blocking; off main.
    func latestUprightJPEG(maxWidth: Int) -> (jpeg: Data, frameTime: Double)?
    /// Tracks this box (contract space: upright portrait, normalized, top-left origin) frame to frame on Stream B
    /// (Vision object tracking) and reports it as `.itemSeen` like an on-device sighting; nil stops. The box belongs
    /// to the current target: a target change drops it. Any thread.
    func trackTarget(_ box: NormRect?)
    /// A tracked box is being followed (or a seed is waiting for the next frame). Any thread, cheap.
    var isTrackingTarget: Bool { get }
}

enum VoiceResult {
    case text(String, noisy: Bool), empty(noisy: Bool), cancelled
}

/// `listen` itself waits for speech to end (max ~3 s), holds guidance, beeps, then records until `finish()`
/// (volume down): no silence end, no time limit (§5.10). `cancel()` (danger, stairs, backgrounding) returns
/// `.cancelled`. A second `listen` while one runs returns `.cancelled` at once. A denied permission returns
/// `.empty(noisy: false)`.
protocol VoiceInput: AnyObject {
    var isListening: Bool { get }
    func listen() async -> VoiceResult
    func finish()
    func cancel()
    /// Called on the main queue when the microphone or speech-recognition permission is denied.
    var onPermissionDenied: (() -> Void)? { get set }
    var permissionDenied: Bool { get }
    /// Asks for microphone + speech recognition up front. True when both are granted.
    func requestPermissions() async -> Bool
    /// Recognition hints, e.g. catalog brand names (§9 `contextualStrings`).
    var contextualStrings: [String] { get set }
}

protocol FeedbackOutput: AnyObject {
    /// High threat: vibrations first, then stop speech and say the alert line ("Cart ahead, 2 meters, steer to 1
    /// o'clock"). `vibrate` false (overhead obstacle, low threat): spoken only. Callable from any thread.
    func danger(_ label: String, steer: Steer, distance: Float?, vibrate: Bool)
    /// The danger vibration only (§5.3 step 5: still closing ~2 s later); speech is left alone. Any thread.
    func dangerPulse()
    func say(_ text: String, _ p: SpeechPriority)
    /// Stops and clears lines below stairs only; never cuts a danger or stairs line (§5.10).
    func stopSpeech()
    /// The stream stopped (volume down / stop): cut everything now, danger and stairs lines included.
    func stopAll()
    /// `.done` waits for the line in progress; beeps and ticks play now.
    func chime(_ t: Tone)
    /// Includes VoiceOver announcements; listening waits for false (§5.10).
    var isSpeaking: Bool { get }

    // Setup (§5.13).
    /// Narration is dropped at `.brief` (§5.15).
    var verbosity: Verbosity { get set }
    /// `AVSpeechUtterance.rate` scale.
    var speechRate: Float { get set }
    /// `AVSpeechSynthesisVoice.identifier`; nil = best English voice.
    var voiceIdentifier: String? { get set }
    var tonesEnabled: Bool { get set }
    var dangerHapticsEnabled: Bool { get set }
    /// Distances in alerts as steps (~0.7 m) instead of meters (§5.13).
    var distanceInSteps: Bool { get set }
}

/// Gemini's answer to something unusual the user said (§5.11).
struct GeminiAssist: Equatable {
    /// At most 2 short spoken sentences.
    let say: String
    /// A thing to look for, when the user asked to find something.
    let findItem: String?
}

/// Gemini item finder answer for one photo (owner decision).
struct ItemFinding: Equatable {
    /// Visible, with confidence ≥ 0.5 and a usable box.
    let found: Bool
    /// Contract space (upright portrait, normalized, top-left origin); only when found.
    let box: NormRect?
    /// 0...1.
    let confidence: Double
    /// 3–6 words: what Gemini sees ("blue mug on the desk").
    let description: String
    /// Not found: where to look, ≤ 12 words, clock positions relative to the photo; "" if none.
    let hint: String
    /// A lot of people close around the user.
    var crowded = false
}

/// Stills must be upright JPEGs (`NetworkJPEG.encode`). Errors are `NetworkError`.
/// Frames leave the phone only for these calls (assist, entrance pick, place check, and the item finder while
/// searching online).
protocol GeminiClient {
    /// While searching (~every 2 s): is the goal item in this photo (latest Stream B frame, upright, ~1024 px)?
    /// nil = no usable answer.
    func findItem(_ description: String, image: Data) async throws -> ItemFinding?
    /// Anything the offline router couldn't handle (question, unknown item, unmatched words) + one still + context.
    func assist(_ transcript: String, context: AssistContext, still: Data) async throws -> GeminiAssist
    /// nil = no entrance visible.
    func pickEntrance(still: Data) async throws -> EntrancePick?
    /// Grocery store or anywhere else, from 3 stills in one request. Once at app open (+ one low-confidence retry).
    func classifyPlace(stills: [Data]) async throws -> PlaceAnswer?
}

struct OnlineProduct {
    let info: ProductInfo
    let categoryTags: [String]
}

/// Open Food Facts. Throws `NetworkError` (`.rateLimited` = 10/min hit, not sent).
protocol ProductLookupClient {
    func search(_ words: String) async throws -> [OnlineProduct]
}

protocol SystemMonitor: AnyObject {
    /// Main queue. `.backgrounded` also fires for audio interruptions (call, Siri); `.foregrounded` when active again.
    var onEvent: ((SystemEvent) -> Void)? { get set }
    var isOnline: Bool { get }
    func start()
}
