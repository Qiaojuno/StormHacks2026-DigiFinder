import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import DigiFinderCore

/// Shared plumbing for the camera-backed frame sources: permission, start/stop on a session queue, stills,
/// rate caps and thermal hooks, interruptions, idle timer and debug snapshots. Subclasses only build the session
/// (`configureSession()`, called once on the session queue after permission is granted).
///
/// Queues: session (configuration, start/stop, stills), Stream B video, depth (= the capture queue `onDepth`
/// runs on), debug 1× video. Each delegate queue is serial; late frames are discarded while a consumer is busy.
class CaptureSessionSource: NSObject, FrameSource, @unchecked Sendable {
    let sessionQueue = DispatchQueue(label: "DigiFinder.capture.session", qos: .userInitiated)
    let videoQueue = DispatchQueue(label: "DigiFinder.capture.streamB", qos: .userInitiated)
    let depthQueue = DispatchQueue(label: "DigiFinder.capture.depth", qos: .userInteractive)
    let debugQueue = DispatchQueue(label: "DigiFinder.capture.debug", qos: .utility)

    let calibration: CaptureCalibration
    let streamBRelay: CaptureStreamBRelay
    let depthRelay = CaptureDepthRelay()
    let debugRelay = CaptureDebugVideoRelay()
    private let stills = CaptureStillTaker()

    private let lock = NSLock()
    private var planned: CaptureCapabilities
    private var wantsRunning = false
    private var info: CaptureDebugInfo
    private var externalThermal: ThermalLevel = .nominal
    private var pressures: [String: ThermalLevel] = [:]
    private var requestedRates = CaptureRates.full
    private var debugOn = false
    private var capabilitiesHandler: ((CaptureCapabilities) -> Void)?

    // Session queue only.
    private var setup: CaptureSessionSetup?
    private var configured = false
    private var appliedDeviceFPS: Double?
    private var observers: [NSObjectProtocol] = []
    private var pressureObservations: [NSKeyValueObservation] = []

    init(planned: CaptureCapabilities, backend: String, calibration: CaptureCalibration) {
        self.planned = planned
        self.calibration = calibration
        streamBRelay = CaptureStreamBRelay(calibration: calibration)
        info = CaptureDebugInfo(backend: backend)
        super.init()
        applyRates()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let o = orientationObserver { NotificationCenter.default.removeObserver(o) }
        pressureObservations.forEach { $0.invalidate() }
        if let session = setup?.session, session.isRunning { session.stopRunning() }
        CaptureIdleTimer.hold(ObjectIdentifier(self), false)
    }

    /// Subclass hook: build the session (inputs, outputs, delegates, formats). nil = no usable camera.
    func configureSession() -> CaptureSessionSetup? { nil }

    // MARK: FrameSource

    var capabilities: CaptureCapabilities {
        var c = lock.withLock { planned }
        if CapturePermission.isDenied { c.cameraAvailable = false }
        return c
    }

    var onDepth: ((DepthFrame) -> Void)? {
        get { depthRelay.handler }
        set { depthRelay.handler = newValue }
    }

