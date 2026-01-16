This strategy is designed to be "Space-Efficient," meaning it only requires the **Shoulder, Elbow, and Wrist** to be in the camera frame. By focusing on **relative joint angles** rather than absolute screen position, the tracker remains accurate even if the user is close to the camera or the phone is tilted.

Below is the technical specification in Markdown format.

---

# Push-Up Tracking Strategy: Upper-Body Centric

## 1. Requirement & Input

* **Target Joints:** Shoulder, Elbow, Wrist (Left or Right).
* **Input Data:** 2D Coordinates  and a confidence score for each joint.
* **Goal:** Detect a full repetition using only the upper limb geometry to allow for close-proximity tracking.

---

## 2. Perspective & Joint Selection

To handle both **Side View** and **Front View** without manual toggling:

* **Visibility Logic:** For every frame, compare the confidence scores of the Left arm and Right arm.
* **Primary Arm:** Select the arm with the highest aggregate confidence (Shoulder + Elbow + Wrist).
* **Fallback:** If the user is in a pure profile (side) view and one arm is hidden, the system automatically tracks the visible arm.

---

## 3. The Core Metric: Interior Elbow Angle

The app should not track "inches moved," but rather the **Interior Angle ()** of the elbow.

* **Vector A:** Shoulder  to Elbow 
* **Vector B:** Wrist  to Elbow 
* **Calculation:**


* **Benefit:** This angle is mathematically identical whether the user is 2 feet or 10 feet from the camera.

---

## 4. State Machine Logic

To ensure a rep is high-quality and to prevent double-counting, use the following Finite State Machine (FSM):

| State | Name | Condition |
| --- | --- | --- |
| **State 0** | **READY / UP** | Elbow Angle . (Arms locked or nearly straight). |
| **State 1** | **DESCENDING** | Elbow Angle is decreasing AND . |
| **State 2** | **BOTTOM / DOWN** | Elbow Angle hits the "Depth Threshold" (Default: ). |
| **State 3** | **ASCENDING** | Elbow Angle is increasing AND . |

**Repetition Trigger:** A count is only incremented when the sequence completes: `0 -> 1 -> 2 -> 3 -> 0`.

---

## 5. Robustness & Edge Cases

* **Dynamic Depth Threshold:** Since some users have limited mobility, allow a "Calibration Rep" where the app records the minimum angle reached and sets the `State 2` threshold to  above that minimum.
* **Jitter Suppression:** * **Temporal Buffer:** Do not change states based on a single frame. A state change must be sustained for 2 consecutive frames.
* **Coordinate Smoothing:** Use a One-Euro Filter or Simple Moving Average (SMA) on the  coordinates before calculating the angle.


* **Perspective Scaling:** If the user is in a **Front View**, the Elbow moves "outward" or "toward" the camera. Because the 2D distance between Shoulder and Wrist shortens as the elbow bends, the angle calculation remains valid in 2D space.

---

## 6. Advanced Robustness Features (v2.0)

### 6.1 Z-Axis Depth Compensation (Foreshortening Problem)

When facing the camera, the 2D elbow angle often doesn't hit 90° even with proper depth due to perspective compression.

* **Arm Length Compression:** Measure the 2D distance from Shoulder to Wrist in the UP state (`baseArmLength`).
* **Dynamic Threshold:** If facing camera AND `currentArmLength < baseArmLength * 0.70`, relax the DOWN threshold from 90° to 105°.
* **Benefit:** Uses arm "shortening" as a proxy for 3D depth movement.

### 6.2 Arm Selection Hysteresis (Arm Swap Prevention)

Prevents rapid switching between left/right arm tracking during movement.

* **Hysteresis Rule:** Once a primary arm is selected, only switch if the alternate arm has >20% higher confidence for 5+ consecutive frames.
* **Formula:** `if (newArmConfidence > currentArmConfidence * 1.2) && (frameCount >= 5) { switch }`
* **Benefit:** Eliminates angle spikes from sudden arm switches.

### 6.3 Vertical Displacement Validation (Shoulder Travel)

Prevents counting "arm fidgeting" as reps when the body doesn't actually move.

* **Calibration:** Capture `shoulderY` position in the UP state.
* **Validation:** A transition to DOWN is only valid if `shoulder.y` has dropped by at least 8% of screen height.
* **Rep Gate:** Only count a rep if `sawValidShoulderDropInCycle` is true when transitioning ASCENDING → UP.

### 6.4 Standing Detection (Horizontal-First Strategy v2.1)

Uses inverse logic: detects "Push-up Ready" position instead of "Standing" to prevent false positives when facing camera.

**Detection Rules (in order):**

1. **Horizontal Check (Inverse Standing):**
   - If shoulder and hip are on same horizontal plane (side view): NOT standing
   - If shoulder-hip 2D distance is compressed (<0.18) when facing camera: NOT standing (body pointing toward camera)

2. **Face-Camera Exception:**
   - When facing camera, disable vertical-based standing detection
   - Use shoulder-width-to-hip-width ratio instead:
     - Standing: ratio ~1.0-1.3 (similar widths)
     - Pushup: ratio >1.8 (arms spread wide)
   - Also requires shoulders significantly above hips (>25% screen height)

3. **Height-Width Bounding Box:**
   - If upper body bounding box is wider than 1.2x its height: NOT standing
   - Handles face-camera floor positions where body appears spread out

4. **Side View (Fallback):**
   - Only used when NOT facing camera and NOT horizontal
   - Strict vertical check: shoulder must be >25% above hip AND deltaY > 2x deltaX

**State-Locked Standing Detection:**
- Cannot transition to `.standing` if in active rep cycle (descending/down/ascending)
- Once a rep starts, app must "commit" until returning to stable UP

**Grace Periods:**
- `standingStateFrameBuffer`: 30 frames (~1 second) before transitioning to standing
- `stableUpFramesForStanding`: 60 frames (~2 seconds) must be in stable UP before standing detection is even considered

**Standing Reset:** When standing is confirmed:
- Clear `angleHistory`, `baseArmLength`, `upStateShoulderY`
- Reset `stableUpStateFrameCount`

---

## 6. Implementation Checklist for AI Agent

1. **Extract Landmarks:** Get  for `shoulder`, `elbow`, `wrist`.
2. **Filter Noise:** Apply a 3-frame SMA to the coordinates.
3. **Calculate Angle:** Use the `atan2` or Dot Product method to find the interior angle of the elbow.
4. **State Logic:** Implement the FSM to transition from `UP` to `DOWN` and back to `UP`.
5. **Feedback Loop:** (Optional) If the user stays in `State 1` for too long without hitting `State 2`, trigger a "Go Lower" UI hint.

---

**Would you like me to create a specific list of "Failure Triggers" (like when the user moves too fast) to help your agent build a more polished UI?**