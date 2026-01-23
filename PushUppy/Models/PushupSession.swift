import Foundation
import Combine

/// Represents a single pushup workout session
/// Designed for future storage and history tracking
struct PushupSession: Identifiable, Codable {
    /// Unique identifier for the session
    let id: UUID
    
    /// When the session started
    let startTime: Date
    
    /// When the session ended (nil if still in progress)
    var endTime: Date?
    
    /// Final pushup count
    var finalCount: Int
    
    /// Highest elbow angle observed during session (indicates best form in UP position)
    var peakElbowAngle: Double?
    
    /// Lowest elbow angle observed during session (indicates depth in DOWN position)
    var minElbowAngle: Double?
    
    /// Duration of the session in seconds
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    /// Average pushups per minute
    var pushupRate: Double? {
        guard let dur = duration, dur > 0 else { return nil }
        return Double(finalCount) / (dur / 60.0)
    }
    
    /// Creates a new session starting now
    init(id: UUID = UUID(), startTime: Date = Date()) {
        self.id = id
        self.startTime = startTime
        self.endTime = nil
        self.finalCount = 0
        self.peakElbowAngle = nil
        self.minElbowAngle = nil
    }
    
    /// Ends the session and records final stats
    mutating func endSession(count: Int, peakAngle: Double? = nil, minAngle: Double? = nil) {
        self.endTime = Date()
        self.finalCount = count
        self.peakElbowAngle = peakAngle
        self.minElbowAngle = minAngle
    }
}

// MARK: - Session History Manager (Future Implementation Placeholder)

/// Manager for storing and retrieving pushup session history
/// This is a placeholder for future implementation with CoreData, SwiftData, or UserDefaults
class SessionHistoryManager: ObservableObject {
    
    @Published var sessions: [PushupSession] = []
    
    /// Singleton instance
    static let shared = SessionHistoryManager()
    
    private init() {
        loadSessions()
    }
    
    // MARK: - CRUD Operations (Placeholder)
    
    /// Save a completed session
    func saveSession(_ session: PushupSession) {
        sessions.insert(session, at: 0) // Most recent first
        persistSessions()
    }
    
    /// Load all sessions from storage
    func loadSessions() {
        // TODO: Implement actual persistence (CoreData, SwiftData, or UserDefaults)
        // For now, sessions are only kept in memory
    }
    
    /// Persist sessions to storage
    private func persistSessions() {
        // TODO: Implement actual persistence
    }
    
    // MARK: - Statistics
    
    /// Total pushups across all sessions
    var totalPushups: Int {
        sessions.reduce(0) { $0 + $1.finalCount }
    }
    
    /// Best single session count
    var maxPushups: Int {
        sessions.map { $0.finalCount }.max() ?? 0
    }
    
    /// Sessions today
    var todaySessions: [PushupSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return sessions.filter { calendar.startOfDay(for: $0.startTime) == today }
    }
    
    /// Pushups completed today
    var todayPushups: Int {
        todaySessions.reduce(0) { $0 + $1.finalCount }
    }
    
    /// Current streak (consecutive days with at least one session)
    var currentStreak: Int {
        guard !sessions.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        var streak = 0
        var checkDate = calendar.startOfDay(for: Date())
        
        // Group sessions by day
        let sessionDays = Set(sessions.map { calendar.startOfDay(for: $0.startTime) })
        
        while sessionDays.contains(checkDate) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: checkDate) else { break }
            checkDate = previousDay
        }
        
        return streak
    }
}

// MARK: - Session Summary (for UI display)

/// A lightweight summary of a session for list displays
struct SessionSummary: Identifiable {
    let id: UUID
    let date: Date
    let count: Int
    let duration: TimeInterval?
    
    init(from session: PushupSession) {
        self.id = session.id
        self.date = session.startTime
        self.count = session.finalCount
        self.duration = session.duration
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var formattedDuration: String {
        guard let dur = duration else { return "--" }
        let minutes = Int(dur) / 60
        let seconds = Int(dur) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
