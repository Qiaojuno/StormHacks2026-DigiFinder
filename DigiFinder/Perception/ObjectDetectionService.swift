import CoreML
import CoreVideo
import Foundation
import ImageIO
import Vision
import DigiFinderCore

/// YOLOv8s-oiv7 on Stream B (§2, §9 Vision requests), loaded by URL so the app builds and runs without the model
/// (no model → no labels: `detect` returns [] and danger says "Obstacle ahead").
/// Thread-safe: `detect` may be called from any queue (calls are serialized); `latest` never blocks for long,
/// so the safety lane can read it without waiting.
final class ObjectDetectionService: ObjectDetector, @unchecked Sendable {
    /// Minimum class confidence kept.
    static let minConfidence: Float = 0.3
    /// The only classes the app uses (guide-dog job). The model knows 601 Open Images classes; everything else
    /// ("Building", "Office building", furniture, clothing…) is dropped right after detection, so danger, stairs,
    /// doors, "What's around?" and the debug overlay never see it. Aisle clues (catalog `visualClasses`) are added
    /// at runtime with `allowContextLabels`.
    /// Owner decision: on-device object detection is ONLY for obstacles. Items are found by Gemini.
    static let essentialLabels: Set<String> = [
        // People and things that move toward the user (danger labels).
        "Person", "Man", "Woman", "Boy", "Girl", "Cart", "Wheelchair", "Bicycle", "Dog", "Car",
        // Stairs confirmation for the stairs check (safety).
        "Stairs",
    ]

    /// Model names renamed at load, so speech, categories.json and aisle_map.json all use one spelling
    /// (the OIV7 export says "Doughnut"; the app says "Donut").
    static let renamed: [String: String] = ["Doughnut": "Donut"]
    static func displayName(_ modelLabel: String) -> String { renamed[modelLabel] ?? modelLabel }

    /// OIV7 names that differ from common spellings used in categories.json / aisle_map.json.
    static let labelAliases: [String: [String]] = [
        "donut": ["doughnut"], "doughnut": ["donut"],
        "shopping cart": ["cart"], "trolley": ["cart"],
    ]

    /// Class names of the loaded model (empty without the model).
    let modelLabels: [String]
    var isModelLoaded: Bool { request != nil }

    private let request: VNCoreMLRequest?
    private let detectLock = NSLock()
    private let stateLock = NSLock()
    private var tracker = PerceptionObjectTracker()
    private var latestDetections: [Detection] = []
    /// Essentials + aisle clues (guarded by `stateLock`).
    private var allowed = ObjectDetectionService.essentialLabels
    private var latestSeconds: Double = 0

    init(bundle: Bundle = .main) {
        var labels: [String] = []
        var req: VNCoreMLRequest?
        if let url = bundle.url(forResource: "yolov8s-oiv7", withExtension: "mlmodelc") {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            if let ml = try? MLModel(contentsOf: url, configuration: config), let vn = try? VNCoreMLModel(for: ml) {
                labels = Self.classLabels(of: ml).map(Self.displayName)
                let inputs = ml.modelDescription.inputDescriptionsByName
                if inputs["iouThreshold"] != nil || inputs["confidenceThreshold"] != nil {
                    vn.featureProvider = try? MLDictionaryFeatureProvider(dictionary: [
                        "iouThreshold": MLFeatureValue(double: 0.45),
                        "confidenceThreshold": MLFeatureValue(double: Double(Self.minConfidence)),
                    ])
                }
                let r = VNCoreMLRequest(model: vn)
                r.imageCropAndScaleOption = .scaleFill
                req = r
            }
        }
        request = req
        modelLabels = labels
    }

    /// Adds the aisle-clue classes (catalog `visualClasses`, already resolved to model names) to the allowlist.
    /// Kept for compatibility; obstacle classes only (owner decision), so extra labels are ignored.
    func allowContextLabels(_ labels: Set<String>) {
        stateLock.lock(); allowed = Self.essentialLabels; stateLock.unlock()
    }

    /// Essential labels the loaded model doesn't have (logged at start; empty without the model).
    var missingEssentialLabels: [String] {
        modelLabels.isEmpty ? [] : Self.essentialLabels.subtracting(modelLabels).sorted()
    }

    /// Latest tracked detections (contract space). Empty without the model.
    var latest: [Detection] {
        stateLock.lock(); defer { stateLock.unlock() }
        return latestDetections
    }

    /// Host-clock seconds of the frame behind `latest` (0 before the first detection).
    var latestTime: Double {
        stateLock.lock(); defer { stateLock.unlock() }
        return latestSeconds
    }

    /// Runs YOLO on one frame, updates `latest` (with track IDs) and returns it.
    func detect(_ f: FrameB) -> [Detection] {
        guard let request else { return [] }
        detectLock.lock()
        defer { detectLock.unlock() }
        let handler = VNImageRequestHandler(cvPixelBuffer: f.pixelBuffer, orientation: CaptureOrientation.visionOrientation, options: [:])
        do { try handler.perform([request]) } catch { return latest }
        let raw: [Detection] = (request.results ?? []).compactMap { obs in
            guard let o = obs as? VNRecognizedObjectObservation, let top = o.labels.first,
                  top.confidence >= Self.minConfidence else { return nil }
            let b = o.boundingBox
            let box = Geometry.fromVision(NormRect(x: Double(b.origin.x), y: Double(b.origin.y),
                                                   width: Double(b.width), height: Double(b.height))).clamped()
            guard box.area > 0 else { return nil }
            return Detection(label: Self.displayName(top.identifier), confidence: top.confidence, box: box)
        }
        let t = f.time.isValid ? f.time.seconds : ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        let kept = raw.filter { allowed.contains($0.label) }
        let tracked = tracker.update(kept, time: t)
        latestDetections = tracked
        latestSeconds = t
        stateLock.unlock()
        return tracked
    }

    /// The model's spelling of a class name (exact, then case/punctuation-insensitive, then known aliases).
    func modelLabel(for name: String) -> String? {
        Self.resolve(name, in: modelLabels)
    }

    static func resolve(_ name: String, in labels: [String]) -> String? {
        if labels.contains(name) { return name }
        let wanted = normalizeText(name)
        if let hit = labels.first(where: { normalizeText($0) == wanted }) { return hit }
        for alias in labelAliases[wanted] ?? [] {
            if let hit = labels.first(where: { normalizeText($0) == alias }) { return hit }
        }
        return nil
    }

    /// Class labels from the model description, else from Ultralytics' "names" metadata (`{0: 'Accordion', ...}`).
    private static func classLabels(of model: MLModel) -> [String] {
        if let labels = model.modelDescription.classLabels as? [String], !labels.isEmpty { return labels }
        let meta = model.modelDescription.metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: String]
        guard let names = meta?["names"] else { return [] }
        var out: [String] = []
        var i = names.startIndex
        while let colon = names[i...].firstIndex(of: ":") {
            var j = names.index(after: colon)
            while j < names.endIndex, names[j] == " " { j = names.index(after: j) }
            guard j < names.endIndex, names[j] == "'" || names[j] == "\"" else { i = names.index(after: colon); continue }
            let quote = names[j]
            let start = names.index(after: j)
            guard let end = names[start...].firstIndex(of: quote) else { break }
            out.append(String(names[start..<end]))
            i = names.index(after: end)
        }
        return out
    }
}
