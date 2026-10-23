import Foundation
import Testing
@testable import Ourin

/// 日付計算が実行環境のタイムゾーンに左右されないよう、固定のカレンダーを使う。
private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func event(_ summary: String, start: Date, end: Date? = nil, allDay: Bool = true, rrule: String = "", exdates: [Date] = []) -> ICalEvent {
    var event = ICalEvent(start: start)
    event.uid = summary
    event.summary = summary
    event.end = end
    event.allDay = allDay
    event.rrule = rrule
    event.exdates = exdates
    return event
}

private func days(_ dates: [Date]) -> [String] {
    dates.map { ICalendarCodec.formatDate($0, calendar: tokyo) }
}

struct ICalendarCodecTests {
    @Test
    func parsesFoldedLinesEscapesAndAllDayEnd() {
        let text = """
        BEGIN:VCALENDAR\r
        X-WR-CALNAME:仕事\\, 私用\r
        X-WR-TIMEZONE:Asia/Tokyo\r
        BEGIN:VEVENT\r
        UID:a1\r
        DTSTART;VALUE=DATE:20260910\r
        DTEND;VALUE=DATE:20260913\r
        SUMMARY:合宿\\;\r
         準備\r
        DESCRIPTION:一行目\\n二行目\r
        BEGIN:VALARM\r
        SUMMARY:alarm\r
        END:VALARM\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:no-summary\r
        DTSTART:20260910T100000\r
        END:VEVENT\r
        END:VCALENDAR\r

        """
        let parsed = ICalendarCodec.parse(text, calendar: tokyo)
        #expect(parsed.name == "仕事, 私用")
        #expect(parsed.timeZone == "Asia/Tokyo")
        // SUMMARY の無い VEVENT は除外される。
        #expect(parsed.events.count == 1)
        let first = parsed.events[0]
        #expect(first.summary == "合宿;準備")
        #expect(first.description == "一行目\n二行目")
        #expect(first.allDay)
        // DTEND は排他指定なので、最終日は 9/12。
        #expect(first.end == day(2026, 9, 12))
    }

    @Test
    func convertsUTCAndTimezoneToLocalAndReadsDuration() {
        let text = """
        BEGIN:VEVENT
        UID:u
        SUMMARY:utc
        DTSTART:20260910T000000Z
        DURATION:PT1H30M
        END:VEVENT
        BEGIN:VEVENT
        UID:t
        SUMMARY:tz
        DTSTART;TZID=America/New_York:20260910T090000
        DTEND;TZID=America/New_York:20260910T100000
        END:VEVENT
        """
        let events = ICalendarCodec.parse(text, calendar: tokyo).events
        // 0:00 UTC は東京で 9:00。
        #expect(events[0].start == day(2026, 9, 10, 9, 0))
        #expect(events[0].end == day(2026, 9, 10, 10, 30))
        // 9:00 EDT(UTC-4) = 13:00 UTC = 22:00 東京。
        #expect(events[1].start == day(2026, 9, 10, 22, 0))
    }

    @Test
    func serializeRoundTripsEventsIncludingOurinExtensions() {
        var original = event("打ち合わせ, A;B", start: day(2026, 10, 1, 10, 0), end: day(2026, 10, 1, 11, 0), allDay: false, rrule: "FREQ=WEEKLY;BYDAY=TH", exdates: [day(2026, 10, 8)])
        original.uid = "myghost-meeting"
        original.description = "改行\nあり"
        original.location = "会議室"
        original.type = "meeting"
        original.notifyMinutes = 10
        original.script = "\\0予定です\\e"
        let allDay = event("記念日", start: day(2026, 12, 24))
        let text = ICalendarCodec.serialize(ICalCalendar(name: "x", events: [original, allDay]), calendar: tokyo)
        #expect(text.contains("\r\n"))
        #expect(text.split(separator: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        let back = ICalendarCodec.parse(text, calendar: tokyo)
        #expect(back.events.count == 2)
        #expect(back.events[0] == original)
        #expect(back.events[1].allDay)
        #expect(back.events[1].start == day(2026, 12, 24))
        #expect(back.events[1].end == day(2026, 12, 24))
    }

