// Wave 1 stub. The UI agent implements the debug panel (typed requests + event buttons, §6).
import Foundation
import Observation

@Observable @MainActor
final class DebugViewModel {
    var typedRequest = ""
}
