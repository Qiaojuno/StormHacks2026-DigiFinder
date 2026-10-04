import Foundation

/// Read-only Safety values for the debug overlay (§6): `(env.safety as? SafetyDebugSource)?.debugSnapshot`.
/// Safe to read from any thread (a copy taken under a lock).
protocol SafetyDebugSource: AnyObject {
    var debugSnapshot: SafetyDebugSnapshot { get }
}
