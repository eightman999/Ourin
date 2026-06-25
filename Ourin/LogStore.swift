import Foundation
import OSLog

@available(macOS 11.0, *)
class LogStore {
    private let logger = CompatLogger(subsystem: "jp.ourin.logstore", category: "main")

    func fetchLogEntries(subsystem: String, category: String, level: OSLogEntryLog.Level, since: Date) -> [LogEntry] {
        var entries: [LogEntry] = []

        do {
            let store: OSLogStore
            if #available(macOS 12.0, *) {
                store = try OSLogStore(scope: .currentProcessIdentifier)
            } else {
                store = try OSLogStore.local()
            }
            let position = store.position(date: since)

            // NSPredicate is tricky. We'll build it carefully.
            // 重要: 述語が空のままだと OSLogStore がプロセス内の全ログを走査し、
            // 呼び出しスレッドを長時間ブロックする（メインで呼ぶと UI がハングする）。
            // そのため "jp.ourin.*" のようなワイルドカードでも必ず BEGINSWITH 述語を立てる。
            var predicates: [NSPredicate] = []
            if !subsystem.isEmpty {
                if subsystem.hasSuffix(".*") {
                    let prefix = String(subsystem.dropLast(2)) // "jp.ourin.*" -> "jp.ourin"
                    let prefixPred = NSPredicate(format: "subsystem BEGINSWITH %@", prefix)
                    // "jp.ourin.*" は「アプリ自身のログ」を意図する。jp.ourin.* 配下に加え、
                    // 素の "Ourin" サブシステム（CompatLogger で多用）も取りこぼさない。
                    if prefix.caseInsensitiveCompare("jp.ourin") == .orderedSame {
                        let barePred = NSPredicate(format: "subsystem ==[c] %@", "Ourin")
                        predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [prefixPred, barePred]))
                    } else {
                        predicates.append(prefixPred)
                    }
                } else {
                    predicates.append(NSPredicate(format: "subsystem == %@", subsystem))
                }
            }
            if !category.isEmpty {
                predicates.append(NSPredicate(format: "category == %@", category))
            }

            let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            // 安全弁: 取得件数に上限を設け、巨大走査でも有界時間で返す。
            let maxEntries = 5000
            var collected: [OSLogEntryLog] = []
            for case let log as OSLogEntryLog in try store.getEntries(with: [], at: position, matching: compoundPredicate) {
                guard log.level.rawValue >= level.rawValue else { continue }
                collected.append(log)
                if collected.count >= maxEntries { break }
            }
            let logEntries = collected

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
            logger.warning("Failed to fetch log entries: \(error.localizedDescription)")
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
