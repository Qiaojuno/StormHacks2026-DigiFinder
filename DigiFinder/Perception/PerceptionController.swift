import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import Vision
import DigiFinderCore

/// Stream B perception (§3.5, §3.6): signs, aisles, destinations, doors, inside/outside, pointing, hold-up check,
/// positioning prompts and "What's around?".
///
/// Threads: one Stream B subscription feeds two serial queues (YOLO, Vision), each dropping frames while busy;
/// held-item stills run on their own queue. `onDepth` only stores the latest depth frame (no work on the capture
/// queue). `onEvent` is called from those queues, never the main thread.
final class PerceptionController: PerceptionService, @unchecked Sendable {
    var onEvent: ((SessionEvent) -> Void)?

    private let frames: FrameSource
    private let depth: DepthProvider
    private let motion: MotionService
    private let detector: ObjectDetector
    private let products: ProductDatabase?
    private let catalog: Catalog
    private let memory: ProductMemory

    private let synonyms: MatchingSynonyms
    private let wordToAisle: [String: String]
    /// Model label → aisle (catalog `visualClasses` resolved to the model's spelling; "Doughnut" is renamed "Donut" at load).
    private let classToAisle: [String: String]

    private let yoloQueue = DispatchQueue(label: "DigiFinder.Perception.yolo", qos: .userInitiated)
    private let visionQueue = DispatchQueue(label: "DigiFinder.Perception.vision", qos: .userInitiated)
    private let stillQueue = DispatchQueue(label: "DigiFinder.Perception.still", qos: .userInitiated)

    // MARK: Shared state (guarded by `lock`)
    private let lock = NSLock()
    private var started = false
    private var work = StreamWork()
    private var target = PerceptionTarget()
    private var yoloBusy = false
    private var visionBusy = false
    private var yoloGate = PerceptionGate()
    private var visionGate = PerceptionGate()
    private var latestDepth: DepthFrame?
    private var latestDepthAt = -Double.infinity
    private var latestFrame: FrameB?
    private var latestFrameAt = -Double.infinity
    private var latestSigns: [PerceptionSign] = []
    private var latestSignsAt = -Double.infinity
    private var holdUpGeneration = 0
    private var lastConfirmed: (product: ProductInfo, crop: CGImage?, time: Double)?
    private var debug = PerceptionDebugSnapshot()
    private var yoloMeter = PerceptionRateMeter()
    private var visionMeter = PerceptionRateMeter()
    /// Gemini item finder: a box to start tracking (nil = stop) for the target generation it belongs to, and
    /// whether a box is being tracked (or waits for the next frame).
    private var pendingTrack: (box: NormRect?, generation: Int)?
    private var trackingOn = false

    // MARK: YOLO-queue state
    private var outside = PerceptionOutsideDetector()

    // MARK: Vision-queue state
    private let textFast = TextRecognitionService(level: .fast)
    private let hands = HandPoseService()
    private let signage: SignageService
    private let pointingAnalyzer: PerceptionPointingAnalyzer
    private let doorFinder = PerceptionDoorFinder()
    private var seenGeneration = -1
    private var seenMode: PerceptionMode = .idle
    private var vote = AisleVote()
    private var lastVerdict: String?
    private var arrival = PerceptionArrivalTracker()
    private var positioning = PositioningAdvisor()
    private var lastSignsKey = ""
    /// Last "item seen" sent (vision queue).
    private var lastItem: PerceptionItemFinder.Sighting?
    private var lastItemEmit = -Double.infinity
    private var lastSignsEmit = -Double.infinity
    private var signsShown = false
    private var signsLastSeen = -Double.infinity
    private var lastDoorsKey = ""
    private var lastDoorsEmit = -Double.infinity
    private var doorsShown = false
    private var doorsLastSeen = -Double.infinity
    private var pointLines: [PerceptionTextRegion] = []
    private var pointRegions: [PerceptionProductRegion] = []
    private var lastPointText = -Double.infinity
    private var lastDoorText = -Double.infinity
    /// Wet floor sign text check while walking (owner decision), at most this often (s).
    private var lastWetFloorText = -Double.infinity
    static let wetFloorTextInterval = 1.0
    private var lastPointed: PointedProduct??
    private var lastPointedEmit = -Double.infinity
    private var hintRegion: NormRect?
    private var hint: ProductInfo?
    private var lastHintAt = -Double.infinity
    private var lastShelfDistanceAt = -Double.infinity
    /// Gemini item finder box, followed frame to frame.
    private let targetTracker = PerceptionTargetTracker()

