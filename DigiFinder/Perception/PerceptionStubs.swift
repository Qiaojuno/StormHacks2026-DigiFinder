// Wave 1 compiling stubs. The Perception agent replaces these (one file per type).
import CoreGraphics
import Foundation
import DigiFinderCore

/// YOLOv8s-oiv7 on Stream B, loaded by URL (the app builds without the model).
final class ObjectDetectionService: ObjectDetector {
    private(set) var latest: [Detection] = []
    func detect(_ f: FrameB) -> [Detection] { [] }
}

/// Stream B perception: signs, aisles, doors, pointing, confirmation, positioning, "What's around?".
final class PerceptionController: PerceptionService {
    var onEvent: ((SessionEvent) -> Void)?
    private let frames: FrameSource
    private let depth: DepthProvider
    private let motion: MotionService
    private let detector: ObjectDetector
    private let products: ProductDatabase?
    private let catalog: Catalog
    private let memory: ProductMemory

    init(frames: FrameSource, depth: DepthProvider, motion: MotionService, detector: ObjectDetector,
         products: ProductDatabase?, catalog: Catalog, memory: ProductMemory) {
        self.frames = frames; self.depth = depth; self.motion = motion; self.detector = detector
        self.products = products; self.catalog = catalog; self.memory = memory
    }

    func start() {}
    func setWork(_ w: StreamWork) {}
    func setTarget(_ g: Goal?, candidates: [ProductInfo], destination: Destination?) {}
    func describeSurroundings() -> String { "" }
}

final class TextRecognitionService {}
final class HandPoseService {}
final class BarcodeService {}
final class SignageService {}
final class ProductRegions {}
final class PositioningAdvisor {}
