import Foundation
import Testing
@testable import Ourin

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func makeStore() -> (GhostScheduleStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-ghost-schedule-\(UUID().uuidString)", isDirectory: true)
    let url = dir.appendingPathComponent("ghost/schedule.ics")
    return (GhostScheduleStore(fileURL: url, calendar: tokyo), dir)
}

private func run(_ subcommand: String, _ arguments: [String], store: GhostScheduleStore, external: Bool = false, now: Date = day(2026, 9, 10)) -> GhostScheduleCommand.Outcome {
    GhostScheduleCommand.run(subcommand: subcommand, arguments: arguments, isExternalScript: external, store: store, now: now, calendar: tokyo)
}

struct GhostScheduleCommandTests {
    @Test
    func addDeleteAndGetRoundTrip() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let added = run("schedule-add", ["--uid=myghost-meeting", "--summary=打ち合わせ", "--start=20261001T1000", "--end=20261001T1100", "--rrule=FREQ=WEEKLY;BYDAY=TH", "--notify=10", "--type=meeting", "--script=\\0時間です\\e", "--event=OnMyScheduleAdded"], store: store)
        #expect(added.eventName == "OnMyScheduleAdded")
        #expect(added.references == ["Reference0": "add", "Reference1": "myghost-meeting"])

        // 同じ UID は置き換わる（件数は増えない）。
        _ = run("schedule-add", ["--uid=myghost-meeting", "--summary=打ち合わせ2", "--start=20261001T1000"], store: store)
        #expect(try store.load().events.count == 1)
        #expect(try store.load().events[0].summary == "打ち合わせ2")

        _ = run("schedule-add", ["--summary=記念日", "--start=20261224", "--rrule=FREQ=YEARLY"], store: store)
        let loaded = try store.load()
        #expect(loaded.events.count == 2)
        // UID を省略すると割り当てられ、Complete の R1 で返る。
        let assigned = run("schedule-add", ["--summary=X", "--start=20261101"], store: store)
        #expect(assigned.eventName == GhostScheduleCommand.completeEvent)
        #expect(assigned.references["Reference1"]?.hasPrefix("ourin-") == true)

        let got = run("schedule-get", ["--from=20261201", "--to=20261231", "--expand", "--event=OnMySchedule"], store: store)
        #expect(got.eventName == "OnMySchedule")
        #expect(got.references["Reference0"]?.hasPrefix("Ourin Ghost Schedule") == true)
        let fields = (got.references["Reference1"] ?? "").components(separatedBy: "\u{1}")
        #expect(fields[3] == "記念日")
        #expect(fields[11] == "2026,12,24,,,")

        let plainGet = run("schedule-get", [], store: store)
        #expect(plainGet.eventName == GhostScheduleCommand.getCompleteEvent)
        #expect(plainGet.references["Reference0"]?.contains("\u{1}3\u{1}3\u{1}") == true)