    // MARK: Still-queue state
    private let labelChecker: PerceptionLabelChecker
    private let describeLock = NSLock()
    private let describeText = TextRecognitionService(level: .fast)

    private var streamTask: Task<Void, Never>?

    init(frames: FrameSource, depth: DepthProvider, motion: MotionService, detector: ObjectDetector,
         products: ProductDatabase?, catalog: Catalog, memory: ProductMemory) {
        self.frames = frames; self.depth = depth; self.motion = motion; self.detector = detector
        self.products = products; self.catalog = catalog; self.memory = memory

        synonyms = MatchingSynonyms(catalog.synonyms)
        wordToAisle = AisleVote.wordToAisle(catalog.aisles)
        signage = SignageService(aisles: catalog.aisles, destinations: catalog.destinations, synonyms: synonyms)
        pointingAnalyzer = PerceptionPointingAnalyzer(synonyms: synonyms)
        labelChecker = PerceptionLabelChecker(products: products, extraProducts: catalog.extraProducts, synonyms: synonyms)

        // Validate catalog visualClasses against the model's labels (§2: OIV7 spells some names its own way).
        let service = detector as? ObjectDetectionService
        let labels = service?.modelLabels ?? []
        var resolved = catalog.aisles
        var unknown: [String] = []
        if !labels.isEmpty {
            for (key, info) in catalog.aisles {
                var copy = info
                copy.visualClasses = info.visualClasses.compactMap { name in
                    if let m = ObjectDetectionService.resolve(name, in: labels) { return m }
                    if !unknown.contains(name) { unknown.append(name) }
                    return nil
                }
                resolved[key] = copy
            }
            if !unknown.isEmpty { print("[Perception] visualClasses not in the model: \(unknown.sorted())") }
        }
        classToAisle = AisleVote.classToAisle(resolved)
        // Aisle clues + household objects (found by their camera class in nearby searches).
        service?.allowContextLabels(Set(resolved.values.flatMap(\.visualClasses)).union(MatchingHousehold.allClasses))
        if let missing = service?.missingEssentialLabels, !missing.isEmpty {
            print("[Perception] essential labels not in the model: \(missing)")
        }
        debug.modelLoaded = service?.isModelLoaded ?? false
        debug.unknownVisualClasses = unknown.sorted()
    }

    deinit { streamTask?.cancel() }

    // MARK: - PerceptionService

    func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        // Safety lane shares onDepth: chain onto it and only store the latest frame here.
        let previous = frames.onDepth
        frames.onDepth = { [weak self] f in
            previous?(f)
            self?.storeLatest(f)
        }

