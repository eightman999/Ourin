import Foundation

// MARK: - Log Data Models

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: String
    let category: String
    let message: String
    let metadata: String
}
