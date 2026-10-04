// Wave 1 compiling stubs. The Voice-Feedback-Network-System agent replaces these (one file per type).
import Foundation
import DigiFinderCore

/// Battery, thermal, audio route, lifecycle, orientation, NWPathMonitor (§5.16).
final class DeviceSystemMonitor: SystemMonitor {
    var onEvent: ((SystemEvent) -> Void)?
    private(set) var isOnline = false
    func start() {}
}

/// CoreMotion: gravity, yaw, rotation rate, pedometer steps, walking.
final class DeviceMotionService: MotionService {
    private(set) var gravity = SIMD3<Float>(0, -1, 0)
    private(set) var yawDegrees: Double = 0
    private(set) var rotationRate: Double = 0
    private(set) var isWalking = false
    private(set) var steps = 0
    func start() {}
}
