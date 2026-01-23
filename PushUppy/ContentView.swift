import SwiftUI

// MARK: - Design System
struct AppTheme {
    // Colors
    static let primary = Color.orange
    static let secondary = Color.orange.opacity(0.7)
    static let background = Color(UIColor.systemGray6)
    static let cardBackground = Color(UIColor.systemGray5)
    static let glassBackground = Color.white.opacity(0.2)
    
    // Fonts
    static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
    static let title = Font.system(size: 24, weight: .semibold, design: .rounded)
    static let headline = Font.system(size: 20, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 17, weight: .regular, design: .rounded)
    static let caption = Font.system(size: 14, weight: .medium, design: .rounded)
    
    // Spacing
    static let cornerRadius: CGFloat = 24
    static let cardCornerRadius: CGFloat = 20
    static let padding: CGFloat = 20
}

// MARK: - Models
struct WorkoutStats {
    var currentStreak: Int = 113
    var longestStreak: Int = 32
    var maxPushups: Int = 13
    var totalPushups: Int = 1232
}

// MARK: - Main App View
struct ContentView: View {
    @State private var selectedTab = 0
    @State private var stats = WorkoutStats()
    @StateObject private var cameraManager = CameraManager()
    @State private var showingSession = false
    
    // Namespace for matched geometry effect (expanding camera animation)
    @Namespace private var cameraNamespace
    
    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Fixed Stats Header - stays at top, expands downward
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 60)
                    
                    StatsHeaderView(
                        stats: stats,
                        isCompact: selectedTab == 1
                    )
                    .padding(.horizontal, AppTheme.padding)
                }
                .frame(height: selectedTab == 1 ? 140 : 220)
                .frame(maxWidth: .infinity)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: selectedTab)
                
                // Main Content Area - swipe between views
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        WorkoutContentView(
                            cameraManager: cameraManager,
                            showingSession: $showingSession,
                            cameraNamespace: cameraNamespace
                        )
                        .frame(width: geometry.size.width)
                        
                        HistoryContentView()
                            .frame(width: geometry.size.width)
                    }
                    .offset(x: selectedTab == 0 ? 0 : -geometry.size.width)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: selectedTab)
                }
                
                // Fixed Liquid Glass Navbar at bottom
                LiquidGlassNavBar(selectedTab: $selectedTab)
                    .padding(.horizontal, AppTheme.padding)
                    .padding(.bottom, 10)
            }
        }
        .fullScreenCover(isPresented: $showingSession) {
            PushupSessionView(
                cameraManager: cameraManager,
                isPresented: $showingSession,
                onSessionEnd: { count in
                    // Update stats with session result
                    if count > 0 {
                        stats.totalPushups += count
                        if count > stats.maxPushups {
                            stats.maxPushups = count
                        }
                    }
                }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}

// MARK: - Workout Content (without header)
struct WorkoutContentView: View {
    @ObservedObject var cameraManager: CameraManager
    @Binding var showingSession: Bool
    var cameraNamespace: Namespace.ID
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live Camera View with Record Button
                LiveCameraCardView(
                    cameraManager: cameraManager,
                    onRecordTapped: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingSession = true
                        }
                    }
                )
                .padding(.horizontal, AppTheme.padding)
                .padding(.top, 20)
            }
        }
        .onAppear {
            cameraManager.startSession()
        }
    }
}

// MARK: - Live Camera Card View
struct LiveCameraCardView: View {
    @ObservedObject var cameraManager: CameraManager
    let onRecordTapped: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // Camera Preview or Placeholder
            if cameraManager.permissionGranted {
                CameraPreviewView(cameraManager: cameraManager)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
            } else {
                // Placeholder when no camera permission
                RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                    .fill(Color.black)
                
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("Camera access required")
                        .font(AppTheme.caption)
                        .foregroundColor(.white.opacity(0.7))
                    
                    Button("Enable Camera") {
                        cameraManager.checkPermissions()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
            }
            
            // Overlay content
            VStack {
                Spacer()
                
                // Record button at bottom
                RecordButtonView(onTap: onRecordTapped)
                    .padding(.bottom, 30)
            }
            
            // Top instruction text
            VStack {
                Text("Tap to start tracking")
                    .font(AppTheme.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.top, 20)
                
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 450)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }
}

// MARK: - Record Button
struct RecordButtonView: View {
    let onTap: () -> Void
    
