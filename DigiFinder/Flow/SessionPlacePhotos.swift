import CoreGraphics
import Foundation
import DigiFinderCore

/// The app-open grocery check's photos: wait (max ~5 s after the camera starts) for a good moment — phone upright,
/// still, a bright enough frame, LiDAR not blocked — then 3 stills ~0.7 s apart, as upright JPEGs.
/// If the gate never passes, the best frames are used anyway.
enum SessionPlacePhotos {
    /// Longest wait for a good moment (s).
    static let gateWait = 5.0
    /// Upright: gravity mostly along the device's −y (g).
    static let uprightGravityY: Float = -0.8
    /// Still: rotation rate below this (rad/s).
    static let maxRotation = 0.5
    /// Not dark: mean luma of a still above this (0...1).
    static let minLuma = 0.12
    /// LiDAR not blocked: median depth in the middle above this (m), when depth exists.
    static let minCenterDepth: Float = 0.5
    static let count = 3
    static let spacing = 0.7

    /// Upright JPEGs (empty without a camera).
    static func take(frames: FrameSource, motion: MotionService) async -> [Data] {
        let deadline = ProcessInfo.processInfo.systemUptime + gateWait
        // Camera running (first Stream B frame) and the phone held well.
        while ProcessInfo.processInfo.systemUptime < deadline, !Task.isCancelled {
            if frames.streamBCalibration != nil, isSteady(motion), depthClear(frames) { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard frames.capabilities.cameraAvailable else { return [] }
        var best: [(jpeg: Data, luma: Double)] = []
        var tries = 0
        while best.filter({ $0.luma >= minLuma }).count < count, tries < count * 2, !Task.isCancelled {
            if tries > 0 { try? await Task.sleep(nanoseconds: UInt64(spacing * 1_000_000_000)) }
            tries += 1
            guard let still = try? await frames.captureStill() else { continue }
            let shot: (Data, Double)? = await withCheckedContinuation { c in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let jpeg = NetworkJPEG.encode(still) else { return c.resume(returning: nil) }
                    c.resume(returning: (jpeg, meanLuma(still)))
                }
            }
            if let shot { best.append(shot) }
            // Past the gate's time: take what comes.
            if ProcessInfo.processInfo.systemUptime >= deadline + Double(count) * spacing, best.count >= count { break }
        }
        // Bright ones first, keep at most 3.
        return Array(best.sorted { ($0.luma >= minLuma ? 1 : 0) > ($1.luma >= minLuma ? 1 : 0) }.prefix(count).map(\.jpeg))
    }

    static func isSteady(_ m: MotionService) -> Bool {
        m.gravity.y <= uprightGravityY && m.rotationRate < maxRotation
    }

    static func depthClear(_ frames: FrameSource) -> Bool {
        guard let s = frames.latestDepthSummary, let c = s.center,
              ProcessInfo.processInfo.systemUptime - s.time < 2 else { return true }   // no depth: nothing to check
        return c > minCenterDepth
    }

    /// Mean luma 0...1 from a 16×16 grayscale downsample.
    static func meanLuma(_ image: CGImage) -> Double {
        let n = 16
        var px = [UInt8](repeating: 0, count: n * n)
        let ok = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return 1 }
        return Double(px.reduce(0) { $0 + Int($1) }) / Double(n * n * 255)
    }
}
