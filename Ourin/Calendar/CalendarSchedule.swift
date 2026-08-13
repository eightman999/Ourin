import Foundation

/// SSP のカレンダーが扱う1件の予定。
///
/// スケジュールセンサーの SCHEDULE/1.0 レコードをそのまま保持できるよう、
/// 日付と時刻を整数フィールドで保存する。時刻が不要な終日予定では
/// `startHour`/`startMinute` が nil になる。
struct CalendarSchedule: Codable, Equatable, Identifiable {
    let id: UUID
    var type: String
    var year: Int
    var month: Int
    var day: Int
    var startHour: Int?
    var startMinute: Int?
    var endHour: Int?
    var endMinute: Int?
    var caption: String
    var subtitle: String
    var script: String

    init(
        id: UUID = UUID(),
        type: String = "event",
        year: Int,
        month: Int,
        day: Int,
        startHour: Int? = nil,
        startMinute: Int? = nil,
        endHour: Int? = nil,
        endMinute: Int? = nil,
        caption: String,
        subtitle: String = "",
        script: String = ""
    ) {
        self.id = id
        self.type = type.isEmpty ? "event" : type
        self.year = year
        self.month = month
        self.day = day
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.caption = caption
        self.subtitle = subtitle
        self.script = script
    }

    /// 開始時刻が存在し、カレンダー上で有効な日時なら返す。
    func startDate(calendar: Calendar = .current) -> Date? {
        guard let startHour, let startMinute else { return nil }
        guard (0...23).contains(startHour), (0...59).contains(startMinute) else { return nil }
        return calendar.date(from: DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day,
            hour: startHour,
            minute: startMinute
        ))
    }

    /// 終了時刻がそろっていて有効なら返す。
    func endDate(calendar: Calendar = .current) -> Date? {
        guard let endHour, let endMinute else { return nil }
        guard (0...23).contains(endHour), (0...59).contains(endMinute) else { return nil }
        return calendar.date(from: DateComponents(
            calendar: calendar,
            year: year,
            month: month,
            day: day,
            hour: endHour,
            minute: endMinute
        ))
    }

    /// `OnSchedule5MinutesToGo` / `OnScheduleRead` の Reference 値。
    func eventReferences() -> [String: String] {
        [
            "type": type,
            "caption": caption,
            "subtitle": subtitle,
            "script": script
        ]
    }
}

struct CalendarScheduleParseResult: Equatable {
    let schedules: [CalendarSchedule]
    let rejectedLineNumbers: [Int]
}

/// SCHEDULE/1.0 のタブ区切りレコードを解析する。
///
/// 仕様上、時刻を使わない欄は空欄で返される。壊れたレコードは全体を
/// 失敗させず、その行番号を結果に残して他の予定を読み込む。
enum CalendarScheduleParser {
    enum ParseError: Error {
        case undecodableData
    }

    static func parse(data: Data) throws -> CalendarScheduleParseResult {
        guard let text = LegacyDescriptor.decode(data) else {
            throw ParseError.undecodableData
        }
        return parse(text: text)
    }

