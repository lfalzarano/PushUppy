# PushUppy Architecture

## CLI Testing Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                  CLI TESTING WORKFLOW                        │
└─────────────────────────────────────────────────────────────┘

  Test Videos                CLI Tool                Processing
  (TestVideos/Input/)        (PushupCLI)             (macOS)
       │                           │                         │
   ┌───────┐                ┌──────────┐              ┌─────────────┐
   │pushup │  ──Reads──>    │ main.swift│  ──Calls──> │VideoProcessor│
   │_5.mp4 │                │          │              │ processes    │
   └───────┘                └──────────┘              │ frame by     │
       │                           │                   │ frame        │
       │                           │                   └─────────────┘
       │                           │                         │
       │                           │                   ┌─────┴────────┐
       │                           │                   ▼              ▼
       │                           │           ┌────────────┐   ┌──────────┐
       │                           │           │   Vision   │   │ Pushup   │
       │                           │           │   Body     │──>│ Detector │
       │                           │           │   Pose     │   │ Algorithm│
       │                           │           └────────────┘   └──────────┘
       │                           │                                 │
       │                           │                                 │
       │         ┌─────────────────┴─────────────────────────────────┘
       │         │
       │         ▼
       │   ┌─────────────────────────────────────────────┐
       │   │           RESULTS & OUTPUTS                 │
       │   │                                             │
       │   │  1. Annotated Video (TestVideos/Output/)   │
       │   │  2. Console output (accuracy, performance) │
       │   │  3. State breakdown & angle stats         │
       │   └─────────────────────────────────────────────┘
       │                      │
       │                      ▼
       │              ┌───────────────┐
       └──Compare────>│   Accuracy    │
                      │   Detected: 5 │
                      │   Expected: 5 │
                      │   Score: 100% │
                      └───────────────┘
```

## Class Responsibilities

### PushupDetector
**Location:** `PushUppy/PushupDetector.swift`  
**Target Membership:** Both `PushUppy` and `PushupCLI`

**Responsibilities:**
- Takes `VNHumanBodyPoseObservation` from Vision framework
- Calculates elbow angles from joint positions
- Maintains state machine (up, down, transition, unknown)
- Counts pushups based on state transitions (down → up)
- Returns current state and metrics

**Key Methods:**
```swift
func detectPushup(observation: VNHumanBodyPoseObservation) 
    -> (state: PushupState, count: Int, elbowAngle: Double?, shoulderWristRatio: Double?)
```

**Tunable Parameters:**
- `downAngleThreshold: Double = 90.0`
- `upAngleThreshold: Double = 160.0`
- `shoulderToWristRatioThreshold: Double = 0.3`

### VideoProcessor
**Location:** `PushUppy/VideoProcessor.swift`  
**Target Membership:** Both `PushUppy` and `PushupCLI`

**Responsibilities:**
- Loads video files using AVFoundation
- Extracts frames as pixel buffers
- Runs Vision body pose detection on each frame
- Calls PushupDetector for each detected body pose
- Annotates frames with skeleton overlay
- Writes annotated video output
- Collects frame-by-frame results
- Returns comprehensive test results

**Key Methods:**
```swift
func processVideo(inputURL: URL, outputURL: URL, expectedCount: Int?) 
    async -> VideoTestResult?
```

### PushupCLI
**Location:** `PushupCLI/main.swift`  
**Target Membership:** `PushupCLI` only

**Responsibilities:**
- Discovers all videos in `TestVideos/Input/` folder
- Parses expected counts from filenames
- Orchestrates video processing
- Prints formatted console output with stats
- Calculates aggregate statistics
- Outputs annotated videos to `TestVideos/Output/`

**Main Entry Point:**
```swift
static func main() async
```

## Data Flow

### Input Flow
```
Video File (.mp4/.mov)
    │
    ▼
AVAssetReader (AVFoundation)
    │
    ▼
CMSampleBuffer (each frame)
    │
    ▼
CVPixelBuffer (image data)
    │
    ▼
VNDetectHumanBodyPoseRequest (Vision)
    │
    ▼
VNHumanBodyPoseObservation (joint positions)
    │
    ▼
PushupDetector.detectPushup()
    │
    ▼
(state, count, elbowAngle, ratio)
```

### Output Flow
```
PushupDetector Results
    │
    ├──> FrameResult (stored for JSON)
    │
    ├──> Annotation Drawing (skeleton overlay)
    │       │
    │       ▼
    │   Annotated CVPixelBuffer
    │       │
    │       ▼
    │   AVAssetWriterInputPixelBufferAdaptor
    │       │
    │       ▼
    │   Annotated Video File
    │
    └──> VideoTestResult
            │
            ├──> detection_results.json
            ├──> summary.csv
            └──> Console Output
