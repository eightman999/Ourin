import Foundation

/// iCalendar（RFC 5545）の VEVENT。UKADOC の ical-get / schedule-* が扱う項目だけを持つ。
///
/// 日時はローカルのカレンダーで扱う。`DTSTART:...Z`（UTC）や `TZID=` 付きは、読み込み時に
/// ローカルの日時へ換算する。終日予定は `allDay == true` で、`start` は当日の 0 時、
/// `end` は **最終日の 0 時**（DTEND の排他指定を 1 日戻した値）として保持する。
struct ICalEvent: Equatable {
    var uid: String = ""
    var summary: String = ""
    var description: String = ""
    var location: String = ""
    var url: String = ""
    var status: String = ""
    var categories: String = ""
    var start: Date
    /// 終了日時。nil なら開始日の 1 日だけ（終日）、または開始時刻だけの予定。
    var end: Date?
    var allDay: Bool = false
    /// RRULE の値部分の原文（無ければ空）。
    var rrule: String = ""
    /// 繰り返しから除外する日（その日の 0 時）。
    var exdates: [Date] = []
    /// Ourin 独自の拡張（X-OURIN-TYPE / X-OURIN-NOTIFY / X-OURIN-SCRIPT）。
    var type: String = ""
    var notifyMinutes: Int?
    var script: String = ""
}

struct ICalCalendar: Equatable {
    var name: String = ""
    var timeZone: String = ""
    var calendarScale: String = "GREGORIAN"
    var events: [ICalEvent] = []
}

enum ICalendarCodec {
    static func makeCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    // MARK: - 解析

    /// SUMMARY を持たない VEVENT（UKADOC: 無効として除外）は結果に含めない。
    static func parse(_ text: String, calendar: Calendar = makeCalendar()) -> ICalCalendar {
        var result = ICalCalendar()
        var current: [(name: String, params: [String: String], value: String)]?
        var depth = 0 // VEVENT 内の入れ子（VALARM など）

        for line in unfold(text) {
            guard let property = splitProperty(line) else { continue }
            let name = property.name.uppercased()
            if name == "BEGIN" {
                let kind = property.value.uppercased()
                if kind == "VEVENT", current == nil {
                    current = []
                    depth = 0
                } else if current != nil {
                    depth += 1
                }
                continue
            }
            if name == "END" {
                let kind = property.value.uppercased()
                if current != nil, depth > 0 {
                    depth -= 1
                } else if kind == "VEVENT", let properties = current {
                    if let event = makeEvent(properties, calendar: calendar) {
                        result.events.append(event)
                    }
                    current = nil
                }
                continue
            }
            if current != nil {
                if depth == 0 { current?.append((name, property.params, property.value)) }
                continue
            }
            switch name {
            case "X-WR-CALNAME": result.name = unescapeText(property.value)
            case "X-WR-TIMEZONE": result.timeZone = property.value
            case "CALSCALE": result.calendarScale = property.value
            default: break
            }
        }
        return result
    }

