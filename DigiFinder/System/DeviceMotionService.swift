import CoreMotion
import Foundation
import DigiFinderCore

/// CoreMotion: gravity (device frame, g, pointing down), camera heading (`SystemMotionHeading`), rotation rate,
/// pedometer steps since `start()`, and the motion state. Every sensor is availability-checked (the Simulator has
/// none: the state holds at Standing). Properties are thread-safe.
///
/// `isWalking` is the one motion state (layer 1) for everyone: Core's `MotionStateTracker` hysteresis over a 1.5 s
/// window of pedometer steps and user-acceleration spread (thresholds in `MotionTuning`). Safety reads it directly;
/// the runner forwards it to the session in `.motion(walking:)`. No ARKit (it can't share the cameras).
final class DeviceMotionService: MotionService {
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
    private var tracker = MotionStateTracker()

    init() {}

    var gravity: SIMD3<Float> { locked { _gravity } }
    var yawDegrees: Double { locked { _yaw } }
    /// Magnitude of the device rotation rate, rad/s.
    var rotationRate: Double { locked { _rate } }
    var steps: Int { locked { _steps } }

    var isWalking: Bool {
        locked { tracker.update(now: Self.now()) == .walking }
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
            locked { tracker.addSteps(t: Self.now(), total: 0) }
            pedometer.startUpdates(from: Date()) { [weak self] data, _ in
                guard let self, let data else { return }
                let n = data.numberOfSteps.intValue
                self.locked {
                    self.tracker.addSteps(t: Self.now(), total: n)
                    self._steps = n
                }
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
            tracker.addAcceleration(t: now, magnitude: mag)
        }
    }

    /// Movement signal for the debug overlay.
    var movement: MotionMovement { locked { tracker.movement(at: Self.now()) } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}
