import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Format selection and device tuning. Every setter is guarded by the matching "supported" check so a bad
/// value never raises an Objective-C exception.
enum CaptureFormats {
    /// Target depth-map width (§2: ~320×240, sampled with stride 2).
    static let targetDepthWidth: Int32 = 320
    /// Widest Stream B buffer (§2 Step 0: 1920×1440 or 1280×960).
    static let maxStreamBWidth: Int32 = 1920
    /// Stream B frame-rate step-down when resolution alone can't bring costs under 1.0.
    static let frameRateSteps: [Double] = [30, 24, 20, 15]

    static func dimensions(_ f: AVCaptureDevice.Format) -> CMVideoDimensions {
        CMVideoFormatDescriptionGetDimensions(f.formatDescription)
    }

    static func area(_ f: AVCaptureDevice.Format) -> Int {
        let d = dimensions(f)
        return Int(d.width) * Int(d.height)
    }

    static func is4x3(_ f: AVCaptureDevice.Format) -> Bool {
        let d = dimensions(f)
        return Int(d.width) * 3 == Int(d.height) * 4
    }

    static func maxFrameRate(_ f: AVCaptureDevice.Format) -> Double {
        f.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
    }

    static func describe(_ f: AVCaptureDevice.Format?, fps: Double? = nil) -> String {
        guard let f else { return "–" }
        let d = dimensions(f)
        return "\(d.width)×\(d.height)" + (fps.map { " @\(Int($0))" } ?? "")
    }

    static func describeDepth(_ f: AVCaptureDevice.Format?) -> String {
        guard let f else { return "–" }
        let d = dimensions(f)
        let type = CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_DepthFloat32 ? "f32" : "other"
        return "\(d.width)×\(d.height) \(type)"
    }

    // MARK: Stream B (ultra-wide or wide)

    /// Candidate Stream B formats, best first: 4:3 (full field of view), ≤ 1920 wide, ≥ 24 fps, 8-bit 4:2:0,
    /// one per size, largest first. The rest of the list is the resolution step-down.
    static func streamBCandidates(_ device: AVCaptureDevice, multiCam: Bool) -> [AVCaptureDevice.Format] {
        let yuv: Set<FourCharCode> = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        let usable = device.formats.filter { f in
            (!multiCam || f.isMultiCamSupported)
                && yuv.contains(CMFormatDescriptionGetMediaSubType(f.formatDescription))
                && dimensions(f).width <= maxStreamBWidth
                && maxFrameRate(f) >= 24
        }
        let preferred = usable.contains(where: is4x3) ? usable.filter(is4x3) : usable
        var seen = Set<Int>()
        var out: [AVCaptureDevice.Format] = []
        // Full-range first so the deduped entry per size is 420f when it exists.
        let ordered = preferred.sorted { a, b in
            if area(a) != area(b) { return area(a) > area(b) }
            return CMFormatDescriptionGetMediaSubType(a.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                && CMFormatDescriptionGetMediaSubType(b.formatDescription) != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
        for f in ordered where seen.insert(area(f)).inserted { out.append(f) }
        return out
    }

    /// Applies a Stream B format plus focus, distortion correction and a frame-rate cap.
    @discardableResult
    static func applyStreamB(_ format: AVCaptureDevice.Format, to device: AVCaptureDevice, maxFPS: Double) -> Bool {
        do { try device.lockForConfiguration() } catch { return false }
        defer { device.unlockForConfiguration() }
        if device.formats.contains(format) { device.activeFormat = format }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .none }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isGeometricDistortionCorrectionSupported { device.isGeometricDistortionCorrectionEnabled = true }
        applyFrameRateLocked(device, fps: maxFPS)
        return true
    }

    /// Caps the device frame rate (needs no prior lock). Returns the applied rate, nil if unchanged.
    @discardableResult
    static func setMaxFrameRate(_ device: AVCaptureDevice, fps: Double) -> Double? {
        do { try device.lockForConfiguration() } catch { return nil }
        defer { device.unlockForConfiguration() }
        return applyFrameRateLocked(device, fps: fps)
    }

    @discardableResult
    private static func applyFrameRateLocked(_ device: AVCaptureDevice, fps: Double) -> Double? {
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
        guard fps > 0, let top = ranges.map(\.maxFrameRate).max(), let bottom = ranges.map(\.minFrameRate).min() else { return nil }
        let target = min(max(fps, bottom), top)
        guard ranges.contains(where: { target >= $0.minFrameRate && target <= $0.maxFrameRate }) else { return nil }
        let duration = CMTime(value: 1000, timescale: CMTimeScale((target * 1000).rounded()))
        // Keep min ≤ max: widen the max duration first when the new min is longer than it.
        if CMTimeCompare(device.activeVideoMaxFrameDuration, duration) < 0 { device.activeVideoMaxFrameDuration = duration }
        device.activeVideoMinFrameDuration = duration
        return target
    }

    // MARK: LiDAR

    /// Multi-cam LiDAR formats that offer Float32 depth, best first: 4:3, depth width closest to 320,
    /// then the smallest video (the 1× video is debug only).
    static func lidarCandidates(_ device: AVCaptureDevice) -> [AVCaptureDevice.Format] {
        let usable = device.formats.filter { $0.isMultiCamSupported && depthFormat(in: $0) != nil }
        return usable.sorted { a, b in
            if is4x3(a) != is4x3(b) { return is4x3(a) }
            let da = depthDistance(a), db = depthDistance(b)
            if da != db { return da < db }
            return area(a) < area(b)
        }
    }

    /// The Float32 depth format with width closest to 320.
    static func depthFormat(in f: AVCaptureDevice.Format) -> AVCaptureDevice.Format? {
        f.supportedDepthDataFormats
            .filter { CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32 }
            .min { abs(dimensions($0).width - targetDepthWidth) < abs(dimensions($1).width - targetDepthWidth) }
    }

    private static func depthDistance(_ f: AVCaptureDevice.Format) -> Int32 {
        depthFormat(in: f).map { abs(dimensions($0).width - targetDepthWidth) } ?? .max
    }

    /// Applies a LiDAR video format and its depth format.
    @discardableResult
    static func applyLiDAR(_ format: AVCaptureDevice.Format, to device: AVCaptureDevice) -> Bool {
        guard device.formats.contains(format), let depth = depthFormat(in: format) else { return false }
        do { try device.lockForConfiguration() } catch { return false }
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        if device.activeFormat.supportedDepthDataFormats.contains(depth) { device.activeDepthDataFormat = depth }
        return true
    }

    // MARK: Outputs

    /// 8-bit full-range 4:2:0 if the output offers it (what Vision and Core ML take without conversion).
    static func configureVideoOutput(_ output: AVCaptureVideoDataOutput) {
        let preferred = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        if let type = preferred.first(where: { output.availableVideoPixelFormatTypes.contains($0) }) {
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: type]
        }
        output.alwaysDiscardsLateVideoFrames = true
    }

    /// Largest still the device's active format supports; call after the photo output is connected.
    static func updateMaxPhotoDimensions(_ output: AVCapturePhotoOutput, device: AVCaptureDevice) {
        let sizes = device.activeFormat.supportedMaxPhotoDimensions
        if let best = sizes.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            output.maxPhotoDimensions = best
        }
    }
}
