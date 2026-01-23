import SwiftUI
import AVFoundation

/// UIViewRepresentable wrapper for AVCaptureVideoPreviewLayer
/// Displays the live camera feed in SwiftUI
struct CameraPreviewView: UIViewRepresentable {
    
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.setupPreviewLayer(session: cameraManager.captureSession)
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Preview layer updates automatically with session
    }
}

/// Custom UIView that hosts the AVCaptureVideoPreviewLayer
class CameraPreviewUIView: UIView {
    
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
    
    func setupPreviewLayer(session: AVCaptureSession) {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            // Fallback: create and add preview layer manually
            let newLayer = AVCaptureVideoPreviewLayer(session: session)
            newLayer.videoGravity = .resizeAspectFill
            newLayer.frame = bounds
            layer.addSublayer(newLayer)
            self.previewLayer = newLayer
            return
        }
        
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        self.previewLayer = previewLayer
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update preview layer frame when view resizes
        if let previewLayer = layer as? AVCaptureVideoPreviewLayer {
            previewLayer.frame = bounds
        } else {
            previewLayer?.frame = bounds
        }
    }
}

// MARK: - Preview Provider

#Preview {
    CameraPreviewView(cameraManager: CameraManager())
        .ignoresSafeArea()
}
