import Foundation

/// RRULE（UKADOC: FREQ・INTERVAL・COUNT・UNTIL・BYDAY・BYMONTHDAY・BYMONTH）。
struct ICalRecurrenceRule: Equatable {
    enum Frequency: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }
    /// weekday は Calendar と同じ 1=日曜 … 7=土曜。ordinal は 1MO（第1月曜）や -1FR（最終金曜）。
    struct DayRule: Equatable { var ordinal: Int?; var weekday: Int }

    var frequency: Frequency
    var interval = 1
    var count: Int?
    var untilDay: Date?
    var byDay: [DayRule] = []
    var byMonthDay: [Int] = []
    var byMonth: [Int] = []
    /// 週の開始（WKST）。既定は月曜。
    var weekStart = 2

    private static let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    init?(_ text: String, calendar: Calendar = ICalendarCodec.makeCalendar()) {
        var values: [String: String] = [:]
        for part in text.split(separator: ";") {
            guard let eq = part.firstIndex(of: "=") else { continue }
            values[String(part[..<eq]).uppercased()] = String(part[part.index(after: eq)...])
        }
        guard let rawFreq = values["FREQ"], let frequency = Frequency(rawValue: rawFreq.uppercased()) else { return nil }
        self.frequency = frequency
        if let interval = values["INTERVAL"].flatMap(Int.init), interval >= 1 { self.interval = interval }
        count = values["COUNT"].flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
        if let until = values["UNTIL"] {
            let parsed = ICalendarCodec.parseDate(("UNTIL", [:], until), calendar: calendar)
            untilDay = parsed.map { calendar.startOfDay(for: $0.date) }
        }
        if let days = values["BYDAY"] {
            byDay = days.split(separator: ",").compactMap { token in
                let text = token.uppercased()
                guard text.count >= 2, let weekday = Self.weekdays[String(text.suffix(2))] else { return nil }
                let prefix = String(text.dropLast(2))
                return DayRule(ordinal: prefix.isEmpty ? nil : Int(prefix), weekday: weekday)
            }
        }
        byMonthDay = values["BYMONTHDAY"]?.split(separator: ",").compactMap { Int($0) } ?? []
        byMonth = values["BYMONTH"]?.split(separator: ",").compactMap { Int($0) } ?? []
        if let wkst = values["WKST"]?.uppercased(), let day = Self.weekdays[wkst] { weekStart = day }
    }
}

enum ICalendarRecurrence {
    /// 暴走防止（繰り返し 1 件で調べる周期数の上限）。
    static let maxPeriods = 20_000

    /// 各回の開始日（0 時）を昇順で返す。`through` を超える日は含めない。EXDATE は除く。
    static func occurrenceDays(of event: ICalEvent, through limit: Date, calendar: Calendar) -> [Date] {
        let first = calendar.startOfDay(for: event.start)
        let limitDay = calendar.startOfDay(for: limit)
        let excluded = Set(event.exdates.map { calendar.startOfDay(for: $0) })
        guard let rule = ICalRecurrenceRule(event.rrule, calendar: calendar) else {
            return first <= limitDay && !excluded.contains(first) ? [first] : []
        }

        var days: [Date] = []
        var produced = 0
        var period = 0
        while period < maxPeriods {
            let candidates = candidateDays(period: period, rule: rule, start: first, calendar: calendar)
            guard let earliest = candidates.first ?? periodAnchor(period: period, rule: rule, start: first, calendar: calendar) else { break }
            if earliest > limitDay { break }
            for day in candidates where day >= first {
                if let until = rule.untilDay, day > until { return days }
                if day > limitDay { return days }
                produced += 1
                if !excluded.contains(day) { days.append(day) }
                if let count = rule.count, produced >= count { return days }
            }
            period += 1
        }
        return days
    }

