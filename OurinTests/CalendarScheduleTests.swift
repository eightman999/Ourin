import Foundation
import Testing
@testable import Ourin

struct CalendarScheduleTests {
    @Test
    func parsesScheduleProtocolRecordsAndKeepsEmptyTimes() {
        let result = CalendarScheduleParser.parse(text: """
        # comment
        meeting\t2026\t8\t14\t9\t30\t10\t15\t朝会\t会議室\t\\0朝会です\\e
        date\t2026\t8\t15\t\t\t\t\t終日\t\t
        broken\t2026\t8
        """)

        #expect(result.schedules.count == 2)
        #expect(result.rejectedLineNumbers == [4])
        #expect(result.schedules[0].type == "meeting")
        #expect(result.schedules[0].startHour == 9)
        #expect(result.schedules[0].startMinute == 30)
        #expect(result.schedules[0].eventReferences()["script"] == "\\0朝会です\\e")
        #expect(result.schedules[1].startHour == nil)
        #expect(result.schedules[1].endMinute == nil)
    }

    @Test
    func rejectsInvalidDatesAndClockValues() {
        let result = CalendarScheduleParser.parse(text: """
        event\t2026\t2\t30\t9\t00\t\t\tinvalid date\t\t
        event\t2026\t8\t14\t24\t00\t\t\tinvalid hour\t\t
        event\t2026\t8\t14\t9\t\t\t\tpartial time\t\t
        """)

        #expect(result.schedules.isEmpty)
        #expect(result.rejectedLineNumbers == [1, 2, 3])
    }

    @Test
    func storesAndUpdatesSchedulesAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinCalendarStore-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("schedules.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = CalendarScheduleStore(fileURL: file)
        let first = CalendarSchedule(year: 2026, month: 8, day: 14, caption: "first")
        let updated = CalendarSchedule(
            id: first.id,
            type: "meeting",
            year: 2026,
            month: 8,
            day: 14,
            startHour: 12,
            startMinute: 30,
            caption: "updated"
        )

        try store.upsert(first)
        try store.upsert(updated)
        #expect(try store.load() == [updated])

        try store.remove(id: updated.id)
        #expect(try store.load().isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func scheduleReferencesAreRegisteredInTheEventTable() {
        #expect(EventReferenceTable.specs["OnSchedule5MinutesToGo"]?.references == ["type", "caption", "subtitle", "script"])
        #expect(EventReferenceTable.specs["OnSchedulesenseComplete"]?.references == ["sensorName", "scheduleCount"])
        #expect(EventReferenceTable.specs["OnSchedulepostComplete"]?.category == "calendar")
    }

    @Test
    func emitsFiveMinuteReminderOnceAndReadsStoredSchedule() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinCalendarEmitter-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = CalendarScheduleStore(fileURL: file)
        let calendar = Calendar(identifier: .gregorian)
        let schedule = CalendarSchedule(
            year: 2026,
            month: 8,
            day: 14,
            startHour: 12,
            startMinute: 0,
            caption: "meeting"
        )
        try? store.replace([schedule])

        let emitter = CalendarScheduleEmitter(store: store)
        var events: [ShioriEvent] = []
        emitter.setHandler { events.append($0) }
        _ = emitter.refresh(emitEvents: false)

        let start = schedule.startDate(calendar: calendar)!
        emitter.emitDueEvents(now: start.addingTimeInterval(-4 * 60), calendar: calendar)
        emitter.emitDueEvents(now: start.addingTimeInterval(-3 * 60), calendar: calendar)
        #expect(events.map(\.id) == [.OnSchedule5MinutesToGo])
        #expect(events.first?.params["Reference1"] == "meeting")

        #expect(emitter.read(id: schedule.id))
        #expect(events.map(\.id) == [.OnSchedule5MinutesToGo, .OnScheduleRead])
        #expect(events.last?.params["Reference1"] == "meeting")
    }

    // MARK: - #119 PlayTodaysEvent

    @Test
    func todaysEventScriptIncludesHeaderAndScheduleLines() {
        let schedules = [
            CalendarSchedule(
                year: 2026, month: 8, day: 14,
                startHour: 9, startMinute: 30,
                endHour: 10, endMinute: 15,
                caption: "朝会", subtitle: "会議室"
            ),
            CalendarSchedule(
                year: 2026, month: 8, day: 14,
                startHour: 12, startMinute: 0,
                caption: "お昼\\休憩%", script: "\\0本体\\e"
            ),
            CalendarSchedule(year: 2026, month: 8, day: 14, caption: "終日")
        ]

        let script = CalendarScheduleEmitter.buildTodaysEventScript(
            month: 8,
            day: 14,
            schedules: schedules,
            header: "今日の予定をお知らせします。"
        )

        // 先頭は \b[2]M/D 形式
        #expect(script.hasPrefix("\\b[2]8/14"))
        // 辞書ヘッダと区切り
        #expect(script.contains("今日の予定をお知らせします。"))
        #expect(script.contains("\\n\\n[half]"))
        // 範囲付き予定: >>[09:30]->[10:15]
        #expect(script.contains(">>[09:30]->[10:15] 朝会"))
        #expect(script.contains("会議室"))
        // 同一時刻開始=終了は >>[HH:MM] のみ（バックスラッシュ・% はタグ無効化エスケープ済み）
        #expect(script.contains(">>[12:00] お昼\\\\休憩\\%"))
        // タグ無効化エスケープ（% → \%）
        #expect(script.contains("\\%"))
        #expect(!script.contains("\\0本体\\e"))
        // 時刻なし予定は >> のみ
        #expect(script.contains(">>終日"))
    }

    @Test
    func todaysEventScriptWithoutHeaderStillProducesValidScript() {
        let schedules = [CalendarSchedule(year: 2026, month: 8, day: 14, caption: "予定")]
        let script = CalendarScheduleEmitter.buildTodaysEventScript(
            month: 8, day: 14, schedules: schedules, header: nil
        )
        #expect(script.hasPrefix("\\b[2]8/14"))
        #expect(script.contains("\\n\\n[half]"))
        #expect(script.contains(">>予定"))
    }

    @Test
    func todaysEventScriptEscapesBackslashAndNewline() {
        let schedules = [CalendarSchedule(
            year: 2026, month: 8, day: 14,
            startHour: 15, startMinute: 0,
            caption: "一行目\n二行目\\末尾"
        )]
        let script = CalendarScheduleEmitter.buildTodaysEventScript(
            month: 8, day: 14, schedules: schedules, header: nil
        )
        // 改行 → \n、バックスラッシュ → \\
        #expect(script.contains(">>[15:00] 一行目\\n二行目\\\\末尾"))
    }

    @Test
    func schedulesOnDateFiltersAndSortsByTime() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinCalendarSchedulesOn-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let store = CalendarScheduleStore(fileURL: file)
        try? store.replace([
            CalendarSchedule(year: 2026, month: 8, day: 14, startHour: 14, startMinute: 0, caption: "午後"),
            CalendarSchedule(year: 2026, month: 8, day: 15, startHour: 9, startMinute: 0, caption: "翌日"),
            CalendarSchedule(year: 2026, month: 8, day: 14, startHour: 9, startMinute: 0, caption: "朝")
        ])

        let emitter = CalendarScheduleEmitter(store: store)
        _ = emitter.refresh(emitEvents: false)
        let calendar = Calendar(identifier: .gregorian)
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))
        )
        let result = emitter.schedules(on: date, calendar: calendar)
        #expect(result.map(\.caption) == ["朝", "午後"])
    }
}