    @Test
    func durationParsing() {
        #expect(ICalendarCodec.parseDuration("P1D") == 86_400)
        #expect(ICalendarCodec.parseDuration("PT1H30M") == 5_400)
        #expect(ICalendarCodec.parseDuration("P1W") == 604_800)
        #expect(ICalendarCodec.parseDuration("-PT5M") == -300)
        #expect(ICalendarCodec.parseDuration("1D") == nil)
    }
}

struct ICalendarRecurrenceTests {
    private func occurrences(_ event: ICalEvent, through: Date) -> [String] {
        days(ICalendarRecurrence.occurrenceDays(of: event, through: through, calendar: tokyo))
    }

    @Test
    func dailyWithIntervalCountAndExdate() {
        let base = event("d", start: day(2026, 9, 1), rrule: "FREQ=DAILY;INTERVAL=2;COUNT=4", exdates: [day(2026, 9, 3)])
        // 9/1, 9/3, 9/5, 9/7 の 4 回のうち、EXDATE の 9/3 を除く（COUNT は除外前に数える）。
        #expect(occurrences(base, through: day(2026, 12, 31)) == ["20260901", "20260905", "20260907"])
    }

    @Test
    func weeklyByDayWithUntil() {
        let base = event("w", start: day(2026, 10, 1), rrule: "FREQ=WEEKLY;BYDAY=TH,MO;UNTIL=20261014")
        // 2026-10-01 は木曜。
        #expect(occurrences(base, through: day(2026, 12, 31)) == ["20261001", "20261005", "20261008", "20261012"])
    }

    @Test
    func monthlyByMonthDayAndNthWeekday() {
        let fifteenth = event("m", start: day(2026, 1, 31), rrule: "FREQ=MONTHLY;BYMONTHDAY=31;COUNT=4")
        // 31 日が無い月は飛ばす。
        #expect(occurrences(fifteenth, through: day(2026, 12, 31)) == ["20260131", "20260331", "20260531", "20260731"])
        let lastFriday = event("f", start: day(2026, 9, 25), rrule: "FREQ=MONTHLY;BYDAY=-1FR;COUNT=3")
        #expect(occurrences(lastFriday, through: day(2026, 12, 31)) == ["20260925", "20261030", "20261127"])
        let firstMonday = event("n", start: day(2026, 9, 7), rrule: "FREQ=MONTHLY;BYDAY=1MO;COUNT=3")
        #expect(occurrences(firstMonday, through: day(2026, 12, 31)) == ["20260907", "20261005", "20261102"])
    }

    @Test
    func yearlyByMonthAndDefaultAnniversary() {
        let anniversary = event("y", start: day(2026, 12, 24), rrule: "FREQ=YEARLY;COUNT=3")
        #expect(occurrences(anniversary, through: day(2040, 1, 1)) == ["20261224", "20271224", "20281224"])
        let leap = event("l", start: day(2024, 2, 29), rrule: "FREQ=YEARLY;COUNT=2")
        // うるう日は平年に存在しないので次のうるう年へ。
        #expect(occurrences(leap, through: day(2040, 1, 1)) == ["20240229", "20280229"])
        let byMonth = event("bm", start: day(2026, 3, 1), rrule: "FREQ=YEARLY;BYMONTH=3,9;BYMONTHDAY=1;COUNT=3")
        #expect(occurrences(byMonth, through: day(2040, 1, 1)) == ["20260301", "20260901", "20270301"])
    }

    @Test
    func noRuleIsSingleOccurrenceAndStopsAtLimit() {
        let single = event("s", start: day(2026, 9, 10))
        #expect(occurrences(single, through: day(2026, 9, 9)).isEmpty)
        #expect(occurrences(single, through: day(2026, 9, 10)) == ["20260910"])
        let endless = event("e", start: day(2026, 9, 1), rrule: "FREQ=DAILY")
        #expect(occurrences(endless, through: day(2026, 9, 3)) == ["20260901", "20260902", "20260903"])
        // 解釈できない RRULE は繰り返しなしとして扱う。
        #expect(occurrences(event("bad", start: day(2026, 9, 1), rrule: "FREQ=SECONDLY"), through: day(2026, 9, 9)) == ["20260901"])
    }
}

