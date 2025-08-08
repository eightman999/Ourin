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

struct SignpostEntry: Identifiable {
    let id = UUID()
    let name: String
    let type: SignpostType
    let duration: Double
}

enum SignpostType {
    case interval
    case instant
}
