// Wave 1 compiling stubs. The UI agent replaces these (one file per view).
import SwiftUI

/// Drag-to-hear + double-tap surface when still (§5.10).
struct AccessibleSurface: View {
    var body: some View { Color.clear }
}

/// One-sheet setup (§5.13).
struct SetupView: View {
    var body: some View { Text("Setup") }
}

/// Judges' debug overlay; in the Simulator, typed requests + event buttons (§6).
struct DebugOverlayView: View {
    var body: some View { Text("Debug") }
}

struct CameraUnavailableView: View {
    var body: some View { Text("Camera unavailable") }
}

/// Open Food Facts (ODbL), USDA, Ultralytics YOLO (AGPL-3.0) credits (§7.1).
struct LicensesView: View {
    var body: some View { Text("Licenses") }
}
