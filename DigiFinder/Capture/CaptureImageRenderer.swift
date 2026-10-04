import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO

/// Turns sensor-oriented buffers into upright portrait images (stills, debug preview, depth heatmap).
/// The phone hangs portrait, so "upright" is the sensor image turned 90° clockwise (Vision orientation `.right`).
enum CaptureImageRenderer {
    /// Thread-safe; shared to avoid re-creating GPU state per image.
    static let context = CIContext(options: [.cacheIntermediates: false])

    /// Orientation that makes a photo upright in portrait: its EXIF orientation when the capture connection was
    /// rotated, else `.right` (sensor landscape → portrait).
    static func portraitOrientation(exif: CGImagePropertyOrientation?) -> CGImagePropertyOrientation {
        guard let exif, exif != .up else { return .right }
        return exif
    }

    static func upright(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .right, maxWidth: CGFloat? = nil) -> CGImage? {
        render(CIImage(cvPixelBuffer: pixelBuffer), orientation: orientation, maxWidth: maxWidth)
    }

    static func upright(_ image: CGImage, orientation: CGImagePropertyOrientation = .right, maxWidth: CGFloat? = nil) -> CGImage? {
        render(CIImage(cgImage: image), orientation: orientation, maxWidth: maxWidth)
    }

    private static func render(_ input: CIImage, orientation: CGImagePropertyOrientation, maxWidth: CGFloat?) -> CGImage? {
        var image = input.oriented(orientation)
        if let maxWidth, image.extent.width > maxWidth, image.extent.width > 0 {
            let s = maxWidth / image.extent.width
            image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0 else { return nil }
        return context.createCGImage(image, from: extent)
    }

    /// Upright depth heatmap: red near → blue at `maxRange`, black where depth is unusable.
    /// `depth` must be Float32 (see `CaptureDepthMap.float32`).
    static func depthHeatmap(_ depth: AVDepthData, maxRange: Float = 5) -> CGImage? {
        let result: CGImage?? = CaptureDepthMap.read(depth) { map -> CGImage? in
            let outW = map.height, outH = map.width            // portrait
            var bytes = [UInt8](repeating: 0, count: outW * outH * 4)
            let near = CaptureDepthMap.minDepth, span = max(maxRange - near, 0.1)
            for py in 0..<outH {
                for px in 0..<outW {
                    // Inverse of Geometry.fromSensorPixels: portrait (px, py) ← sensor (x = py, y = h − 1 − px).
                    let i = (py * outW + px) * 4
                    bytes[i + 3] = 255
                    guard let z = map.depth(py, map.height - 1 - px) else { continue }
                    let t = min(max((z - near) / span, 0), 1)
                    bytes[i] = UInt8(255 * (1 - t))
                    bytes[i + 1] = UInt8(255 * (1 - abs(2 * t - 1)))
                    bytes[i + 2] = UInt8(255 * t)
                }
            }
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            return CGImage(width: outW, height: outH, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: outW * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        return result ?? nil
    }
}