    /// 周期の先頭日（候補が空でも終了判定に使う）。
    private static func periodAnchor(period: Int, rule: ICalRecurrenceRule, start: Date, calendar: Calendar) -> Date? {
        let step = period * rule.interval
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: step, to: start)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: step, to: weekStartDay(of: start, rule: rule, calendar: calendar))
        case .monthly:
            return calendar.date(byAdding: .month, value: step, to: monthStart(of: start, calendar: calendar))
        case .yearly:
            return calendar.date(byAdding: .year, value: step, to: yearStart(of: start, calendar: calendar))
        }
    }

    private static func candidateDays(period: Int, rule: ICalRecurrenceRule, start: Date, calendar: Calendar) -> [Date] {
        guard let anchor = periodAnchor(period: period, rule: rule, start: start, calendar: calendar) else { return [] }
        let startComponents = calendar.dateComponents([.year, .month, .day, .weekday], from: start)
        func monthOK(_ day: Date) -> Bool {
            rule.byMonth.isEmpty || rule.byMonth.contains(calendar.component(.month, from: day))
        }
        switch rule.frequency {
        case .daily:
            let weekday = calendar.component(.weekday, from: anchor)
            let dayOfMonth = calendar.component(.day, from: anchor)
            let monthLength = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 31
            let byDayOK = rule.byDay.isEmpty || rule.byDay.contains { $0.weekday == weekday }
            let monthDayOK = rule.byMonthDay.isEmpty || rule.byMonthDay.contains {
                $0 > 0 ? $0 == dayOfMonth : monthLength + $0 + 1 == dayOfMonth
            }
            return monthOK(anchor) && byDayOK && monthDayOK ? [anchor] : []
        case .weekly:
            let weekdays = rule.byDay.isEmpty ? [startComponents.weekday ?? 1] : rule.byDay.map(\.weekday)
            return (0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: anchor)
            }.filter { weekdays.contains(calendar.component(.weekday, from: $0)) && monthOK($0) }
        case .monthly:
            guard monthOK(anchor) else { return [] }
            return monthDays(in: anchor, rule: rule, startComponents: startComponents, calendar: calendar)
        case .yearly:
            let months = rule.byMonth.isEmpty ? [startComponents.month ?? 1] : rule.byMonth
            return months.sorted().flatMap { month -> [Date] in
                guard let monthDate = calendar.date(byAdding: .month, value: month - 1, to: anchor) else { return [] }
                return monthDays(in: monthDate, rule: rule, startComponents: startComponents, calendar: calendar)
            }
        }
    }

    /// 1 か月の中で、BYMONTHDAY / BYDAY（第N曜日）に合う日。どちらも無ければ開始日と同じ日。
    private static func monthDays(in monthDate: Date, rule: ICalRecurrenceRule, startComponents: DateComponents, calendar: Calendar) -> [Date] {
        let first = monthStart(of: monthDate, calendar: calendar)
        guard let length = calendar.range(of: .day, in: .month, for: first)?.count else { return [] }
        let all = (0..<length).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        var result: [Date] = []
        if !rule.byMonthDay.isEmpty {
            for value in rule.byMonthDay {
                let day = value > 0 ? value : length + value + 1
                if (1...length).contains(day) { result.append(all[day - 1]) }
            }
        }
        if !rule.byDay.isEmpty {
            for dayRule in rule.byDay {
                let matches = all.filter { calendar.component(.weekday, from: $0) == dayRule.weekday }
                if let ordinal = dayRule.ordinal {
                    let index = ordinal > 0 ? ordinal - 1 : matches.count + ordinal
                    if matches.indices.contains(index) { result.append(matches[index]) }
                } else {
                    result.append(contentsOf: matches)
                }
            }
        }
        if rule.byMonthDay.isEmpty && rule.byDay.isEmpty, let day = startComponents.day, day <= length {
            result.append(all[day - 1])
        }
        // BYMONTHDAY と BYDAY を両方指定した場合は両方に合う日だけ。
        if !rule.byMonthDay.isEmpty && !rule.byDay.isEmpty {
            let byMonthDay = Set(rule.byMonthDay.compactMap { value -> Date? in
                let day = value > 0 ? value : length + value + 1
                return (1...length).contains(day) ? all[day - 1] : nil
            })
            result = result.filter { byMonthDay.contains($0) }
        }
        return Array(Set(result)).sorted()
    }

    private static func weekStartDay(of day: Date, rule: ICalRecurrenceRule, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: day)
        let back = (weekday - rule.weekStart + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    private static func monthStart(of day: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
    }

    private static func yearStart(of day: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year], from: day)) ?? day
    }
}

