// Clock directions (§5.5): 12 ahead, 3 right, 9 left, 6 behind; "slightly right/left" = 1/11 o'clock;
// turn cues "Turn to 9 o'clock." Hand guidance at the shelf uses up/down/left/right instead.

/// Clock hour (1...12) for a horizontal angle right of straight ahead (degrees; negative = left).
/// Any angle is accepted (wrapped to -180...180); non-finite angles give 12.
public func clockPosition(degreesRight angle: Double) -> Int {
    let a = Geometry.normalizeDegrees(angle)
    let hour = Int((a / 30).rounded())          // -6 ... 6
    return hour <= 0 ? 12 + hour : hour
}

/// Clock hour for an upright-portrait x (0...1) using the sensor intrinsics (see `Geometry.degreesRight`).
public func clockPosition(portraitX x: Double, intrinsics k: Mat3, sensorHeight: Double) -> Int {
    clockPosition(degreesRight: Geometry.degreesRight(portraitX: x, intrinsics: k, sensorHeight: sensorHeight))
}

/// Clock hour for an upright-portrait x (0...1) from the image's horizontal field of view.
public func clockPosition(portraitX x: Double, horizontalFOV fov: Double) -> Int {
    clockPosition(degreesRight: Geometry.degreesRight(portraitX: x, horizontalFOV: fov))
}

/// Angle right of ahead for a clock hour: 12 → 0, 3 → 90, 9 → -90, 6 → 180.
public func clockDegrees(_ clock: Int) -> Double {
    let c = normalizedClock(clock)
    return c <= 6 ? Double(c % 12) * 30 : Double(c - 12) * 30
}

/// Any integer folded into 1...12 (0 → 12, 13 → 1, -1 → 11).
public func normalizedClock(_ clock: Int) -> Int {
    let m = ((clock % 12) + 12) % 12
    return m == 0 ? 12 : m
}

/// "9 o'clock".
public func clockPhrase(_ clock: Int) -> String { "\(normalizedClock(clock)) o'clock" }

/// "Turn to 9 o'clock."
public func clockTurnCue(_ clock: Int) -> String { "Turn to \(clockPhrase(clock))." }

/// Plain words for a clock hour: 12 "ahead", 1 "slightly right", 11 "slightly left", 2–4 "right", 8–10 "left", 5–7 "behind".
public func clockRelativeWords(_ clock: Int) -> String {
    switch normalizedClock(clock) {
    case 12: return "ahead"
    case 1: return "slightly right"
    case 11: return "slightly left"
    case 2, 3, 4: return "right"
    case 8, 9, 10: return "left"
    default: return "behind"
    }
}

/// Clock hour for spoken or written directions ("slightly right" → 1, "on your left" → 9, "straight ahead" → 12,
/// "behind you" → 6, "2 o'clock" → 2). nil when there's no direction.
public func clockPosition(relative words: String) -> Int? {
    let t = normalizeText(words)
    let w = t.split(separator: " ").map(String.init)
    if let i = w.firstIndex(of: "o"), i > 0, i + 1 < w.count, w[i + 1] == "clock", let h = Int(w[i - 1]), (1...12).contains(h) {
        return h
    }
    let slight = ["slightly", "little", "bit", "bear"].contains(where: w.contains)
    if w.contains("right") { return slight ? 1 : 3 }
    if w.contains("left") { return slight ? 11 : 9 }
    if w.contains("behind") || w.contains("back") { return 6 }
    if w.contains("ahead") || w.contains("front") || w.contains("straight") || w.contains("forward") { return 12 }
    return nil
}