    func captureStill() async throws -> CGImage {
        guard capabilities.cameraAvailable else { throw CaptureError.unavailable }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGImage, Error>) in
            sessionQueue.async { [self] in
                guard let setup, setup.session.isRunning, let output = setup.photoOutput else {
                    cont.resume(throwing: CaptureError.notRunning)
                    return
                }
                stills.capture(from: output) { cont.resume(with: $0) }
            }
        }
    }

    /// Main-screen preview of Stream B. Kept weakly; connected on the session queue once configured.
    private weak var previewLayer: AVCaptureVideoPreviewLayer?
    private var previewConnected = false

    func attachPreview(_ layer: AVCaptureVideoPreviewLayer) {
        layer.videoGravity = .resizeAspectFill
        sessionQueue.async { [weak self, weak layer] in
            guard let self, let layer else { return }
            self.previewLayer = layer
            self.previewConnected = false
            self.connectPreviewIfReady()
        }
    }

    /// Session queue. Multi-cam sessions have no implicit connections, so the preview gets an explicit connection to
    /// the ultra-wide video port; a single-camera session connects automatically. If the session can't take the extra
    /// connection (capture cost), the preview stays empty and capture is unaffected.
    /// Session queue: the preview's rotation follows the flip-camera setting (90°, or 270° upside down).
    private var previewConnection: AVCaptureConnection?
    private var orientationObserver: NSObjectProtocol?

    private func applyPreviewAngle() {
        let angle = CaptureOrientation.previewAngle
        if let c = previewConnection, c.isVideoRotationAngleSupported(angle) { c.videoRotationAngle = angle }
    }

    private func observeOrientation() {
        guard orientationObserver == nil else { return }
        orientationObserver = NotificationCenter.default.addObserver(forName: CaptureOrientation.didChange, object: nil,
                                                                     queue: nil) { [weak self] _ in
            self?.sessionQueue.async { self?.applyPreviewAngle() }
        }
    }

    private func connectPreviewIfReady() {
        observeOrientation()
        guard !previewConnected, let layer = previewLayer, let s = setup else { return }
        let session = s.session
        if let multi = session as? AVCaptureMultiCamSession {
            let input = multi.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device == s.streamBDevice }
            guard let port = input?.ports(for: .video, sourceDeviceType: s.streamBDevice.deviceType,
                                          sourceDevicePosition: s.streamBDevice.position).first else { return }
            layer.setSessionWithNoConnection(multi)
            let c = AVCaptureConnection(inputPort: port, videoPreviewLayer: layer)
            multi.beginConfiguration()
            if multi.canAddConnection(c) {
                multi.addConnection(c)
                previewConnection = c
                applyPreviewAngle()
                previewConnected = true
            }
            multi.commitConfiguration()
            refreshCosts()
        } else {
            layer.session = session
            previewConnection = layer.connection
            applyPreviewAngle()
            previewConnected = true
        }
    }

    /// Returns at once; configuration and `startRunning()` happen on the session queue. Asks for camera permission
    /// if needed. Throws `CaptureError.denied` when permission is already denied.
    func start() throws {
        switch CapturePermission.status {
        case .denied:
            updateInfo { $0.lastError = "Camera permission denied" }
            notifyCapabilities()
            throw CaptureError.denied
        case .notDetermined:
            markWanted(true)
            CapturePermission.request { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.sessionQueue.async { self.runIfWanted() }
                } else {
                    self.updateInfo { $0.lastError = "Camera permission denied" }
                    self.markWanted(false)
                    self.notifyCapabilities()
                }
            }
        case .authorized:
            markWanted(true)
            sessionQueue.async { self.runIfWanted() }
        }
    }

    func stop() {
        markWanted(false)
        sessionQueue.async { [self] in
            if let session = setup?.session, session.isRunning { session.stopRunning() }
            updateInfo { $0.isRunning = false }
        }
    }

    // MARK: Rates, thermal, calibration, debug

    var onCapabilitiesChange: ((CaptureCapabilities) -> Void)? {
        get { lock.withLock { capabilitiesHandler } }
        set { lock.withLock { capabilitiesHandler = newValue } }
    }

    func setThermalLevel(_ level: ThermalLevel) {
        lock.withLock { externalThermal = level }
        applyRates()
    }

    func setRates(_ rates: CaptureRates) {
        lock.withLock { requestedRates = rates }
        applyRates()
    }

    var rates: CaptureRates { lock.withLock { effectiveRatesLocked() } }

    func makeStreamB() -> AsyncStream<FrameB> { streamBRelay.makeStream() }

    var streamBCalibration: CaptureCalibration.StreamB? { calibration.streamB }

    var debugInfo: CaptureDebugInfo {
        var i = lock.withLock { () -> CaptureDebugInfo in
            var i = info
            i.thermal = thermalLocked()
            i.rates = effectiveRatesLocked()
            return i
        }
        i.streamBFPS = streamBRelay.fps
        i.droppedStreamB = streamBRelay.droppedCount
        i.depthFPS = depthRelay.fps
        i.droppedDepth = depthRelay.droppedCount
        if CapturePermission.isDenied { i.lastError = "Camera permission denied" }
        return i
    }

    var latestDepthSummary: CaptureDepthSummary? { depthRelay.latestSummary }
    var latestDebugImage: CGImage? { debugRelay.latestImage }
    var latestDepthHeatmap: CGImage? { depthRelay.latestHeatmap }

    var debugOverlayEnabled: Bool {
        get { lock.withLock { debugOn } }
        set {
            lock.withLock { debugOn = newValue }
            depthRelay.setDebugEnabled(newValue)
            debugRelay.setEnabled(newValue)
        }
    }

    // MARK: Subclass helpers

    func report(error message: String) {
        updateInfo { $0.lastError = message }
    }

    /// One camera with video + photo in a plain AVCaptureSession (fallback devices, or a multi-cam pair that
    /// failed to configure). Session queue only.
    func configureSingleCamera(_ device: AVCaptureDevice, backend: String, capabilities: CaptureCapabilities) -> CaptureSessionSetup? {
        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: device) } catch {
            report(error: "Camera input: \(error.localizedDescription)")
            return nil
        }
        let session = AVCaptureSession()
        // The app's audio session belongs to speech + recording (FeedbackAudioSession). If capture managed it too,
        // switching to record mode would interrupt the camera (frozen preview while the user talks).
        session.automaticallyConfiguresApplicationAudioSession = false
        let video = AVCaptureVideoDataOutput()
        let photo = AVCapturePhotoOutput()

        session.beginConfiguration()
        let built: Bool = {
            guard session.canAddInput(input) else { report(error: "Can't add camera input"); return false }
            session.addInput(input)
            guard session.canAddOutput(video), session.canAddOutput(photo) else { report(error: "Can't add outputs"); return false }
            session.addOutput(video)
            session.addOutput(photo)
            // Setting the format after the input switches the session to input priority.
            let format = CaptureFormats.streamBCandidates(device, multiCam: false).first ?? device.activeFormat
            CaptureFormats.applyStreamB(format, to: device, maxFPS: 30)
            CaptureFormats.configureVideoOutput(video)
            video.setSampleBufferDelegate(streamBRelay, queue: videoQueue)
            if let c = video.connection(with: .video), c.isCameraIntrinsicMatrixDeliverySupported {
                c.isCameraIntrinsicMatrixDeliveryEnabled = true
            }
            photo.maxPhotoQualityPrioritization = .balanced
            return true
        }()
        session.commitConfiguration()
        guard built else { return nil }
        CaptureFormats.updateMaxPhotoDimensions(photo, device: device)

        return CaptureSessionSetup(
            session: session, photoOutput: photo, streamBDevice: device, depthDevice: nil,
            capabilities: capabilities, backend: backend,
            streamBFormat: CaptureFormats.describe(device.activeFormat, fps: 30), depthFormat: "–", streamBFrameCap: 30)
    }

    // MARK: Private

    private func markWanted(_ on: Bool) {
        lock.withLock { wantsRunning = on }
        CaptureIdleTimer.hold(ObjectIdentifier(self), on)
    }

    private func updateInfo(_ body: (inout CaptureDebugInfo) -> Void) {
        lock.withLock { body(&info) }
    }

    private func notifyCapabilities() {
        let handler = lock.withLock { capabilitiesHandler }
        handler?(capabilities)
    }

    /// Session queue.
    private func runIfWanted() {
        guard lock.withLock({ wantsRunning }) else { return }
        if !configured {
            configured = true
            if let s = configureSession() {
                setup = s
                lock.withLock {
                    planned = s.capabilities
                    info.backend = s.backend
                    info.streamBFormat = s.streamBFormat
                    info.depthFormat = s.depthFormat
                }
                observe(s)
                applyDeviceRate()
            } else {
                lock.withLock {
                    planned.cameraAvailable = false
                    if info.lastError == nil { info.lastError = "Camera configuration failed" }
                }
            }
            connectPreviewIfReady()
            refreshCosts()
            notifyCapabilities()
        }
        guard let s = setup, !s.session.isRunning else { return }
        s.session.startRunning()
        let running = s.session.isRunning
        updateInfo { $0.isRunning = running }
    }

    private func thermalLocked() -> ThermalLevel {
        pressures.values.reduce(externalThermal, CaptureRates.worse)
    }

    private func effectiveRatesLocked() -> CaptureRates {
        CaptureRates.forThermal(thermalLocked()).capped(by: requestedRates)
    }

    private func applyRates() {
        let r = rates
        streamBRelay.setMaxFPS(r.streamBFPS)
        depthRelay.setMaxFPS(r.depthFPS)
        sessionQueue.async { [weak self] in self?.applyDeviceRate() }
    }

    /// Session queue. Lowers the Stream B camera's own frame rate as well (saves sensor/ISP power and lowers the
    /// session's pressure cost), never above the step-down cap or below 15 fps.
    private func applyDeviceRate() {
        guard let s = setup else { return }
        let fps = min(s.streamBFrameCap, max(15, rates.streamBFPS.rounded(.up)))
        guard fps != appliedDeviceFPS else { return }
        appliedDeviceFPS = CaptureFormats.setMaxFrameRate(s.streamBDevice, fps: fps) ?? appliedDeviceFPS
        refreshCosts()
    }

    /// Session queue.
    private func refreshCosts() {
        let multi = setup?.session as? AVCaptureMultiCamSession
        let hw = multi?.hardwareCost, pressure = multi?.systemPressureCost
        updateInfo { $0.hardwareCost = hw; $0.systemPressureCost = pressure }
    }

    /// Session queue.
    private func observe(_ s: CaptureSessionSetup) {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: s.session, queue: nil) {
            [weak self] note in self?.handleRuntimeError(note)
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: s.session, queue: nil) {
            [weak self] note in
            let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
            let reason = raw.flatMap { AVCaptureSession.InterruptionReason(rawValue: $0) }
            self?.updateInfo { $0.interruption = reason.map(Self.describe) ?? "unknown" }
        })
        observers.append(nc.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: s.session, queue: nil) {
            [weak self] _ in
            self?.updateInfo { $0.interruption = nil }
            self?.sessionQueue.async { self?.runIfWanted() }         // make sure the camera is running again
        })
        for device in [s.streamBDevice, s.depthDevice].compactMap({ $0 }) {
            pressureObservations.append(device.observe(\.systemPressureState, options: [.initial, .new]) { [weak self] d, _ in
                self?.pressureChanged(d.uniqueID, CaptureRates.level(d.systemPressureState.level))
            })
        }
    }

    private func pressureChanged(_ id: String, _ level: ThermalLevel) {
        let changed: Bool = lock.withLock {
            let before = thermalLocked()
            pressures[id] = level
            return thermalLocked() != before
        }
        if changed { applyRates() }
    }

    private func handleRuntimeError(_ note: Notification) {
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
        updateInfo {
            $0.lastError = error?.localizedDescription ?? "Capture runtime error"
            $0.isRunning = false
        }
        // Restart whenever capture is still wanted (not only after a media-services reset).
        sessionQueue.async { [weak self] in self?.runIfWanted() }
    }

    private static func describe(_ r: AVCaptureSession.InterruptionReason) -> String {
        switch r {
        case .videoDeviceNotAvailableInBackground: return "in background"
        case .audioDeviceInUseByAnotherClient: return "audio in use"
        case .videoDeviceInUseByAnotherClient: return "camera in use"
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return "multitasking"
        case .videoDeviceNotAvailableDueToSystemPressure: return "system pressure"
        default: return "other"
        }
    }
}
