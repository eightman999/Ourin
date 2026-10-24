import Foundation
import Testing
@testable import Ourin

/// 外国の祝日と言語ごとの祝日名（#165）。
struct ForeignHolidayTests {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func today(_ y: Int, _ m: Int, _ d: Int, region: String, language: String?) -> HolidayInfo? {
        HolidayInfoProvider.today(now: date(y, m, d), calendar: utc, regionCode: region,
                                  sources: .init(userDirectory: nil, bundle: .main, language: language))
    }

    @Test
    func bundledTablesNameHolidaysInTheCountrysLanguage() {
        #expect(today(2026, 7, 4, region: "US", language: "ja") == HolidayInfo(name: "Independence Day", date: "2026,07,04", countryCode: "US"))
        #expect(today(2026, 12, 25, region: "DE", language: "ja")?.name == "Erster Weihnachtstag")
        #expect(today(2026, 10, 1, region: "CN", language: "ja")?.name == "国庆节")
        #expect(today(2026, 3, 1, region: "KR", language: "ja")?.name == "삼일절")
        #expect(today(2026, 1, 1, region: "TW", language: "ja")?.name == "中華民國開國紀念日")
        #expect(today(2026, 12, 25, region: "FR", language: "ja")?.name == "Noël")
        // 振替休日は UKADOC の例と同じ書き方。
        #expect(today(2026, 12, 28, region: "GB", language: "en")?.name == "Boxing Day (substitute day)")
        // 祝日でない日は送らない。
        #expect(today(2026, 7, 5, region: "US", language: "en") == nil)
        #expect(today(2026, 6, 15, region: "DE", language: "en") == nil)
    }

    @Test
    func theDisplayLanguageFolderComesFirst() {
        // 表示が英語なら英語の表（en.lproj）、日本語なら言語によらない表（その国の公用語）。
        #expect(today(2026, 12, 25, region: "DE", language: "en")?.name == "Christmas Day")
        #expect(today(2026, 12, 25, region: "KR", language: "en")?.name == "Christmas Day")
        #expect(today(2026, 12, 25, region: "KR", language: "ja")?.name == "기독탄신일")
        // 日本は、日本語なら内閣府の表、英語なら英語名。
        #expect(today(2026, 1, 1, region: "JP", language: "ja")?.name == "元日")
        #expect(today(2026, 1, 1, region: "JP", language: "en")?.name == "New Year's Day")
        #expect(today(2026, 1, 1, region: "JP", language: "en")?.countryCode == "JP")
        // 言語が分からなければ言語によらない表。
        #expect(today(2026, 12, 25, region: "DE", language: nil)?.name == "Erster Weihnachtstag")
    }

    @Test
    func japaneseSubstituteAndCitizensHolidaysAreNamed() {
        #expect(today(2026, 5, 6, region: "JP", language: "ja")?.name == "振替休日")
        #expect(today(2008, 5, 6, region: "JP", language: "ja")?.name == "振替休日") // 5/4（日）みどりの日の振替
        #expect(today(2009, 9, 22, region: "JP", language: "ja")?.name == "国民の休日") // 敬老の日と秋分の日に挟まれた日
        #expect(today(2019, 4, 30, region: "JP", language: "ja")?.name == "国民の休日")
        // 内閣府の表の後（2028 年以降）も補ってある。
        #expect(today(2030, 1, 1, region: "JP", language: "ja")?.name == "元日")
        #expect(today(2050, 11, 3, region: "JP", language: "ja")?.name == "文化の日")
    }

    @Test
    func userTablesInTheLanguageFolderComeBeforeOtherTables() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ourin-holiday-lang-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("en"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("2026/12/25,Christmas (user, en)\n".utf8).write(to: dir.appendingPathComponent("en/holidays-DE.txt"))
        try Data("2026/12/25,Weihnachten (user)\n".utf8).write(to: dir.appendingPathComponent("holidays-DE.txt"))
        func name(_ language: String?) -> String? {
            HolidayInfoProvider.today(now: date(2026, 12, 25), calendar: utc, regionCode: "DE",
                                      sources: .init(userDirectory: dir, bundle: .main, language: language))?.name
        }
        #expect(name("en") == "Christmas (user, en)")
        #expect(name("ja") == "Weihnachten (user)")
        #expect(name(nil) == "Weihnachten (user)")
    }

    @Test
    func everyBundledTableParsesAndUsesISOCodes() throws {
        let resources = try #require(Bundle.main.resourceURL)
        let files = try FileManager.default.contentsOfDirectory(atPath: resources.path).filter { $0.hasPrefix("holidays-") && $0.hasSuffix(".txt") }
        #expect(files.count > 200)
        for file in files {
            let code = String(file.dropFirst("holidays-".count).dropLast(".txt".count))
            #expect(code.count == 2 && code == code.uppercased(), "\(file)")
            let table = HolidayTable(text: try String(contentsOf: resources.appendingPathComponent(file), encoding: .utf8))
            #expect(!table.isEmpty, "\(file)")
        }
    }
}
