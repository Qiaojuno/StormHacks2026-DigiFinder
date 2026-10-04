// Wave 1 compiling stubs. The Safety agent replaces these (one file per type).
import Foundation
import DigiFinderCore

/// Danger + stairs on Stream A (safety lane, off the main thread, no network).
final class SafetyController: SafetyService {
    var onEvent: ((SessionEvent) -> Void)?
    private let frames: FrameSource
    private let depth: DepthProvider
    private let motion: MotionService
    private let detector: ObjectDetector
    private let feedback: FeedbackOutput
    private let voice: VoiceInput

    init(frames: FrameSource, depth: DepthProvider, motion: MotionService, detector: ObjectDetector,
         feedback: FeedbackOutput, voice: VoiceInput) {
        self.frames = frames; self.depth = depth; self.motion = motion
        self.detector = detector; self.feedback = feedback; self.voice = voice
    }

    func start() {}
    func setWork(_ w: StreamWork) {}
}

/// Corridor, TTC, emergency rule and steer (wraps Core geometry).
final class DangerDetector {}

/// Floor profile → stairs notice (spoken only).
final class StairsDetector {}

/// Tracks YOLO boxes and corridor distance over time.
final class SafetyTracker {}
