//
//  main.swift
//  PushupCLI
//
//  Created by lfalzarano on 1/6/26.
//

import Foundation
import Vision
import AVFoundation
import CoreGraphics
import CoreImage

// MARK: - Pushup Detection CLI Tool
// This tool processes pushup videos on macOS for fast algorithm iteration.
// No iOS device needed - runs directly on your Mac!

// MARK: - Configuration
struct CLIConfig {
    // Default paths relative to project root
    // Note: Videos are stored inside PushUppy/ folder to be part of the iOS app bundle
    static let defaultInputFolder = "PushUppy/TestVideos/Input"
    static let defaultOutputFolder = "PushUppy/TestVideos/Output"
    
    // Get project root - look for .xcodeproj or use script location
    static var projectRoot: URL {
        let fileManager = FileManager.default
        var currentPath = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        
        // Walk up the directory tree looking for .xcodeproj
        while currentPath.path != "/" {
            let contents = try? fileManager.contentsOfDirectory(atPath: currentPath.path)
            if let contents = contents, contents.contains(where: { $0.hasSuffix(".xcodeproj") }) {
                return currentPath
            }
            currentPath = currentPath.deletingLastPathComponent()
        }
        
        // Fallback: try to find project root relative to executable location
        if let executablePath = Bundle.main.executablePath {
            var execURL = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
            // Go up from DerivedData/Build/Products/Debug to project root
            while execURL.path.contains("DerivedData") || execURL.path.contains("Build") {
                execURL = execURL.deletingLastPathComponent()
            }
            // Try to find project root from here
            var searchPath = execURL
            while searchPath.path != "/" {
                let contents = try? fileManager.contentsOfDirectory(atPath: searchPath.path)
                if let contents = contents, contents.contains(where: { $0.hasSuffix(".xcodeproj") }) {
                    return searchPath
                }
                searchPath = searchPath.deletingLastPathComponent()
            }
        }
        
        // Last resort: use the working directory
        return URL(fileURLWithPath: fileManager.currentDirectoryPath)
    }
    
    static var inputFolder: URL {
        projectRoot.appendingPathComponent(defaultInputFolder)
    }
    
    static var outputFolder: URL {
        projectRoot.appendingPathComponent(defaultOutputFolder)
    }
}

