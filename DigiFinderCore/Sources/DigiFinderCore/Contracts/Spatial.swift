// Frozen contract (§3.3). Change requests go to CONTRACT_CHANGES.md.

/// Leveled 3D point in meters relative to the phone: +x right, +y up, +z forward.
public struct Vec3: Equatable {
    public var x, y, z: Float
    public init(x: Float, y: Float, z: Float) { self.x = x; self.y = y; self.z = z }
}

/// 3×3 matrix, row-major. Intrinsics are `[fx, 0, cx, 0, fy, cy, 0, 0, 1]`.
public struct Mat3: Equatable {
    public var m: [Float]
    public init(m: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1]) { self.m = m }
}

// All 2D positions in contracts: the upright portrait image, normalized 0...1, origin top-left.
// Geometry/ owns the only converters: Geometry.fromVision(_:) (Vision is bottom-left origin) and
// Geometry.fromSensorPixels(_:width:height:) (landscape sensor pixels, as used by intrinsics → rotate to portrait).

public struct NormPoint: Equatable {
    public var x, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct NormRect: Equatable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
