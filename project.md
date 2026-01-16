# PushUppy: iOS Pushup Tracker

## Purpose
A high-polish iOS application built with SwiftUI to track pushups using Vision 2D Body Pose detection. The app prioritizes a "lovable" UI with smooth animations.

## Tech Stack
- **Language/Framework:** Swift / SwiftUI (iOS 17+)
- **Computer Vision:** Vision Framework
- **UI Architecture:** Centralized `AppTheme` for easy customization.
- **Algorithm Testing:** macOS Command Line Tool for fast iteration (no device needed).

## Design Principles
- **Typography:** Rounded bubbly fonts (SF Pro Rounded).
- **Animations:** Spring animations (`response: 0.6, dampingFraction: 0.8`).
- **Layout:** One unified header that transforms (resizes vertically) while content below swipes horizontally using a `GeometryReader` + `HStack` offset pattern.

## Project Structure & Target Membership
- **Main App Target (PushUppy):**
    - `ContentView.swift`: Main UI hierarchy.
    - `PushupDetector.swift`: The logic class (elbow angle calculation, state machine).
    - `VideoProcessor.swift`: Handles frame-by-frame processing.
- **CLI Target (PushupCLI):**
    - `main.swift`: Command line tool for algorithm testing on macOS.
    - **Note:** `PushupDetector.swift` and `VideoProcessor.swift` are shared with CLI target.

## Algorithm Testing Workflow
- **See CLI_SETUP.md** for setup instructions.
- **Run on macOS** - no iOS device needed!
- Put test videos in `TestVideos/Input/`
- Name videos with expected count: `pushup_5.mp4`, `workout_10.mov`
- Run CLI tool → Get annotated videos in `TestVideos/Output/`
- Fast iteration cycle: adjust algorithm → run CLI → check results