// MARK: - Main Entry Point
struct PushupCLI {
    static func run() async {
        print("""
        
        ╔══════════════════════════════════════════════════════════════╗
        ║           🏋️ PushUppy Algorithm Testing Tool 🏋️              ║
        ╚══════════════════════════════════════════════════════════════╝
        
        """)
        
        // Parse command line arguments
        let args = CommandLine.arguments
        
        let inputFolder: URL
        let outputFolder: URL
        
        if args.count >= 3 {
            inputFolder = URL(fileURLWithPath: args[1])
            outputFolder = URL(fileURLWithPath: args[2])
        } else if args.count == 2 {
            // Single video file mode
            let videoPath = URL(fileURLWithPath: args[1])
            if FileManager.default.fileExists(atPath: videoPath.path) {
                await processSingleVideo(videoPath)
                return
            } else {
                inputFolder = CLIConfig.inputFolder
                outputFolder = CLIConfig.outputFolder
            }
        } else {
            inputFolder = CLIConfig.inputFolder
            outputFolder = CLIConfig.outputFolder
        }
        
        print("📂 Project root:  \(CLIConfig.projectRoot.path)")
        print("📂 Input folder:  \(inputFolder.path)")
        print("📂 Output folder: \(outputFolder.path)")
        print("")
        
        // Verify folders exist
        guard FileManager.default.fileExists(atPath: inputFolder.path) else {
            print("❌ Error: Input folder does not exist!")
            print("   Create it at: \(inputFolder.path)")
            print("   Or specify a path: PushupCLI <input_folder> <output_folder>")
            return
        }
        
        // Create output folder if needed
        try? FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        
        // Find video files
        let videoExtensions = ["mp4", "mov", "m4v", "MP4", "MOV", "M4V"]
        let videos: [URL]
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: inputFolder, includingPropertiesForKeys: nil)
            videos = contents.filter { url in
                videoExtensions.contains(url.pathExtension)
            }
        } catch {
            print("❌ Error reading input folder: \(error.localizedDescription)")
            return
        }
        
        guard !videos.isEmpty else {
            print("⚠️  No video files found in input folder!")
            print("   Supported formats: .mp4, .mov, .m4v")
            print("")
            print("📝 Usage:")
            print("   1. Add pushup videos to: \(inputFolder.path)")
            print("   2. Name videos with expected count: pushup_5.mp4, workout_10.mov")
            print("   3. Run this tool again")
            return
        }
        
        print("🎬 Found \(videos.count) video(s) to process\n")
        print(String(repeating: "─", count: 60))
        
        // Process each video
        let processor = VideoProcessor()
        var results: [ProcessingResult] = []
        
        for (index, videoURL) in videos.enumerated() {
            print("\n[\(index + 1)/\(videos.count)] Processing: \(videoURL.lastPathComponent)")
            
            let outputURL = outputFolder.appendingPathComponent("annotated_\(videoURL.lastPathComponent)")
            let expectedCount = parseExpectedCount(from: videoURL.lastPathComponent)
            
            let startTime = Date()
            
            if let result = await processor.processVideo(
                inputURL: videoURL,
                outputURL: outputURL,
                expectedCount: expectedCount
            ) {
                let processingTime = Date().timeIntervalSince(startTime)
                
                let procResult = ProcessingResult(
                    filename: videoURL.lastPathComponent,
                    outputPath: outputURL.path,
                    detected: result.detectedPushups,
                    expected: expectedCount,
                    accuracy: result.accuracy,
                    frameCount: result.frameCount,
                    processingTime: processingTime,
                    frameResults: result.frameResults
                )
                results.append(procResult)
                
                printVideoResult(procResult)
            } else {
                print("   ❌ Failed to process video")
            }
        }
        
        // Print summary
        printSummary(results)
        
        print("\n📂 Annotated videos saved to:")
        print("   \(outputFolder.path)")
        print("\n💡 Open in Finder: open \"\(outputFolder.path)\"")
        print("")
    }
    
    static func processSingleVideo(_ videoURL: URL) async {
        print("🎬 Processing single video: \(videoURL.lastPathComponent)\n")
        
        let outputFolder = videoURL.deletingLastPathComponent()
        let outputURL = outputFolder.appendingPathComponent("annotated_\(videoURL.lastPathComponent)")
        let expectedCount = parseExpectedCount(from: videoURL.lastPathComponent)
        
        let processor = VideoProcessor()
        let startTime = Date()
        
        if let result = await processor.processVideo(
            inputURL: videoURL,
            outputURL: outputURL,
            expectedCount: expectedCount
        ) {
            let processingTime = Date().timeIntervalSince(startTime)
            
            let procResult = ProcessingResult(
                filename: videoURL.lastPathComponent,
                outputPath: outputURL.path,
                detected: result.detectedPushups,
                expected: expectedCount,
                accuracy: result.accuracy,
                frameCount: result.frameCount,
                processingTime: processingTime,
                frameResults: result.frameResults
            )
            
            printVideoResult(procResult)
            
            print("\n📂 Annotated video saved to:")
            print("   \(outputURL.path)")
        } else {
            print("❌ Failed to process video")
        }
    }
    
    static func parseExpectedCount(from filename: String) -> Int? {
        let numbers = filename.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        return numbers.first
    }
    
    static func printVideoResult(_ result: ProcessingResult) {
        print("")
        print("   ✅ Detected: \(result.detected) pushups")
        
        if let expected = result.expected {
            print("   📊 Expected: \(expected) pushups")
            
            if let accuracy = result.accuracy {
                let emoji = accuracy >= 0.9 ? "🎯" : (accuracy >= 0.7 ? "📈" : "⚠️")
                print("   \(emoji) Accuracy: \(String(format: "%.1f%%", accuracy * 100))")
            }
        }
        
        print("   ⏱️  Time: \(String(format: "%.2fs", result.processingTime))")
        print("   📹 Frames: \(result.frameCount)")
        
        // Show state breakdown
        let framesWithBody = result.frameResults.filter { $0.bodyDetected }.count
        print("   👤 Body detected: \(framesWithBody)/\(result.frameCount) frames")
        
        if framesWithBody > 0 {
            // Primary arm detection
            let leftArmFrames = result.frameResults.filter { $0.primaryArm == "LEFT" }.count
            let rightArmFrames = result.frameResults.filter { $0.primaryArm == "RIGHT" }.count
            print("   💪 Primary arm: LEFT=\(leftArmFrames), RIGHT=\(rightArmFrames)")
            
            let stateBreakdown = Dictionary(grouping: result.frameResults.filter { $0.bodyDetected }, by: { $0.pushupState })
                .mapValues { $0.count }
            
            print("   📊 States: ", terminator: "")
            let stateOrder: [PushupState] = [.up, .descending, .down, .ascending, .unknown]
            let states = stateOrder.compactMap { state -> (PushupState, Int)? in
                guard let count = stateBreakdown[state] else { return nil }
                return (state, count)
            }
            print(states.map { "\($0.0.rawValue)=\($0.1)" }.joined(separator: ", "))
            
            // Show elbow angle stats
            let angles = result.frameResults.compactMap { $0.elbowAngle }
            if !angles.isEmpty {
                let minAngle = angles.min() ?? 0
                let maxAngle = angles.max() ?? 0
                let avgAngle = angles.reduce(0, +) / Double(angles.count)
                print("   📐 Elbow angles: min=\(String(format: "%.0f°", minAngle)), avg=\(String(format: "%.0f°", avgAngle)), max=\(String(format: "%.0f°", maxAngle))")
            }
            
            // Show when count increased (state transitions that triggered a rep)
            var lastCount = 0
            var repTransitions: [(frame: Int, angle: Double?)] = []
            for frame in result.frameResults {
                if frame.pushupCount > lastCount {
                    repTransitions.append((frame: frame.frameNumber, angle: frame.elbowAngle))
                    lastCount = frame.pushupCount
                }
            }
            
            if !repTransitions.isEmpty {
                print("   🔢 Rep counted at frames: \(repTransitions.map { "F\($0.frame)" }.joined(separator: ", "))")
            }
        }
    }
    
    static func printSummary(_ results: [ProcessingResult]) {
        guard !results.isEmpty else { return }
        
        print("\n" + String(repeating: "═", count: 60))
        print("📊 SUMMARY")
        print(String(repeating: "═", count: 60))
        
        print("\n📹 Videos processed: \(results.count)")
        
        let withExpected = results.filter { $0.expected != nil }
        if !withExpected.isEmpty {
            let accuracies = withExpected.compactMap { $0.accuracy }
            if !accuracies.isEmpty {
                let avgAccuracy = accuracies.reduce(0, +) / Double(accuracies.count)
                let minAccuracy = accuracies.min() ?? 0
                let maxAccuracy = accuracies.max() ?? 0
                
                print("\n📈 Accuracy:")
                print("   Average: \(String(format: "%.1f%%", avgAccuracy * 100))")
                print("   Range:   \(String(format: "%.1f%%", minAccuracy * 100)) - \(String(format: "%.1f%%", maxAccuracy * 100))")
            }
        }
        
        let totalFrames = results.reduce(0) { $0 + $1.frameCount }
        let totalTime = results.reduce(0) { $0 + $1.processingTime }
        let fps = Double(totalFrames) / totalTime
        
        print("\n⚡ Performance:")
        print("   Total frames: \(totalFrames)")
        print("   Total time:   \(String(format: "%.2fs", totalTime))")
        print("   Speed:        \(String(format: "%.1f", fps)) fps")
        
        print("\n" + String(repeating: "═", count: 60))
    }
}

// MARK: - Async Entry Point
let semaphore = DispatchSemaphore(value: 0)

Task {
    await PushupCLI.run()
    semaphore.signal()
}

semaphore.wait()

// MARK: - Result Types
struct ProcessingResult {
    let filename: String
    let outputPath: String
    let detected: Int
    let expected: Int?
    let accuracy: Double?
    let frameCount: Int
    let processingTime: TimeInterval
    let frameResults: [FrameResult]
}