struct ICalendarQueryTests {
    private let today = day(2026, 9, 10)

    @Test
    func optionsParse() {
        let query = ICalQuery(options: ["--from=20261201", "--to=20261231", "--expand", "--limit=50", "--async=OnX"], calendar: tokyo)
        #expect(query.from == day(2026, 12, 1))
        #expect(query.to == day(2026, 12, 31))
        #expect(query.expandDays == 0)
        #expect(query.limit == 50)
        #expect(ICalQuery(options: ["--expand=7"], calendar: tokyo).expandDays == 7)
        #expect(!ICalQuery(options: ["--async=OnX"], calendar: tokyo).isPeriodMode)
        // --limit だけでも期間モード。
        #expect(ICalQuery(options: ["--limit=5"], calendar: tokyo).isPeriodMode)
    }

    @Test
    func withoutOptionsReturnsEveryEventInFileOrder() {
        let events = [event("b", start: day(2030, 1, 1)), event("a", start: day(2020, 1, 1))]
        let selection = ICalendarQuerying.select(events: events, query: ICalQuery(), today: today, calendar: tokyo)
        #expect(selection.occurrences.map(\.event.summary) == ["b", "a"])
        #expect(selection.occurrences.allSatisfy { $0.day == nil })
        #expect(selection.periodStart == nil)
    }

    @Test
    func expandReturnsOneEntryPerOccurrenceSortedByDate() {
        let events = [
            event("daily", start: day(2026, 9, 1), rrule: "FREQ=DAILY"),
            event("once", start: day(2026, 9, 12))
        ]
        let selection = ICalendarQuerying.select(events: events, query: ICalQuery(expandDays: 3), today: today, calendar: tokyo)
        // 9/10〜9/12 の 3 日ぶん。9/12 は daily と once の 2 件。
        #expect(selection.occurrences.map { "\($0.event.summary)@\(ICalendarCodec.formatDate($0.day!, calendar: tokyo))" }
            == ["daily@20260910", "daily@20260911", "daily@20260912", "once@20260912"])
        #expect(selection.totalEvents == 2)
    }

    @Test
    func withoutExpandReturnsOnePerEventWithFirstOccurrenceInPeriod() {
        let events = [event("weekly", start: day(2026, 9, 1), rrule: "FREQ=WEEKLY")]
        let selection = ICalendarQuerying.select(events: events, query: ICalQuery(from: day(2026, 9, 10), to: day(2026, 9, 30)), today: today, calendar: tokyo)
        #expect(selection.occurrences.count == 1)
        // 9/1 の週次 → 期間内の最初は 9/15。
        #expect(days([selection.occurrences[0].day!]) == ["20260915"])
    }

    @Test
    func multiDayEventCountsEveryDayAndLimitApplies() {
        let trip = event("trip", start: day(2026, 9, 8), end: day(2026, 9, 11))
        // 期間の開始（9/10）より前に始まっても、期間に掛かれば返る。発生日は期間内の最初の日。
        let inside = ICalendarQuerying.select(events: [trip], query: ICalQuery(from: day(2026, 9, 10), to: day(2026, 9, 10)), today: today, calendar: tokyo)
        #expect(inside.occurrences.count == 1)
        #expect(days([inside.occurrences[0].day!]) == ["20260910"])
        let outside = ICalendarQuerying.select(events: [trip], query: ICalQuery(from: day(2026, 9, 12), to: day(2026, 9, 20)), today: today, calendar: tokyo)
        #expect(outside.occurrences.isEmpty)

        let many = (0..<5).map { event("e\($0)", start: day(2026, 9, 10 + $0)) }
        let limited = ICalendarQuerying.select(events: many, query: ICalQuery(from: day(2026, 9, 10), to: day(2026, 9, 30), limit: 2), today: today, calendar: tokyo)
        #expect(limited.occurrences.count == 2)
        #expect(limited.totalEvents == 5)
        // --limit=0 は無制限。
        let unlimited = ICalendarQuerying.select(events: many, query: ICalQuery(from: day(2026, 9, 10), to: day(2026, 9, 30), limit: 0), today: today, calendar: tokyo)
        #expect(unlimited.occurrences.count == 5)
    }

    @Test
    func reversedPeriodIsEmptyAndPeriodIsCappedAt1830Days() {
        let events = [event("e", start: day(2026, 9, 10))]
        let reversed = ICalendarQuerying.select(events: events, query: ICalQuery(from: day(2026, 9, 20), to: day(2026, 9, 10)), today: today, calendar: tokyo)
        #expect(reversed.occurrences.isEmpty)
        let far = [event("far", start: day(2040, 1, 1))]
        let capped = ICalendarQuerying.select(events: far, query: ICalQuery(from: day(2026, 9, 10), to: day(2040, 12, 31)), today: today, calendar: tokyo)
        #expect(capped.occurrences.isEmpty)
        #expect(days([capped.periodEnd!]) == days([tokyo.date(byAdding: .day, value: 1829, to: day(2026, 9, 10))!]))
    }
}

