import Foundation
import Vision
import AVFoundation
import CoreGraphics
import CoreImage
import VideoToolbox
import CoreText

// MARK: - Configuration
struct TestConfig {
    static let inputFolder = "TestVideos"
    static let outputFolder = "AnnotatedVideos"
    static let resultsFile = "detection_results.json"
    
    // Detection thresholds
    static let minConfidence: Float = 0.3
    
    // Annotation colors
    static let jointColor = CGColor(red: 1.0, green: 0.0, blue: 0.0, alpha: 1.0)
    static let connectionColor = CGColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 0.8)
    static let textColor = CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
}

// MARK: - Data Models
struct VideoTestResult: Codable {
    let filename: String
    let detectedPushups: Int
    let expectedPushups: Int?
    let accuracy: Double?
    let frameCount: Int
    let processingTime: TimeInterval
    let frameResults: [FrameResult]
}

struct FrameResult: Codable {
    let frameNumber: Int
    let timestamp: Double
    let bodyDetected: Bool
    let pushupState: PushupState
    let elbowAngle: Double?
    let primaryArm: String
    let pushupCount: Int
}

// MARK: - Video Processor
class VideoProcessor {
    private let detector = PushupDetector()
    
    func processVideo(inputURL: URL, outputURL: URL, expectedCount: Int?) async -> VideoTestResult? {
        let startTime = Date()
        var frameResults: [FrameResult] = []
        
        #if os(iOS) && targetEnvironment(simulator)
        print("⚠️ WARNING: Running on iOS simulator. Vision body pose detection will fail.")
        print("   Please run on a real iOS device for proper testing.")
        return nil
        #endif
        
        // Load the video using modern API
        let asset = AVURLAsset(url: inputURL)
        
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            print("No video track found")
            return nil
        }
        
        let reader: AVAssetReader
        let writer: AVAssetWriter
        
        do {
            // Remove existing file if it exists
            try? FileManager.default.removeItem(at: outputURL)
            
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            print("Error creating reader/writer: \(error)")
            return nil
        }
        
        // Load properties we need
        let naturalSize = try? await videoTrack.load(.naturalSize)
        let nominalFrameRate = try? await videoTrack.load(.nominalFrameRate)
        
        guard let size = naturalSize, let frameRate = nominalFrameRate else {
            print("Could not load video properties")
            return nil
        }
        
