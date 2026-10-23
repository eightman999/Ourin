import Foundation
import Testing
@testable import Ourin

private let tokyo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
}()

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    tokyo.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}

private func makeDirectory(_ files: [String: String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-holiday-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, text) in files {
        try Data(text.utf8).write(to: dir.appendingPathComponent(name))
    }
    return dir
}

struct HolidayTableTests {
    @Test
    func parsesDatesAndIgnoresHeadersCommentsAndBrokenLines() {
        let table = HolidayTable(text: """
        # コメント
        国民の祝日・休日月日,国民の祝日・休日名称
        2026/1/1,元日
        2026/05/05 ,こどもの日
        2026/13/40,不正な日付ではない（月日の範囲は見ない）
        2026/9/22,
        broken line
        """)
        #expect(table.name(year: 2026, month: 1, day: 1) == "元日")
        #expect(table.name(year: 2026, month: 5, day: 5) == "こどもの日")
        // 名前の無い行は載せない。
        #expect(table.name(year: 2026, month: 9, day: 22) == nil)
        #expect(table.name(year: 2026, month: 1, day: 2) == nil)
    }

    @Test
    func bundledJapaneseTableCoversKnownHolidays() throws {
        // 同梱の表そのものを読み、よく知られた日付で確認する。
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "holidays-JP", withExtension: "txt", subdirectory: "Holidays")
            ?? Bundle.main.url(forResource: "holidays-JP", withExtension: "txt", subdirectory: "Holidays")
            ?? Bundle.main.url(forResource: "holidays-JP", withExtension: "txt"))
        let table = HolidayTable(text: try String(contentsOf: url, encoding: .utf8))
        #expect(table.name(year: 2026, month: 1, day: 1) == "元日")
        #expect(table.name(year: 2026, month: 2, day: 11) == "建国記念の日")
        #expect(table.name(year: 2026, month: 11, day: 3) == "文化の日")
        #expect(table.name(year: 2026, month: 5, day: 6) != nil) // 振替休日
        #expect(table.name(year: 2026, month: 6, day: 15) == nil)
        #expect(table.name(year: 1955, month: 1, day: 1) == "元日")
    }
}

private final class BundleToken {}

struct HolidayInfoProviderTests {
    @Test
    func usesTheRegionTableAndFormatsTheDateWithZeroPadding() throws {
        let dir = try makeDirectory(["holidays-JP.txt": "2026/1/1,元日\n2026/10/12,スポーツの日\n"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let sources = HolidayInfoProvider.Sources(userDirectory: dir, bundle: nil)

        let info = try #require(HolidayInfoProvider.today(now: date(2026, 1, 1), calendar: tokyo, regionCode: "jp", sources: sources))
        #expect(info == HolidayInfo(name: "元日", date: "2026,01,01", countryCode: "JP"))
        #expect(info.parameters == ["Reference0": "元日", "Reference1": "2026,01,01", "Reference2": "JP"])
        #expect(HolidayInfoProvider.today(now: date(2026, 10, 12), calendar: tokyo, regionCode: "JP", sources: sources)?.date == "2026,10,12")
        // 祝日でない日は何も送らない。
        #expect(HolidayInfoProvider.today(now: date(2026, 1, 2), calendar: tokyo, regionCode: "JP", sources: sources) == nil)
    }

    @Test
    func fallsBackToTheDefaultTableWithAnEmptyCountryCode() throws {
        let dir = try makeDirectory(["holidays.txt": "2026/12/25,Christmas Day\n"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let sources = HolidayInfoProvider.Sources(userDirectory: dir, bundle: nil)

        let info = try #require(HolidayInfoProvider.today(now: date(2026, 12, 25), calendar: tokyo, regionCode: "GB", sources: sources))
        #expect(info == HolidayInfo(name: "Christmas Day", date: "2026,12,25", countryCode: ""))
        // 地域が取れない場合も既定の表。
        #expect(HolidayInfoProvider.today(now: date(2026, 12, 25), calendar: tokyo, regionCode: nil, sources: sources) != nil)
    }

    @Test
    func aRegionTableShadowsTheDefaultTableEvenWhenTheDayIsMissing() throws {
        let dir = try makeDirectory([
            "holidays-JP.txt": "2026/1/1,元日\n",
            "holidays.txt": "2026/12/25,Christmas Day\n"
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let sources = HolidayInfoProvider.Sources(userDirectory: dir, bundle: nil)
        #expect(HolidayInfoProvider.today(now: date(2026, 12, 25), calendar: tokyo, regionCode: "JP", sources: sources) == nil)
    }

    @Test
    func userTableTakesPrecedenceOverTheBundledOne() throws {
        let userDir = try makeDirectory(["holidays-JP.txt": "2030/1/1,ユーザー定義の祝日\n"])
        defer { try? FileManager.default.removeItem(at: userDir) }
        // 同梱の表（2027 年までしか無い）の外の年でも、ユーザーの表があれば通知できる。
        let sources = HolidayInfoProvider.Sources(userDirectory: userDir, bundle: .main)
        #expect(HolidayInfoProvider.today(now: date(2030, 1, 1), calendar: tokyo, regionCode: "JP", sources: sources)?.name == "ユーザー定義の祝日")
        // 表が無い場合は何も送らない。
        let none = HolidayInfoProvider.Sources(userDirectory: nil, bundle: nil)
        #expect(HolidayInfoProvider.today(now: date(2026, 1, 1), calendar: tokyo, regionCode: "JP", sources: none) == nil)
    }

    @Test
    func eventReferencesAreRegistered() {
        #expect(EventID.OnNotifyHolidayInfo.rawValue == "OnNotifyHolidayInfo")
        #expect(EventReferenceTable.specs["OnNotifyHolidayInfo"]?.references == ["name", "date", "countryCode"])
    }
}
