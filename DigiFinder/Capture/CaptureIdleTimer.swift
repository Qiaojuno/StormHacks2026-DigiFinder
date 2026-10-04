import Foundation
import UIKit

/// Keeps the screen awake while any frame source is running (§5.16 "Idle timer disabled for the whole session").
/// Callable from any thread; updates are applied in order on the main queue.
enum CaptureIdleTimer {
    @MainActor private static var holders = Set<ObjectIdentifier>()

    static func hold(_ owner: ObjectIdentifier, _ active: Bool) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if active { holders.insert(owner) } else { holders.remove(owner) }
                UIApplication.shared.isIdleTimerDisabled = !holders.isEmpty
            }
        }
    }
}
