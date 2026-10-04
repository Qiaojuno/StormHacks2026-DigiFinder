import AVFoundation
import SwiftUI
import UIKit

/// Live 0.5× (Stream B) feed for the Home background. The view model hands the layer to Capture, which connects it
/// to the running session.
struct UICameraPreview: UIViewRepresentable {
    let attach: (AVCaptureVideoPreviewLayer) -> Void

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer? { layer as? AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        if let layer = view.previewLayer {
            layer.videoGravity = .resizeAspectFill
            attach(layer)
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
