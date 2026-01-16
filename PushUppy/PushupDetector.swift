import Foundation
import Vision

// MARK: - Data Models
enum PushupState: String, Codable {
    case up = "UP"
    case descending = "DESCENDING"
    case down = "DOWN"
    case ascending = "ASCENDING"
    case unknown = "UNKNOWN"
    case standing = "STANDING"  // New state for when user is standing upright
}

// MARK: - Coordinate Smoother (Simple Moving Average)
class CoordinateSmoother {
    private var history: [CGPoint] = []
    private let windowSize: Int
    
    init(windowSize: Int = 3) {
        self.windowSize = windowSize
    }
    
    func smooth(_ point: CGPoint) -> CGPoint {
        history.append(point)
        if history.count > windowSize {
            history.removeFirst()
        }
        
        let sumX = history.reduce(0) { $0 + $1.x }
        let sumY = history.reduce(0) { $0 + $1.y }
        let count = CGFloat(history.count)
        
        return CGPoint(x: sumX / count, y: sumY / count)
    }
    
    func reset() {
        history.removeAll()
    }
}

// MARK: - Arm Data
struct ArmData {
    let shoulder: CGPoint
    let elbow: CGPoint
    let wrist: CGPoint
    let confidence: Float
    let isLeft: Bool
    