        // Configure reader
        let readerOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerOutputSettings)
        reader.add(readerOutput)
        
        // Configure writer
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ])
        writerInput.expectsMediaDataInRealTime = false
        
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        
        writer.add(writerInput)
        
        // Start reading and writing
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        
        detector.reset()
        var frameNumber = 0
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        
        // Process each frame
        while reader.status == .reading {
            guard let sampleBuffer = readerOutput.copyNextSampleBuffer(),
                  let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                break
            }
            
            let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            
            // Perform body pose detection (2D - works with any video)
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            
            var bodyDetected = false
            var pushupState = PushupState.unknown
            var elbowAngle: Double?
            var primaryArm = "none"
            var currentCount = 0
            var annotatedBuffer = pixelBuffer
            
            do {
                try handler.perform([request])
                
                if let observation = request.results?.first as? VNHumanBodyPoseObservation {
                    bodyDetected = true
                    let result = detector.detectPushup(observation: observation)
                    pushupState = result.state
                    elbowAngle = result.elbowAngle
                    primaryArm = result.primaryArm
                    currentCount = result.count
                    
                    // Annotate the frame
                    annotatedBuffer = annotateFrame(
                        pixelBuffer: pixelBuffer,
                        observation: observation,
                        pushupCount: result.count,
                        state: result.state,
                        elbowAngle: result.elbowAngle,
                        primaryArm: result.primaryArm
                    )
                }
            } catch {
                print("Error performing detection on frame \(frameNumber): \(error)")
            }
            
            // Record frame result
            frameResults.append(FrameResult(
                frameNumber: frameNumber,
                timestamp: timestamp,
                bodyDetected: bodyDetected,
                pushupState: pushupState,
                elbowAngle: elbowAngle,
                primaryArm: primaryArm,
                pushupCount: currentCount
            ))
            
            // Write annotated frame
            let presentationTime = CMTime(value: Int64(frameNumber), timescale: frameDuration.timescale)
            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            }
            pixelBufferAdaptor.append(annotatedBuffer, withPresentationTime: presentationTime)
            
            frameNumber += 1
        }
        
        // Finish writing
        writerInput.markAsFinished()
        await writer.finishWriting()
        print("Finished writing video to \(outputURL.path)")
        
        let processingTime = Date().timeIntervalSince(startTime)
        let detectedCount = detector.pushupCount
        
        var accuracy: Double?
        if let expected = expectedCount, expected > 0 {
            accuracy = 1.0 - abs(Double(detectedCount - expected)) / Double(expected)
        }
        
        return VideoTestResult(
            filename: inputURL.lastPathComponent,
            detectedPushups: detectedCount,
            expectedPushups: expectedCount,
            accuracy: accuracy,
            frameCount: frameNumber,
            processingTime: processingTime,
            frameResults: frameResults
        )
    }
    
    private func annotateFrame(
        pixelBuffer: CVPixelBuffer,
        observation: VNHumanBodyPoseObservation,
        pushupCount: Int,
        state: PushupState,
        elbowAngle: Double?,
        primaryArm: String
    ) -> CVPixelBuffer {
        var outputBuffer: CVPixelBuffer?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            CVPixelBufferGetPixelFormatType(pixelBuffer),
            nil,
            &outputBuffer
        )
        
        guard let output = outputBuffer else { return pixelBuffer }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        
        let sourceData = CVPixelBufferGetBaseAddress(pixelBuffer)
        let destData = CVPixelBufferGetBaseAddress(output)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        
        memcpy(destData, sourceData, bytesPerRow * bufferHeight)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: destData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(output, [])
            return pixelBuffer
        }
        
        // Draw skeleton
        drawSkeleton(context: context, observation: observation, width: width, height: height, primaryArm: primaryArm)
        
        // Draw info overlay
        drawInfoOverlay(
            context: context,
            width: width,
            height: height,
            pushupCount: pushupCount,
            state: state,
            elbowAngle: elbowAngle,
            primaryArm: primaryArm
        )
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferUnlockBaseAddress(output, [])
        
        return output
    }
    
    private func drawInfoOverlay(
        context: CGContext,
        width: Int,
        height: Int,
        pushupCount: Int,
        state: PushupState,
        elbowAngle: Double?,
        primaryArm: String
    ) {
        // Calculate sizes based on video dimensions
        let scale = CGFloat(width) / 1080.0
        let padding = 20.0 * scale
        let lineHeight = 45.0 * scale
        let boxWidth = 400.0 * scale
        
        // State color based on current state
        let stateColor: CGColor
        switch state {
        case .up:
            stateColor = CGColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
        case .descending:
            stateColor = CGColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        case .down:
            stateColor = CGColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)
        case .ascending:
            stateColor = CGColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        case .unknown:
            stateColor = CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        case .standing:
            stateColor = CGColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 1.0)  // Purple for standing
        }
        
        // Calculate panel dimensions - more precise spacing
        let topPadding = 12 * scale
        let bottomPadding = 12 * scale
        let itemSpacing = 8 * scale
        
        // Calculate total height needed
        let countHeight = 40 * scale
        let stateHeight = 32 * scale
        let angleLabelHeight = 26 * scale
        let angleBarHeight = 18 * scale
        let trackingHeight = 22 * scale
        
        let panelHeight = topPadding + countHeight + itemSpacing + stateHeight + itemSpacing + 
                         angleLabelHeight + itemSpacing + angleBarHeight + itemSpacing + 
                         trackingHeight + bottomPadding
        
        // Position at TOP LEFT of video
        // CGContext has (0,0) at bottom-left, so we calculate Y from top
        let panelY = CGFloat(height) - panelHeight - padding
        let panelRect = CGRect(x: padding, y: panelY, width: boxWidth, height: panelHeight)
        
        // Draw background
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        context.fill(panelRect)
        
        // Draw colored border based on state
        context.setStrokeColor(stateColor)
        context.setLineWidth(4 * scale)
        context.stroke(panelRect)
        
        // Draw text labels (from top to bottom, so Y decreases in CGContext coords)
        let textX = padding + 15 * scale
        var yPos = panelY + panelHeight - topPadding  // Start from top of panel
        
        // Row 1: PUSHUP COUNT (large)
        let countFontSize = 36 * scale
        drawText(
            context: context,
            text: "PUSHUPS: \(pushupCount)",
            x: textX,
            y: yPos,
            fontSize: countFontSize,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            bold: true
        )
        yPos -= (countHeight + itemSpacing)
        
        // Row 2: STATE
        let stateFontSize = 28 * scale
        drawText(
            context: context,
            text: "STATE: \(state.rawValue)",
            x: textX,
            y: yPos,
            fontSize: stateFontSize,
            color: stateColor,
            bold: true
        )
        yPos -= (stateHeight + itemSpacing)
        
        // Row 3: ELBOW ANGLE label
        let angleText = elbowAngle.map { String(format: "%.0f°", $0) } ?? "N/A"
        let angleFontSize = 24 * scale
        drawText(
            context: context,
            text: "ELBOW ANGLE: \(angleText)",
            x: textX,
            y: yPos,
            fontSize: angleFontSize,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9),
            bold: false
        )
        yPos -= (angleLabelHeight + itemSpacing)
        
        // Row 4: Angle bar (below the label)
        if let angle = elbowAngle {
            let barWidth = boxWidth - 40 * scale
            let barHeight = 16 * scale
            let barX = textX
            let barY = yPos - barHeight - 2 * scale
            
            // Background
            context.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0))
            context.fill(CGRect(x: barX, y: barY, width: barWidth, height: barHeight))
            
            // Angle progress
            let angleProgress = min(1.0, max(0.0, CGFloat(angle) / 180.0))
            let angleColor: CGColor
            if angle > 150 {
                angleColor = CGColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0)
            } else if angle > 90 {
                angleColor = CGColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
            } else {
                angleColor = CGColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)
            }
            context.setFillColor(angleColor)
            context.fill(CGRect(x: barX, y: barY, width: barWidth * angleProgress, height: barHeight))
            
            // Threshold markers (90° and 150°)
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            context.setLineWidth(2 * scale)
            
            // 90° marker (DOWN threshold)
            let marker90X = barX + barWidth * (90.0 / 180.0)
            context.move(to: CGPoint(x: marker90X, y: barY - 5 * scale))
            context.addLine(to: CGPoint(x: marker90X, y: barY + barHeight + 5 * scale))
            context.strokePath()
            
            // 150° marker (UP threshold)
            let marker150X = barX + barWidth * (150.0 / 180.0)
            context.move(to: CGPoint(x: marker150X, y: barY - 5 * scale))
            context.addLine(to: CGPoint(x: marker150X, y: barY + barHeight + 5 * scale))
            context.strokePath()
            
            // Label the markers (above the bar)
            let markerFontSize = 12 * scale
            drawText(context: context, text: "90°", x: marker90X - 14 * scale, y: barY + barHeight + 8 * scale, fontSize: markerFontSize, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.8), bold: false)
            drawText(context: context, text: "150°", x: marker150X - 18 * scale, y: barY + barHeight + 8 * scale, fontSize: markerFontSize, color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.8), bold: false)
        }
        yPos -= (angleBarHeight + itemSpacing)
        
        // Row 5: PRIMARY ARM
        let trackingFontSize = 20 * scale
        drawText(
            context: context,
            text: "TRACKING: \(primaryArm) ARM",
            x: textX,
            y: yPos,
            fontSize: trackingFontSize,
            color: CGColor(red: 1, green: 0.9, blue: 0, alpha: 1),
            bold: false
        )
        
        // Draw state legend at top right of panel (better positioned)
        let legendX = panelRect.maxX - 75 * scale
        let legendY = panelY + panelHeight - topPadding
        let legendFontSize = 14 * scale
        let legendSpacing = 18 * scale
        
        drawText(context: context, text: "UP", x: legendX, y: legendY, fontSize: legendFontSize, color: CGColor(red: 0.2, green: 0.8, blue: 0.2, alpha: state == .up ? 1 : 0.5), bold: state == .up)
        drawText(context: context, text: "DESC", x: legendX, y: legendY - legendSpacing, fontSize: legendFontSize, color: CGColor(red: 1.0, green: 0.6, blue: 0.0, alpha: state == .descending ? 1 : 0.5), bold: state == .descending)
        drawText(context: context, text: "DOWN", x: legendX, y: legendY - legendSpacing * 2, fontSize: legendFontSize, color: CGColor(red: 1.0, green: 0.2, blue: 0.2, alpha: state == .down ? 1 : 0.5), bold: state == .down)
        drawText(context: context, text: "ASC", x: legendX, y: legendY - legendSpacing * 3, fontSize: legendFontSize, color: CGColor(red: 0.2, green: 0.6, blue: 1.0, alpha: state == .ascending ? 1 : 0.5), bold: state == .ascending)
        drawText(context: context, text: "STAND", x: legendX, y: legendY - legendSpacing * 4, fontSize: legendFontSize, color: CGColor(red: 0.8, green: 0.2, blue: 0.8, alpha: state == .standing ? 1 : 0.5), bold: state == .standing)
    }
    
    /// Draw text using Core Text
    private func drawText(
        context: CGContext,
        text: String,
        x: CGFloat,
        y: CGFloat,
        fontSize: CGFloat,
        color: CGColor,
        bold: Bool
    ) {
        #if os(macOS)
        let fontName = bold ? "Helvetica-Bold" : "Helvetica"
        #else
        let fontName = bold ? "HelveticaNeue-Bold" : "HelveticaNeue"
        #endif
        
        guard let font = CTFontCreateWithName(fontName as CFString, fontSize, nil) as CTFont? else { return }
        
        // Use CoreText attribute keys (works on both iOS and macOS without UIKit/AppKit)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color
        ]
        
        let attributedString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
        guard let attrString = attributedString else { return }
        let line = CTLineCreateWithAttributedString(attrString)
        
        context.saveGState()
        // CoreText uses bottom-left origin, and y is the baseline
        // We pass y as the top of the text, so adjust for baseline
        let baseline = y - fontSize * 0.2  // Approximate baseline offset
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }
    
    private func drawSkeleton(
        context: CGContext,
        observation: VNHumanBodyPoseObservation,
        width: Int,
        height: Int,
        primaryArm: String = "none"
    ) {
        // Retrieve all recognized points using Apple's API pattern
        guard let recognizedPoints = try? observation.recognizedPoints(.all) else {
            return
        }
        
        // Define skeleton connections
        let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            // Torso
            (.neck, .leftShoulder),
            (.neck, .rightShoulder),
            (.leftShoulder, .leftHip),
            (.rightShoulder, .rightHip),
            (.leftHip, .rightHip),
            
            // Left arm
            (.leftShoulder, .leftElbow),
            (.leftElbow, .leftWrist),
            
            // Right arm
            (.rightShoulder, .rightElbow),
            (.rightElbow, .rightWrist),
            
            // Left leg
            (.leftHip, .leftKnee),
            (.leftKnee, .leftAnkle),
            
            // Right leg
            (.rightHip, .rightKnee),
            (.rightKnee, .rightAnkle)
        ]
        
        context.setStrokeColor(TestConfig.connectionColor)
        context.setLineWidth(3)
        
        // Helper to convert Vision normalized coordinates to image coordinates
        // Vision: (0,0) = bottom-left, (1,1) = top-right
        // For video frames from AVAssetReaderTrackOutput, use direct conversion
        // (the frames are delivered in storage orientation, matching Vision's processing)
        func convertPoint(_ point: CGPoint) -> CGPoint {
            return CGPoint(
                x: point.x * CGFloat(width),
                y: point.y * CGFloat(height)  // No flip - matches video storage orientation
            )
        }
        
        // Determine which arm connections to highlight
        let leftArmJoints: Set<VNHumanBodyPoseObservation.JointName> = [.leftShoulder, .leftElbow, .leftWrist]
        let rightArmJoints: Set<VNHumanBodyPoseObservation.JointName> = [.rightShoulder, .rightElbow, .rightWrist]
        
        // Draw connections
        for (start, end) in connections {
            if let startPoint = recognizedPoints[start],
               let endPoint = recognizedPoints[end],
               startPoint.confidence > 0,
               endPoint.confidence > 0 {
                
                // Highlight primary arm connections
                let isPrimaryArmConnection: Bool
                if primaryArm == "LEFT" {
                    isPrimaryArmConnection = leftArmJoints.contains(start) && leftArmJoints.contains(end)
                } else if primaryArm == "RIGHT" {
                    isPrimaryArmConnection = rightArmJoints.contains(start) && rightArmJoints.contains(end)
                } else {
                    isPrimaryArmConnection = false
                }
                
                if isPrimaryArmConnection {
                    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)) // Yellow for primary arm
                    context.setLineWidth(6)
                } else {
                    context.setStrokeColor(TestConfig.connectionColor)
                    context.setLineWidth(3)
                }
                
                let startCG = convertPoint(startPoint.location)
                let endCG = convertPoint(endPoint.location)
                
                context.move(to: startCG)
                context.addLine(to: endCG)
                context.strokePath()
            }
        }
        
        // Draw joints
        for (jointName, point) in recognizedPoints where point.confidence > 0 {
            let center = convertPoint(point.location)
            
            // Highlight primary arm joints
            let isPrimaryArmJoint: Bool
            if primaryArm == "LEFT" {
                isPrimaryArmJoint = leftArmJoints.contains(jointName)
            } else if primaryArm == "RIGHT" {
                isPrimaryArmJoint = rightArmJoints.contains(jointName)
            } else {
                isPrimaryArmJoint = false
            }
            
            if isPrimaryArmJoint {
                context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)) // Yellow
                context.fillEllipse(in: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16))
            } else {
                context.setFillColor(TestConfig.jointColor)
                context.fillEllipse(in: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))
            }
        }
    }
}
