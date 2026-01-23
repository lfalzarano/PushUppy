import Foundation
import AVFoundation
import Vision
import Combine

/// Manages camera capture session, frame processing, and Vision body pose detection
class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties (for SwiftUI binding)
    
    /// All detected joint positions in normalized coordinates (0-1)
    @Published var detectedJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    
    /// Joint confidence values for filtering low-confidence detections
    @Published var jointConfidences: [VNHumanBodyPoseObservation.JointName: Float] = [:]
    
    /// Current pushup state from detector
    @Published var pushupState: PushupState = .unknown
    
    /// Total pushup count in current session
    @Published var pushupCount: Int = 0
    
    /// Current elbow angle (degrees)
    @Published var elbowAngle: Double? = nil
    
    /// Which arm is being tracked ("LEFT", "RIGHT", or "none")
    @Published var primaryArm: String = "none"
    
    /// Whether detection is active (recording mode)
    @Published var isRecording: Bool = false
    
    /// Whether body is currently detected in frame
    @Published var bodyDetected: Bool = false
    
    /// Camera authorization status
    @Published var permissionGranted: Bool = false
    
    // MARK: - Camera Components
    
    let captureSession = AVCaptureSession()
    private var videoOutput: AVCaptureVideoDataOutput?
    private let videoOutputQueue = DispatchQueue(label: "com.pushuppy.videoOutput", qos: .userInteractive)
    
    // MARK: - Detection Components
    
    private let detector = PushupDetector()
    private var lastProcessedTime: TimeInterval = 0
    private let minProcessingInterval: TimeInterval = 1.0 / 30.0 // Cap at 30 FPS for detection
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    // MARK: - Permission Handling
    
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permissionGranted = true
            setupCamera()
        case .notDetermined:
            requestPermission()
        case .denied, .restricted:
            permissionGranted = false
        @unknown default:
            permissionGranted = false
        }
    }
    
    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.permissionGranted = granted
                if granted {
                    self?.setupCamera()
                }
            }
        }
    }
    
    // MARK: - Camera Setup
    
    private func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        // Find front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            print("❌ Front camera not available")
            captureSession.commitConfiguration()
            return
        }
        
        // Configure camera input
        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            print("❌ Error setting up camera input: \(error)")
            captureSession.commitConfiguration()
            return
        }
        
        // Configure video output for frame processing
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)
        
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoOutput = output
            
            // Configure video orientation
            if let connection = output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                // Mirror front camera
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
        }
        
        captureSession.commitConfiguration()
    }
    
    // MARK: - Session Control
    
    func startSession() {
        guard !captureSession.isRunning else { return }
        
        videoOutputQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    func stopSession() {
        guard captureSession.isRunning else { return }
        
        videoOutputQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    
    // MARK: - Recording Control
    
    func startRecording() {
        detector.reset()
        DispatchQueue.main.async {
            self.pushupCount = 0
            self.pushupState = .unknown
            self.elbowAngle = nil
            self.primaryArm = "none"
            self.isRecording = true
        }
    }
    
    func stopRecording() {
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    /// Get the current session data for future storage
    func getCurrentSessionData() -> (count: Int, state: PushupState) {
        return (pushupCount, pushupState)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Only process if recording
        guard isRecording else {
            // Clear detected joints when not recording
            if bodyDetected {
                DispatchQueue.main.async {
                    self.bodyDetected = false
                    self.detectedJoints = [:]
                    self.jointConfidences = [:]
                }
            }
            return
        }
        
        // Throttle processing to target FPS
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastProcessedTime >= minProcessingInterval else { return }
        lastProcessedTime = currentTime
        
        // Get pixel buffer from sample
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Create Vision request
        let request = VNDetectHumanBodyPoseRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Vision error: \(error)")
                return
            }
            
            self.processBodyPoseResults(request.results)
        }
        
        // Perform detection
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform Vision request: \(error)")
        }
    }
    
    private func processBodyPoseResults(_ results: [Any]?) {
        guard let observations = results as? [VNHumanBodyPoseObservation],
              let observation = observations.first else {
            // No body detected
            DispatchQueue.main.async {
                self.bodyDetected = false
                self.detectedJoints = [:]
                self.jointConfidences = [:]
            }
            return
        }
        
        // Extract joint positions
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else {
            return
        }
        
        // Run pushup detection
        let result = detector.detectPushup(observation: observation)
        
        // Convert recognized points to dictionary format
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        var confidences: [VNHumanBodyPoseObservation.JointName: Float] = [:]
        
        for (jointName, point) in recognizedPoints {
            // Only include joints with reasonable confidence
            if point.confidence > 0.1 {
                joints[jointName] = point.location
                confidences[jointName] = point.confidence
            }
        }
        
        // Update published properties on main thread
        DispatchQueue.main.async {
            self.bodyDetected = true
            self.detectedJoints = joints
            self.jointConfidences = confidences
            self.pushupState = result.state
            self.pushupCount = result.count
            self.elbowAngle = result.elbowAngle
            self.primaryArm = result.primaryArm
        }
    }
}
