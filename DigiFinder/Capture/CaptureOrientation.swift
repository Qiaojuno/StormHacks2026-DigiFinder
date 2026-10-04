import CoreGraphics
import Foundation
import ImageIO
import DigiFinderCore

/// Which way the phone hangs on the lanyard (owner decision: detected from gravity by the runner, `OrientationTracker`;
/// no button). One value, read everywhere:
/// Vision's image orientation, stills, debug images, the live preview, and (in Core) every sensor ↔ portrait
/// mapping and left/right direction via `Geometry.cameraUpsideDown`.
enum CaptureOrientation {
    /// Posted (any thread) after the setting changes; the preview re-rotates.
    static let didChange = Notification.Name("DigiFinder.cameraOrientationChanged")

    static var isUpsideDown: Bool { Geometry.cameraUpsideDown }

    /// Turns the landscape sensor buffer upright for Vision and rendering.
    static var visionOrientation: CGImagePropertyOrientation { isUpsideDown ? .left : .right }

    /// Preview connection rotation (degrees).
    static var previewAngle: CGFloat { isUpsideDown ? 270 : 90 }

    static func set(upsideDown: Bool) {
        guard Geometry.cameraUpsideDown != upsideDown else { return }
        Geometry.cameraUpsideDown = upsideDown
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// The same orientation turned another 180° (a photo's EXIF orientation when the phone hangs upside down).
    static func rotated180(_ o: CGImagePropertyOrientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        case .upMirrored: return .downMirrored
        case .downMirrored: return .upMirrored
        case .leftMirrored: return .rightMirrored
        case .rightMirrored: return .leftMirrored
        @unknown default: return o
        }
    }
}