/// iCal 絞り込みオプション（--from・--to・--expand・--limit）。
struct ICalQuery: Equatable {
    var from: Date?
    var to: Date?
    /// nil = --expand なし。値は展開する日数（日数を書かなければ 0）。
    var expandDays: Int?
    var limit: Int?
    /// 期間モードの最大日数。
    static let maxPeriodDays = 1830
    static let defaultLimit = 200
    static let defaultExpandDays = 30

    var isPeriodMode: Bool { from != nil || to != nil || expandDays != nil || limit != nil }

    init(from: Date? = nil, to: Date? = nil, expandDays: Int? = nil, limit: Int? = nil) {
        self.from = from; self.to = to; self.expandDays = expandDays; self.limit = limit
    }

    /// `--from=yyyymmdd`、`--to=yyyymmdd`、`--expand[=日数]`、`--limit=件数` を読む。
    init(options: [String], calendar: Calendar = ICalendarCodec.makeCalendar()) {
        for option in options {
            let trimmed = option.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("--") else { continue }
            let body = trimmed.dropFirst(2)
            let eq = body.firstIndex(of: "=")
            let key = String(body[..<(eq ?? body.endIndex)]).lowercased()
            let value = eq.map { String(body[body.index(after: $0)...]) } ?? ""
            switch key {
            case "from": from = Self.parseDay(value, calendar: calendar) ?? from
            case "to": to = Self.parseDay(value, calendar: calendar) ?? to
            case "expand": expandDays = Int(value).map { max(0, $0) } ?? 0
            case "limit": limit = Int(value).map { max(0, $0) }
            default: break
            }
        }
    }

    private static func parseDay(_ value: String, calendar: Calendar) -> Date? {
        ICalendarCodec.parseDate(("DATE", ["VALUE": "DATE"], value), calendar: calendar).map { $0.date }
    }
}

struct ICalOccurrence: Equatable {
    var event: ICalEvent
    /// 発生日（期間モードのみ）。
    var day: Date?
}

struct ICalSelection: Equatable {
    var occurrences: [ICalOccurrence]
    var totalEvents: Int
    var periodStart: Date?
    var periodEnd: Date?
}

enum ICalendarQuerying {
    static func select(
        events: [ICalEvent],
        query: ICalQuery,
        today: Date = Date(),
        calendar: Calendar = ICalendarCodec.makeCalendar()
    ) -> ICalSelection {
        guard query.isPeriodMode else {
            return ICalSelection(
                occurrences: events.map { ICalOccurrence(event: $0, day: nil) },
                totalEvents: events.count, periodStart: nil, periodEnd: nil
            )
        }
        let periodStart = calendar.startOfDay(for: query.from ?? today)
        var periodEnd: Date
        if let to = query.to {
            periodEnd = calendar.startOfDay(for: to)
        } else if let days = query.expandDays {
            let length = days > 0 ? days : ICalQuery.defaultExpandDays
            periodEnd = calendar.date(byAdding: .day, value: length - 1, to: periodStart) ?? periodStart
        } else {
            periodEnd = calendar.date(byAdding: .day, value: ICalQuery.maxPeriodDays - 1, to: periodStart) ?? periodStart
        }
        if let cap = calendar.date(byAdding: .day, value: ICalQuery.maxPeriodDays - 1, to: periodStart), periodEnd > cap {
            periodEnd = cap
        }
        guard periodEnd >= periodStart else {
            return ICalSelection(occurrences: [], totalEvents: events.count, periodStart: periodStart, periodEnd: periodEnd)
        }

        let expanding = query.expandDays != nil
        var found: [(event: ICalEvent, day: Date, order: Int)] = []
        for (order, event) in events.enumerated() {
            let spanDays = Self.spanDays(of: event, calendar: calendar)
            // 開始が期間より前でも、複数日にわたって期間に掛かる回を拾うため、期間の手前まで遡って展開する。
            let days = ICalendarRecurrence.occurrenceDays(of: event, through: periodEnd, calendar: calendar)
            var firstForEvent: Date?
            for startDay in days {
                let lastDay = calendar.date(byAdding: .day, value: spanDays - 1, to: startDay) ?? startDay
                guard lastDay >= periodStart, startDay <= periodEnd else { continue }
                let day = max(startDay, periodStart)
                if expanding {
                    found.append((event, day, order))
                } else if firstForEvent == nil {
                    firstForEvent = day
                }
            }
            if !expanding, let day = firstForEvent { found.append((event, day, order)) }
        }
        found.sort { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            if lhs.event.start != rhs.event.start {
                return timeOfDay(lhs.event.start, calendar: calendar) < timeOfDay(rhs.event.start, calendar: calendar)
            }
            return lhs.order < rhs.order
        }
        var limit = query.limit ?? ICalQuery.defaultLimit
        if limit == 0 { limit = Int.max }
        let limited = found.prefix(limit).map { ICalOccurrence(event: $0.event, day: $0.day) }
        return ICalSelection(occurrences: Array(limited), totalEvents: events.count, periodStart: periodStart, periodEnd: periodEnd)
    }

