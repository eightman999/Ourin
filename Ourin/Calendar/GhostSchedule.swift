import Foundation

/// ゴースト用の予定表（UKADOC 2.8.91: `\![execute,schedule-add/delete/get]`）。
///
/// ユーザーの予定・スケジュールセンサの予定とは別の iCalendar ファイル
/// （`calendar/ghost/schedule.ics`）に保存し、すべてのゴーストで共有する。
final class GhostScheduleStore {
    static let shared = GhostScheduleStore()

    private let injectedURL: URL?
    private let lock = NSRecursiveLock()
    private let calendar: Calendar
    private var cache: (stamp: String, calendar: ICalCalendar)?

    init(fileURL: URL? = nil, calendar: Calendar = ICalendarCodec.makeCalendar()) {
        self.injectedURL = fileURL
        self.calendar = calendar
    }

    func fileURL() throws -> URL {
        if let injectedURL { return injectedURL }
        return try OurinPaths.subdirectory("calendar")
            .appendingPathComponent("ghost", isDirectory: true)
            .appendingPathComponent("schedule.ics", isDirectory: false)
    }

    /// ファイルの更新を検知するための印（更新日時とサイズ）。ファイルが無ければ空。
    func revision() -> String {
        guard let url = try? fileURL(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "" }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return "\(modified)|\(size)"
    }

    func load() throws -> ICalCalendar {
        lock.lock(); defer { lock.unlock() }
        let stamp = revision()
        if let cache, cache.stamp == stamp, !stamp.isEmpty { return cache.calendar }
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ICalCalendar(name: "Ourin Ghost Schedule")
        }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var parsed = ICalendarCodec.parse(text, calendar: calendar)
        if parsed.name.isEmpty { parsed.name = "Ourin Ghost Schedule" }
        cache = (stamp, parsed)
        return parsed
    }

    func save(_ data: ICalCalendar) throws {
        lock.lock(); defer { lock.unlock() }
        let url = try fileURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = ICalendarCodec.serialize(data, calendar: calendar)
        try Data(text.utf8).write(to: url, options: [.atomic])
        cache = nil
    }

    /// 同じ UID があれば置き換え、無ければ追加する。
    func add(_ event: ICalEvent) throws {
        lock.lock(); defer { lock.unlock() }
        var current = try load()
        if let index = current.events.firstIndex(where: { $0.uid == event.uid }) {
            current.events[index] = event
        } else {
            current.events.append(event)
        }
        try save(current)
    }

    /// 削除できたら true、該当する予定が無ければ false。
    func delete(uid: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        var current = try load()
        let before = current.events.count
        current.events.removeAll { $0.uid == uid }
        guard current.events.count != before else { return false }
        try save(current)
        return true
    }
}

/// `\![execute,schedule-add/delete/get]` の実行と、結果イベントの組み立て。
enum GhostScheduleCommand {
    struct Outcome: Equatable {
        var eventName: String
        var references: [String: String]
    }

    enum Operation: String {
        case add, delete
    }

    static let completeEvent = "OnExecuteScheduleComplete"
    static let failureEvent = "OnExecuteScheduleFailure"
    static let getCompleteEvent = "OnExecuteScheduleGetComplete"

    /// - Parameter arguments: `schedule-add` などの後ろの引数（`--summary=...` など）。
    static func run(
        subcommand: String,
        arguments: [String],
        isExternalScript: Bool,
        store: GhostScheduleStore,
        now: Date = Date(),
        calendar: Calendar = ICalendarCodec.makeCalendar()
    ) -> Outcome {
        switch subcommand {
        case "schedule-add":
            return add(arguments: arguments, isExternal: isExternalScript, store: store, calendar: calendar)
        case "schedule-delete":
            return delete(arguments: arguments, isExternal: isExternalScript, store: store)
        default:
            return get(arguments: arguments, store: store, now: now, calendar: calendar)
        }
    }

    // MARK: - schedule-add

