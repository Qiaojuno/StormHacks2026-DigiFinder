import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import DigiFinderCore

/// Small pixel helpers: frame brightness and upright crops (contract-space rects) for product memory.
enum PerceptionImageTools {
    /// Mean luma 0...1 from a sparse sample of the frame (YUV plane 0, or BGRA). nil for other formats.
    static func meanLuma(_ pb: CVPixelBuffer, samples: Int = 32) -> Double? {
        guard CVPixelBufferLockBaseAddress(pb, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let format = CVPixelBufferGetPixelFormatType(pb)
        let yuv: Set<OSType> = [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        let base: UnsafeMutableRawPointer?, width: Int, height: Int, rowBytes: Int, stride: Int, offset: Int
        if yuv.contains(format) {
            base = CVPixelBufferGetBaseAddressOfPlane(pb, 0)
            width = CVPixelBufferGetWidthOfPlane(pb, 0); height = CVPixelBufferGetHeightOfPlane(pb, 0)
            rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pb, 0); stride = 1; offset = 0
        } else if format == kCVPixelFormatType_32BGRA {
            base = CVPixelBufferGetBaseAddress(pb)
            width = CVPixelBufferGetWidth(pb); height = CVPixelBufferGetHeight(pb)
            rowBytes = CVPixelBufferGetBytesPerRow(pb); stride = 4; offset = 1      // green ≈ luma
        } else {
            return nil
        }
        guard let base, width > 0, height > 0 else { return nil }
        let p = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0, count = 0
        for sy in 0..<samples {
            let y = (sy * height + height / 2) / samples
            for sx in 0..<samples {
                let x = (sx * width + width / 2) / samples
                sum += Int(p[y * rowBytes + x * stride + offset]); count += 1
            }
        }
        return count > 0 ? Double(sum) / Double(count) / 255 : nil
    }

    /// Upright crop of a Stream B frame (sensor buffer turned `.right`) for a contract-space rect, padded a little.
    static func uprightCrop(_ pb: CVPixelBuffer, rect r: NormRect, pad: Double = 0.02, maxWidth: CGFloat = 400) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pb).oriented(CaptureOrientation.visionOrientation)
        return crop(image, rect: r, pad: pad, maxWidth: maxWidth)
    }

    /// Crop of an already-upright image for a contract-space rect.
    static func crop(_ cg: CGImage, rect r: NormRect, pad: Double = 0.02, maxWidth: CGFloat = 400) -> CGImage? {
        crop(CIImage(cgImage: cg), rect: r, pad: pad, maxWidth: maxWidth)
    }

    private static func crop(_ image: CIImage, rect r: NormRect, pad: Double, maxWidth: CGFloat) -> CGImage? {
        let e = image.extent
        guard e.width > 0, e.height > 0 else { return nil }
        let p = NormRect(x: r.x - pad, y: r.y - pad, width: r.width + 2 * pad, height: r.height + 2 * pad).clamped()
        guard p.area > 0 else { return nil }
        // CoreImage is bottom-left origin.
        let rect = CGRect(x: e.minX + CGFloat(p.x) * e.width, y: e.minY + CGFloat(1 - p.maxY) * e.height,
                          width: CGFloat(p.width) * e.width, height: CGFloat(p.height) * e.height).integral
        var out = image.cropped(to: rect)
        if rect.width > maxWidth {
            let s = maxWidth / rect.width
            out = out.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        let extent = out.extent.integral
        guard extent.width >= 8, extent.height >= 8 else { return nil }
        return CaptureImageRenderer.context.createCGImage(out, from: extent)
    }
}
