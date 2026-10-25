import Foundation

/// 日時の整形と計算。日時は内部では UTC のエポック秒で扱う。
struct InternalTimeModule: InternalSaoriModule {
    let name = "internal_time"

    /// UTC で扱える範囲（0001-01-01T00:00:00Z 〜 9999-12-31T23:59:59Z）。
    static let minimumEpoch: Int64 = -62_135_596_800
    static let maximumEpoch: Int64 = 253_402_300_799
    /// ISO 8601・HTTP の日付の文字列で書ける最小の年。
    static let minimumStringYear = 1601

    var functions: [InternalSaoriFunction] {
        [
            // 日時を --tz= のゾーンの日時として整形する。
            InternalSaoriFunction("Format", required: 1, total: 2, options: ["tz"]) { call, _ in
                let zone = try Self.timeZone(call.option("tz"))
                let epoch = try Self.parseDateTime(call.positionals[0], zone: zone)
                let format = call.positionals.count > 1 ? call.positionals[1] : ""
                return InternalSaoriResult(try Self.format(epoch: epoch, format: format.isEmpty ? "iso8601" : format, zone: zone))
            },
            // 日時に量を足した日時を、エポック秒で返す。
            InternalSaoriFunction("Add", positionals: 3, options: ["tz"]) { call, _ in
                let zone = try Self.timeZone(call.option("tz"))
                let epoch = try Self.parseDateTime(call.positionals[0], zone: zone)
                guard let amount = Int(call.positionals[1].trimmingCharacters(in: .whitespaces)) else { throw InternalSaoriError.invalidParameter }
                return InternalSaoriResult(String(try Self.add(epoch: epoch, amount: amount, unit: call.positionals[2], zone: zone)))
            },
            // 日時2 − 日時1 を、単位で数えた整数で返す（端数は 0 の方向へ切り捨て）。
            InternalSaoriFunction("Diff", positionals: 3, options: ["tz"]) { call, _ in
                let zone = try Self.timeZone(call.option("tz"))
                let first = try Self.parseDateTime(call.positionals[0], zone: zone)
                let second = try Self.parseDateTime(call.positionals[1], zone: zone)
                return InternalSaoriResult(String(try Self.diff(from: first, to: second, unit: call.positionals[2], zone: zone)))
            }
        ]
    }

    // MARK: - ゾーン

    /// `--tz=`: local（既定）/ UTC / Z / +09:00・+0900・+09 / IANA のゾーン名。
    static func timeZone(_ text: String?) throws -> TimeZone {
        guard let text, !text.isEmpty else { return .current }
        let lowered = text.lowercased()
        if lowered == "local" { return .current }
        if lowered == "utc" || lowered == "z" { return TimeZone(secondsFromGMT: 0)! }
        if let offset = parseOffset(text) {
            guard abs(offset) <= 18 * 3600, let zone = TimeZone(secondsFromGMT: offset) else { throw InternalSaoriError.invalidParameter }
            return zone
        }
        // IANA の名前は大文字小文字を区別しない。
        if let identifier = TimeZone.knownTimeZoneIdentifiers.first(where: { $0.lowercased() == lowered }),
           let zone = TimeZone(identifier: identifier) {
            return zone
        }
        // OS が持っていない名前は、UTC として扱わずに失敗させる。
        throw InternalSaoriError.invalidParameter
    }

