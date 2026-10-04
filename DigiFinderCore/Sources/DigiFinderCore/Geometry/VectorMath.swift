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

    subscript(row: Int, col: Int) -> Float { m[row * 3 + col] }

    var fx: Float { m[0] }
    var fy: Float { m[4] }
    var cx: Float { m[2] }
    var cy: Float { m[5] }

    /// Intrinsics for the same lens at a different image size (e.g. reference dimensions → depth map size).
    func scaled(x sx: Float, y sy: Float) -> Mat3 {
        Mat3(m: [m[0] * sx, m[1], m[2] * sx, m[3], m[4] * sy, m[5] * sy, m[6], m[7], m[8]])
    }

    func apply(_ v: Vec3) -> Vec3 {
        Vec3(x: m[0] * v.x + m[1] * v.y + m[2] * v.z,
             y: m[3] * v.x + m[4] * v.y + m[5] * v.z,
             z: m[6] * v.x + m[7] * v.y + m[8] * v.z)
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
        atan((x - 0.5) * 2 * tan(fov / 2 * .pi / 180)) * 180 / .pi
    }
}
