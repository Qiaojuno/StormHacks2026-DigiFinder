import SwiftUI

/// Shown when `capabilities.cameraAvailable` is false. In the Simulator it hosts the debug panel
/// (typed requests + event buttons) that drives the session.
struct CameraUnavailableView: View {
    let debug: DebugViewModel
    let showsDebugPanel: Bool
    let isWalking: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Camera unavailable", systemImage: "video.slash")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(showsDebugPanel
                         ? "Simulator: type a request or send test events below."
                         : "Camera access may be off. Ask someone to turn it on in Settings.")
                        .font(.body)
                        .foregroundStyle(UITheme.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(UITheme.panel))
                .accessibilityElement(children: .combine)

                if showsDebugPanel {
                    UIDebugPanelView(debug: debug)
                        .disabled(isWalking)
                }
            }
        }
        .scrollIndicators(.visible)
    }
}
