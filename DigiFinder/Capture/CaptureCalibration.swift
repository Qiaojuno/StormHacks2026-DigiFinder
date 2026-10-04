import Foundation
import simd

/// Latest Stream B intrinsics and buffer size, shared between the frame source (writer, video queue) and
/// `LiDARDepthProvider` (reader) so Stream B points can be looked up in the depth map.
final class CaptureCalibration: @unchecked Sendable {
    struct StreamB {
        /// Relative to the Stream B buffer (landscape sensor pixels).
        var intrinsics: simd_float3x3
        var width: Int
        var height: Int
    }

    private let lock = NSLock()
    private var value: StreamB?

    var streamB: StreamB? { lock.withLock { value } }

    func update(_ K: simd_float3x3, width: Int, height: Int) {
        guard width > 0, height > 0, K[0][0] > 0, K[1][1] > 0 else { return }
        lock.withLock { value = StreamB(intrinsics: K, width: width, height: height) }
    }
}
