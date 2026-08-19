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

            // SCHEDULE/1.0 は type から script まで11欄。script 内に
            // タブが含まれても最後の欄へ残るよう、最大10回だけ分割する。
            let fields = line.split(separator: "\t", maxSplits: 10, omittingEmptySubsequences: false)
            guard fields.count == 11,
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
                subtitle: field(fields, at: 9),
                script: rawField(fields, at: 10)
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

    private static func rawField(_ fields: [Substring], at index: Int) -> String {
        guard fields.indices.contains(index) else { return "" }
        return String(fields[index])
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

struct CalendarScheduleRefreshResult: Equatable {
    let schedules: [CalendarSchedule]
    let rejectedLineNumbers: [Int]
}

/// 保存済みの予定を監視し、標準カレンダーイベントを発火する。
///
/// スケジュールセンサーのDLLを模倣せず、Ourin が実際に保持する
/// CalendarScheduleStore を唯一の予定ソースとする。センサー応答を取り込む
/// 場合も SCHEDULE/1.0 を importSensorData で解析して同じストアへ統合する。
final class CalendarScheduleEmitter {
    static let builtinSensorName = "builtin:calendar"

    private let store: CalendarScheduleStore
    private let stateLock = NSLock()
    private var schedules: [CalendarSchedule] = []
    private var firedFiveMinuteKeys: Set<String> = []
    private var timer: DispatchSourceTimer?
    private var handler: ((ShioriEvent) -> Void)?

    init(store: CalendarScheduleStore = CalendarScheduleStore()) {
        self.store = store
    }

    func setHandler(_ handler: ((ShioriEvent) -> Void)?) {
        stateLock.lock()
        self.handler = handler
        stateLock.unlock()
    }

    func start() {
        stop()
        _ = refresh(emitEvents: false)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        timer.setEventHandler { [weak self] in
            self?.emitDueEvents(now: Date())
        }
        timer.resume()
        stateLock.lock()
        self.timer = timer
        stateLock.unlock()
    }

    func stop() {
        stateLock.lock()
        let timer = self.timer
        self.timer = nil
        self.schedules.removeAll()
        self.firedFiveMinuteKeys.removeAll()
        stateLock.unlock()
        timer?.cancel()
    }

    /// 保存済み予定を読み直し、実データのセンス開始/完了イベントを発火する。
    @discardableResult
    func refresh(
        sensorName: String = CalendarScheduleEmitter.builtinSensorName,
        emitEvents: Bool = true
    ) -> CalendarScheduleRefreshResult {
        if emitEvents {
            emit(ShioriEvent(id: .OnSchedulesenseBegin, refs: ["sensorName": sensorName]))
        }

        do {
            let loaded = try store.load()
            stateLock.lock()
            schedules = loaded
            let validKeys = Set(loaded.map { scheduleKey($0) })
            firedFiveMinuteKeys = firedFiveMinuteKeys.intersection(validKeys)
            stateLock.unlock()
            if emitEvents {
                emit(ShioriEvent(id: .OnSchedulesenseComplete, refs: [
                    "sensorName": sensorName,
                    "scheduleCount": String(loaded.count)
                ]))
            }
            return CalendarScheduleRefreshResult(schedules: loaded, rejectedLineNumbers: [])
        } catch {
            if emitEvents {
                emit(ShioriEvent(id: .OnSchedulesenseFailure, refs: [
                    "reason": reason(for: error)
                ]))
            }
            return CalendarScheduleRefreshResult(schedules: [], rejectedLineNumbers: [])
        }
    }

    /// SCHEDULE/1.0 のセンサー応答を実データとして保存・反映する。
    @discardableResult
    func importSensorData(
        _ data: Data,
        sensorName: String,
        emitEvents: Bool = true
    ) -> CalendarScheduleRefreshResult {
        if emitEvents {
            emit(ShioriEvent(id: .OnSchedulesenseBegin, refs: ["sensorName": sensorName]))
        }
        do {
            let parsed = try CalendarScheduleParser.parse(data: data)
            try store.replace(parsed.schedules)
            stateLock.lock()
            schedules = parsed.schedules
            firedFiveMinuteKeys.removeAll()
            stateLock.unlock()
            if emitEvents {
                emit(ShioriEvent(id: .OnSchedulesenseComplete, refs: [
                    "sensorName": sensorName,
                    "scheduleCount": String(parsed.schedules.count)
                ]))
            }
            return CalendarScheduleRefreshResult(
                schedules: parsed.schedules,
                rejectedLineNumbers: parsed.rejectedLineNumbers
            )
        } catch {
            if emitEvents {
                emit(ShioriEvent(id: .OnSchedulesenseFailure, refs: [
                    "reason": reason(for: error)
                ]))
            }
            return CalendarScheduleRefreshResult(schedules: [], rejectedLineNumbers: [])
        }
    }

    /// 投稿モードの開始/完了を、実際のローカルストア操作として通知する。
    /// 外部センサーの投稿処理は importSensorData の呼び出し側が担う。
    func beginPost(sensorName: String) {
        emit(ShioriEvent(id: .OnSchedulepostBegin, refs: ["sensorName": sensorName]))
    }

    func completePost(sensorName: String) {
        emit(ShioriEvent(id: .OnSchedulepostComplete, refs: ["sensorName": sensorName]))
    }

    /// カレンダー画面等から予定を読み上げる。
    @discardableResult
    func read(id: UUID) -> Bool {
        stateLock.lock()
        let schedule = schedules.first { $0.id == id }
        stateLock.unlock()
        guard let schedule else { return false }
        emit(ShioriEvent(id: .OnScheduleRead, refs: schedule.eventReferences()))
        return true
    }

    /// 指定日付の予定一覧（時刻順・ソート済み）。
    func schedules(on date: Date, calendar: Calendar = .current) -> [CalendarSchedule] {
        stateLock.lock()
        let result = schedules.filter {
            guard let scheduleDate = calendar.date(from: DateComponents(
                year: $0.year, month: $0.month, day: $0.day
            )) else { return false }
            return calendar.isDate(scheduleDate, inSameDayAs: date)
        }.sorted { lhs, rhs in
            let left = (lhs.startHour ?? 24) * 60 + (lhs.startMinute ?? 0)
            let right = (rhs.startHour ?? 24) * 60 + (rhs.startMinute ?? 0)
            return left == right ? lhs.caption < rhs.caption : left < right
        }
        stateLock.unlock()
        return result
    }

    /// SSP `SPCalendarCell::PlayTodaysEvent` 互換の当日イベント再生。
    ///
    /// `header` はゴースト辞書の `#todays event header` エントリ（無ければ nil）。
    /// 組み立て: `\b[2]M/D` + header + `\n\n[half]` + 各予定を
    /// `>>[HH:MM] `（または範囲）と本文のタグ無効化エスケープで列挙。
    static func buildTodaysEventScript(
        month: Int,
        day: Int,
        schedules: [CalendarSchedule],
        header: String?
    ) -> String {
        var script = "\\b[2]\(month)/\(day)"
        if let header, !header.isEmpty {
            script += header
        }
        script += "\\n\\n[half]"
        for schedule in schedules {
            script += scheduleTimePrefix(schedule)
            script += disableScriptTag(schedule.caption)
            if !schedule.subtitle.isEmpty {
                script += "\\n" + disableScriptTag(schedule.subtitle)
            }
            script += "\\n"
        }
        return script
    }

    /// `>>[HH:MM] ` / `>>[HH:MM]->[HH:MM] ` / `>>`（時刻なし）の行頭プレフィックス。
    private static func scheduleTimePrefix(_ schedule: CalendarSchedule) -> String {
        guard let startHour = schedule.startHour, let startMinute = schedule.startMinute,
              (0...23).contains(startHour), (0...59).contains(startMinute) else {
            return ">>"
        }
        if let endHour = schedule.endHour, let endMinute = schedule.endMinute,
           startHour == endHour, startMinute == endMinute {
            return String(format: ">>[%02d:%02d] ", startHour, startMinute)
        }
        if let endHour = schedule.endHour, let endMinute = schedule.endMinute,
           (0...23).contains(endHour), (0...59).contains(endMinute) {
            return String(format: ">>[%02d:%02d]->[%02d:%02d] ", startHour, startMinute, endHour, endMinute)
        }
        return String(format: ">>[%02d:%02d] ", startHour, startMinute)
    }

    /// SSP `SPDisableScriptTag` 互換: `\`→`\\`、`%`→`\%`、改行→`\n`（CR は除去）。
    private static func disableScriptTag(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for ch in value {
            switch ch {
            case "\\": result += "\\\\"
            case "%": result += "\\%"
            case "\n": result += "\\n"
            case "\r": continue
            default: result.append(ch)
            }
        }
        return result
    }

    /// テストとカレンダー画面から同じ時刻判定を実行できる入口。
    func emitDueEvents(now: Date, calendar: Calendar = .current) {
        stateLock.lock()
        let due = schedules.filter { schedule in
            guard let start = schedule.startDate(calendar: calendar) else { return false }
            let reminder = start.addingTimeInterval(-5 * 60)
            guard now >= reminder, now < start else { return false }
            return !firedFiveMinuteKeys.contains(scheduleKey(schedule, calendar: calendar))
        }
        for schedule in due {
            firedFiveMinuteKeys.insert(scheduleKey(schedule, calendar: calendar))
        }
        stateLock.unlock()

        for schedule in due {
            emit(ShioriEvent(id: .OnSchedule5MinutesToGo, refs: schedule.eventReferences()))
        }
    }

    private func emit(_ event: ShioriEvent) {
        stateLock.lock()
        let handler = self.handler
        stateLock.unlock()
        handler?(event)
    }

    private func scheduleKey(_ schedule: CalendarSchedule, calendar: Calendar = .current) -> String {
        let date = schedule.startDate(calendar: calendar)?.timeIntervalSince1970 ?? 0
        return "\(schedule.id.uuidString)|\(date)"
    }

    private func reason(for error: Error) -> String {
        switch error {
        case CalendarScheduleParser.ParseError.undecodableData:
            return "decode_failed"
        case CalendarScheduleStore.StoreError.invalidJSON:
            return "invalid_data"
        case CalendarScheduleStore.StoreError.encodeFailed:
            return "write_failed"
        default:
            return "read_failed"
        }
    }
}
