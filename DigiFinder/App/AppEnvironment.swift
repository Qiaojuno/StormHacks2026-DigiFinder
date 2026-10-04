import Foundation
import DigiFinderCore

/// Dependency container (§3.4).
struct AppEnvironment {
    let frames: FrameSource
    let depth: DepthProvider
    let motion: MotionService
    let detector: ObjectDetector
    let safety: SafetyService
    let perception: PerceptionService
    let voice: VoiceInput
    let feedback: FeedbackOutput
    let products: ProductDatabase?
    let catalog: Catalog
    let memory: ProductMemory
    /// nil without Secrets.plist.
    let gemini: GeminiClient?
    let lookup: ProductLookupClient
    let system: SystemMonitor

    static func current() -> AppEnvironment {
        #if targetEnvironment(simulator)
        return simulator()
        #else
        return live()
        #endif
    }

    /// LiDAR+ultra-wide → ultra-wide → wide → unavailable (`CaptureFactory` picks the frame source and the matching
    /// depth provider; LiDAR shares the Stream B calibration). On-device speech recognition.
    static func live() -> AppEnvironment {
        let (frames, depth) = CaptureFactory.makeBest()
        return make(frames: frames, depth: depth, voice: SpeechVoiceInput())
    }

    /// NoCameraSource ("Camera unavailable") + typed input; the debug panel drives the session through the runner.
    static func simulator() -> AppEnvironment {
        make(frames: NoCameraSource(reason: "Simulator"), depth: EstimatedDepthProvider(), voice: TypedVoiceInput())
    }

    private static func make(frames: FrameSource, depth: DepthProvider, voice: VoiceInput) -> AppEnvironment {
        let secrets = NetworkSecrets.load()
        let motion = DeviceMotionService()
        let detector = ObjectDetectionService()
        let feedback = SpeechFeedback(haptics: HapticsService(), tones: ToneService())
        let catalog = Catalog.load()
        let products = Bundle.main.url(forResource: "products", withExtension: "sqlite").flatMap { ProductDatabase(url: $0) }
        let memory = ProductMemory()
        var gemini: GeminiClient?
        if secrets.hasGemini, let model = secrets.geminiModel {
            gemini = GeminiRESTClient(apiKeys: secrets.geminiKeys, model: model)
        }
        return AppEnvironment(
            frames: frames, depth: depth, motion: motion, detector: detector,
            safety: SafetyController(frames: frames, depth: depth, motion: motion, detector: detector,
                                     feedback: feedback, voice: voice),
            perception: PerceptionController(frames: frames, depth: depth, motion: motion, detector: detector,
                                             products: products, catalog: catalog, memory: memory),
            voice: voice, feedback: feedback, products: products, catalog: catalog, memory: memory,
            gemini: gemini, lookup: OpenFoodFactsClient(contact: secrets.offContact), system: DeviceSystemMonitor())
    }
}