    /// 折り返し（CRLF + 空白/タブ）を解く。
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(raw.dropFirst())
            } else {
                lines.append(String(raw))
            }
        }
        return lines
    }

    static func splitProperty(_ line: String) -> (name: String, params: [String: String], value: String)? {
        // 値の中の ':' ではなく、引用符の外で最初の ':' を区切りとする。
        var inQuotes = false
        var colon: String.Index?
        for index in line.indices {
            let ch = line[index]
            if ch == "\"" { inQuotes.toggle() }
            if ch == ":" && !inQuotes { colon = index; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        var parts: [String] = []
        var buffer = ""
        inQuotes = false
        for ch in head {
            if ch == "\"" { inQuotes.toggle(); buffer.append(ch); continue }
            if ch == ";" && !inQuotes { parts.append(buffer); buffer = ""; continue }
            buffer.append(ch)
        }
        parts.append(buffer)
        guard let name = parts.first, !name.isEmpty else { return nil }
        var params: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = String(part[..<eq]).uppercased()
            let raw = String(part[part.index(after: eq)...])
            params[key] = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return (name, params, value)
    }

    static func unescapeText(_ value: String) -> String {
        var out = ""
        var iterator = value.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\", let next = iterator.next() else { out.append(ch); continue }
            switch next {
            case "n", "N": out.append("\n")
            case ",", ";", "\\": out.append(next)
            default: out.append(next)
            }
        }
        return out
    }

    static func escapeText(_ value: String) -> String {
        var out = ""
        for ch in value {
            switch ch {
            case "\\": out += "\\\\"
            case ";": out += "\\;"
            case ",": out += "\\,"
            case "\n": out += "\\n"
            case "\r": continue
            default: out.append(ch)
            }
        }
        return out
    }

    private static func makeEvent(
        _ properties: [(name: String, params: [String: String], value: String)],
        calendar: Calendar
    ) -> ICalEvent? {
        var event = ICalEvent(start: Date(timeIntervalSince1970: 0))
        var haveStart = false
        var haveSummary = false
        var dtEnd: (date: Date, allDay: Bool)?
        var duration: TimeInterval?
        for property in properties {
            switch property.name {
            case "UID": event.uid = property.value
            case "SUMMARY":
                event.summary = unescapeText(property.value)
                haveSummary = !event.summary.isEmpty
            case "DESCRIPTION": event.description = unescapeText(property.value)
            case "LOCATION": event.location = unescapeText(property.value)
            case "URL": event.url = property.value
            case "STATUS": event.status = property.value.uppercased()
            case "CATEGORIES":
                event.categories = event.categories.isEmpty ? unescapeText(property.value) : event.categories + "," + unescapeText(property.value)
            case "DTSTART":
                if let parsed = parseDate(property, calendar: calendar) {
                    event.start = parsed.date
                    event.allDay = parsed.allDay
                    haveStart = true
                }
            case "DTEND":
                dtEnd = parseDate(property, calendar: calendar)
            case "DURATION":
                duration = parseDuration(property.value)
            case "RRULE": event.rrule = property.value
            case "EXDATE":
                for piece in property.value.split(separator: ",") {
                    var p = property
                    p.value = String(piece)
                    if let parsed = parseDate(p, calendar: calendar) {
                        event.exdates.append(calendar.startOfDay(for: parsed.date))
                    }
                }
            case "X-OURIN-TYPE": event.type = unescapeText(property.value)
            case "X-OURIN-NOTIFY": event.notifyMinutes = Int(property.value)
            case "X-OURIN-SCRIPT": event.script = unescapeText(property.value)
            default: break
            }
        }
        guard haveStart, haveSummary else { return nil }

        if let dtEnd {
            if event.allDay {
                // DTEND の日付は排他指定。最終日はその前日（開始日より前にはならない）。
                let last = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: dtEnd.date)) ?? dtEnd.date
                event.end = max(last, calendar.startOfDay(for: event.start))
            } else {
                event.end = dtEnd.date
            }
        } else if let duration {
            if event.allDay {
                let days = max(1, Int((duration / 86_400).rounded(.up)))
                event.end = calendar.date(byAdding: .day, value: days - 1, to: calendar.startOfDay(for: event.start))
            } else {
                event.end = event.start.addingTimeInterval(duration)
            }
        }
        if event.allDay { event.start = calendar.startOfDay(for: event.start) }
        return event
    }

    /// `20261001`（終日）/ `20261001T100000`（ローカル）/ `...Z`（UTC）/ `TZID=...` を解釈する。
    static func parseDate(
        _ property: (name: String, params: [String: String], value: String),
        calendar: Calendar
    ) -> (date: Date, allDay: Bool)? {
        let value = property.value.trimmingCharacters(in: .whitespaces)
        let isDateOnly = property.params["VALUE"]?.uppercased() == "DATE" || (value.count == 8 && !value.contains("T"))
        let digits = value.filter { $0.isNumber || $0 == "T" || $0 == "Z" }
        var zone = calendar.timeZone
        if value.hasSuffix("Z") {
            zone = TimeZone(identifier: "UTC") ?? zone
        } else if let tzid = property.params["TZID"], let named = TimeZone(identifier: tzid) {
            zone = named
        }
        var parsing = calendar
        parsing.timeZone = zone

        if isDateOnly {
            guard digits.count >= 8, let year = Int(digits.prefix(4)),
                  let month = Int(digits.dropFirst(4).prefix(2)),
                  let day = Int(digits.dropFirst(6).prefix(2)) else { return nil }
            var local = calendar
            local.timeZone = calendar.timeZone
            guard let date = local.date(from: DateComponents(year: year, month: month, day: day)),
                  // Calendar は 13 月や 2/30 を黙って補正するため、読み戻して一致しなければ不正とする。
                  formatDate(date, calendar: local) == String(format: "%04d%02d%02d", year, month, day) else { return nil }
            return (date, true)
        }
        let parts = digits.replacingOccurrences(of: "Z", with: "").split(separator: "T")
        guard parts.count == 2, parts[0].count == 8, parts[1].count >= 4,
              let year = Int(parts[0].prefix(4)),
              let month = Int(parts[0].dropFirst(4).prefix(2)),
              let day = Int(parts[0].dropFirst(6).prefix(2)),
              let hour = Int(parts[1].prefix(2)),
              let minute = Int(parts[1].dropFirst(2).prefix(2)) else { return nil }
        let second = parts[1].count >= 6 ? (Int(parts[1].dropFirst(4).prefix(2)) ?? 0) : 0
        guard (0...23).contains(hour), (0...59).contains(minute), (0...60).contains(second),
              let date = parsing.date(from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute, second: second
              )),
              formatDate(date, calendar: parsing) == String(format: "%04d%02d%02d", year, month, day) else { return nil }
        return (date, false)
    }

    /// `P1D` / `PT1H30M` / `P1W` などの長さ（秒）。
    static func parseDuration(_ value: String) -> TimeInterval? {
        var text = value.trimmingCharacters(in: .whitespaces)
        var sign = 1.0
        if text.hasPrefix("-") { sign = -1; text.removeFirst() } else if text.hasPrefix("+") { text.removeFirst() }
        guard text.hasPrefix("P") else { return nil }
        text.removeFirst()
        var total = 0.0
        var number = ""
        var inTime = false
        for ch in text {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber { number.append(ch); continue }
            guard let amount = Double(number) else { return nil }
            number = ""
            switch ch {
            case "W": total += amount * 7 * 86_400
            case "D": total += amount * 86_400
            case "H" where inTime: total += amount * 3_600
            case "M" where inTime: total += amount * 60
            case "S" where inTime: total += amount
            default: return nil
            }
        }
        return sign * total
    }

    // MARK: - 書き出し

    /// VCALENDAR として書き出す（CRLF、75 オクテットで折り返し）。
    static func serialize(_ calendarData: ICalCalendar, calendar: Calendar = makeCalendar()) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Ourin//Ghost Schedule//JA", "CALSCALE:\(calendarData.calendarScale)"]
        if !calendarData.name.isEmpty { lines.append("X-WR-CALNAME:\(escapeText(calendarData.name))") }
        for event in calendarData.events {
            lines.append("BEGIN:VEVENT")
            lines.append("UID:\(event.uid)")
            lines.append("DTSTAMP:\(formatUTC(Date()))")
            if event.allDay {
                lines.append("DTSTART;VALUE=DATE:\(formatDate(event.start, calendar: calendar))")
                // 最終日の翌日を DTEND（排他）として書く。
                let last = calendar.startOfDay(for: event.end ?? event.start)
                if let exclusive = calendar.date(byAdding: .day, value: 1, to: last) {
                    lines.append("DTEND;VALUE=DATE:\(formatDate(exclusive, calendar: calendar))")
                }
            } else {
                lines.append("DTSTART:\(formatLocal(event.start, calendar: calendar))")
                if let end = event.end { lines.append("DTEND:\(formatLocal(end, calendar: calendar))") }
            }
            lines.append("SUMMARY:\(escapeText(event.summary))")
            if !event.description.isEmpty { lines.append("DESCRIPTION:\(escapeText(event.description))") }
            if !event.location.isEmpty { lines.append("LOCATION:\(escapeText(event.location))") }
            if !event.url.isEmpty { lines.append("URL:\(event.url)") }
            if !event.categories.isEmpty { lines.append("CATEGORIES:\(event.categories)") }
            if !event.status.isEmpty { lines.append("STATUS:\(event.status)") }
            if !event.rrule.isEmpty { lines.append("RRULE:\(event.rrule)") }
            for day in event.exdates { lines.append("EXDATE;VALUE=DATE:\(formatDate(day, calendar: calendar))") }
            if !event.type.isEmpty { lines.append("X-OURIN-TYPE:\(escapeText(event.type))") }
            if let minutes = event.notifyMinutes { lines.append("X-OURIN-NOTIFY:\(minutes)") }
            if !event.script.isEmpty { lines.append("X-OURIN-SCRIPT:\(escapeText(event.script))") }
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    private static func fold(_ line: String) -> String {
        var out = ""
        var octets = 0
        var limit = 75
        for ch in line {
            let size = String(ch).utf8.count
            if octets + size > limit {
                out += "\r\n "
                octets = 1
                limit = 75
            }
            out.append(ch)
            octets += size
        }
        return out
    }

    static func formatDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func formatLocal(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    private static func formatUTC(_ date: Date) -> String {
        var calendar = makeCalendar(timeZone: TimeZone(identifier: "UTC") ?? .current)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return formatLocal(date, calendar: calendar) + "Z"
    }
}
