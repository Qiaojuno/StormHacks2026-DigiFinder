import Foundation

public extension Vec3 {
    static let zero = Vec3(x: 0, y: 0, z: 0)

    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x + b.x, y: a.y + b.y, z: a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(x: a.x - b.x, y: a.y - b.y, z: a.z - b.z) }
    static func * (a: Vec3, s: Float) -> Vec3 { Vec3(x: a.x * s, y: a.y * s, z: a.z * s) }

    func dot(_ o: Vec3) -> Float { x * o.x + y * o.y + z * o.z }
    func cross(_ o: Vec3) -> Vec3 { Vec3(x: y * o.z - z * o.y, y: z * o.x - x * o.z, z: x * o.y - y * o.x) }
    var length: Float { dot(self).squareRoot() }
    var normalized: Vec3 { let l = length; return l > 0 ? self * (1 / l) : self }
}

public extension Mat3 {
    static let identity = Mat3()

    static func intrinsics(fx: Float, fy: Float, cx: Float, cy: Float) -> Mat3 {
        Mat3(m: [fx, 0, cx, 0, fy, cy, 0, 0, 1])
    }

    /// True when `m` holds 9 finite values. Accessors below treat a malformed matrix as identity.
    var isValid: Bool { m.count == 9 && m.allSatisfy(\.isFinite) }
    private var e: [Float] { isValid ? m : Mat3.identity.m }

    subscript(row: Int, col: Int) -> Float { e[row * 3 + col] }

    var fx: Float { e[0] }
    var fy: Float { e[4] }
    var cx: Float { e[2] }
    var cy: Float { e[5] }

    /// Intrinsics for the same lens at a different image size (e.g. reference dimensions → depth map size).
    func scaled(x sx: Float, y sy: Float) -> Mat3 {
        let m = e
        return Mat3(m: [m[0] * sx, m[1], m[2] * sx, m[3], m[4] * sy, m[5] * sy, m[6], m[7], m[8]])
    }

    func apply(_ v: Vec3) -> Vec3 {
        let m = e
        return Vec3(x: m[0] * v.x + m[1] * v.y + m[2] * v.z,
                    y: m[3] * v.x + m[4] * v.y + m[5] * v.z,
                    z: m[6] * v.x + m[7] * v.y + m[8] * v.z)
    }

    var transposed: Mat3 {
        let m = e
        return Mat3(m: [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]])
    }

    static func * (a: Mat3, b: Mat3) -> Mat3 {
        var out = [Float](repeating: 0, count: 9)
        for r in 0..<3 { for c in 0..<3 { out[r * 3 + c] = (0..<3).reduce(0) { $0 + a[r, $1] * b[$1, c] } } }
        return Mat3(m: out)
    }
}

public extension NormRect {
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var center: NormPoint { NormPoint(x: midX, y: midY) }
    var area: Double { max(width, 0) * max(height, 0) }

    func contains(_ p: NormPoint) -> Bool { p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY }

    func intersection(_ o: NormRect) -> NormRect? {
        let x0 = max(x, o.x), y0 = max(y, o.y), x1 = min(maxX, o.maxX), y1 = min(maxY, o.maxY)
        guard x1 > x0, y1 > y0 else { return nil }
        return NormRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Intersection over union, 0...1.
    func iou(_ o: NormRect) -> Double {
        guard let i = intersection(o) else { return 0 }
        let u = area + o.area - i.area
        return u > 0 ? i.area / u : 0
    }
}

/// The only converters into contract space (upright portrait, normalized, origin top-left).
public enum Geometry {
    /// Vision result (normalized, origin bottom-left, image already upright via orientation `.right`) → contract space.
    public static func fromVision(_ p: NormPoint) -> NormPoint { NormPoint(x: p.x, y: 1 - p.y) }

    public static func fromVision(_ r: NormRect) -> NormRect {
        NormRect(x: r.x, y: 1 - r.y - r.height, width: r.width, height: r.height)
    }

    /// Landscape sensor pixel (the buffer's own pixel grid, as used by intrinsics) → upright portrait, normalized.
    /// The back-camera buffer is shown upright by a 90° clockwise turn (Vision orientation `.right`):
    /// buffer row 0 becomes the right edge, buffer column 0 the top edge.
    public static func fromSensorPixels(_ p: (x: Double, y: Double), width: Double, height: Double) -> NormPoint {
        NormPoint(x: 1 - p.y / height, y: p.x / width)
    }

    /// Inverse of `fromSensorPixels`.
    public static func toSensorPixels(_ p: NormPoint, width: Double, height: Double) -> (x: Double, y: Double) {
        (x: p.y * width, y: (1 - p.x) * height)
    }

    /// Horizontal angle right of straight ahead (degrees, negative = left) for an upright-portrait x,
    /// using the sensor intrinsics (`sensorHeight` = buffer height in pixels, the portrait image's width).
    public static func degreesRight(portraitX x: Double, intrinsics k: Mat3, sensorHeight: Double) -> Double {
        let v = (1 - x) * sensorHeight
        return atan((Double(k.cy) - v) / Double(k.fy)) * 180 / .pi
    }