    /// Calculate the 2D distance from shoulder to wrist (arm length in screen space)
    var armLength: CGFloat {
        let dx = wrist.x - shoulder.x
        let dy = wrist.y - shoulder.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Pushup Detection Algorithm (Robust Multi-Angle)
class PushupDetector {
    private var currentState: PushupState = .unknown
    private var previousState: PushupState = .unknown
    private var lastKnownActiveState: PushupState = .unknown  // Persist last non-unknown state
    private(set) var pushupCount = 0
    
    // Thresholds based on strategy document
    private let upAngleThreshold: Double = 150.0      // State 0: Arms nearly straight
    private let downAngleThreshold: Double = 90.0     // State 2: Depth threshold
    private let relaxedDownAngleThreshold: Double = 105.0  // Relaxed threshold for front-facing view
    private let minConfidence: Float = 0.3            // Minimum joint confidence
    private let relaxedMinConfidence: Float = 0.15    // More relaxed threshold for partial visibility
    
    // Temporal buffer: require N consecutive frames in new state before transitioning
    private let stateChangeFrameBuffer: Int = 2
    private let standingStateFrameBuffer: Int = 30  // ~1 second grace period for standing detection
    private var pendingState: PushupState = .unknown
    private var pendingStateFrameCount: Int = 0
    
    // Stable UP state tracking for standing detection
    private var stableUpStateFrameCount: Int = 0
    private let stableUpFramesForStanding: Int = 60  // ~2 seconds in stable UP before allowing standing
    
    // Coordinate smoothing
    private var leftShoulderSmoother = CoordinateSmoother()
    private var leftElbowSmoother = CoordinateSmoother()
    private var leftWristSmoother = CoordinateSmoother()
    private var rightShoulderSmoother = CoordinateSmoother()
    private var rightElbowSmoother = CoordinateSmoother()
    private var rightWristSmoother = CoordinateSmoother()
    
    // Angle tracking for direction detection
    private var previousAngle: Double?
    private var angleHistory: [Double] = []
    private let angleHistorySize = 5
    
    // Primary arm tracking with HYSTERESIS (prevents arm-swap glitches)
    private(set) var primaryArmIsLeft: Bool = true
    private var currentPrimaryArmConfidence: Float = 0
    private var alternateArmHigherConfidenceFrames: Int = 0
    private let armSwitchConfidenceMargin: Float = 1.2  // New arm must be 20% more confident
    private let armSwitchFrameThreshold: Int = 5        // Must maintain higher confidence for 5 frames
    
    // Face-camera detection (when elbows go behind the body)
    private var isFacingCamera: Bool = false
    
    // Z-AXIS DEPTH COMPENSATION: Arm length tracking
    private var baseArmLength: CGFloat?  // Captured in UP state
    private let armCompressionThreshold: CGFloat = 0.70  // 30% compression triggers relaxed threshold
    
    // VERTICAL DISPLACEMENT: Shoulder Y tracking
    private var upStateShoulderY: CGFloat?  // Shoulder Y position captured in UP state
    private let minShoulderDropRatio: CGFloat = 0.08  // Shoulder must drop at least 8% of screen height
    
    func reset() {
        currentState = .unknown
        previousState = .unknown
        lastKnownActiveState = .unknown
        pushupCount = 0
        pendingState = .unknown
        pendingStateFrameCount = 0
        previousAngle = nil
        angleHistory.removeAll()
        isFacingCamera = false
        
        // Reset arm tracking
        currentPrimaryArmConfidence = 0
        alternateArmHigherConfidenceFrames = 0
        
        // Reset depth compensation
        baseArmLength = nil
        
        // Reset vertical displacement tracking
        upStateShoulderY = nil
        sawValidShoulderDropInCycle = false
        
        // Reset stable UP tracking
        stableUpStateFrameCount = 0
        
        // Reset smoothers
        leftShoulderSmoother.reset()
        leftElbowSmoother.reset()
        leftWristSmoother.reset()
        rightShoulderSmoother.reset()
        rightElbowSmoother.reset()
        rightWristSmoother.reset()
    }
    
    func detectPushup(observation: VNHumanBodyPoseObservation) -> (state: PushupState, count: Int, elbowAngle: Double?, primaryArm: String) {
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else {
            // Return last known state instead of unknown
            return (lastKnownActiveState != .unknown ? lastKnownActiveState : .unknown, pushupCount, nil, "none")
        }
        
        // Detect if user is facing camera FIRST (affects standing detection logic)
        isFacingCamera = detectFacingCamera(from: recognizedPoints)
        
        // STATE-LOCKED STANDING DETECTION:
        // Only check for standing if we meet ALL of these conditions:
        // 1. NOT in an active rep cycle (descending/down/ascending)
        // 2. Been in stable UP state for at least 2 seconds (stableUpFramesForStanding)
        // 3. Pass the "Horizontal-First" detection checks
        let inActiveRepCycle = (currentState == .descending || currentState == .down || currentState == .ascending)
        let inStableUpLongEnough = (currentState == .up && stableUpStateFrameCount >= stableUpFramesForStanding)
        let canConsiderStanding = !inActiveRepCycle && (currentState == .unknown || currentState == .standing || inStableUpLongEnough)
        
        if canConsiderStanding && shouldDetectAsStanding(from: recognizedPoints) {
            // Reset tracking data when standing to prevent stale data
            resetTrackingDataOnStanding()
            currentState = .standing
            stableUpStateFrameCount = 0
            return (.standing, pushupCount, nil, "standing")
        }
        
        // Get arm data with confidence-based selection and HYSTERESIS
        guard let primaryArmData = selectPrimaryArmWithHysteresis(from: recognizedPoints) else {
            // Return last known state instead of unknown when no arm detected
            if lastKnownActiveState != .unknown {
                return (lastKnownActiveState, pushupCount, nil, "none")
            }
            return (.unknown, pushupCount, nil, "none")
        }
        
        primaryArmIsLeft = primaryArmData.isLeft
        currentPrimaryArmConfidence = primaryArmData.confidence
        
        // Apply coordinate smoothing
        let smoothedShoulder = primaryArmData.isLeft 
            ? leftShoulderSmoother.smooth(primaryArmData.shoulder)
            : rightShoulderSmoother.smooth(primaryArmData.shoulder)
        let smoothedElbow = primaryArmData.isLeft
            ? leftElbowSmoother.smooth(primaryArmData.elbow)
            : rightElbowSmoother.smooth(primaryArmData.elbow)
        let smoothedWrist = primaryArmData.isLeft
            ? leftWristSmoother.smooth(primaryArmData.wrist)
            : rightWristSmoother.smooth(primaryArmData.wrist)
        
        // Calculate current arm length for depth compensation
        let currentArmLength = calculateArmLength(shoulder: smoothedShoulder, wrist: smoothedWrist)
        
        // Calculate interior elbow angle
        let elbowAngle = calculateElbowAngle(
            shoulder: smoothedShoulder,
            elbow: smoothedElbow,
            wrist: smoothedWrist
        )
        
        // Check for face-camera down position using shoulder/face relative to elbow
        let faceCameraDownDetected = isFacingCamera && detectFaceCameraDown(from: recognizedPoints, elbow: smoothedElbow)
        
        // Calculate arm compression ratio for depth compensation
        let armCompressionRatio = calculateArmCompressionRatio(currentLength: currentArmLength)
        
        // Track angle history for direction detection
        angleHistory.append(elbowAngle)
        if angleHistory.count > angleHistorySize {
            angleHistory.removeFirst()
        }
        
        // Determine angle direction (increasing = extending, decreasing = bending)
        let angleDirection = determineAngleDirection()
        
        // Calculate vertical displacement for shoulder travel validation
        let shoulderY = smoothedShoulder.y
        let validShoulderDrop = validateShoulderDrop(currentShoulderY: shoulderY)
        
        // Determine raw state with all robustness features
        let rawState = determineRawState(
            angle: elbowAngle,
            direction: angleDirection,
            faceCameraDownDetected: faceCameraDownDetected,
            armCompressionRatio: armCompressionRatio,
            validShoulderDrop: validShoulderDrop
        )
        
        // Capture calibration data when in UP state
        if rawState == .up {
            captureUpStateCalibration(armLength: currentArmLength, shoulderY: shoulderY)
        }
        
        // Apply temporal buffer for state stability
        let stableState = applyTemporalBuffer(rawState: rawState)
        
        // Update state and count reps (with shoulder drop validation)
        updateStateAndCount(newState: stableState, validShoulderDrop: validShoulderDrop)
        
        previousAngle = elbowAngle
        
        // Track stable UP state duration (for standing detection eligibility)
        updateStableUpTracking(newState: currentState)
        
        // Track last known active state (non-unknown, non-standing)
        if currentState != .unknown && currentState != .standing {
            lastKnownActiveState = currentState
        }
        
        let armName = primaryArmData.isLeft ? "LEFT" : "RIGHT"
        return (currentState, pushupCount, elbowAngle, armName)
    }
    
    // MARK: - Standing Reset Helper
    
    /// Resets tracking data when user is standing to prevent stale data from counting reps
    private func resetTrackingDataOnStanding() {
        angleHistory.removeAll()
        pendingState = .unknown
        pendingStateFrameCount = 0
        baseArmLength = nil
        upStateShoulderY = nil
    }
    
    // MARK: - Standing Detection (Horizontal-First Strategy)
    
    /// Main standing detection entry point with temporal buffering and state-locking
    /// Uses "Horizontal-First" validation - detects pushup-ready position instead of standing
    private func shouldDetectAsStanding(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        // RULE 1: If user is horizontal (pushup-ready), definitely NOT standing
        if isHorizontal(from: points) {
            return false
        }
        
        // RULE 2: If facing camera, disable vertical-based standing detection
        // Use shoulder-to-hip width ratio instead
        if isFacingCamera {
            return isFacingCameraAndStanding(from: points)
        }
        
        // RULE 3: Height-Width bounding box check
        // If upper body is wider than tall, user cannot be standing
        if isUpperBodyWiderThanTall(from: points) {
            return false
        }
        
        // RULE 4: Only use simple side-view standing detection for non-facing-camera scenarios
        return isSideViewStanding(from: points)
    }
    
    // MARK: - Horizontal Detection (Inverse Standing)
    
    /// Detects if user is in a horizontal/pushup-ready position
    /// A user is horizontal if:
    /// - Shoulder and Hip are nearly on the same horizontal plane (Side View), OR
    /// - The 2D shoulder-hip distance is compressed (leaning toward camera)
    private func isHorizontal(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        let minConfidence: Float = 0.15
        
        let leftShoulder = points[.leftShoulder]
        let rightShoulder = points[.rightShoulder]
        let leftHip = points[.leftHip]
        let rightHip = points[.rightHip]
        
        // Check shoulder-hip pairs for horizontal alignment
        let shoulderHipPairs: [(VNRecognizedPoint?, VNRecognizedPoint?)] = [
            (leftShoulder, leftHip),
            (rightShoulder, rightHip)
        ]
        
        for (shoulder, hip) in shoulderHipPairs {
            guard let s = shoulder, let h = hip,
                  s.confidence > minConfidence, h.confidence > minConfidence else {
                continue
            }
            
            let deltaY = abs(s.location.y - h.location.y)
            let deltaX = abs(s.location.x - h.location.x)
            let distance2D = sqrt(deltaX * deltaX + deltaY * deltaY)
            
            // SIDE VIEW HORIZONTAL: Shoulder and hip are roughly on same Y level
            // In a plank, the torso is horizontal, so deltaY should be small
            // and deltaX (horizontal spread) should be larger
            if deltaY < 0.15 && deltaX > deltaY * 1.5 {
                return true
            }
            
            // FRONT VIEW HORIZONTAL (compressed torso):
            // When doing pushups facing camera, the shoulder-hip distance appears very short
            // because the torso is pointing toward the camera
            // A typical standing torso would be 0.25-0.40 in normalized coords
            if distance2D < 0.18 && isFacingCamera {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Face Camera Standing Detection
    
    /// When facing camera, use shoulder-width-to-hip-width ratio for standing detection
    /// Standing: shoulders and hips have similar width ratio
    /// Pushup position: shoulders appear much wider due to arm spread
    private func isFacingCameraAndStanding(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        let minConfidence: Float = 0.15
        
        guard let leftShoulder = points[.leftShoulder],
              let rightShoulder = points[.rightShoulder],
              let leftHip = points[.leftHip],
              let rightHip = points[.rightHip],
              leftShoulder.confidence > minConfidence,
              rightShoulder.confidence > minConfidence,
              leftHip.confidence > minConfidence,
              rightHip.confidence > minConfidence else {
            return false
        }
        
        let shoulderWidth = abs(leftShoulder.location.x - rightShoulder.location.x)
        let hipWidth = abs(leftHip.location.x - rightHip.location.x)
        
        // Prevent division by zero
        guard hipWidth > 0.01 else { return false }
        
        let widthRatio = shoulderWidth / hipWidth
        
        // When standing facing camera:
        // - Shoulder width and hip width are relatively consistent (ratio ~1.0-1.3)
        // When doing pushups facing camera:
        // - Arms are spread wide, making shoulders appear MUCH wider (ratio > 1.8)
        // - Or the body is tilted, compressing the hip width significantly
        
        // Also check if shoulders are significantly ABOVE hips (standing indicator)
        let avgShoulderY = (leftShoulder.location.y + rightShoulder.location.y) / 2
        let avgHipY = (leftHip.location.y + rightHip.location.y) / 2
        let shoulderAboveHip = avgShoulderY - avgHipY
        
        // Standing requires: moderate width ratio AND shoulders clearly above hips
        let reasonableWidthRatio = widthRatio > 0.8 && widthRatio < 1.8
        let shouldersSignificantlyAbove = shoulderAboveHip > 0.25
        
        return reasonableWidthRatio && shouldersSignificantlyAbove
    }
    
    // MARK: - Height-Width Bounding Box Check
    
    /// If the upper body bounding box is wider than tall, user cannot be standing
    /// This handles face-camera floor positions where the body appears spread out
    private func isUpperBodyWiderThanTall(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        let minConfidence: Float = 0.15
        
        // Collect all upper body points
        var xCoords: [CGFloat] = []
        var yCoords: [CGFloat] = []
        
        let upperBodyJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow, .leftWrist, .rightWrist,
            .leftHip, .rightHip
        ]
        
        for joint in upperBodyJoints {
            if let point = points[joint], point.confidence > minConfidence {
                xCoords.append(point.location.x)
                yCoords.append(point.location.y)
            }
        }
        
        // Need at least 4 points for a meaningful bounding box
        guard xCoords.count >= 4 else { return false }
        
        let minX = xCoords.min()!
        let maxX = xCoords.max()!
        let minY = yCoords.min()!
        let maxY = yCoords.max()!
        
        let width = maxX - minX
        let height = maxY - minY
        
        // If width > height, body is in a horizontal/spread position (not standing)
        // Add some margin (1.2x) to account for natural body proportions
        return width > height * 1.2
    }
    
    // MARK: - Side View Standing Detection (Simple)
    
    /// Simple side-view standing detection: torso must be clearly vertical
    /// Only used when NOT facing camera and NOT horizontal
    private func isSideViewStanding(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        let minConfidence: Float = 0.15
        
        let leftShoulder = points[.leftShoulder]
        let rightShoulder = points[.rightShoulder]
        let leftHip = points[.leftHip]
        let rightHip = points[.rightHip]
        
        // Check if shoulder is significantly above hip with clear vertical orientation
        let shoulderHipPairs: [(VNRecognizedPoint?, VNRecognizedPoint?)] = [
            (leftShoulder, leftHip),
            (rightShoulder, rightHip)
        ]
        
        for (shoulder, hip) in shoulderHipPairs {
            guard let s = shoulder, let h = hip,
                  s.confidence > minConfidence, h.confidence > minConfidence else {
                continue
            }
            
            let deltaY = s.location.y - h.location.y  // Positive = shoulder above hip
            let deltaX = abs(s.location.x - h.location.x)
            
            // STRICT vertical check: Y difference must be large AND much greater than X
            // This ensures torso is truly vertical, not just slightly tilted
            if deltaY > 0.25 && deltaY > deltaX * 2.0 {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Face Camera Detection (Issue 2)
    
    /// Detects if user is facing the camera (both shoulders visible at similar depth)
    private func detectFacingCamera(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Bool {
        guard let leftShoulder = points[.leftShoulder],
              let rightShoulder = points[.rightShoulder],
              leftShoulder.confidence > relaxedMinConfidence,
              rightShoulder.confidence > relaxedMinConfidence else {
            return false
        }
        
        // When facing camera, both shoulders are at similar Y positions
        // and the horizontal distance between them is relatively small
        let shoulderYDiff = abs(leftShoulder.location.y - rightShoulder.location.y)
        let shoulderXDiff = abs(leftShoulder.location.x - rightShoulder.location.x)
        
        // Facing camera: shoulders roughly level (small Y diff) and not too far apart horizontally
        // (when from the side, one shoulder would be much higher/further)
        return shoulderYDiff < 0.1 && shoulderXDiff < 0.4
    }
    
    /// Detects down position when facing camera using shoulder/face position relative to elbow
    /// When facing camera and going down, the shoulder and face drop BELOW the elbow level
    private func detectFaceCameraDown(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], elbow: CGPoint) -> Bool {
        // Get shoulder points
        let leftShoulder = points[.leftShoulder]
        let rightShoulder = points[.rightShoulder]
        
        // Get face points (nose, ears, eyes)
        let nose = points[.nose]
        let leftEar = points[.leftEar]
        let rightEar = points[.rightEar]
        
        // Check if any shoulder is below the elbow (in Vision coords, lower Y = lower position)
        var shoulderBelowElbow = false
        if let ls = leftShoulder, ls.confidence > relaxedMinConfidence {
            if ls.location.y < elbow.y - 0.02 {  // Small margin for stability
                shoulderBelowElbow = true
            }
        }
        if let rs = rightShoulder, rs.confidence > relaxedMinConfidence {
            if rs.location.y < elbow.y - 0.02 {
                shoulderBelowElbow = true
            }
        }
        
        // Check if face points are below elbow
        var faceBelowElbow = false
        let facePoints: [VNRecognizedPoint?] = [nose, leftEar, rightEar]
        for point in facePoints {
            if let p = point, p.confidence > relaxedMinConfidence {
                if p.location.y < elbow.y {
                    faceBelowElbow = true
                    break
                }
            }
        }
        
        // Down position if shoulder OR face is below elbow level
        return shoulderBelowElbow || faceBelowElbow
    }
    
    // MARK: - Primary Arm Selection with Hysteresis
    
    /// Selects the primary arm with hysteresis to prevent "arm flipping" glitches
    /// Once an arm is chosen, only switch if alternate arm is 20%+ more confident for 5+ frames
    private func selectPrimaryArmWithHysteresis(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> ArmData? {
        // Get both arms' data
        let leftArm = getArmData(from: points, isLeft: true)
        let rightArm = getArmData(from: points, isLeft: false)
        
        // If neither arm is valid, return nil
        guard leftArm != nil || rightArm != nil else {
            return nil
        }
        
        // If only one arm is valid, use it (and reset hysteresis counter)
        if leftArm == nil {
            alternateArmHigherConfidenceFrames = 0
            return rightArm
        }
        if rightArm == nil {
            alternateArmHigherConfidenceFrames = 0
            return leftArm
        }
        
        // Both arms valid - apply hysteresis logic
        let currentArm = primaryArmIsLeft ? leftArm! : rightArm!
        let alternateArm = primaryArmIsLeft ? rightArm! : leftArm!
        
        // Check if alternate arm has significantly higher confidence
        let confidenceThreshold = currentPrimaryArmConfidence > 0 
            ? currentPrimaryArmConfidence * armSwitchConfidenceMargin 
            : currentArm.confidence * armSwitchConfidenceMargin
        
        if alternateArm.confidence > confidenceThreshold {
            alternateArmHigherConfidenceFrames += 1
            
            // Only switch if maintained for enough frames
            if alternateArmHigherConfidenceFrames >= armSwitchFrameThreshold {
                alternateArmHigherConfidenceFrames = 0
                return alternateArm
            }
        } else {
            // Reset counter if alternate arm is not significantly better
            alternateArmHigherConfidenceFrames = 0
        }
        
        // Stick with current primary arm
        return currentArm
    }
    
    /// Helper to get arm data with confidence validation
    private func getArmData(from points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint], isLeft: Bool) -> ArmData? {
        let shoulderKey: VNHumanBodyPoseObservation.JointName = isLeft ? .leftShoulder : .rightShoulder
        let elbowKey: VNHumanBodyPoseObservation.JointName = isLeft ? .leftElbow : .rightElbow
        let wristKey: VNHumanBodyPoseObservation.JointName = isLeft ? .leftWrist : .rightWrist
        
        guard let shoulder = points[shoulderKey],
              let elbow = points[elbowKey],
              let wrist = points[wristKey] else {
            return nil
        }
        
        // Try normal confidence first
        if shoulder.confidence > minConfidence && 
           elbow.confidence > minConfidence && 
           wrist.confidence > minConfidence {
            return ArmData(
                shoulder: shoulder.location,
                elbow: elbow.location,
                wrist: wrist.location,
                confidence: shoulder.confidence + elbow.confidence + wrist.confidence,
                isLeft: isLeft
            )
        }
        
        // Fall back to relaxed confidence
        if shoulder.confidence > relaxedMinConfidence && 
           elbow.confidence > relaxedMinConfidence && 
           wrist.confidence > relaxedMinConfidence {
            return ArmData(
                shoulder: shoulder.location,
                elbow: elbow.location,
                wrist: wrist.location,
                confidence: shoulder.confidence + elbow.confidence + wrist.confidence,
                isLeft: isLeft
            )
        }
        
        return nil
    }
    
    // MARK: - Depth Compensation (Arm Length)
    
    /// Calculate the 2D distance from shoulder to wrist
    private func calculateArmLength(shoulder: CGPoint, wrist: CGPoint) -> CGFloat {
        let dx = wrist.x - shoulder.x
        let dy = wrist.y - shoulder.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Calculate how much the arm has compressed compared to the UP state baseline
    /// Returns a ratio where 1.0 = no compression, 0.7 = 30% compression
    private func calculateArmCompressionRatio(currentLength: CGFloat) -> CGFloat? {
        guard let baseline = baseArmLength, baseline > 0 else {
            return nil
        }
        return currentLength / baseline
    }
    
    /// Capture calibration data when entering UP state
    private func captureUpStateCalibration(armLength: CGFloat, shoulderY: CGFloat) {
        // Only capture if we don't have a baseline or transitioning to UP
        if baseArmLength == nil || currentState != .up {
            baseArmLength = armLength
            upStateShoulderY = shoulderY
        }
    }
    
    // MARK: - Vertical Displacement Validation
    
    /// Validates that the shoulder has dropped sufficiently for a real pushup
    /// Returns true if shoulder Y has moved down by at least minShoulderDropRatio
    private func validateShoulderDrop(currentShoulderY: CGFloat) -> Bool {
        guard let upY = upStateShoulderY else {
            return true  // No baseline, assume valid
        }
        
        // In Vision coordinates, Y increases upward
        // So a drop means currentY < upY
        let drop = upY - currentShoulderY
        return drop >= minShoulderDropRatio
    }
    
    // MARK: - Elbow Angle Calculation
    
    private func calculateElbowAngle(shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint) -> Double {
        // Vector A: Shoulder to Elbow
        let vectorA = CGPoint(x: shoulder.x - elbow.x, y: shoulder.y - elbow.y)
        
        // Vector B: Wrist to Elbow
        let vectorB = CGPoint(x: wrist.x - elbow.x, y: wrist.y - elbow.y)
        
        // Calculate angle using dot product
        let dotProduct = vectorA.x * vectorB.x + vectorA.y * vectorB.y
        let magnitudeA = sqrt(vectorA.x * vectorA.x + vectorA.y * vectorA.y)
        let magnitudeB = sqrt(vectorB.x * vectorB.x + vectorB.y * vectorB.y)
        
        guard magnitudeA > 0 && magnitudeB > 0 else { return 180.0 }
        
        let cosAngle = dotProduct / (magnitudeA * magnitudeB)
        let clampedCos = max(-1.0, min(1.0, cosAngle))
        let angleRadians = acos(clampedCos)
        let angleDegrees = angleRadians * 180.0 / .pi
        
        return angleDegrees
    }
    
    // MARK: - Angle Direction Detection
    
    private func determineAngleDirection() -> AngleDirection {
        guard angleHistory.count >= 3 else { return .stable }
        
        // Compare recent angles to determine trend
        let recent = Array(angleHistory.suffix(3))
        let delta1 = recent[1] - recent[0]
        let delta2 = recent[2] - recent[1]
        let avgDelta = (delta1 + delta2) / 2.0
        
        let threshold = 2.0 // Degrees of change to consider significant
        
        if avgDelta > threshold {
            return .increasing // Extending arm
        } else if avgDelta < -threshold {
            return .decreasing // Bending arm
        }
        return .stable
    }
    
    private enum AngleDirection {
        case increasing
        case decreasing
        case stable
    }
    
    // MARK: - State Determination
    
    private func determineRawState(
        angle: Double, 
        direction: AngleDirection, 
        faceCameraDownDetected: Bool = false,
        armCompressionRatio: CGFloat? = nil,
        validShoulderDrop: Bool = true
    ) -> PushupState {
        // Override to DOWN state if face-camera down position detected
        // This handles the case where elbows go behind the body when facing camera
        if faceCameraDownDetected {
            return .down
        }
        
        // State 0: UP/READY - Arms nearly straight (≥150°)
        if angle >= upAngleThreshold {
            return .up
        }
        
        // DYNAMIC DEPTH THRESHOLD based on arm compression (Z-axis compensation)
        // If arm has compressed significantly, relax the angle threshold
        var effectiveDownThreshold = downAngleThreshold
        
        if isFacingCamera, let compressionRatio = armCompressionRatio {
            // Arm has compressed by >30% (ratio < 0.7), use relaxed threshold
            if compressionRatio < armCompressionThreshold {
                effectiveDownThreshold = relaxedDownAngleThreshold  // 105° instead of 90°
            }
        }
        
        // State 2: DOWN/BOTTOM - Hit depth threshold
        // Also require valid shoulder drop to prevent false positives from arm fidgeting
        if angle <= effectiveDownThreshold {
            return .down
        }
        
        // In transition zone (between down threshold and 150°)
        // Determine if descending or ascending based on direction and previous state
        switch currentState {
        case .up:
            // From UP, if angle decreasing, we're descending
            if direction == .decreasing || direction == .stable {
                return .descending
            }
            return .up
            
        case .descending:
            // Continue descending until we hit DOWN or start ascending
            if direction == .increasing && angle > effectiveDownThreshold + 10 {
                return .ascending
            }
            return .descending
            
        case .down:
            // From DOWN, if angle increasing, we're ascending
            if direction == .increasing || direction == .stable {
                return .ascending
            }
            return .down
            
        case .ascending:
            // Continue ascending until we hit UP or start descending
            if direction == .decreasing && angle < upAngleThreshold - 10 {
                return .descending
            }
            return .ascending
            
        case .unknown, .standing:
            // Initial state or recovering from standing - determine based on angle
            if angle >= upAngleThreshold {
                return .up
            } else if angle <= effectiveDownThreshold {
                return .down
            } else if direction == .decreasing {
                return .descending
            } else {
                return .ascending
            }
        }
    }
    
    // MARK: - Temporal Buffer
    
    private func applyTemporalBuffer(rawState: PushupState) -> PushupState {
        if rawState == pendingState {
            pendingStateFrameCount += 1
        } else {
            pendingState = rawState
            pendingStateFrameCount = 1
        }
        
        // Use different buffer thresholds depending on the target state
        // Standing requires a much longer buffer (grace period) to prevent false transitions
        let requiredFrames: Int
        if pendingState == .standing {
            requiredFrames = standingStateFrameBuffer  // 30 frames (~1 second)
        } else {
            requiredFrames = stateChangeFrameBuffer    // 2 frames
        }
        
        // Only change state if we've seen the new state for enough consecutive frames
        if pendingStateFrameCount >= requiredFrames {
            return pendingState
        }
        
        // Otherwise keep current state
        return currentState
    }
    
    // MARK: - Stable UP State Tracking
    
    /// Track how long user has been in stable UP state (for standing detection eligibility)
    private func updateStableUpTracking(newState: PushupState) {
        if newState == .up {
            stableUpStateFrameCount += 1
        } else {
            stableUpStateFrameCount = 0
        }
    }
    
    // MARK: - State Update and Rep Counting
    
    /// Track whether we've seen valid shoulder drop during this rep cycle
    private var sawValidShoulderDropInCycle: Bool = false
    
    private func updateStateAndCount(newState: PushupState, validShoulderDrop: Bool = true) {
        // Track state transition for rep counting
        // A rep is counted when we complete: UP -> DESCENDING -> DOWN -> ASCENDING -> UP
        
        // Don't count reps or update pushup state while standing
        if newState == .standing {
            currentState = .standing
            sawValidShoulderDropInCycle = false  // Reset for next cycle
            return
        }
        
        // Track if we've seen valid shoulder drop during descending/down phases
        if (currentState == .descending || currentState == .down) && validShoulderDrop {
            sawValidShoulderDropInCycle = true
        }
        
        if currentState != newState {
            previousState = currentState
            currentState = newState
            
            // Count a rep when transitioning from ASCENDING to UP
            // This means we completed: UP -> DESCENDING -> DOWN -> ASCENDING -> UP
            // Additional validation: shoulder must have dropped during the cycle
            if previousState == .ascending && currentState == .up {
                if sawValidShoulderDropInCycle {
                    pushupCount += 1
                }
                // Reset for next cycle
                sawValidShoulderDropInCycle = false
                baseArmLength = nil  // Reset calibration for fresh measurement
                upStateShoulderY = nil
            }
            
            // Reset shoulder drop tracking when starting a new descent from UP
            if previousState == .up && currentState == .descending {
                sawValidShoulderDropInCycle = false
            }
        }
    }
}
