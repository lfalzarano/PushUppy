import SwiftUI

/// Full-screen pushup recording session view
/// Displays camera feed with skeleton overlay and info panel
struct PushupSessionView: View {
    
    @ObservedObject var cameraManager: CameraManager
    @Binding var isPresented: Bool
    
    /// Callback when session ends, provides final count for future storage
    var onSessionEnd: ((Int) -> Void)?
    
    @State private var showEndConfirmation = false
    
    var body: some View {
        ZStack {
            // Full-bleed camera preview
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            // Skeleton overlay (only visible when body detected and recording)
            if cameraManager.isRecording && cameraManager.bodyDetected {
                SkeletonOverlayView(cameraManager: cameraManager)
                    .ignoresSafeArea()
            }
            
            // UI Overlays
            VStack {
                // Top bar: Info panel (left) and close button (right)
                HStack(alignment: .top) {
                    // Info panel
                    if cameraManager.isRecording {
                        InfoPanelOverlayView(cameraManager: cameraManager)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Close button
                    CloseButton {
                        endSession()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 60) // Account for safe area
                
                Spacer()
                
                // Bottom: Recording indicator and large count display
                VStack(spacing: 20) {
                    if cameraManager.isRecording {
                        // Large pushup count display
                        VStack(spacing: 4) {
                            Text("\(cameraManager.pushupCount)")
                                .font(.system(size: 120, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.5), radius: 10)
                            
                            Text("PUSHUPS")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.bottom, 40)
                    }
                    
                    // Recording indicator
                    RecordingIndicator(isRecording: cameraManager.isRecording)
                        .padding(.bottom, 50)
                }
            }
            
            // No camera permission overlay
            if !cameraManager.permissionGranted {
                NoCameraPermissionView()
            }
        }
        .statusBarHidden()
        .onAppear {
            cameraManager.startSession()
            cameraManager.startRecording()
        }
        .onDisappear {
            cameraManager.stopRecording()
        }
        .confirmationDialog(
            "End Session?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                finalizeSession()
            }
            Button("Continue", role: .cancel) {}
        } message: {
            Text("You've completed \(cameraManager.pushupCount) pushups. End this session?")
        }
    }
    
    // MARK: - Session Management
    
    private func endSession() {
        if cameraManager.pushupCount > 0 {
            showEndConfirmation = true
        } else {
            finalizeSession()
        }
    }
    
    private func finalizeSession() {
        let finalCount = cameraManager.pushupCount
        cameraManager.stopRecording()
        onSessionEnd?(finalCount)
        isPresented = false
    }
}

// MARK: - Close Button

struct CloseButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 8)
    }
}

// MARK: - Recording Indicator

struct RecordingIndicator: View {
    let isRecording: Bool
    
    @State private var isPulsing = false
    
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isRecording ? Color.red : Color.gray)
                .frame(width: 12, height: 12)
                .scaleEffect(isPulsing ? 1.2 : 1.0)
                .animation(
                    isRecording ?
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                        .default,
                    value: isPulsing
                )
            
            Text(isRecording ? "RECORDING" : "STOPPED")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            isPulsing = isRecording
        }
        .onChange(of: isRecording) { _, newValue in
            isPulsing = newValue
        }
    }
}

// MARK: - No Camera Permission View

struct NoCameraPermissionView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.6))
            
            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("PushUppy needs camera access to detect your pushups. Please enable camera access in Settings.")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
}

// MARK: - Preview

#Preview {
    PushupSessionView(
        cameraManager: CameraManager(),
        isPresented: .constant(true)
    )
}
