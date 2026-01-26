import SwiftUI
import Vision

/// SwiftUI overlay view that draws the detected body skeleton
/// Renders joints as circles and connections as lines
struct SkeletonOverlayView: View {
    
    @ObservedObject var cameraManager: CameraManager
    
    // Colors matching CLI annotation style
    private let jointColor = Color.red
    private let connectionColor = Color.green.opacity(0.8)
    private let primaryArmColor = Color.yellow
    
    // Joint sizes
    private let jointRadius: CGFloat = 8
    private let primaryJointRadius: CGFloat = 12
    private let connectionWidth: CGFloat = 3
    private let primaryConnectionWidth: CGFloat = 6
    
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            
            // Draw connections first (so joints appear on top)
            ForEach(skeletonConnections, id: \.id) { connection in
                if let startPoint = convertPoint(connection.start, in: size),
                   let endPoint = convertPoint(connection.end, in: size) {
                    Path { path in
                        path.move(to: startPoint)
                        path.addLine(to: endPoint)
                    }
                    .stroke(
                        connectionColor(for: connection),
                        lineWidth: connectionWidth(for: connection)
                    )
                }
            }
            
            // Draw joints
            ForEach(Array(cameraManager.detectedJoints.keys), id: \.rawValue) { jointName in
                if let normalizedPoint = cameraManager.detectedJoints[jointName],
                   let confidence = cameraManager.jointConfidences[jointName],
                   confidence > 0.1 {
                    let screenPoint = convertToScreenPoint(normalizedPoint, in: size)
                    let isPrimary = isPrimaryArmJoint(jointName)
                    let radius = isPrimary ? primaryJointRadius : jointRadius
                    
                    Circle()
                        .fill(isPrimary ? primaryArmColor : jointColor)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(screenPoint)
                        .opacity(Double(confidence))
                }
            }
        }
    }
    
    // MARK: - Coordinate Conversion
    
    /// Convert normalized Vision coordinates to screen coordinates for the front camera.
    ///
    /// Coordinate systems:
    /// - Vision: Origin at bottom-left, Y increases upward (0,0) = bottom-left, (1,1) = top-right
    /// - SwiftUI: Origin at top-left, Y increases downward (0,0) = top-left
    ///
    /// Transformations applied:
    /// - X is flipped (1 - x) to mirror horizontally, matching the mirrored front camera preview
    /// - Y is flipped (1 - y) to convert from Vision's bottom-left origin to SwiftUI's top-left origin
    ///
    /// This works with .leftMirrored orientation hint passed to VNImageRequestHandler in CameraManager.
    private func convertToScreenPoint(_ normalizedPoint: CGPoint, in size: CGSize) -> CGPoint {
        return CGPoint(
            x: (1 - normalizedPoint.x) * size.width,   // Mirror X to match front camera preview
            y: (1 - normalizedPoint.y) * size.height   // Flip Y for SwiftUI's top-left origin
        )
    }
    
    /// Get screen point for a joint, if it exists
    private func convertPoint(_ jointName: VNHumanBodyPoseObservation.JointName, in size: CGSize) -> CGPoint? {
        guard let normalizedPoint = cameraManager.detectedJoints[jointName],
              let confidence = cameraManager.jointConfidences[jointName],
              confidence > 0.1 else {
            return nil
        }
        return convertToScreenPoint(normalizedPoint, in: size)
    }
    
    // MARK: - Primary Arm Detection
    
    private let leftArmJoints: Set<VNHumanBodyPoseObservation.JointName> = [
        .leftShoulder, .leftElbow, .leftWrist
    ]
    
    private let rightArmJoints: Set<VNHumanBodyPoseObservation.JointName> = [
        .rightShoulder, .rightElbow, .rightWrist
    ]
    
    private func isPrimaryArmJoint(_ joint: VNHumanBodyPoseObservation.JointName) -> Bool {
        switch cameraManager.primaryArm {
        case "LEFT":
            return leftArmJoints.contains(joint)
        case "RIGHT":
            return rightArmJoints.contains(joint)
        default:
            return false
        }
    }
    
    private func isPrimaryArmConnection(_ connection: SkeletonConnection) -> Bool {
        switch cameraManager.primaryArm {
        case "LEFT":
            return leftArmJoints.contains(connection.start) && leftArmJoints.contains(connection.end)
        case "RIGHT":
            return rightArmJoints.contains(connection.start) && rightArmJoints.contains(connection.end)
        default:
            return false
        }
    }
    
    private func connectionColor(for connection: SkeletonConnection) -> Color {
        isPrimaryArmConnection(connection) ? primaryArmColor : connectionColor
    }
    
    private func connectionWidth(for connection: SkeletonConnection) -> CGFloat {
        isPrimaryArmConnection(connection) ? primaryConnectionWidth : connectionWidth
    }
}

// MARK: - Skeleton Connection Definition

struct SkeletonConnection: Identifiable {
    let id: String
    let start: VNHumanBodyPoseObservation.JointName
    let end: VNHumanBodyPoseObservation.JointName
    
    init(_ start: VNHumanBodyPoseObservation.JointName, _ end: VNHumanBodyPoseObservation.JointName) {
        self.id = "\(start.rawValue.rawValue)-\(end.rawValue.rawValue)"
        self.start = start
        self.end = end
    }
}

/// Define all skeleton connections (matching VideoProcessor.swift)
let skeletonConnections: [SkeletonConnection] = [
    // Torso
    SkeletonConnection(.neck, .leftShoulder),
    SkeletonConnection(.neck, .rightShoulder),
    SkeletonConnection(.leftShoulder, .leftHip),
    SkeletonConnection(.rightShoulder, .rightHip),
    SkeletonConnection(.leftHip, .rightHip),
    
    // Left arm
    SkeletonConnection(.leftShoulder, .leftElbow),
    SkeletonConnection(.leftElbow, .leftWrist),
    
    // Right arm
    SkeletonConnection(.rightShoulder, .rightElbow),
    SkeletonConnection(.rightElbow, .rightWrist),
    
    // Left leg
    SkeletonConnection(.leftHip, .leftKnee),
    SkeletonConnection(.leftKnee, .leftAnkle),
    
    // Right leg
    SkeletonConnection(.rightHip, .rightKnee),
    SkeletonConnection(.rightKnee, .rightAnkle)
]

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        SkeletonOverlayView(cameraManager: CameraManager())
    }
    .ignoresSafeArea()
}