struct ICalendarReferencesTests {
    @Test
    func completeReferencesFollowUkadocLayoutAndEscapeScriptCharacters() {
        var meeting = event("100% 会議\\\n本番", start: day(2026, 9, 10, 10, 30), end: day(2026, 9, 10, 11, 0), allDay: false, rrule: "FREQ=DAILY")
        meeting.uid = "u1"
        meeting.description = "a\tb"
        meeting.categories = "x,y"
        let allDay = event("休み", start: day(2026, 9, 10), end: day(2026, 9, 12))
        let selection = ICalendarQuerying.select(
            events: [meeting, allDay],
            query: ICalQuery(from: day(2026, 9, 10), to: day(2026, 9, 10), expandDays: 0),
            calendar: tokyo
        )
        let info = ICalCalendar(name: "私用%", timeZone: "Asia/Tokyo", events: [meeting, allDay])
        let refs = ICalendarReferences.complete(
            calendarInfo: info, selection: selection,
            query: ICalQuery(from: day(2026, 9, 10), to: day(2026, 9, 10), expandDays: 0), calendar: tokyo
        )
        let sep = "\u{1}"
        #expect(refs["Reference0"] == ["私用\\%", "Asia/Tokyo", "GREGORIAN", "2", "2", "2026,9,10,,,", "2026,9,10,,,"].joined(separator: sep))

        // 同じ日の予定は、時刻なしの終日が先、次に時刻の早い順。
        let fields1 = refs["Reference1"]!.components(separatedBy: sep)
        #expect(fields1[3] == "休み")
        // 終日: 時・分・秒は空、終了は最終日、終日フラグは 1。
        #expect(fields1[1] == "2026,9,10,,,")
        #expect(fields1[2] == "2026,9,12,,,")
        #expect(fields1[10] == "1")

        let fields2 = refs["Reference2"]!.components(separatedBy: sep)
        #expect(fields2[0] == "u1")
        #expect(fields2[1] == "2026,9,10,10,30,0")
        #expect(fields2[2] == "2026,9,10,11,0,0")
        // \ → \\、% → \%、改行とタブ → 半角空白。
        #expect(fields2[3] == "100\\% 会議\\\\ 本番")
        #expect(fields2[4] == "a b")
        #expect(fields2[8] == "x,y")
        #expect(fields2[9] == "FREQ=DAILY")
        #expect(fields2[10] == "0")
        #expect(fields2[11] == "2026,9,10,,,")
    }

    @Test
    func periodFieldsAreEmptyWithoutFilterOptions() {
        let selection = ICalendarQuerying.select(events: [], query: ICalQuery(), calendar: tokyo)
        let refs = ICalendarReferences.complete(calendarInfo: ICalCalendar(), selection: selection, query: ICalQuery(), calendar: tokyo)
        #expect(refs["Reference0"] == ["", "", "GREGORIAN", "0", "0", "", ""].joined(separator: "\u{1}"))
    }
}