    @State private var isPressing = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Outer pulse ring
                Circle()
                    .stroke(Color.red.opacity(0.3), lineWidth: 3)
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulseScale)
                    .opacity(2 - pulseScale)
                
                // Outer ring
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 70, height: 70)
                
                // Inner red circle
                Circle()
                    .fill(Color.red)
                    .frame(width: 54, height: 54)
                    .scaleEffect(isPressing ? 0.85 : 1.0)
                
                // Record icon
                Image(systemName: "record.circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressing ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressing)
        .onAppear {
            // Pulse animation
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulseScale = 1.3
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressing = true }
                .onEnded { _ in isPressing = false }
        )
    }
}

// MARK: - History Content (without header)
struct HistoryContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Calendar Scroll View
            CalendarScrollView()
                .padding(.horizontal, AppTheme.padding)
                .padding(.top, 20)
                .padding(.bottom, 20)
        }
    }
}

// MARK: - Stats Header Component
struct StatsHeaderView: View {
    let stats: WorkoutStats
    let isCompact: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primary.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: AppTheme.primary.opacity(0.3), radius: 10, y: 5)
            
            if isCompact {
                CompactStatsContent(stats: stats)
            } else {
                FullStatsContent(stats: stats)
            }
        }
        .frame(height: isCompact ? 80 : 160)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isCompact)
    }
}

struct FullStatsContent: View {
    let stats: WorkoutStats
    
    var body: some View {
        HStack(spacing: 30) {
            // Fire Emoji and Days
            VStack(spacing: 8) {
                Text("🔥")
                    .font(.system(size: 50))
                Text("\(stats.currentStreak) Days")
                    .font(AppTheme.headline)
                    .foregroundColor(.white)
            }
            
            // Stats Grid
            VStack(alignment: .leading, spacing: 8) {
                StatRow(label: "Max Pushups:", value: "\(stats.maxPushups)")
                StatRow(label: "Longest Streak:", value: "\(stats.longestStreak) days")
                StatRow(label: "Total Pushups:", value: "\(stats.totalPushups)")
            }
        }
        .padding(AppTheme.padding)
    }
}

struct CompactStatsContent: View {
    let stats: WorkoutStats
    
    var body: some View {
        HStack {
            Text("🔥")
                .font(.system(size: 40))
            
            Text("\(stats.currentStreak) Days")
                .font(AppTheme.title)
                .foregroundColor(.white)
                .fontWeight(.bold)
            
            Spacer()
        }
        .padding(AppTheme.padding)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(AppTheme.body)
                .foregroundColor(.white.opacity(0.9))
            Text(value)
                .font(AppTheme.body)
                .foregroundColor(.white)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Calendar Scroll View
struct CalendarScrollView: View {
    let months = ["January", "February", "March", "April"]
    let daysInMonth = 31
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                ForEach(months, id: \.self) { month in
                    MonthGridView(month: month, days: daysInMonth)
                }
            }
            .padding(.vertical)
        }
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius)
                .fill(AppTheme.cardBackground)
        )
    }
}

struct MonthGridView: View {
    let month: String
    let days: Int
    let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    
    var body: some View {
        VStack(spacing: 15) {
            Text(month)
                .font(AppTheme.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(1...days, id: \.self) { day in
                    DayCell(day: day, pushups: Int.random(in: 0...15))
                }
            }
        }
        .padding()
    }
}

struct DayCell: View {
    let day: Int
    let pushups: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(day)")
                .font(AppTheme.caption)
                .foregroundColor(.secondary)
            
            if pushups > 0 {
                Text("\(pushups)")
                    .font(AppTheme.body)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primary)
            } else {
                Text("-")
                    .font(AppTheme.body)
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .frame(width: 40, height: 50)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(pushups > 0 ? AppTheme.primary.opacity(0.1) : Color.clear)
        )
    }
}

// MARK: - Liquid Glass NavBar
struct LiquidGlassNavBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            NavBarButton(
                title: "Workout",
                isSelected: selectedTab == 0,
                action: { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { selectedTab = 0 } }
            )
            
            NavBarButton(
                title: "History",
                isSelected: selectedTab == 1,
                action: { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { selectedTab = 1 } }
            )
        }
        .frame(height: 65)
        .background(
            ZStack {
                // Blur effect
                RoundedRectangle(cornerRadius: 25)
                    .fill(.ultraThinMaterial)
                
                // Glass highlight
                RoundedRectangle(cornerRadius: 25)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 25)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 20, y: 10)
    }
}

struct NavBarButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.headline)
                .foregroundColor(isSelected ? .white : .primary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    ZStack {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.primary, AppTheme.primary.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: AppTheme.primary.opacity(0.3), radius: 8, y: 4)
                        }
                    }
                )
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
