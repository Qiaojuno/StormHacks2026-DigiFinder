import CoreMotion
import Foundation

/// CoreMotion: gravity (device frame, g, pointing down), camera heading (`SystemMotionHeading`), rotation rate,
/// pedometer steps since `start()`, walking flag. Every sensor is availability-checked (the Simulator has none and
/// keeps the defaults). Properties are thread-safe.
final class DeviceMotionService: MotionService {
    /// Walking needs a step within this many seconds (or a pedometer "resume" event).
    static let recentStepSeconds = 3.5
    /// Below this user-acceleration spread (g) over the window the phone is still: not walking.
    static let stillAccelStd = 0.02
    /// Without a pedometer, above this spread counts as walking.
    static let walkingAccelStd = 0.06
    static let accelWindowSeconds = 1.5

    private let manager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "system.motion"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private let lock = NSLock()
    private var started = false
    private var _gravity = SIMD3<Float>(0, -1, 0)
    private var _yaw: Double = 0
    private var _rate: Double = 0
    private var _steps = 0
    private var lastStepAt: Double?
    private var pedometerWalking: Bool?
    private var hasPedometer = false
    private var accel: [(t: Double, g: Double)] = []

    init() {}

    var gravity: SIMD3<Float> { locked { _gravity } }
    var yawDegrees: Double { locked { _yaw } }
    /// Magnitude of the device rotation rate, rad/s.
    var rotationRate: Double { locked { _rate } }
    var steps: Int { locked { _steps } }

    var isWalking: Bool {
        locked {
            let now = Self.now()
            let std = accelStd(now: now)
            if let std, std < Self.stillAccelStd { return false }
            if pedometerWalking == true { return true }
            if let last = lastStepAt, now - last <= Self.recentStepSeconds { return true }
            if !hasPedometer, let std { return std > Self.walkingAccelStd }
            return false
        }
    }

    func start() {
        let first: Bool = locked {
            defer { started = true }
            return !started
        }
        guard first else { return }

        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 1.0 / 30
            let frame: CMAttitudeReferenceFrame =
                CMMotionManager.availableAttitudeReferenceFrames().contains(.xArbitraryZVertical)
                    ? .xArbitraryZVertical : .xArbitraryCorrectedZVertical
            manager.startDeviceMotionUpdates(using: frame, to: motionQueue) { [weak self] motion, _ in
                guard let self, let motion else { return }
                self.handle(motion)
            }
        }
        if CMPedometer.isStepCountingAvailable() {
            locked { hasPedometer = true }
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self, let data else { return }
                let n = data.numberOfSteps.intValue
                self.locked {
                    if n > self._steps { self.lastStepAt = Self.now() }
                    self._steps = n
                }
            }
        }
        if CMPedometer.isPedometerEventTrackingAvailable() {
            pedometer.startEventUpdates { [weak self] event, _ in
                guard let self, let event else { return }
                self.locked { self.pedometerWalking = event.type == .resume }
            }
        }
    }

    private func handle(_ m: CMDeviceMotion) {
        let g = SIMD3(m.gravity.x, m.gravity.y, m.gravity.z)
        let yaw = SystemMotionHeading.yawDegrees(m.attitude.rotationMatrix, gravity: g)
        let r = m.rotationRate
        let rate = (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot()
        let a = m.userAcceleration
        let mag = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
        let now = Self.now()
        locked {
            _gravity = SIMD3<Float>(Float(g.x), Float(g.y), Float(g.z))
            if let yaw { _yaw = yaw }
            _rate = rate
            accel.append((now, mag))
            if let i = accel.firstIndex(where: { now - $0.t <= Self.accelWindowSeconds }), i > 0 {
                accel.removeFirst(i)
            }
        }
    }

    /// Standard deviation of user acceleration over the window; nil until the window is mostly full. Call locked.
    private func accelStd(now: Double) -> Double? {
        let recent = accel.filter { now - $0.t <= Self.accelWindowSeconds }
        guard recent.count >= 20 else { return nil }
        let mean = recent.map(\.g).reduce(0, +) / Double(recent.count)
        let v = recent.map { ($0.g - mean) * ($0.g - mean) }.reduce(0, +) / Double(recent.count)
        return v.squareRoot()
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}