    private static func add(arguments: [String], isExternal: Bool, store: GhostScheduleStore, calendar: Calendar) -> Outcome {
        let options = parseOptions(arguments)
        let eventID = options.values["event"] ?? ""
        func fail(_ reason: String, uid: String = "") -> Outcome {
            failure(.add, reason: reason, uid: uid, eventID: eventID)
        }
        let givenUID = options.values["uid"] ?? ""
        if isExternal { return fail("notauthorized", uid: givenUID) }

        guard let summary = options.values["summary"], !summary.isEmpty,
              let startText = options.values["start"],
              let start = parseSchedulePoint(startText, calendar: calendar) else {
            return fail("invalid", uid: givenUID)
        }
        if !givenUID.isEmpty, !isValidUID(givenUID) { return fail("invalid", uid: givenUID) }
        var end: (date: Date, allDay: Bool)?
        if let endText = options.values["end"] {
            guard let parsed = parseSchedulePoint(endText, calendar: calendar), parsed.allDay == start.allDay else {
                return fail("invalid", uid: givenUID)
            }
            end = parsed
        }
        if let status = options.values["status"], !status.isEmpty,
           !["CONFIRMED", "TENTATIVE", "CANCELLED"].contains(status.uppercased()) {
            return fail("invalid", uid: givenUID)
        }
        var notify: Int?
        if let notifyText = options.values["notify"], !notifyText.isEmpty {
            guard let minutes = Int(notifyText), minutes >= 0 else { return fail("invalid", uid: givenUID) }
            notify = minutes
        }
        let rrule = options.values["rrule"] ?? ""
        if !rrule.isEmpty, ICalRecurrenceRule(rrule, calendar: calendar) == nil { return fail("invalid", uid: givenUID) }

        let uid = givenUID.isEmpty ? "ourin-\(UUID().uuidString.lowercased())" : givenUID
        var event = ICalEvent(start: start.date)
        event.uid = uid
        event.summary = summary
        event.description = options.values["description"] ?? ""
        event.location = options.values["location"] ?? ""
        event.url = options.values["url"] ?? ""
        event.categories = options.values["categories"] ?? ""
        event.status = (options.values["status"] ?? "").uppercased()
        event.allDay = start.allDay
        event.rrule = rrule
        event.type = options.values["type"] ?? ""
        event.notifyMinutes = notify
        event.script = options.values["script"] ?? ""
        // 日付だけの --end は最終日（含む）として扱う。終了が開始より前なら無効。
        if let end {
            guard end.date >= start.date else { return fail("invalid", uid: givenUID) }
            event.end = end.date
        }
        event.exdates = (options.values["exdate"] ?? "").split(separator: ",").compactMap {
            ICalendarCodec.parseDate(("EXDATE", ["VALUE": "DATE"], String($0).filter { $0.isNumber }), calendar: calendar)
                .map { calendar.startOfDay(for: $0.date) }
        }
        do {
            try store.add(event)
        } catch {
            // 保存に失敗した場合の扱いは UKADOC の "save"。
            return fail("save", uid: uid)
        }
        return Outcome(
            eventName: completeName(eventID),
            references: ["Reference0": Operation.add.rawValue, "Reference1": uid]
        )
    }

    // MARK: - schedule-delete

    private static func delete(arguments: [String], isExternal: Bool, store: GhostScheduleStore) -> Outcome {
        let options = parseOptions(arguments)
        let eventID = options.values["event"] ?? ""
        let uid = options.positionals.first ?? ""
        if isExternal { return failure(.delete, reason: "notauthorized", uid: uid, eventID: eventID) }
        guard !uid.isEmpty else { return failure(.delete, reason: "invalid", uid: uid, eventID: eventID) }
        do {
            guard try store.delete(uid: uid) else {
                return failure(.delete, reason: "notfound", uid: uid, eventID: eventID)
            }
        } catch {
            return failure(.delete, reason: "save", uid: uid, eventID: eventID)
        }
        return Outcome(
            eventName: completeName(eventID),
            references: ["Reference0": Operation.delete.rawValue, "Reference1": uid]
        )
    }

    // MARK: - schedule-get

    private static func get(arguments: [String], store: GhostScheduleStore, now: Date, calendar: Calendar) -> Outcome {
        let options = parseOptions(arguments)
        let query = ICalQuery(options: arguments, calendar: calendar)
        let loaded = (try? store.load()) ?? ICalCalendar(name: "Ourin Ghost Schedule")
        let selection = ICalendarQuerying.select(events: loaded.events, query: query, today: now, calendar: calendar)
        let eventID = options.values["event"] ?? ""
        return Outcome(
            eventName: eventID.hasPrefix("On") ? eventID : getCompleteEvent,
            references: ICalendarReferences.complete(calendarInfo: loaded, selection: selection, query: query, calendar: calendar)
        )
    }

    // MARK: - 補助

    private static func completeName(_ eventID: String) -> String {
        eventID.hasPrefix("On") ? eventID : completeEvent
    }

    private static func failure(_ operation: Operation, reason: String, uid: String, eventID: String) -> Outcome {
        Outcome(
            eventName: eventID.hasPrefix("On") ? eventID + "Failure" : failureEvent,
            references: ["Reference0": operation.rawValue, "Reference1": reason, "Reference2": uid]
        )
    }

