import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Encodes an upright still for Gemini (§5.11: ~2000 px on the long side, JPEG ~0.8). No orientation tag is written:
/// `FrameSource.captureStill()` already returns the image upright.
enum NetworkJPEG {
    static func encode(_ image: CGImage, maxDimension: Int = 2000, quality: Double = 0.8) -> Data? {
        let scaled = downscale(image, maxDimension: maxDimension) ?? image
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    private static func downscale(_ image: CGImage, maxDimension: Int) -> CGImage? {
        let w = image.width, h = image.height
        let longest = max(w, h)
        guard longest > maxDimension, maxDimension > 0 else { return nil }
        let s = Double(maxDimension) / Double(longest)
        let nw = max(1, Int((Double(w) * s).rounded())), nh = max(1, Int((Double(h) * s).rounded()))
        guard let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }
}
