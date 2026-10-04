import AVFoundation
import Foundation
import Network
import UIKit
import DigiFinderCore

/// §5.16 system events → `SystemEvent`, delivered on the main queue through `onEvent`:
/// - battery 20 % / 10 %, once each per run (not while charging);
/// - thermal state changes (the first report only if not nominal);
/// - audio route changes that matter (headphones / AirPods connected or lost; our own category switches are ignored);
/// - lifecycle: backgrounded on entering the background or an audio interruption (call, Siri);
///   foregrounded when active again;
/// - online from `NWPathMonitor`.
final class DeviceSystemMonitor: SystemMonitor {
    /// Route-change events closer together than this are merged.
    static let routeDebounceSeconds = 1.0

    private let lock = NSLock()
    private var handler: ((SystemEvent) -> Void)?
    private var online = false
    private var started = false
    private var reportedOnline: Bool?
    private var said20 = false
    private var said10 = false
    private var lastThermal: ThermalLevel?
    private var backgrounded = false
    private var lastRouteEventAt: Double = -.infinity

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "system.path")
    private var observers: [NSObjectProtocol] = []

    init() {}

    deinit {
        pathMonitor.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var onEvent: ((SystemEvent) -> Void)? {
        get { locked { handler } }
        set { locked { handler = newValue } }
    }

    var isOnline: Bool { locked { online } }

    /// Idempotent.
    func start() {
        let first: Bool = locked {
            defer { started = true }
            return !started
        }
        guard first else { return }

        pathMonitor.pathUpdateHandler = { [weak self] path in self?.pathChanged(path.status == .satisfied) }
        pathMonitor.start(queue: pathQueue)

        let center = NotificationCenter.default
        func observe(_ name: Notification.Name, _ object: Any? = nil, _ block: @escaping (Notification) -> Void) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main, using: block))
        }
        observe(ProcessInfo.thermalStateDidChangeNotification) { [weak self] _ in self?.checkThermal() }
        observe(AVAudioSession.routeChangeNotification) { [weak self] note in self?.routeChanged(note) }
        observe(AVAudioSession.interruptionNotification) { [weak self] note in self?.interrupted(note) }
        observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in self?.setBackgrounded(true) }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in self?.setBackgrounded(false) }
        observe(UIDevice.batteryLevelDidChangeNotification) { [weak self] _ in self?.checkBattery() }
        observe(UIDevice.batteryStateDidChangeNotification) { [weak self] _ in self?.checkBattery() }

        Task { @MainActor [weak self] in
            UIDevice.current.isBatteryMonitoringEnabled = true
            self?.checkBattery()
        }
        checkThermal()
    }

    // MARK: Sources

    private func pathChanged(_ satisfied: Bool) {
        let changed: Bool = locked {
            online = satisfied
            defer { reportedOnline = satisfied }
            return reportedOnline != satisfied
        }
        if changed { emit(.online(satisfied)) }
    }

    private func checkThermal() {
        let level: ThermalLevel
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: level = .nominal
        case .fair: level = .fair
        case .serious: level = .serious
        case .critical: level = .critical
        @unknown default: level = .serious
        }
        let send: Bool = locked {
            defer { lastThermal = level }
            if let last = lastThermal { return last != level }
            return level != .nominal
        }
        if send { emit(.thermal(level)) }
    }

    private func routeChanged(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let send: Bool = locked {
            guard now - lastRouteEventAt >= Self.routeDebounceSeconds else { return false }
            lastRouteEventAt = now
            return true
        }
        if send { emit(.audioRouteChanged) }
    }

    private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            setBackgrounded(true)
        case .ended:
            MainActor.assumeIsolated {
                if UIApplication.shared.applicationState == .active { setBackgrounded(false) }
            }
        @unknown default:
            break
        }
    }

    private func setBackgrounded(_ value: Bool) {
        let changed: Bool = locked {
            defer { backgrounded = value }
            return backgrounded != value
        }
        if changed { emit(value ? .backgrounded : .foregrounded) }
    }

    private func checkBattery() {
        let (level, state) = MainActor.assumeIsolated {
            (UIDevice.current.batteryLevel, UIDevice.current.batteryState)
        }
        guard level >= 0, state != .charging, state != .full else { return }
        let percent = Int((level * 100).rounded())
        let send: Int? = locked {
            if percent <= 10 && !said10 { said10 = true; said20 = true; return percent }
            if percent <= 20 && !said20 { said20 = true; return percent }
            return nil
        }
        if let send { emit(.batteryLow(send)) }
    }

    // MARK: Helpers

    private func emit(_ e: SystemEvent) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(e) }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
