import AVFoundation
import SwiftUI
import UIKit

/// Live camera preview (aspect-fill). Front-camera previews are mirrored by default, matching
/// the `.leftMirrored` orientation used for pose detection so the skeleton overlay lines up.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        // Safe: `layerClass` guarantees the layer type.
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Maps normalized Vision coordinates (origin bottom-left) into an aspect-filled view.
struct AspectFillMapping {
    let imageAspect: Double   // width / height of the analysed image
    let viewSize: CGSize

    func point(x: Double, y: Double) -> CGPoint {
        let imageWidth = imageAspect, imageHeight = 1.0
        let scale = max(viewSize.width / imageWidth, viewSize.height / imageHeight)
        let offsetX = (viewSize.width - imageWidth * scale) / 2
        let offsetY = (viewSize.height - imageHeight * scale) / 2
        return CGPoint(x: offsetX + x * imageWidth * scale, y: offsetY + (1 - y) * imageHeight * scale)
    }
}
