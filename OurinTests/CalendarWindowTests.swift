import Foundation
import Testing
@testable import Ourin

struct CalendarWindowTests {
    @Test
    func monthGridAlwaysContainsSixWeeksStartingAtCalendarWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!

        let days = CalendarGrid.days(in: date, calendar: calendar)

        #expect(days.count == 42)
        #expect(calendar.component(.weekday, from: days[0]) == calendar.firstWeekday)
        #expect(days.contains { calendar.isDate($0, inSameDayAs: date) })
    }

    @Test
    func modelRefreshesSortsAndReadsSchedulesForSelectedDate() {
        let calendar = Calendar.current
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
        let early = CalendarSchedule(
            year: 2026,
            month: 8,
            day: 14,
            startHour: 9,
            startMinute: 0,
            caption: "early"
        )
        let allDay = CalendarSchedule(
            year: 2026,
            month: 8,
            day: 14,
            caption: "all day"
        )
        let otherDay = CalendarSchedule(
            year: 2026,
            month: 8,
            day: 15,
            caption: "other"
        )
        var readIDs: [UUID] = []
        let model = CalendarWindowModel(
            now: selectedDate,
            loadSchedules: {
                CalendarScheduleRefreshResult(
                    schedules: [allDay, otherDay, early],
                    rejectedLineNumbers: []
                )
            },
            readSchedule: { schedule in
                readIDs.append(schedule.id)
                return true
            }
        )

        model.refresh()

        #expect(model.lastRefreshMessage == "3件")
        #expect(model.schedules(on: selectedDate).map(\.caption) == ["early", "all day"])
        #expect(model.schedules(on: calendar.date(byAdding: .day, value: 1, to: selectedDate)!).map(\.caption) == ["other"])
        #expect(model.read(early))
        #expect(readIDs == [early.id])
    }

    @Test
    func modelMovesAndSelectsMonthWithoutChangingScheduleData() {
        let calendar = Calendar.current
        let selectedDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 14))!
        let model = CalendarWindowModel(
            now: selectedDate,
            loadSchedules: {
                CalendarScheduleRefreshResult(schedules: [], rejectedLineNumbers: [])
            }
        )

        model.moveMonth(by: 1)

        #expect(calendar.component(.year, from: model.displayedMonth) == 2026)
        #expect(calendar.component(.month, from: model.displayedMonth) == 9)
        #expect(calendar.component(.month, from: model.selectedDate) == 9)

        model.selectToday(now: selectedDate)

        #expect(calendar.isDate(model.selectedDate, inSameDayAs: selectedDate))
        #expect(calendar.component(.month, from: model.displayedMonth) == 8)
    }
}
