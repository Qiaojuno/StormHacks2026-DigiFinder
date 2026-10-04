import AVKit
import SwiftUI
import UIKit

/// Volume buttons via AVCaptureEventInteraction (needs a running capture session, app in foreground).
struct CaptureEventView: UIViewRepresentable {
    /// Volume up: start talking (or done, if already listening).
    let onTalk: () -> Void
    /// Volume down: done talking; ignored when not listening.
    let onDone: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        // Primary is expected to be volume down, secondary volume up. Verify on device (§10).
        view.addInteraction(AVCaptureEventInteraction(
            primary: { if $0.phase == .began { onDone() } },
            secondary: { if $0.phase == .began { onTalk() } }))
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
