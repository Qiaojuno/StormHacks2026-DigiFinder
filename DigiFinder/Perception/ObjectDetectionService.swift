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
    private var latestSeconds: Double = 0

    init(bundle: Bundle = .main) {
        var labels: [String] = []
        var req: VNCoreMLRequest?
        if let url = bundle.url(forResource: "yolov8s-oiv7", withExtension: "mlmodelc") {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            if let ml = try? MLModel(contentsOf: url, configuration: config), let vn = try? VNCoreMLModel(for: ml) {
                labels = Self.classLabels(of: ml)
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
        let handler = VNImageRequestHandler(cvPixelBuffer: f.pixelBuffer, orientation: .right, options: [:])
        do { try handler.perform([request]) } catch { return latest }
        let raw: [Detection] = (request.results ?? []).compactMap { obs in
            guard let o = obs as? VNRecognizedObjectObservation, let top = o.labels.first,
                  top.confidence >= Self.minConfidence else { return nil }
            let b = o.boundingBox
            let box = Geometry.fromVision(NormRect(x: Double(b.origin.x), y: Double(b.origin.y),
                                                   width: Double(b.width), height: Double(b.height))).clamped()
            guard box.area > 0 else { return nil }
            return Detection(label: top.identifier, confidence: top.confidence, box: box)
        }
        let t = f.time.isValid ? f.time.seconds : ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        let tracked = tracker.update(raw, time: t)
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