        let stream = frames.makeStreamB()
        streamTask = Task.detached(priority: .userInitiated) { [weak self] in
            for await frame in stream {
                guard let self else { return }
                self.offer(frame)
            }
        }
    }

    func setWork(_ w: StreamWork) {
        lock.lock()
        let old = PerceptionMode(work)
        work = w
        let mode = PerceptionMode(w)
        debug.mode = mode
        var startHoldUp = false
        if mode != old {
            holdUpGeneration += 1
            startHoldUp = mode == .holdUp
        }
        let generation = holdUpGeneration
        lock.unlock()
        // Hold-up label check (full-res stills → text + barcode → confirm): off (owner decision).
        // if startHoldUp { runHoldUpLoop(generation) }
        _ = (startHoldUp, generation)
    }

    func setTarget(_ g: Goal?, candidates: [ProductInfo], destination: Destination?) {
        lock.lock()
        target = PerceptionTarget(goal: g, candidates: candidates, destination: destination, generation: target.generation + 1)
        lock.unlock()
    }

    // MARK: - Gemini item finder

    func latestUprightJPEG(maxWidth: Int) -> (jpeg: Data, frameTime: Double)? {
        activeLock.lock(); let on = active; activeLock.unlock()
        guard on else { return nil }
        lock.lock()
        let frame = now() - latestFrameAt <= 1 ? latestFrame : nil
        let time = latestFrameAt
        lock.unlock()
        guard let frame else { return nil }
        return autoreleasepool {
            guard let upright = CaptureImageRenderer.upright(frame.pixelBuffer, maxWidth: CGFloat(maxWidth)),
                  let jpeg = NetworkJPEG.encode(upright, maxDimension: 4096, quality: 0.6) else { return nil }
            return (jpeg, time)
        }
    }

    func trackTarget(_ box: NormRect?) {
        lock.lock()
        pendingTrack = (box, target.generation)
        trackingOn = box != nil
        lock.unlock()
    }

    var isTrackingTarget: Bool {
        lock.lock(); defer { lock.unlock() }
        return trackingOn
    }

    func describeSurroundings() -> String {
        let t = now()
        lock.lock()
        var signs = t - latestSignsAt <= 2 ? latestSigns : []
        let frame = t - latestFrameAt <= 1.5 ? latestFrame : nil
        let depthFrame = t - latestDepthAt <= 0.5 ? latestDepth : nil
        let goal = target.goal
        lock.unlock()

        let geometry = frame.map { PerceptionFrameGeometry($0) }
        if signs.isEmpty, let frame, let geometry {
            // Signs aren't being read right now: one quick text pass on the latest frame.
            describeLock.lock()
            let handler = VNImageRequestHandler(cvPixelBuffer: frame.pixelBuffer, orientation: CaptureOrientation.visionOrientation, options: [:])
            if (try? handler.perform([describeText.request])) != nil {
                signs = signage.analyze(describeText.results(), goal: goal, geometry: geometry).signs
            }
            describeLock.unlock()
        }
        let depthAt: (NormPoint) -> Float? = { [depth] p in depthFrame.flatMap { depth.distance(at: p, $0) } }
        return PerceptionSurroundings.describe(signs: signs, detections: detector.latest, geometry: geometry, depthAt: depthAt)
    }

    // MARK: - Memory and debug

    /// Saves the last confirmed label crop to product memory (the runner calls this for `Effect.remember`).
    func remember(_ p: ProductInfo) {
        lock.lock()
        let last = lastConfirmed
        lock.unlock()
        guard let last, let crop = last.crop else { return }
        let same = last.product == p
            || (!p.code.isEmpty && normalizeBarcode(p.code) == normalizeBarcode(last.product.code))
            || normalizeText("\(p.brand ?? "") \(p.name)") == normalizeText("\(last.product.brand ?? "") \(last.product.name)")
        guard same || now() - last.time < 120 else { return }
        memory.save(p, crop: crop)
    }

    /// Debug overlay values (boxes, OCR regions, hand point), safe from any thread.
    var debugSnapshot: PerceptionDebugSnapshot {
        lock.lock(); defer { lock.unlock() }
        return debug
    }

    // MARK: - Frame intake

    private func storeLatest(_ f: DepthFrame) {
        let t = now()
        lock.lock()
        latestDepth = f
        latestDepthAt = t
        lock.unlock()
    }

    /// The stream (owner decision): when off, frames are dropped and nothing is reported.
    private let activeLock = NSLock()
    private var active = true

    func setActive(_ on: Bool) {
        activeLock.lock(); active = on; activeLock.unlock()
        if !on { trackTarget(nil) }                      // no stale box when the stream comes back
    }

    private func offer(_ f: FrameB) {
        activeLock.lock(); let on = active; activeLock.unlock()
        guard on else { return }
        let t = now()
        lock.lock()
        let mode = PerceptionMode(work)
        let yoloFPS = Double(max(work.yoloFPS, 0))
        let runYOLO = !yoloBusy && yoloGate.admit(t, fps: yoloFPS)
        if runYOLO { yoloBusy = true }
        let runVision = !visionBusy && visionGate.admit(t, fps: Self.visionFPS(mode, yoloFPS: yoloFPS))
        if runVision { visionBusy = true }
        // Every frame is the latest for Gemini photos, also in the hold-up step where Vision doesn't run.
        latestFrame = f
        latestFrameAt = t
        lock.unlock()

        if runYOLO {
            yoloQueue.async { [weak self] in
                guard let self else { return }
                self.runYOLO(f)
                self.lock.lock(); self.yoloBusy = false; self.lock.unlock()
            }
        }
        if runVision {
            visionQueue.async { [weak self] in
                guard let self else { return }
                autoreleasepool { self.runVision(f) }
                self.lock.lock(); self.visionBusy = false; self.lock.unlock()
            }
        }
    }

    /// Vision pass rate per mode; a lowered YOLO rate (thermal, §5.16) slows OCR too.
    static func visionFPS(_ mode: PerceptionMode, yoloFPS: Double) -> Double {
        let base: Double
        switch mode {
        case .idle: base = 2
        case .signs: base = 8
        case .pointing: base = 15
        case .holdUp: base = 0
        }
        guard base > 0 else { return 0 }
        if mode == .idle && yoloFPS <= 0 { return 0 }
        let scale = min(1, max(yoloFPS, 0) / 10)
        return max(mode == .idle ? 1 : 2, base * scale)
    }

    // MARK: - YOLO pass

    private func runYOLO(_ f: FrameB) {
        let detections = detector.detect(f)
        let t = now()
        // OWNER DECISION: outside detection off (YOLO is only for obstacles).
        // let change = outside.update(detections, time: t)
        let change: Bool? = nil
        lock.lock()
        yoloMeter.tick(t)
        debug.detections = detections
        debug.yoloFPS = yoloMeter.fps
        debug.isOutside = outside.isOutside
        lock.unlock()
        if let change { emit(.outside(change)) }
    }

    // MARK: - Vision pass

    private func runVision(_ f: FrameB) {
        let t = now()
        lock.lock()
        let mode = PerceptionMode(work)
        let target = self.target
        let depthFrame = t - latestDepthAt <= 0.5 ? latestDepth : nil
        visionMeter.tick(t)
        let trackSeed = pendingTrack
        pendingTrack = nil
        lock.unlock()

        if target.generation != seenGeneration { resetForTarget(); seenGeneration = target.generation }
        if mode != seenMode { resetForMode(from: seenMode, to: mode); seenMode = mode }
        if let seed = trackSeed {
            if let box = seed.box, seed.generation == target.generation { targetTracker.seed(box) }
            if !targetTracker.isTracking || seed.box == nil || seed.generation != target.generation { stopTracking() }
        }
        if (mode != .signs || target.goal == nil) && targetTracker.isTracking { stopTracking() }
        guard mode != .holdUp else { return }

        let geometry = PerceptionFrameGeometry(f)
        let detections = detector.latest
        let doorInView = detections.contains { $0.label == "Door" }

        // OWNER DECISION: on-device item search is commented out; items are found only by Gemini (+ the tracker below).
        // Text reading (signs, door text, labels) and hand pose (pointing) are off.
        // let doText: Bool
        // switch mode {
        // case .signs: doText = true
        // case .pointing: doText = t - lastPointText >= 0.2
        // case .idle: doText = doorInView && t - lastDoorText >= 0.5
        // case .holdUp: doText = false
        // }
        let doText = false
        _ = doorInView
        var requests: [VNRequest] = []
        // Wet floor sign (owner decision): the text reader, ~1 Hz while walking. YOLO has no class for it.
        let wetFloorText = motion.isWalking && t - lastWetFloorText >= Self.wetFloorTextInterval
        if wetFloorText {
            lastWetFloorText = t
            textFast.setRegion(nil)
            requests.append(textFast.request)
        }
        // if doText { textFast.setRegion(nil); requests.append(textFast.request) }
        // if mode == .pointing { requests.append(hands.request) }
        var lines: [PerceptionTextRegion] = []
        var hand: PerceptionHandPoint?
        if !requests.isEmpty {
            let handler = VNImageRequestHandler(cvPixelBuffer: f.pixelBuffer, orientation: CaptureOrientation.visionOrientation, options: [:])
            if (try? handler.perform(requests)) != nil {
                if doText || wetFloorText { lines = textFast.results() }
                if mode == .pointing { hand = hands.result() }
            }
        }
        if doText && mode == .idle { lastDoorText = t }
        if wetFloorText, isWetFloorSignText(lines.map(\.text)) {
            let words = ["wet", "floor", "caution", "piso", "sol", "plancher"]
            let line = lines.first { l in words.contains { l.text.lowercased().contains($0) } } ?? lines.first
            if let b = line?.box { emit(.wetFloorSign(clock: geometry.clock(b.x + b.width / 2))) }
        }
        let depthAt: (NormPoint) -> Float? = { [depth] p in depthFrame.flatMap { depth.distance(at: p, $0) } }
        let heading = -motion.yawDegrees
        let steps = motion.steps

        var signs: [PerceptionSign] = []
        var pointedRegion: PerceptionProductRegion?
        var targetRegion: PerceptionProductRegion?
        var itemBox: NormRect?
        var doors: [PerceptionDoorFinder.Door] = []

        switch mode {
        case .signs:
            // Sign reading, aisle signs and sign memory: off (owner decision).
            // let result = signage.analyze(lines, goal: target.goal, geometry: geometry)
            // signs = result.signs
            // handleSigns(signs, geometry: geometry, target: target, depthAt: depthAt, heading: heading, steps: steps, time: t)
            // Look for the item itself (every search starts by looking; nearby mode only looks), and follow the
            // Gemini item finder's box. Whichever sees it reports; both are the same `.itemSeen`.
            // Owner decision: items are found only by Gemini (tracked here); on-device detection is for obstacles.
            var sighting: PerceptionItemFinder.Sighting?
            switch targetTracker.update(f.pixelBuffer) {
            case .tracked(let box, _)?:
                if sighting == nil {
                    let c = box.center
                    sighting = PerceptionItemFinder.Sighting(box: box, clock: geometry.clock(c.x), distance: depthAt(c))
                }
            case .lost?:
                stopTracking()
            case nil:
                break
            }
            if let s = sighting {
                emitItem(s, time: t)
                itemBox = s.box
            }
            // Aisle vote (shelf labels + YOLO classes) and door finding: off (owner decision).
            // if target.goal != nil { updateVote(labels: result.labels, detections: detections) }
            // doors = doorFinder.doors(detections: detections, text: lines, geometry: geometry, depthAt: depthAt)
            // emitDoors(doors, time: t)
            _ = detections
        case .idle:
            // Door finding: off (owner decision).
            // doors = doorFinder.doors(detections: detections, text: lines, geometry: geometry, depthAt: depthAt)
            // emitDoors(doors, time: t)
            break
        case .pointing:
            // Pointing (hand pose + label under the fingertip + product memory): off (owner decision).
            // if doText {
            //     pointLines = lines
            //     pointRegions = ProductRegions.regions(from: lines)
            //     lastPointText = t
            // }
            // if let hand {
            //     let r = pointingAnalyzer.analyze(spot: hand.spot, regions: pointRegions, goal: target.goal,
            //                                      candidates: target.candidates, wordSearch: target.isWordSearch(catalog.aisles),
            //                                      hint: memoryHint(f, spot: hand.spot, time: t))
            //     pointedRegion = r.pointedRegion
            //     targetRegion = r.target
            //     emitPointed(r.pointed, time: t)
            // }
            break
        case .holdUp:
            break
        }

        // Arrival at an aisle / destination by dead reckoning from signs: off (owner decision).
        // if mode != .pointing, target.goal != nil || target.destination != nil {
        //     let kind: PerceptionArrivalTracker.Kind = target.destination != nil ? .destination : .aisle
        //     if let clock = arrival.update(kind: kind, heading: heading, steps: steps, time: t) {
        //         if kind == .destination {
        //             emit(.arrivedAtDestination)
        //         } else {
        //             emit(.arrivedAtAisle(clock: clock))
        //             vote.reset(); lastVerdict = nil
        //         }
        //     }
        // }
        _ = (heading, steps)

        let luma = PerceptionImageTools.meanLuma(f.pixelBuffer)
        let shelfDistance = mode == .pointing ? depthAt(NormPoint(x: 0.5, y: 0.5)) : nil
        let input = PositioningAdvisor.Input(
            mode: mode, time: t, luma: luma, gravity: motion.gravity, rotationRate: motion.rotationRate,
            handVisible: hand != nil, lines: mode == .pointing ? pointLines : lines, pointedRegion: pointedRegion,
            shelfDistance: shelfDistance)
        if let hint = positioning.advise(input) { emit(.positioning(hint)) }
        // "The shelf is about one step ahead." (LiDAR only; at most every ~2 s while pointing).
        if let d = shelfDistance, d.isFinite, d > 0, t - lastShelfDistanceAt >= 2 {
            lastShelfDistanceAt = t
            emit(.shelfDistance(d))
        }

        lock.lock()
        debug.visionFPS = visionMeter.fps
        debug.textRegions = mode == .pointing ? pointLines : lines
        if mode == .signs {
            debug.signs = signs.map(\.sign)
            latestSigns = signs
            latestSignsAt = t
        }
        debug.handTip = hand?.tip
        debug.pointedSpot = hand?.spot
        debug.pointedRegion = pointedRegion?.box
        debug.targetRegion = targetRegion?.box ?? itemBox
        debug.trackedBox = targetTracker.box
        debug.trackConfidence = targetTracker.confidence
        if mode != .pointing { debug.doors = doors.map(\.observation) }
        lock.unlock()
    }

    /// "Item seen" on a new direction, a distance change, or every ~1 s while it stays in view.
    private func emitItem(_ s: PerceptionItemFinder.Sighting, time t: Double) {
        let moved = s.clock != lastItem?.clock
            || abs((s.distance ?? -1) - (lastItem?.distance ?? -1)) > 0.3
        guard moved || t - lastItemEmit >= 1 else { return }
        lastItem = s
        lastItemEmit = t
        emit(.itemSeen(clock: s.clock, distance: s.distance))
    }

    /// Tracking ended on the vision queue (lost, target or mode change): the runner's finder asks Gemini again.
    private func stopTracking() {
        targetTracker.stop()
        lock.lock()
        if pendingTrack == nil { trackingOn = false }    // a newer box from the finder wins
        debug.trackedBox = nil
        lock.unlock()
    }

    private func resetForTarget() {
        if targetTracker.isTracking { stopTracking() }
        lastItem = nil; lastItemEmit = -.infinity
        vote.reset(); lastVerdict = nil
        arrival.reset()
        lastSignsKey = ""; lastPointed = nil; lastPointedEmit = -.infinity
        hint = nil; hintRegion = nil
    }

    private func resetForMode(from old: PerceptionMode, to new: PerceptionMode) {
        positioning.reset()
        lastPointed = nil; lastPointedEmit = -.infinity
        pointLines = []; pointRegions = []; lastPointText = -.infinity
        if new == .signs && old != .signs { vote.reset(); lastVerdict = nil; lastSignsKey = "" }
    }

    // MARK: Signs, vote, arrival

    private func handleSigns(_ signs: [PerceptionSign], geometry: PerceptionFrameGeometry, target: PerceptionTarget,
                             depthAt: (NormPoint) -> Float?, heading: Double, steps: Int, time t: Double) {
        if !signs.isEmpty {
            signsLastSeen = t
            let key = signs.map { "\($0.key)@\($0.sign.clock)" }.joined(separator: "|")
            if (key != lastSignsKey && t - lastSignsEmit >= 0.25) || t - lastSignsEmit >= 3 {
                lastSignsKey = key; lastSignsEmit = t; signsShown = true
                emit(.signs(signs.map { s in
                    var sign = s.sign
                    sign.distance = signDistance(s, geometry: geometry, depthAt: depthAt)
                    return sign
                }))
            }
        } else if signsShown && t - signsLastSeen >= 1.5 {
            signsShown = false; lastSignsKey = ""; lastSignsEmit = t
            emit(.signs([]))
        }

        // Remember the target sign for arrival by dead reckoning.
        let matching: [PerceptionSign]
        if let d = target.destination {
            matching = signs.filter { $0.destination == d }
        } else if let g = target.goal {
            matching = signs.filter {
                signMatches($0.sign, goal: g, catalog: catalog.aisles, synonyms: synonyms)
                    || (g.category != nil && $0.aisle == g.category)
            }
        } else {
            matching = []
        }
        guard let best = matching.min(by: { abs($0.degreesRight) < abs($1.degreesRight) }) else { return }
        let distance = signDistance(best, geometry: geometry, depthAt: depthAt).map(Double.init)
        arrival.sighted(key: best.key, bearing: best.degreesRight, distance: distance ?? 8, heading: heading, steps: steps, time: t)
    }

    /// LiDAR at the sign's center, else estimated from the letter size (~0.12 m tall), clamped to 1.5–30 m.
    private func signDistance(_ s: PerceptionSign, geometry: PerceptionFrameGeometry,
                              depthAt: (NormPoint) -> Float?) -> Float? {
        if let d = depthAt(s.box.center) { return d }
        guard let d = geometry.distance(boxHeight: s.lineHeight, objectHeight: 0.12) else { return nil }
        return min(max(Float(d), 1.5), 30)
    }

    private func updateVote(labels: [PerceptionTextRegion], detections: [Detection]) {
        for l in labels { vote.addText(l.text, wordToAisle: wordToAisle) }
        for d in detections where d.confidence >= 0.4 {
            if let id = d.trackID { vote.addVisual(trackID: id, yoloClass: d.label, classToAisle: classToAisle) }
        }
        guard let v = vote.verdict(), v != lastVerdict else { return }
        lastVerdict = v
        emit(.aisleVerdict(v, evidence: Array(vote.evidence(for: v).prefix(4))))
    }

    // MARK: Doors

    private func emitDoors(_ doors: [PerceptionDoorFinder.Door], time t: Double) {
        if !doors.isEmpty {
            doorsLastSeen = t
            let key = doors.map { d in
                "\(d.observation.clock)-\(d.observation.label)-\(Int((d.observation.distance ?? -1).rounded()))"
            }.joined(separator: "|")
            if (key != lastDoorsKey && t - lastDoorsEmit >= 0.5) || t - lastDoorsEmit >= 2 {
                lastDoorsKey = key; lastDoorsEmit = t; doorsShown = true
                emit(.doors(doors.map(\.observation)))
            }
        } else if doorsShown && t - doorsLastSeen >= 1.5 {
            doorsShown = false; lastDoorsKey = ""; lastDoorsEmit = t
            emit(.doors([]))
        }
    }

    // MARK: Pointing

    private func emitPointed(_ p: PointedProduct?, time t: Double) {
        guard t - lastPointedEmit >= 1 else { return }
        let changed = lastPointed.map { $0 != p } ?? true
        guard changed || t - lastPointedEmit >= 3 else { return }
        lastPointed = .some(p)
        lastPointedEmit = t
        emit(.pointed(p))
    }

    /// Memory hint for the region under the fingertip, at most once per second (§5.14; a hint, never final).
    private func memoryHint(_ f: FrameB, spot: NormPoint, time t: Double) -> ProductInfo? {
        guard memory.count > 0, let region = ProductRegions.region(at: spot, in: pointRegions) else { return nil }
        if t - lastHintAt < 1 { return (hintRegion?.iou(region.box) ?? 0) > 0.3 ? hint : nil }
        lastHintAt = t
        hintRegion = region.box
        hint = PerceptionImageTools.uprightCrop(f.pixelBuffer, rect: region.box).flatMap { memory.hint(for: $0) }
        return hint
    }

    // MARK: - Hold-up check (~2/s)

    private func holdUpActive(_ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return holdUpGeneration == generation && PerceptionMode(work) == .holdUp
    }

    private func runHoldUpLoop(_ generation: Int) {
        Task.detached(priority: .userInitiated) { [weak self] in
            var lastUnclear = ProcessInfo.processInfo.systemUptime
            var lastResult: (product: ProductInfo, isGoal: Bool, time: Double)?
            while let self, self.holdUpActive(generation) {
                let begin = self.now()
                var pause = 0.5
                if let still = try? await self.frames.captureStill() {
                    let outcome = await self.checkLabel(still)
                    guard self.holdUpActive(generation) else { break }
                    let t = self.now()
                    if let o = outcome {
                        lastUnclear = t
                        self.lock.withLock { self.lastConfirmed = (o.product, o.crop, t) }
                        let repeated = lastResult.map { $0.product == o.product && $0.isGoal == o.isGoal && t - $0.time < 4 } ?? false
                        if !repeated {
                            lastResult = (o.product, o.isGoal, t)
                            self.emit(.confirmed(o.product, isGoal: o.isGoal))
                        }
                        pause = 1.0
                    } else if t - lastUnclear >= 4 {
                        // Still unclear after ~4 s (and every ~4 s after): the flow says "Turn it slowly." etc.
                        lastUnclear = t
                        self.emit(.confirmed(nil, isGoal: false))
                    }
                } else {
                    pause = 1.0                                  // no camera (Simulator) or a failed still
                }
                let wait = max(0.1, pause - (self.now() - begin))
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private func checkLabel(_ still: CGImage) async -> PerceptionLabelChecker.Outcome? {
        let target = lock.withLock { self.target }
        return await withCheckedContinuation { (c: CheckedContinuation<PerceptionLabelChecker.Outcome?, Never>) in
            stillQueue.async { [weak self] in
                guard let self else { c.resume(returning: nil); return }
                let o = autoreleasepool {
                    self.labelChecker.check(still, goal: target.goal, candidates: target.candidates,
                                            wordSearch: target.isWordSearch(self.catalog.aisles), barcodesOn: true)   // passive: always look
                }
                self.lock.lock()
                self.debug.heldLabel = self.labelChecker.lastLines.map(\.text).joined(separator: " ")
                self.debug.heldBarcode = self.labelChecker.lastBarcode
                self.debug.textRegions = self.labelChecker.lastLines
                self.lock.unlock()
                c.resume(returning: o)
            }
        }
    }

    // MARK: - Helpers

    private func emit(_ e: SessionEvent) {
        lock.lock()
        debug.lastEvent = "\(e)"
        lock.unlock()
        onEvent?(e)
    }

    private func now() -> Double { ProcessInfo.processInfo.systemUptime }
}