    /// Same, without intrinsics: from the portrait image's horizontal field of view (degrees).
    public static func degreesRight(portraitX x: Double, horizontalFOV fov: Double) -> Double {
        guard fov > 0, fov < 180 else { return 0 }
        return atan((x - 0.5) * 2 * tan(fov / 2 * .pi / 180)) * 180 / .pi
    }

    // MARK: - Angles and headings

    /// Any angle wrapped into (-180, 180]; non-finite → 0.
    public static func normalizeDegrees(_ a: Double) -> Double {
        guard a.isFinite else { return 0 }
        var r = a.truncatingRemainder(dividingBy: 360)
        if r > 180 { r -= 360 } else if r <= -180 { r += 360 }
        return r
    }

    /// Bearing of `target` relative to `heading`, both measured clockwise (turning right increases them), in (-180, 180].
    /// CoreMotion yaw grows counterclockwise: pass `-yawDegrees`.
    public static func relativeDegreesRight(heading: Double, target: Double) -> Double {
        normalizeDegrees(target - heading)
    }

    // MARK: - Pinhole camera (sensor pixels, intrinsics `[fx, 0, cx, 0, fy, cy, 0, 0, 1]`)

    /// Sensor pixel (u, v) at depth z (meters) → camera-space point (x right along u, y down along v, z forward).
    public static func unproject(u: Double, v: Double, depth z: Float, intrinsics k: Mat3) -> Vec3 {
        guard k.fx != 0, k.fy != 0 else { return Vec3(x: 0, y: 0, z: z) }
        return Vec3(x: (Float(u) - k.cx) * z / k.fx, y: (Float(v) - k.cy) * z / k.fy, z: z)
    }

    /// Camera-space point → sensor pixel; nil behind the camera.
    public static func project(_ p: Vec3, intrinsics k: Mat3) -> (x: Double, y: Double)? {
        guard p.z > 1e-4 else { return nil }
        return (x: Double(k.fx * p.x / p.z + k.cx), y: Double(k.fy * p.y / p.z + k.cy))
    }

    /// Distance from a box's apparent height (§5.2 doors: `fy × 2.1 m / boxHeightPx`).
    /// `normalizedHeight` is the box height in the upright portrait image (0...1); portrait height runs along
    /// the sensor's width, so the focal length is `fx` and `sensorWidth` is the buffer width in pixels.
    public static func distanceFromBoxHeight(normalizedHeight h: Double, objectHeight: Double = 2.1,
                                             intrinsics k: Mat3, sensorWidth: Double) -> Double? {
        let px = h * sensorWidth
        guard px > 0.5, objectHeight > 0, k.fx > 0 else { return nil }
        return Double(k.fx) * objectHeight / px
    }

    /// Fallback time to contact from box growth (§5.3, no LiDAR): TTC ≈ Δt · h / Δh. nil unless the box grows.
    public static func timeToContact(previousHeight h0: Double, currentHeight h1: Double, dt: Double) -> Double? {
        let dh = h1 - h0
        guard dt > 0, h1 > 0, dh > 1e-6 else { return nil }
        return dt * h1 / dh
    }

    // MARK: - Pointing (contract space: upright portrait, origin top-left)

    /// Pointed spot = index tip + (tip − DIP) × k (§5.2).
    public static func pointedSpot(tip: NormPoint, dip: NormPoint, extend k: Double = 1.5) -> NormPoint {
        NormPoint(x: tip.x + (tip.x - dip.x) * k, y: tip.y + (tip.y - dip.y) * k)
    }

    /// "up" / "down" / "left" / "right" to move the pointed spot onto the target; nil when it's already inside.
    public static func pointingDirection(from p: NormPoint, to target: NormRect) -> String? {
        if target.contains(p) { return nil }
        let dx = target.midX - p.x, dy = target.midY - p.y
        return abs(dx) > abs(dy) ? (dx > 0 ? "right" : "left") : (dy > 0 ? "down" : "up")
    }

    // MARK: - Phone flipped (§5.8)

    /// Depth almost all closer than `near` meters (lens against the body): share of valid samples ≥ `share`.
    public static func depthLooksBlocked(_ depths: [Float], near: Float = 0.2, share: Double = 0.9) -> Bool {
        let valid = depths.filter { $0.isFinite && $0 > 0 }
        guard valid.count >= 20 else { return false }
        return Double(valid.filter { $0 < near }.count) / Double(valid.count) >= share
    }
}

public extension Vec3 {
    func distance(to o: Vec3) -> Float { (self - o).length }
    /// Distance in the floor plane (x, z), ignoring height.
    var horizontalDistance: Float { (x * x + z * z).squareRoot() }
}

public extension NormPoint {
    func distance(to o: NormPoint) -> Double { ((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y)).squareRoot() }
}

public extension NormRect {
    func union(_ o: NormRect) -> NormRect {
        let x0 = min(x, o.x), y0 = min(y, o.y)
        return NormRect(x: x0, y: y0, width: max(maxX, o.maxX) - x0, height: max(maxY, o.maxY) - y0)
    }

    /// Clipped to the image (0...1); zero size when entirely outside.
    func clamped() -> NormRect {
        let x0 = min(max(x, 0), 1), y0 = min(max(y, 0), 1)
        let x1 = min(max(maxX, 0), 1), y1 = min(max(maxY, 0), 1)
        return NormRect(x: x0, y: y0, width: max(x1 - x0, 0), height: max(y1 - y0, 0))
    }
}