    static func parse(text: String) -> CalendarScheduleParseResult {
        var schedules: [CalendarSchedule] = []
        var rejected: [Int] = []

        for (offset, rawLine) in text.split(whereSeparator: { $0.isNewline }).enumerated() {
            let lineNumber = offset + 1
            // 末尾のタブは空欄の subtitle/script を表すため、行全体の
            // whitespace trim は行わない。判定用のコピーだけを trim する。
            let line = String(rawLine)
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#"), !trimmedLine.hasPrefix("//") else { continue }

            // script は空欄を保持する必要があるため、最大9回だけ分割する。
            let fields = line.split(separator: "\t", maxSplits: 9, omittingEmptySubsequences: false)
            guard fields.count == 10,
                  let year = Int(field(fields, at: 1)),
                  let month = Int(field(fields, at: 2)),
                  let day = Int(field(fields, at: 3)),
                  let startHour = optionalClockField(fields, at: 4),
                  let startMinute = optionalClockField(fields, at: 5),
                  let endHour = optionalClockField(fields, at: 6),
                  let endMinute = optionalClockField(fields, at: 7) else {
                rejected.append(lineNumber)
                continue
            }

            let schedule = CalendarSchedule(
                type: field(fields, at: 0),
                year: year,
                month: month,
                day: day,
                startHour: startHour,
                startMinute: startMinute,
                endHour: endHour,
                endMinute: endMinute,
                caption: field(fields, at: 8),
                subtitle: field(fields, at: 9).split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "",
                script: field(fields, at: 9).split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first.map(String.init) ?? ""
            )

            // DateComponents は月日を繰り上げてしまうため、作成後に元の
            // 年月日と一致することも検証して不正な予定を受け入れない。
            guard let date = schedule.startDate(calendar: Calendar.current)
                    ?? Calendar.current.date(from: DateComponents(year: year, month: month, day: day)),
                  Calendar.current.component(.year, from: date) == year,
                  Calendar.current.component(.month, from: date) == month,
                  Calendar.current.component(.day, from: date) == day,
                  (startHour == nil) == (startMinute == nil),
                  (endHour == nil) == (endMinute == nil),
                  validDateFields(schedule) else {
                rejected.append(lineNumber)
                continue
            }
            schedules.append(schedule)
        }

        return CalendarScheduleParseResult(schedules: schedules, rejectedLineNumbers: rejected)
    }

    private static func field(_ fields: [Substring], at index: Int) -> String {
        guard fields.indices.contains(index) else { return "" }
        return String(fields[index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 空欄は nil、値があるのに整数でない場合は nil ではなく不正として扱う。
    /// 呼び出し側で空欄の組み合わせを検証するため、ここでは Optional の
    /// 二重化で「空欄」と「不正値」を区別する。
    private static func optionalClockField(_ fields: [Substring], at index: Int) -> Int?? {
        let raw = field(fields, at: index)
        if raw.isEmpty { return .some(nil) }
        guard let value = Int(raw) else { return nil }
        return .some(value)
    }

    private static func validDateFields(_ schedule: CalendarSchedule) -> Bool {
        guard (1...12).contains(schedule.month),
              (1...31).contains(schedule.day) else { return false }
        if let hour = schedule.startHour, !(0...23).contains(hour) { return false }
        if let minute = schedule.startMinute, !(0...59).contains(minute) { return false }
        if let hour = schedule.endHour, !(0...23).contains(hour) { return false }
        if let minute = schedule.endMinute, !(0...59).contains(minute) { return false }
        return true
    }
}

/// Ourin 内蔵カレンダーの永続ストア。
///
/// SSP のバイナリ形式を捏造せず、実際に編集・読み込みできる JSON を
/// `calendar/schedules.json` に保存する。センサーの SCHEDULE/1.0 応答は
/// `CalendarScheduleParser` でこのモデルへ変換してから置き換える。
final class CalendarScheduleStore {
    enum StoreError: Error {
        case invalidJSON(URL)
        case encodeFailed
    }

    static let defaultFilename = "schedules.json"

    private let fileManager: FileManager
    private let injectedURL: URL?
    private let lock = NSRecursiveLock()

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.injectedURL = fileURL
    }

    func fileURL() throws -> URL {
        if let injectedURL { return injectedURL }
        return try OurinPaths.subdirectory("calendar")
            .appendingPathComponent(Self.defaultFilename, isDirectory: false)
    }

    func load() throws -> [CalendarSchedule] {
        lock.lock()
        defer { lock.unlock() }
        let url = try fileURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode([CalendarSchedule].self, from: data)
        } catch {
            throw StoreError.invalidJSON(url)
        }
    }

    func replace(_ schedules: [CalendarSchedule]) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = try fileURL()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(schedules) else { throw StoreError.encodeFailed }
        try data.write(to: url, options: [.atomic])
    }

    func upsert(_ schedule: CalendarSchedule) throws {
        var schedules = try load()
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        try replace(schedules)
    }

    func remove(id: UUID) throws {
        let schedules = try load().filter { $0.id != id }
        try replace(schedules)
    }
}