    /// `+09:00` / `+0900` / `+09` / `-05:30` → 秒。
    static func parseOffset(_ text: String) -> Int? {
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let digits = text.dropFirst().replacingOccurrences(of: ":", with: "")
        guard digits.allSatisfy(\.isNumber), digits.count == 2 || digits.count == 4 else { return nil }
        let hours = Int(digits.prefix(2)) ?? 0
        let minutes = digits.count == 4 ? Int(digits.suffix(2)) ?? 0 : 0
        guard hours < 24, minutes < 60 else { return nil }
        return (sign == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
    }

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    // MARK: - 日時の引数

    /// 整数（エポック秒）/ now / ISO 8601 / HTTP の日付。どれとしても読めなければ invalid parameter、範囲の外は out of range。
    static func parseDateTime(_ raw: String, zone: TimeZone, now: Date = Date()) throws -> Int64 {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { throw InternalSaoriError.invalidParameter }
        if text.lowercased() == "now" { return try checked(Int64(now.timeIntervalSince1970.rounded(.down))) }
        if text.range(of: #"^-?\d+$"#, options: .regularExpression) != nil {
            guard let value = Int64(text) else { throw InternalSaoriError.outOfRange }
            return try checked(value)
        }
        if let epoch = try parseISO8601(text, zone: zone) { return try checked(epoch) }
        if let epoch = try parseHTTPDate(text) { return try checked(epoch) }
        throw InternalSaoriError.invalidParameter
    }

    private static func checked(_ epoch: Int64) throws -> Int64 {
        guard epoch >= minimumEpoch, epoch <= maximumEpoch else { throw InternalSaoriError.outOfRange }
        return epoch
    }

    private static let isoPatterns: [String] = [
        // 2026-10-11 / 2026-10-11T21:00 / 2026-10-11 21:00:00.123 +09:00
        #"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d+)?)?)?\s*(Z|z|[+-]\d{2}(?::?\d{2})?)?$"#,
        // 20261011T210000Z
        #"^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(?:(\d{2})(?:[.,]\d+)?)?(Z|z|[+-]\d{2}(?::?\d{2})?)?$"#
    ]

    private static func parseISO8601(_ text: String, zone: TimeZone) throws -> Int64? {
        for pattern in isoPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            func group(_ index: Int) -> String? {
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return String(text[range])
            }
            guard let year = Int(group(1) ?? ""), let month = Int(group(2) ?? ""), let day = Int(group(3) ?? "") else { return nil }
            let hour = Int(group(4) ?? "0") ?? 0
            let minute = Int(group(5) ?? "0") ?? 0
            let second = Int(group(6) ?? "0") ?? 0
            // 書けるのは 1601 年以降。範囲外の月日・時刻（2 月 30 日など）も不正。
            guard year >= minimumStringYear, (1...12).contains(month), (1...31).contains(day),
                  (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
                throw InternalSaoriError.invalidParameter
            }
            var effective = zone
            if let zoneText = group(7), !zoneText.isEmpty {
                if zoneText.lowercased() == "z" {
                    effective = TimeZone(secondsFromGMT: 0)!
                } else if let offset = parseOffset(zoneText), abs(offset) <= 18 * 3600, let offsetZone = TimeZone(secondsFromGMT: offset) {
                    effective = offsetZone
                } else {
                    throw InternalSaoriError.invalidParameter
                }
            }
            let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            let cal = calendar(effective)
            // Calendar は 2 月 30 日などを補正してしまうので、読み戻して一致しなければ存在しない日付。
            guard let date = cal.date(from: components) else { throw InternalSaoriError.invalidParameter }
            let back = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            guard back.year == year, back.month == month, back.day == day, back.hour == hour, back.minute == minute, back.second == second else {
                throw InternalSaoriError.invalidParameter
            }
            return Int64(date.timeIntervalSince1970.rounded(.down))
        }
        return nil
    }

    /// `Sun, 11 Oct 2026 12:00:00 GMT`。
    private static func parseHTTPDate(_ text: String) throws -> Int64? {
        let regex = try? NSRegularExpression(pattern: #"^[A-Za-z]{3}, (\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) (?:GMT|UTC|Z)$"#)
        guard let match = regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        func group(_ index: Int) -> String {
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let month = months.firstIndex(of: group(2).lowercased()).map({ $0 + 1 }),
              let day = Int(group(1)), let year = Int(group(3)),
              let hour = Int(group(4)), let minute = Int(group(5)), let second = Int(group(6)),
              year >= minimumStringYear, (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            throw InternalSaoriError.invalidParameter
        }
        let cal = calendar(TimeZone(secondsFromGMT: 0)!)
        guard let date = cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)),
              cal.component(.day, from: date) == day, cal.component(.month, from: date) == month else {
            throw InternalSaoriError.invalidParameter
        }
        return Int64(date.timeIntervalSince1970.rounded(.down))
    }

    // MARK: - Format

