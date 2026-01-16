# 🖥️ PushupCLI Setup Guide

A macOS command line tool for fast pushup detection algorithm iteration.

## Why Use This?

| Old Workflow (iOS Tests) | New Workflow (macOS CLI) |
|--------------------------|--------------------------|
| Requires iOS device | Runs on your Mac |
| Download container to view files | Files saved locally |
| Container downloads can fail | No device communication |
| ~30 seconds to see results | ~5 seconds to see results |

## Quick Setup (5 minutes)

### Step 1: Add CLI Target in Xcode

1. **Open your project** in Xcode
2. **File → New → Target...** (or click `+` at bottom of targets list)
3. Choose **macOS → Command Line Tool**
4. Configure:
   - **Product Name:** `PushupCLI`
   - **Language:** Swift
5. Click **Finish**

### Step 2: Add Source Files to CLI Target

You need to share the detection code with the CLI target:

1. **Click on `PushupDetector.swift`** in the Project Navigator
2. **Open File Inspector** (right panel, or `Cmd+Opt+1`)
3. Under **Target Membership**, check ✅ **PushupCLI**

4. **Click on `VideoProcessor.swift`**
5. Under **Target Membership**, check ✅ **PushupCLI**

### Step 3: Add the CLI main.swift

1. **In Project Navigator**, expand the new `PushupCLI` folder
2. **Delete the default `main.swift`** that Xcode created
3. **Drag `PushupCLI/main.swift`** (from the PushupCLI folder we created) into the PushupCLI group in Xcode
4. Make sure it's added to the **PushupCLI** target

### Step 4: Set Working Directory

1. **Edit Scheme**: Product → Scheme → Edit Scheme (or `Cmd+<`)
2. Select **Run** in the left sidebar
3. Go to **Options** tab
4. Check ✅ **Use custom working directory**
5. Set it to your project folder:
   ```
   /path/to/PushUppy
   ```
6. Click **Close**

### Step 5: Build & Run

1. **Select the PushupCLI scheme** in Xcode's scheme selector (top toolbar)
2. **Build & Run**: `Cmd+R`

## Usage

### Default Mode (uses TestVideos folder)

1. Put your pushup videos in:
   ```
   TestVideos/Input/
   ```

2. Name videos with expected count for accuracy tracking:
   - `pushup_5.mp4` → expects 5 pushups
   - `workout_10.mov` → expects 10 pushups

3. Run the CLI (in Xcode or Terminal)

4. Find annotated videos in:
   ```
   TestVideos/Output/
   ```

### From Terminal

```bash
cd "/path/to/PushUppy"

# Process all videos in TestVideos/Input
./DerivedData/Build/Products/Debug/PushupCLI

# Or specify folders
./DerivedData/Build/Products/Debug/PushupCLI /path/to/input /path/to/output

# Or process a single video
./DerivedData/Build/Products/Debug/PushupCLI /path/to/video.mp4
```

### From Xcode

Just select the PushupCLI scheme and press `Cmd+R`!

## Example Output

```
╔══════════════════════════════════════════════════════════════╗
║           🏋️ PushUppy Algorithm Testing Tool 🏋️              ║
╚══════════════════════════════════════════════════════════════╝

📂 Input folder:  /Users/.../PushUppy/TestVideos/Input
📂 Output folder: /Users/.../PushUppy/TestVideos/Output

🎬 Found 2 video(s) to process
────────────────────────────────────────────────────────────────

[1/2] Processing: pushup_5.mp4

   ✅ Detected: 5 pushups
   📊 Expected: 5 pushups
   🎯 Accuracy: 100.0%
   ⏱️  Time: 2.34s
   📹 Frames: 150
   👤 Body detected: 148/150 frames
   📊 States: down=45, transition=58, up=45
   📐 Elbow angles: min=72°, avg=125°, max=168°

[2/2] Processing: workout_10.mov

   ✅ Detected: 9 pushups
   📊 Expected: 10 pushups
   📈 Accuracy: 90.0%
   ⏱️  Time: 4.56s
   📹 Frames: 300
   👤 Body detected: 295/300 frames
   📊 States: down=85, transition=120, up=90
   📐 Elbow angles: min=68°, avg=130°, max=172°

════════════════════════════════════════════════════════════════
📊 SUMMARY
════════════════════════════════════════════════════════════════

📹 Videos processed: 2

📈 Accuracy:
   Average: 95.0%
   Range:   90.0% - 100.0%

⚡ Performance:
   Total frames: 450
   Total time:   6.90s
   Speed:        65.2 fps

════════════════════════════════════════════════════════════════

📂 Annotated videos saved to:
   /Users/.../PushUppy/TestVideos/Output

💡 Open in Finder: open "/Users/.../PushUppy/TestVideos/Output"
```

## Algorithm Iteration Workflow

1. **Add test video** to `TestVideos/Input/`
2. **Run CLI** (`Cmd+R` in Xcode)
3. **Check console** for accuracy & stats
4. **Watch annotated video** in `TestVideos/Output/`
5. **Adjust thresholds** in `PushupDetector.swift`:
   ```swift
   private let downAngleThreshold: Double = 90.0
   private let upAngleThreshold: Double = 160.0
   ```
6. **Re-run CLI** → See if accuracy improved
7. **Repeat** until satisfied

## Troubleshooting

### "No video track found"
- Video file might be corrupted
- Try a different video format

### "Body not detected"
- Check video quality and lighting
- Ensure clear side view of person

### Build errors about missing types
- Make sure `PushupDetector.swift` and `VideoProcessor.swift` are added to PushupCLI target

### "Use custom working directory" not set
- Edit scheme → Run → Options → Check "Use custom working directory"
- Set to project folder path

## Files Structure

```
PushUppy/
├── PushupCLI/
│   └── main.swift              ← CLI entry point
├── PushUppy/
│   ├── PushupDetector.swift    ← Shared with CLI ✅
│   └── VideoProcessor.swift    ← Shared with CLI ✅
├── TestVideos/
│   ├── Input/                  ← Put videos here
│   │   └── pushup_5.mp4
│   └── Output/                 ← Annotated videos appear here
│       └── annotated_pushup_5.mp4
└── CLI_SETUP.md               ← This file
```

## Comparison: CLI vs iOS Tests

| Feature | CLI (macOS) | iOS Tests |
|---------|-------------|-----------|
| Device needed | ❌ No | ✅ Yes |
| Iteration speed | ⚡ Fast | 🐢 Slow |
| Output access | 📂 Local folder | 📱 Download container |
| Good for | Algorithm tuning | Final validation |

**Recommendation:** Use CLI for day-to-day algorithm work. Use iOS tests for final validation before shipping.