    /// UID は空白を含まない半角英数記号のみ。
    static func isValidUID(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7f }
    }

    struct ParsedOptions {
        var values: [String: String] = [:]
        var positionals: [String] = []
    }

    static func parseOptions(_ arguments: [String]) -> ParsedOptions {
        var parsed = ParsedOptions()
        for argument in arguments {
            let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("--") else {
                if !trimmed.isEmpty { parsed.positionals.append(trimmed) }
                continue
            }
            let body = trimmed.dropFirst(2)
            guard let eq = body.firstIndex(of: "=") else { continue }
            parsed.values[String(body[..<eq]).lowercased()] = String(body[body.index(after: eq)...])
        }
        return parsed
    }

    /// `yyyymmdd`（終日）/ `yyyymmddThhmm` / `yyyymmddThhmmss`（ローカル時刻）。`-` と `:` は無視する。
    static func parseSchedulePoint(_ text: String, calendar: Calendar) -> (date: Date, allDay: Bool)? {
        let cleaned = text.filter { $0 != "-" && $0 != ":" && !$0.isWhitespace }
        if cleaned.count == 8, cleaned.allSatisfy(\.isNumber) {
            return ICalendarCodec.parseDate(("DTSTART", ["VALUE": "DATE"], cleaned), calendar: calendar)
        }
        guard cleaned.contains("T") else { return nil }
        let parsed = ICalendarCodec.parseDate(("DTSTART", [:], cleaned), calendar: calendar)
        // 範囲外の月日・時分（13月など）は Calendar が補正してしまうため、往復して検証する。
        if let parsed, ICalendarCodec.formatLocal(parsed.date, calendar: calendar).hasPrefix(String(cleaned.prefix(13))) {
            return parsed
        }
        return nil
    }
}

/// ゴースト用予定表の「今日の予定」を、カレンダーの予定として扱う変換。
enum GhostScheduleToday {
    /// 今日（`day` を含む日）に掛かるゴースト用予定を、カレンダーの予定とリード分数へ変換する。
    static func schedules(
        in store: GhostScheduleStore,
        on day: Date,
        calendar: Calendar = ICalendarCodec.makeCalendar()
    ) -> [(schedule: CalendarSchedule, leadMinutes: Int?, uid: String)] {
        guard let loaded = try? store.load() else { return [] }
        let dayStart = calendar.startOfDay(for: day)
        let query = ICalQuery(from: dayStart, to: dayStart, expandDays: 0, limit: 0)
        let selection = ICalendarQuerying.select(events: loaded.events, query: query, today: dayStart, calendar: calendar)
        return selection.occurrences.map { occurrence in
            let event = occurrence.event
            let startParts = calendar.dateComponents([.hour, .minute], from: event.start)
            let endParts = event.end.map { calendar.dateComponents([.hour, .minute], from: $0) }
            // 今日がその回の開始日のときだけ時刻を付ける。複数日にわたる予定の途中の日は時刻なしにする。
            let startsToday = ICalendarRecurrence.occurrenceDays(of: event, through: dayStart, calendar: calendar).contains(dayStart)
            let timed = !event.allDay && startsToday
            let schedule = CalendarSchedule(
                id: stableID(uid: event.uid, day: dayStart, calendar: calendar),
                type: event.type.isEmpty ? "event" : event.type,
                year: calendar.component(.year, from: dayStart),
                month: calendar.component(.month, from: dayStart),
                day: calendar.component(.day, from: dayStart),
                startHour: timed ? startParts.hour : nil,
                startMinute: timed ? startParts.minute : nil,
                endHour: timed ? endParts?.hour : nil,
                endMinute: timed ? endParts?.minute : nil,
                caption: event.summary,
                subtitle: event.description,
                script: event.script
            )
            return (schedule, event.notifyMinutes, event.uid)
        }
    }

    /// UID と日付から決まる ID（同じ予定・同じ日なら常に同じ値）。
    static func stableID(uid: String, day: Date, calendar: Calendar) -> UUID {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(uid)|\(ICalendarCodec.formatDate(day, calendar: calendar))".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 { bytes[index] = UInt8((hash >> (UInt64(index) * 8)) & 0xff) }
        var second: UInt64 = hash &* 0x9e3779b97f4a7c15
        for index in 8..<16 {
            bytes[index] = UInt8(second & 0xff)
            second >>= 8
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

// MARK: - GhostManager

extension GhostManager {
    /// \![execute,schedule-add/schedule-delete/schedule-get,...]
    /// 結果は OnExecuteScheduleComplete / Failure / GetComplete（`--event=On...` で名前を置き換え）で通知する。
    func executeGhostSchedule(subcommand: String, arguments: [String], isExternal: Bool) {
        let outcome = GhostScheduleCommand.run(
            subcommand: subcommand,
            arguments: arguments,
            isExternalScript: isExternal,
            store: GhostScheduleStore.shared
        )
        if let id = EventID(rawValue: outcome.eventName) {
            EventBridge.shared.notify(id, params: outcome.references)
        } else {
            EventBridge.shared.notifyCustom(outcome.eventName, params: outcome.references)
        }
    }
}