    private static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                                     "September", "October", "November", "December"]

    /// 書式は iso8601 / rfc3339 / http / epoch / epochms、または % を使った書式。曜日・月名は英語で固定。
    static func format(epoch: Int64, format: String, zone: TimeZone) throws -> String {
        switch format.lowercased() {
        case "epoch": return String(epoch)
        case "epochms": return String(epoch * 1000)
        case "http": return try render("%a, %d %b %Y %H:%M:%S GMT", epoch: epoch, zone: TimeZone(secondsFromGMT: 0)!)
        case "iso8601", "rfc3339":
            let offset = zone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(epoch)))
            let suffix = offset == 0 ? "Z" : try render("%:z", epoch: epoch, zone: zone)
            return try render("%Y-%m-%dT%H:%M:%S", epoch: epoch, zone: zone) + suffix
        default:
            guard format.contains("%") else { throw InternalSaoriError.invalidParameter }
            return try render(format, epoch: epoch, zone: zone)
        }
    }

    private static func render(_ format: String, epoch: Int64, zone: TimeZone) throws -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let cal = calendar(zone)
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        let offset = zone.secondsFromGMT(for: date)
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        func offsetText(colon: Bool) -> String {
            let sign = offset < 0 ? "-" : "+"
            let minutes = abs(offset) / 60
            return String(format: "%@%02d%@%02d", sign, minutes / 60, colon ? ":" : "", minutes % 60)
        }
        var output = ""
        var iterator = format.makeIterator()
        while let character = iterator.next() {
            guard character == "%" else { output.append(character); continue }
            guard let code = iterator.next() else { throw InternalSaoriError.invalidParameter }
            switch code {
            case "Y": output += String(format: "%04d", c.year ?? 0)
            case "y": output += two((c.year ?? 0) % 100)
            case "m": output += two(c.month)
            case "d": output += two(c.day)
            case "H": output += two(c.hour)
            case "M": output += two(c.minute)
            case "S": output += two(c.second)
            case "j":
                let day = cal.ordinality(of: .day, in: .year, for: date) ?? 1
                output += String(format: "%03d", day)
            case "u": output += String(((c.weekday ?? 1) + 5) % 7 + 1) // 月=1〜日=7
            case "w": output += String((c.weekday ?? 1) - 1) // 日=0〜土=6
            case "a": output += String(weekdayNames[(c.weekday ?? 1) - 1].prefix(3))
            case "A": output += weekdayNames[(c.weekday ?? 1) - 1]
            case "b": output += String(monthNames[(c.month ?? 1) - 1].prefix(3))
            case "B": output += monthNames[(c.month ?? 1) - 1]
            case "z": output += offsetText(colon: false)
            case ":":
                guard iterator.next() == "z" else { throw InternalSaoriError.invalidParameter }
                output += offsetText(colon: true)
            case "s": output += String(epoch)
            case "%": output += "%"
            default: throw InternalSaoriError.invalidParameter
            }
        }
        return output
    }

    // MARK: - Add / Diff

    private enum Unit {
        case second, minute, hour, day, week, month, year

        init(_ text: String) throws {
            var name = text.lowercased()
            if name.hasSuffix("s") { name.removeLast() }
            switch name {
            case "second": self = .second
            case "minute": self = .minute
            case "hour": self = .hour
            case "day": self = .day
            case "week": self = .week
            case "month": self = .month
            case "year": self = .year
            default: throw InternalSaoriError.invalidParameter
            }
        }
    }

    /// second / minute / hour は経過時間で、day 以上は --tz= のゾーンの暦で足す（月末は丸める）。
    static func add(epoch: Int64, amount: Int, unit: String, zone: TimeZone) throws -> Int64 {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let cal = calendar(zone)
        let result: Date?
        switch try Unit(unit) {
        case .second: result = date.addingTimeInterval(TimeInterval(amount))
        case .minute: result = date.addingTimeInterval(TimeInterval(amount) * 60)
        case .hour: result = date.addingTimeInterval(TimeInterval(amount) * 3600)
        case .day: result = cal.date(byAdding: .day, value: amount, to: date)
        case .week: result = cal.date(byAdding: .day, value: amount.multipliedReportingOverflow(by: 7).partialValue, to: date)
        case .month: result = cal.date(byAdding: .month, value: amount, to: date)
        case .year: result = cal.date(byAdding: .year, value: amount, to: date)
        }
        guard let result else { throw InternalSaoriError.outOfRange }
        let value = Int64(result.timeIntervalSince1970.rounded(.down))
        return try checked(value)
    }

    static func diff(from first: Int64, to second: Int64, unit: String, zone: TimeZone) throws -> Int64 {
        let from = Date(timeIntervalSince1970: TimeInterval(first))
        let to = Date(timeIntervalSince1970: TimeInterval(second))
        let cal = calendar(zone)
        switch try Unit(unit) {
        case .second: return second - first
        case .minute: return (second - first) / 60
        case .hour: return (second - first) / 3600
        case .day: return Int64(cal.dateComponents([.day], from: from, to: to).day ?? 0)
        case .week: return Int64((cal.dateComponents([.day], from: from, to: to).day ?? 0) / 7)
        case .month: return Int64(cal.dateComponents([.month], from: from, to: to).month ?? 0)
        case .year: return Int64(cal.dateComponents([.year], from: from, to: to).year ?? 0)
        }
    }
}
