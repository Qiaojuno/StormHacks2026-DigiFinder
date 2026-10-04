// Clock directions (§5.5): 12 ahead, 3 right, 9 left, 6 behind.

public func clockPosition(degreesRight angle: Double) -> Int {
    let hour = Int((angle / 30).rounded()); return hour <= 0 ? 12 + hour : hour
}
