import AVFoundation
import CoreMedia
import Foundation

/// LiDAR depth + 0.5× ultra-wide in one AVCaptureMultiCamSession (§2 Cameras, §9 Multi-cam setup).
/// - Stream B (ultra-wide): video for all vision, with per-frame intrinsics; photo output for full-res stills.
/// - Stream A (LiDAR): Float32 depth (~320×240) for the safety lane; its 1× video feeds only the debug overlay.
/// Formats step down until `hardwareCost` and `systemPressureCost` are both < 1.0. If the pair can't be
/// configured at all, the service falls back to the ultra-wide alone (capabilities update accordingly).
final class MultiCamService: CaptureSessionSource, @unchecked Sendable {
    private let lidar: AVCaptureDevice
    private let ultraWide: AVCaptureDevice

    init(lidar: AVCaptureDevice, ultraWide: AVCaptureDevice, calibration: CaptureCalibration = CaptureCalibration()) {
        self.lidar = lidar
        self.ultraWide = ultraWide
        super.init(planned: CaptureCapabilities(cameraAvailable: true, hasLiDAR: true, hasUltraWide: true, isMultiCam: true),
                   backend: "LiDAR + ultra-wide", calibration: calibration)
    }

    /// nil unless multi-cam is supported and both back cameras exist (never in the Simulator).
    convenience init?(calibration: CaptureCalibration = CaptureCalibration()) {
        guard AVCaptureMultiCamSession.isMultiCamSupported,
              let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back),
              let ultra = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        else { return nil }
        self.init(lidar: lidar, ultraWide: ultra, calibration: calibration)
    }

    override func configureSession() -> CaptureSessionSetup? {
        if let s = configureMultiCam() { return s }
        return configureSingleCamera(ultraWide, backend: "ultra-wide (multi-cam failed)",
                                     capabilities: CaptureCapabilities(cameraAvailable: true, hasUltraWide: true))
    }

    private func configureMultiCam() -> CaptureSessionSetup? {
        guard AVCaptureMultiCamSession.isMultiCamSupported else { return fail("Multi-cam not supported") }
        let lidarFormats = CaptureFormats.lidarCandidates(lidar)
        let ultraFormats = CaptureFormats.streamBCandidates(ultraWide, multiCam: true)
        guard let lidarFormat = lidarFormats.first, let ultraFormat = ultraFormats.first else {
            return fail("No multi-cam formats (LiDAR \(lidarFormats.count), ultra-wide \(ultraFormats.count))")
        }

        let session = AVCaptureMultiCamSession()
        // The app's audio session belongs to speech + recording (FeedbackAudioSession). If capture managed it too,
        // switching to record mode would interrupt the camera (frozen preview while the user talks).
        session.automaticallyConfiguresApplicationAudioSession = false
        let videoA = AVCaptureVideoDataOutput()     // 1×: debug only
        let depthA = AVCaptureDepthDataOutput()     // LiDAR distances
        let videoB = AVCaptureVideoDataOutput()     // ultra-wide: all vision
        let photoB = AVCapturePhotoOutput()         // ultra-wide: full-res stills

        session.beginConfiguration()
        let wired = wire(session, lidarFormat: lidarFormat, ultraFormat: ultraFormat,
                         videoA: videoA, depthA: depthA, videoB: videoB, photoB: photoB)
        session.commitConfiguration()
        guard wired else { return nil }

        let frameCap = stepDown(session, ultraFormats: ultraFormats, lidarFormats: lidarFormats)
        guard session.hardwareCost < 1 else {
            return fail(String(format: "Multi-cam hardware cost %.2f even at the lowest formats", session.hardwareCost))
        }
        if session.systemPressureCost >= 1 {
            report(error: String(format: "System pressure cost %.2f at the lowest formats", session.systemPressureCost))
        }
        CaptureFormats.updateMaxPhotoDimensions(photoB, device: ultraWide)

        return CaptureSessionSetup(
            session: session, photoOutput: photoB, streamBDevice: ultraWide, depthDevice: lidar,
            capabilities: CaptureCapabilities(cameraAvailable: true, hasLiDAR: true, hasUltraWide: true, isMultiCam: true),
            backend: "LiDAR + ultra-wide",
            streamBFormat: CaptureFormats.describe(ultraWide.activeFormat, fps: frameCap),
            depthFormat: CaptureFormats.describeDepth(lidar.activeDepthDataFormat)
                + " (1× \(CaptureFormats.describe(lidar.activeFormat)))",
            streamBFrameCap: frameCap)
    }

    /// Inside begin/commitConfiguration: formats, inputs without implicit connections, outputs, explicit connections.
    private func wire(_ session: AVCaptureMultiCamSession, lidarFormat: AVCaptureDevice.Format, ultraFormat: AVCaptureDevice.Format,
                      videoA: AVCaptureVideoDataOutput, depthA: AVCaptureDepthDataOutput,
                      videoB: AVCaptureVideoDataOutput, photoB: AVCapturePhotoOutput) -> Bool {
        guard CaptureFormats.applyLiDAR(lidarFormat, to: lidar) else { return failed("Can't configure the LiDAR camera") }
        CaptureFormats.applyStreamB(ultraFormat, to: ultraWide, maxFPS: 30)

        let inA: AVCaptureDeviceInput, inB: AVCaptureDeviceInput
        do {
            inA = try AVCaptureDeviceInput(device: lidar)
            inB = try AVCaptureDeviceInput(device: ultraWide)
        } catch {
            return failed("Camera input: \(error.localizedDescription)")
        }
        guard session.canAddInput(inA) else { return failed("Can't add the LiDAR input") }
        session.addInputWithNoConnections(inA)
        guard session.canAddInput(inB) else { return failed("Can't add the ultra-wide input") }
        session.addInputWithNoConnections(inB)

        let outputs: [AVCaptureOutput] = [videoA, depthA, videoB, photoB]
        for output in outputs {
            guard session.canAddOutput(output) else { return failed("Can't add \(type(of: output))") }
            session.addOutputWithNoConnections(output)
        }

        func port(_ input: AVCaptureDeviceInput, _ type: AVMediaType, _ device: AVCaptureDevice) -> AVCaptureInput.Port? {
            input.ports(for: type, sourceDeviceType: device.deviceType, sourceDevicePosition: device.position).first
        }
        guard let pAV = port(inA, .video, lidar), let pAD = port(inA, .depthData, lidar),
              let pBV = port(inB, .video, ultraWide) else { return failed("Camera ports missing") }

        let pairs: [(AVCaptureInput.Port, AVCaptureOutput)] = [(pAV, videoA), (pAD, depthA), (pBV, videoB), (pBV, photoB)]
        var streamBConnection: AVCaptureConnection?
        for (p, o) in pairs {
            let c = AVCaptureConnection(inputPorts: [p], output: o)
            guard session.canAddConnection(c) else { return failed("Can't connect \(type(of: o))") }
            session.addConnection(c)
            if o === videoB { streamBConnection = c }
        }
        if let c = streamBConnection, c.isCameraIntrinsicMatrixDeliverySupported { c.isCameraIntrinsicMatrixDeliveryEnabled = true }

        CaptureFormats.configureVideoOutput(videoB)
        videoB.setSampleBufferDelegate(streamBRelay, queue: videoQueue)
        CaptureFormats.configureVideoOutput(videoA)
        videoA.setSampleBufferDelegate(debugRelay, queue: debugQueue)
        depthA.isFilteringEnabled = true
        depthA.alwaysDiscardsLateDepthData = true
        depthA.setDelegate(depthRelay, callbackQueue: depthQueue)
        photoB.maxPhotoQualityPrioritization = .balanced
        return true
    }

    /// Steps Stream B resolution down, then the LiDAR video size, then the Stream B frame rate, until both costs
    /// are < 1.0 (or nothing is left to lower). Returns the Stream B frame-rate cap.
    private func stepDown(_ session: AVCaptureMultiCamSession, ultraFormats: [AVCaptureDevice.Format],
                          lidarFormats: [AVCaptureDevice.Format]) -> Double {
        func underLimit() -> Bool { session.hardwareCost < 1 && session.systemPressureCost < 1 }
        let steps = CaptureFormats.frameRateSteps
        let currentLiDARArea = CaptureFormats.area(lidar.activeFormat)
        let smallerLiDAR = lidarFormats
            .filter { CaptureFormats.area($0) < currentLiDARArea }
            .sorted { CaptureFormats.area($0) > CaptureFormats.area($1) }
        var ui = ultraFormats.firstIndex(of: ultraWide.activeFormat) ?? 0
        var li = -1
        var fi = 0
        while !underLimit() {
            if ui + 1 < ultraFormats.count {
                ui += 1
                CaptureFormats.applyStreamB(ultraFormats[ui], to: ultraWide, maxFPS: steps[fi])
            } else if li + 1 < smallerLiDAR.count {
                li += 1
                CaptureFormats.applyLiDAR(smallerLiDAR[li], to: lidar)
            } else if fi + 1 < steps.count {
                fi += 1
                CaptureFormats.setMaxFrameRate(ultraWide, fps: steps[fi])
            } else {
                break
            }
        }
        return steps[fi]
    }

    private func fail(_ message: String) -> CaptureSessionSetup? {
        report(error: message)
        return nil
    }

    private func failed(_ message: String) -> Bool {
        report(error: message)
        return false
    }
}