```

## State Machine

```
┌───────────┐
│  UNKNOWN  │  (Initial state, or body not detected clearly)
└─────┬─────┘
      │
      │ Elbow angle > 160°
      ▼
┌───────────┐
│    UP     │  (Arms extended, ready position)
└─────┬─────┘
      │
      │ Elbow angle between 90° and 160°
      ▼
┌───────────┐
│TRANSITION │  (Moving between up and down)
└─────┬─────┘
      │
      │ Elbow angle < 90° AND shoulder close to wrist
      ▼
┌───────────┐
│   DOWN    │  (Bottom of pushup, chest near ground)
└─────┬─────┘
      │
      │ Elbow angle between 90° and 160°
      ▼
┌───────────┐
│TRANSITION │
└─────┬─────┘
      │
      │ Elbow angle > 160°
      ▼
┌───────────┐
│    UP     │  ← PUSHUP COUNTED! (down → up transition)
└───────────┘

Note: Count increments only on DOWN → UP transition
```

## Joint Detection (Vision Framework)

### Key Joints Used
```
        HEAD
         │
        NECK
       /   \
      /     \
   L.SHOULDER─R.SHOULDER
      │         │
   L.ELBOW   R.ELBOW  ← Primary angle calculation
      │         │
   L.WRIST   R.WRIST  ← Used for height ratio
      │         │
    L.HIP───R.HIP
      │     │
   L.KNEE R.KNEE
      │     │
   L.ANKLE R.ANKLE
```

### Angle Calculation (2D)
```
For each arm:
  Vector1 = Shoulder → Elbow (upper arm)
  Vector2 = Wrist → Elbow (forearm)
  
  Angle = arccos(dot(Vector1, Vector2) / (|Vector1| × |Vector2|))
  
Average of left and right elbow angles used for detection
```

## Future Architecture (Live App)

```
┌──────────────────────────────────────────────┐
│             SwiftUI ContentView               │
│  ┌────────────┐          ┌────────────┐     │
│  │  Camera    │          │  Stats     │     │
│  │  Preview   │          │  Display   │     │
│  └────────────┘          └────────────┘     │
│         │                       ▲            │
│         │                       │            │
│         │                  State Updates     │
│         │                       │            │
│         ▼                       │            │
│  ┌──────────────────────────────┴──────┐    │
│  │      CameraViewController           │    │
│  │  (AVCaptureSession)                 │    │
│  └──────────────────────────────────────┘   │
│         │                                    │
│         │ Frames                             │
│         ▼                                    │
│  ┌──────────────────────────────────────┐   │
│  │   Vision Body Pose Detection         │   │
│  └──────────────────────────────────────┘   │
│         │                                    │
│         │ VNHumanBodyPoseObservation         │
│         ▼                                    │
│  ┌──────────────────────────────────────┐   │
│  │   PushupDetector (SAME CLASS!)       │   │
│  │   (Already tested with videos)       │   │
│  └──────────────────────────────────────┘   │
└──────────────────────────────────────────────┘
```

## Why This Architecture Works

### Separation of Concerns
- **PushupDetector**: Pure algorithm, no UI/video dependencies
- **VideoProcessor**: Video I/O only, delegates detection logic
- **Tests**: Orchestration and reporting

### Testability
- Algorithm tested in isolation with known inputs
- No need for live camera during development
- Repeatable, deterministic tests
- Can regression test algorithm improvements

### Reusability
- Same `PushupDetector` class works for:
  - Video testing (current)
  - Live camera (future)
  - Recorded workouts (future)
- Logic is independent of data source

### Iterability
- Fast feedback loop: change threshold → run test → see results
- Visual debugging: watch annotated videos
- Quantitative metrics: accuracy percentages
- Frame-by-frame analysis: JSON output

## Performance Considerations

### Current (Testing)
- Processes videos as fast as possible (no real-time constraint)
- ~20-30 FPS on typical hardware
- Can batch process multiple videos
- I/O bound (reading/writing video files)

### Future (Live App)
- Must maintain 30 FPS for smooth UI
- Vision framework is optimized for real-time
- Detection is fast (~5-10ms per frame on iPhone)
- UI updates must be throttled (not every frame)

## Error Handling

### Simulator Detection
```swift
#if targetEnvironment(simulator)
    throw XCTSkip("Vision requires real device")
#endif
```

### Missing Video
- Test continues with available videos
- Reports missing videos in summary

### Body Not Detected
- State set to `.unknown`
- Count doesn't increment
- Logged in frame results

### Invalid Video Format
- Test fails gracefully
- Error logged to console
- Continues with next video

---

**Remember:** The beauty of this architecture is that the detection algorithm (`PushupDetector`) is completely independent and thoroughly tested before you ever need to deal with live camera integration!
