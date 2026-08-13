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
}