    /// 開始日から最終日までの日数（1 日の予定は 1）。
    static func spanDays(of event: ICalEvent, calendar: Calendar) -> Int {
        guard let end = event.end else { return 1 }
        let first = calendar.startOfDay(for: event.start)
        var last = calendar.startOfDay(for: end)
        // 時刻付きで 0 時ちょうどに終わる予定は、その日に掛からない。
        if !event.allDay, end == last, end > event.start {
            last = calendar.date(byAdding: .day, value: -1, to: last) ?? last
        }
        let days = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        return max(1, days + 1)
    }

    private static func timeOfDay(_ date: Date, calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// OnExecuteICalComplete / OnExecuteScheduleGetComplete の Reference を組み立てる。
enum ICalendarReferences {
    static let separator = "\u{1}"

    /// タイトル・説明などをさくらスクリプトとして解釈されないようにする（\→\\、%→\%、改行とタブ→半角空白）。
    static func escapeForScript(_ value: String) -> String {
        var out = ""
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case "%": out += "\\%"
            case "\n", "\r", "\t": out += " "
            default: out.append(ch)
            }
        }
        return out
    }

    static func dayString(_ date: Date?, calendar: Calendar) -> String {
        guard let date else { return "" }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0),\(c.month ?? 0),\(c.day ?? 0),,,"
    }

    static func dateTimeString(_ date: Date, allDay: Bool, calendar: Calendar) -> String {
        if allDay { return dayString(date, calendar: calendar) }
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return "\(c.year ?? 0),\(c.month ?? 0),\(c.day ?? 0),\(c.hour ?? 0),\(c.minute ?? 0),\(c.second ?? 0)"
    }

    /// 戻り値のキーは `Reference0`, `Reference1`, …。
    static func complete(
        calendarInfo: ICalCalendar,
        selection: ICalSelection,
        query: ICalQuery,
        calendar: Calendar = ICalendarCodec.makeCalendar()
    ) -> [String: String] {
        var refs: [String: String] = [:]
        refs["Reference0"] = [
            escapeForScript(calendarInfo.name),
            calendarInfo.timeZone,
            calendarInfo.calendarScale,
            String(selection.occurrences.count),
            String(selection.totalEvents),
            query.isPeriodMode ? dayString(selection.periodStart, calendar: calendar) : "",
            query.isPeriodMode ? dayString(selection.periodEnd, calendar: calendar) : ""
        ].joined(separator: separator)
        for (index, occurrence) in selection.occurrences.enumerated() {
            refs["Reference\(index + 1)"] = eventFields(occurrence, calendar: calendar).joined(separator: separator)
        }
        return refs
    }

    static func eventFields(_ occurrence: ICalOccurrence, calendar: Calendar) -> [String] {
        let event = occurrence.event
        let end: String
        if let eventEnd = event.end {
            end = dateTimeString(eventEnd, allDay: event.allDay, calendar: calendar)
        } else {
            end = dateTimeString(event.start, allDay: event.allDay, calendar: calendar)
        }
        return [
            event.uid,
            dateTimeString(event.start, allDay: event.allDay, calendar: calendar),
            end,
            escapeForScript(event.summary),
            escapeForScript(event.description),
            escapeForScript(event.location),
            escapeForScript(event.url),
            event.status,
            escapeForScript(event.categories),
            event.rrule,
            event.allDay ? "1" : "0",
            dayString(occurrence.day, calendar: calendar)
        ]
    }
}
