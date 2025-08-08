import Foundation
import OSLog

@available(macOS 11.0, *)
class LogStore {
    private let logger = CompatLogger(subsystem: "jp.ourin.logstore", category: "main")

    func fetchLogEntries(subsystem: String, category: String, level: OSLogEntryLog.Level, since: Date) -> [LogEntry] {
        var entries: [LogEntry] = []

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: since)

            // NSPredicate is tricky. We'll build it carefully.
            var predicates: [NSPredicate] = []
            if !subsystem.isEmpty && subsystem != "jp.ourin.*" {
                predicates.append(NSPredicate(format: "subsystem == %@", subsystem))
            }
            if !category.isEmpty {
                predicates.append(NSPredicate(format: "category == %@", category))
            }

            let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            let logEntries = try store.getEntries(with: [], at: position, matching: compoundPredicate)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.level.rawValue >= level.rawValue }

            entries = logEntries.map { log in
                LogEntry(
                    timestamp: log.date,
                    level: levelToString(log.level),
                    category: log.category,
                    message: log.composedMessage,
                    metadata: "" // OSLogEntry doesn't directly expose metadata in a simple string format
                )
            }
            logger.info("Fetched \(entries.count) log entries.")

        } catch {
            logger.error("Failed to fetch log entries: \(error.localizedDescription)")
        }

        return entries
    }

    private func levelToString(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "undefined"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault:
            return "fault"
        @unknown default:
            return "unknown"
        }
    }
}

extension OSLogEntryLog.Level {
    static func fromString(_ string: String) -> OSLogEntryLog.Level {
        switch string.lowercased() {
        case "debug": return .debug
        case "info": return .info
        case "notice": return .notice
        case "error": return .error
        case "fault": return .fault
        default: return .undefined // "all"
        }
    }
}