        let deleted = run("schedule-delete", ["myghost-meeting"], store: store)
        #expect(deleted.references == ["Reference0": "delete", "Reference1": "myghost-meeting"])
        #expect(try store.load().events.count == 2)
    }

    @Test
    func failuresReportReasons() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let external = run("schedule-add", ["--summary=x", "--start=20261001", "--uid=u1"], store: store, external: true)
        #expect(external.eventName == GhostScheduleCommand.failureEvent)
        #expect(external.references == ["Reference0": "add", "Reference1": "notauthorized", "Reference2": "u1"])

        // --summary / --start が無い、日時の書式が正しくない、UID に使えない文字、不正な RRULE は invalid。
        for arguments in [["--start=20261001"], ["--summary=x"], ["--summary=x", "--start=20261301"],
                          ["--summary=x", "--start=20261001T2560"], ["--summary=x", "--start=20261001", "--uid=a b"],
                          ["--summary=x", "--start=20261001", "--rrule=FREQ=NEVER"], ["--summary=x", "--start=20261001", "--end=20260901"],
                          ["--summary=x", "--start=20261001", "--status=MAYBE"]] {
            let outcome = run("schedule-add", arguments, store: store)
            #expect(outcome.eventName == GhostScheduleCommand.failureEvent, "\(arguments)")
            #expect(outcome.references["Reference1"] == "invalid", "\(arguments)")
        }
        // --event=On... のときの Failure は ID + "Failure"。
        let named = run("schedule-add", ["--start=20261001", "--event=OnMyAdd"], store: store)
        #expect(named.eventName == "OnMyAddFailure")

        let missing = run("schedule-delete", ["nope", "--event=OnMyDel"], store: store)
        #expect(missing.eventName == "OnMyDelFailure")
        #expect(missing.references == ["Reference0": "delete", "Reference1": "notfound", "Reference2": "nope"])
        #expect(run("schedule-delete", [], store: store).references["Reference1"] == "invalid")
        #expect(run("schedule-delete", ["x"], store: store, external: true).references["Reference1"] == "notauthorized")
        #expect(try store.load().events.isEmpty)
    }

    @Test
    func startParsingIgnoresSeparatorsAndRejectsOverflowingFields() {
        #expect(GhostScheduleCommand.parseSchedulePoint("2026-10-01", calendar: tokyo)?.allDay == true)
        let timed = GhostScheduleCommand.parseSchedulePoint("2026-10-01T10:30", calendar: tokyo)
        #expect(timed?.allDay == false)
        #expect(timed?.date == day(2026, 10, 1, 10, 30))
        #expect(GhostScheduleCommand.parseSchedulePoint("20261001T103015", calendar: tokyo) != nil)
        #expect(GhostScheduleCommand.parseSchedulePoint("20261301", calendar: tokyo) == nil)
        #expect(GhostScheduleCommand.parseSchedulePoint("20261001T2460", calendar: tokyo) == nil)
        #expect(GhostScheduleCommand.parseSchedulePoint("tomorrow", calendar: tokyo) == nil)
    }
}

struct GhostScheduleTodayTests {
    @Test
    func todaysScheduleCoversRecurrenceAndMultiDayAndKeepsStableIDs() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = run("schedule-add", ["--uid=a", "--summary=朝会", "--start=20260901T0900", "--end=20260901T0930", "--rrule=FREQ=DAILY", "--notify=15"], store: store)
        _ = run("schedule-add", ["--uid=b", "--summary=出張", "--start=20260909", "--end=20260911"], store: store)
        _ = run("schedule-add", ["--uid=c", "--summary=来月", "--start=20261001"], store: store)

        let today = GhostScheduleToday.schedules(in: store, on: day(2026, 9, 10, 8, 0), calendar: tokyo)
        #expect(today.map(\.schedule.caption).sorted() == ["出張", "朝会"])
        let meeting = try #require(today.first { $0.uid == "a" })
        #expect(meeting.schedule.startHour == 9 && meeting.schedule.startMinute == 0)
        #expect(meeting.schedule.endHour == 9 && meeting.schedule.endMinute == 30)
        #expect(meeting.leadMinutes == 15)
        // 複数日にわたる予定の途中の日は、時刻なしの終日として扱う。
        let trip = try #require(today.first { $0.uid == "b" })
        #expect(trip.schedule.startHour == nil)

        let again = GhostScheduleToday.schedules(in: store, on: day(2026, 9, 10, 23, 0), calendar: tokyo)
        #expect(again.first { $0.uid == "a" }?.schedule.id == meeting.schedule.id)
        let nextDay = GhostScheduleToday.schedules(in: store, on: day(2026, 9, 11), calendar: tokyo)
        #expect(nextDay.first { $0.uid == "a" }?.schedule.id != meeting.schedule.id)
    }
}

