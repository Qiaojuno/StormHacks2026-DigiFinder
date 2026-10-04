import AVFoundation
import Foundation

/// Camera permission (§5.16). A denial shows up as `capabilities.cameraAvailable == false` on every frame source;
/// the runner maps that to `SystemEvent.cameraDenied`.
enum CapturePermission {
    enum Status: Equatable { case authorized, notDetermined, denied }

    static var status: Status {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied                      // .denied, .restricted, future cases
        }
    }

    static var isDenied: Bool { status == .denied }

    /// Shows the system prompt once; later calls return the stored answer. Safe to call from any thread.
    static func request() async -> Bool {
        switch status {
        case .authorized: return true
        case .denied: return false
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        }
    }

    /// Callback form; `completion` runs on an arbitrary queue.
    static func request(_ completion: @escaping @Sendable (Bool) -> Void) {
        switch status {
        case .authorized: completion(true)
        case .denied: completion(false)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
        }
    }
}
