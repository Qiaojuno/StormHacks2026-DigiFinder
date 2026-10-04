import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

/// Full-resolution stills from a photo output connected to the Stream B camera. The photo output runs beside
/// the video output, so video keeps flowing; decoding and rotation happen on the photo callback queue.
final class CaptureStillTaker: @unchecked Sendable {
    static let timeout: TimeInterval = 6

    private let lock = NSLock()
    private var inFlight: [Int64: Request] = [:]

    /// Call on the session queue with a running session. `completion` runs exactly once, on an arbitrary queue.
    func capture(from output: AVCapturePhotoOutput, completion: @escaping (Result<CGImage, Error>) -> Void) {
        guard let connection = output.connection(with: .video), connection.isEnabled, connection.isActive else {
            completion(.failure(CaptureError.notRunning))
            return
        }
        let settings = Self.settings(for: output)
        let id = settings.uniqueID
        let request = Request { [weak self] result in
            self?.lock.withLock { _ = self?.inFlight.removeValue(forKey: id) }
            completion(result)
        }
        lock.withLock { inFlight[id] = request }          // the photo output does not retain its delegate
        output.capturePhoto(with: settings, delegate: request)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.timeout) { [weak request] in
            request?.finish(.failure(CaptureError.timeout))
        }
    }

    /// Uncompressed BGRA when offered (no encode/decode), largest size, balanced quality, no flash.
    private static func settings(for output: AVCapturePhotoOutput) -> AVCapturePhotoSettings {
        let bgra = kCVPixelFormatType_32BGRA
        let settings = output.availablePhotoPixelFormatTypes.contains(bgra)
            ? AVCapturePhotoSettings(format: [kCVPixelBufferPixelFormatTypeKey as String: bgra])
            : AVCapturePhotoSettings()
        settings.maxPhotoDimensions = output.maxPhotoDimensions
        let quality: AVCapturePhotoOutput.QualityPrioritization =
            output.maxPhotoQualityPrioritization.rawValue >= AVCapturePhotoOutput.QualityPrioritization.balanced.rawValue
            ? .balanced : output.maxPhotoQualityPrioritization
        settings.photoQualityPrioritization = quality
        if output.supportedFlashModes.contains(.off) { settings.flashMode = .off }
        return settings
    }

    /// Upright full-resolution image from a delivered photo.
    static func uprightImage(_ photo: AVCapturePhoto) -> CGImage? {
        let exif = (photo.metadata[kCGImagePropertyOrientation as String] as? NSNumber)
            .flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) }
        let orientation = CaptureImageRenderer.portraitOrientation(exif: exif)
        if let pixelBuffer = photo.pixelBuffer {
            return CaptureImageRenderer.upright(pixelBuffer, orientation: orientation)
        }
        if let image = photo.cgImageRepresentation() {
            return CaptureImageRenderer.upright(image, orientation: orientation)
        }
        return nil
    }

    private final class Request: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var completion: ((Result<CGImage, Error>) -> Void)?
        private var gotPhoto = false

        init(_ completion: @escaping (Result<CGImage, Error>) -> Void) { self.completion = completion }

        func finish(_ result: Result<CGImage, Error>) {
            let c: ((Result<CGImage, Error>) -> Void)? = lock.withLock {
                defer { completion = nil }
                return completion
            }
            c?(result)
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
            lock.withLock { gotPhoto = true }
            if let error { finish(.failure(error)); return }
            if let image = CaptureStillTaker.uprightImage(photo) { finish(.success(image)) }
            else { finish(.failure(CaptureError.stillFailed)) }
        }

        func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                         error: Error?) {
            let got = lock.withLock { gotPhoto }
            if let error { finish(.failure(error)) } else if !got { finish(.failure(CaptureError.stillFailed)) }
        }
    }
}
