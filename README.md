# PushUppy 💪

A beautiful iOS pushup tracking app using Vision framework for real-time body pose detection.

## Quick Start

### For Development
1. Open `PushUppy.xcodeproj` in Xcode
2. Select **PushUppy** scheme
3. Build and run (Cmd + R)

### For Testing Pushup Detection Algorithm
1. **Set up CLI tool** (one-time): See [CLI_SETUP.md](CLI_SETUP.md)
2. **Add test videos** to `TestVideos/Input/`
3. **Name videos** with expected count: `pushup_5.mp4`, `workout_10.mov`
4. **Run CLI**: Select **PushupCLI** scheme → `Cmd + R`
5. **Check results**: Annotated videos appear in `TestVideos/Output/`

📖 **See [CLI_SETUP.md](CLI_SETUP.md) for detailed setup guide**

## Project Structure

```
PushUppy/
├── PushUppy/                    # Main app target
│   ├── ContentView.swift        # Main UI
│   ├── PushupDetector.swift     # Detection algorithm ⭐
│   ├── VideoProcessor.swift     # Video processing ⭐
│   └── PushUppyApp.swift        # App entry point
├── PushupCLI/                  # macOS CLI tool
│   └── main.swift              # Command line interface
├── TestVideos/                 # Test video folders
│   ├── Input/                  # Put videos here
│   └── Output/                 # Annotated videos appear here
├── project.md                  # Design doc
├── CLI_SETUP.md               # CLI setup guide
└── README.md                  # This file
```

⭐ = Files shared between app and CLI targets

## Tech Stack

- **Swift + SwiftUI** (iOS 17+)
- **Vision Framework** for body pose detection (2D)
- **AVFoundation** for video processing
- **macOS CLI Tool** for algorithm testing (runs on Mac, no device needed!)

## Current Status

✅ Pushup detection algorithm (2D body pose)  
✅ macOS CLI tool for fast algorithm iteration  
✅ Annotated video output with skeleton overlay  
✅ Accuracy tracking & performance metrics  
⏳ Live camera integration (coming next)  
⏳ Beautiful UI with animations  
⏳ Workout history & stats  

## Design Principles

- **Lovable UI**: Rounded fonts (SF Pro Rounded), smooth spring animations
- **Fast Iteration**: Test algorithm on macOS CLI before integrating into app
- **Modular**: Detection logic separate from UI, reusable across targets

## Development Workflow

1. **Add test videos** to `TestVideos/Input/` with known pushup counts
2. **Run CLI tool** (macOS, no device needed!)
3. **Check console** for accuracy metrics and stats
4. **Watch annotated videos** in `TestVideos/Output/` to debug
5. **Tune thresholds** in `PushupDetector.swift`
6. **Repeat** until accuracy is high
7. **Integrate** into live iOS app

## Requirements

- Xcode 15+
- macOS for CLI tool (algorithm testing)
- iOS 17+ device for running the app (when ready)

## Notes

- **CLI tool runs on macOS** - Vision framework works great on Mac!
- **Same detection code** used in both CLI and iOS app
- **Fast iteration** - no device connection needed for algorithm development

---

Built with ❤️ using Apple's Vision framework