struct CalendarEmitterGhostScheduleTests {
    @Test
    func ghostScheduleFiresRemindersAtTheRequestedLeadTimeOnce() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let userStore = CalendarScheduleStore(fileURL: dir.appendingPathComponent("user.json"))
        let emitter = CalendarScheduleEmitter(store: userStore, ghostStore: store)
        var events: [ShioriEvent] = []
        emitter.setHandler { events.append($0) }
        _ = run("schedule-add", ["--uid=m", "--summary=会議", "--start=20260910T1000", "--notify=15", "--type=meeting", "--script=\\0もうすぐ\\e"], store: store)

        // 15 分前より前は何も出ない。
        emitter.emitDueEvents(now: day(2026, 9, 10, 9, 40), calendar: tokyo)
        #expect(events.filter { $0.id == .OnSchedule5MinutesToGo }.isEmpty)
        emitter.emitDueEvents(now: day(2026, 9, 10, 9, 45), calendar: tokyo)
        emitter.emitDueEvents(now: day(2026, 9, 10, 9, 50), calendar: tokyo)
        let reminders = events.filter { $0.id == .OnSchedule5MinutesToGo }
        #expect(reminders.count == 1)
        #expect(reminders[0].params["Reference0"] == "meeting")
        #expect(reminders[0].params["Reference1"] == "会議")
        #expect(reminders[0].params["Reference3"] == "\\0もうすぐ\\e")
    }

    @Test
    func todayNotifyIsSentOnlyWhenTodaysScheduleChanges() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let emitter = CalendarScheduleEmitter(store: CalendarScheduleStore(fileURL: dir.appendingPathComponent("user.json")), ghostStore: store)
        var events: [ShioriEvent] = []
        emitter.setHandler { events.append($0) }
        func notifications() -> [ShioriEvent] { events.filter { $0.id == .OnScheduleTodayNotify } }

        // 最初の計測は基準にするだけ。変化が無ければ通知しない。
        emitter.emitDueEvents(now: day(2026, 9, 10, 8, 0), calendar: tokyo)
        emitter.emitDueEvents(now: day(2026, 9, 10, 8, 1), calendar: tokyo)
        #expect(notifications().isEmpty)

        _ = run("schedule-add", ["--uid=a", "--summary=会議", "--start=20260910T1000", "--end=20260910T1100", "--type=meeting"], store: store)
        emitter.emitDueEvents(now: day(2026, 9, 10, 8, 2), calendar: tokyo)
        #expect(notifications().count == 1)
        let event = try #require(notifications().first)
        #expect(event.delivery == .notify)
        let fields = (event.params["Reference0"] ?? "").components(separatedBy: "\u{1}")
        // 末尾にも区切りが付くので、最後の要素は空。
        #expect(Array(fields.prefix(6)) == ["meeting", "会議", "", "", "2026,9,10,10,0,0", "2026,9,10,11,0,0"])
        #expect(fields.last == "")

        // 変化が無ければ出ない。
        emitter.emitDueEvents(now: day(2026, 9, 10, 8, 3), calendar: tokyo)
        #expect(notifications().count == 1)

        // 削除で 0 件になったら、Reference なしで通知する。
        _ = run("schedule-delete", ["a"], store: store)
        emitter.emitDueEvents(now: day(2026, 9, 10, 8, 4), calendar: tokyo)
        #expect(notifications().count == 2)
        #expect(notifications()[1].params.filter { $0.key.hasPrefix("Reference") }.isEmpty)
    }

    @Test
    func referencesForUserSchedulesWithoutTimeLeaveTimeFieldsEmpty() {
        let schedules = [CalendarSchedule(type: "event", year: 2026, month: 9, day: 10, caption: "休み", subtitle: "s", script: "x")]
        let refs = CalendarScheduleEmitter.todayNotifyReferences(schedules, calendar: tokyo)
        #expect(refs["Reference0"] == ["event", "休み", "s", "x", "2026,9,10,,,", ""].joined(separator: "\u{1}") + "\u{1}")
    }
}
