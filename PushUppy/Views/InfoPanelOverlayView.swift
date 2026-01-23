import SwiftUI

/// Info panel overlay matching the CLI annotation style
/// Displays pushup count, state, elbow angle bar, and tracking info
struct InfoPanelOverlayView: View {
    
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Pushup Count (large)
            Text("PUSHUPS: \(cameraManager.pushupCount)")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            // Row 2: State with color
            HStack(spacing: 8) {
                Text("STATE:")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                
                Text(cameraManager.pushupState.rawValue)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(stateColor)
            }
            
            // Row 3: Elbow Angle Label
            HStack(spacing: 8) {
                Text("ELBOW ANGLE:")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                
                Text(angleText)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            
            // Row 4: Angle Progress Bar
            AngleProgressBar(angle: cameraManager.elbowAngle)
            
            // Row 5: Primary Arm
            Text("TRACKING: \(cameraManager.primaryArm) ARM")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.yellow)
            
            Divider()
                .background(Color.white.opacity(0.3))
            
            // State Legend
            StateLegend(currentState: cameraManager.pushupState)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(stateColor, lineWidth: 3)
                )
        )
        .frame(width: 280)
    }
    
    // MARK: - Computed Properties
    
    private var stateColor: Color {
        switch cameraManager.pushupState {
        case .up:
            return Color(red: 0.2, green: 0.8, blue: 0.2) // Green
        case .descending:
            return Color(red: 1.0, green: 0.6, blue: 0.0) // Orange
        case .down:
            return Color(red: 1.0, green: 0.2, blue: 0.2) // Red
        case .ascending:
            return Color(red: 0.2, green: 0.6, blue: 1.0) // Blue
        case .unknown:
            return Color(red: 0.5, green: 0.5, blue: 0.5) // Gray
        case .standing:
            return Color(red: 0.8, green: 0.2, blue: 0.8) // Purple
        }
    }
    
    private var angleText: String {
        if let angle = cameraManager.elbowAngle {
            return String(format: "%.0f°", angle)
        }
        return "N/A"
    }
}

// MARK: - Angle Progress Bar

struct AngleProgressBar: View {
    let angle: Double?
    
    private let barHeight: CGFloat = 16
    private let downThreshold: Double = 90
    private let upThreshold: Double = 150
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color(white: 0.3))
                
                // Progress fill
                if let angle = angle {
                    let progress = min(1.0, max(0.0, angle / 180.0))
                    Rectangle()
                        .fill(angleColor(for: angle))
                        .frame(width: width * progress)
                }
                
                // Threshold markers
                // 90° marker (DOWN threshold)
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2)
                    .offset(x: width * (90.0 / 180.0) - 1)
                
                // 150° marker (UP threshold)
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2)
                    .offset(x: width * (150.0 / 180.0) - 1)
            }
            .cornerRadius(4)
            
            // Marker labels
            Text("90°")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .position(x: width * (90.0 / 180.0), y: barHeight + 12)
            
            Text("150°")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .position(x: width * (150.0 / 180.0), y: barHeight + 12)
        }
        .frame(height: barHeight + 20)
    }
    
    private func angleColor(for angle: Double) -> Color {
        if angle > 150 {
            return Color(red: 0.2, green: 0.8, blue: 0.2) // Green - UP zone
        } else if angle > 90 {
            return Color(red: 1.0, green: 0.6, blue: 0.0) // Orange - transition
        } else {
            return Color(red: 1.0, green: 0.2, blue: 0.2) // Red - DOWN zone
        }
    }
}

// MARK: - State Legend

struct StateLegend: View {
    let currentState: PushupState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow(state: .up, label: "UP", color: Color(red: 0.2, green: 0.8, blue: 0.2))
            legendRow(state: .descending, label: "DESC", color: Color(red: 1.0, green: 0.6, blue: 0.0))
            legendRow(state: .down, label: "DOWN", color: Color(red: 1.0, green: 0.2, blue: 0.2))
            legendRow(state: .ascending, label: "ASC", color: Color(red: 0.2, green: 0.6, blue: 1.0))
            legendRow(state: .standing, label: "STAND", color: Color(red: 0.8, green: 0.2, blue: 0.8))
        }
    }
    
    @ViewBuilder
    private func legendRow(state: PushupState, label: String, color: Color) -> some View {
        let isActive = currentState == state
        
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(isActive ? 1.0 : 0.4))
                .frame(width: 8, height: 8)
            
            Text(label)
                .font(.system(size: 12, weight: isActive ? .bold : .regular, design: .monospaced))
                .foregroundColor(color.opacity(isActive ? 1.0 : 0.5))
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black
        
        VStack {
            InfoPanelOverlayView(cameraManager: {
                let manager = CameraManager()
                // Preview with mock data would require @Published changes
                return manager
            }())
            
            Spacer()
        }
        .padding()
    }
    .ignoresSafeArea()
}
