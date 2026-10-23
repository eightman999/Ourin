import Foundation

/// 今日の祝日名（OnNotifyHolidayInfo、UKADOC 2.9.11）。
struct HolidayInfo: Equatable {
    var name: String
    /// `2026,01,01` のようにカンマ区切り（月日は 0 埋め）。
    var date: String
    /// 読み込んだ祝日表の国コード（ISO 3166）。国別でない既定の表（holidays.txt）なら空。
    var countryCode: String

    var parameters: [String: String] {
        ["Reference0": name, "Reference1": date, "Reference2": countryCode]
    }
}

/// 祝日表（`年/月/日,名称` の行）。`#` で始まる行と日付で始まらない行（見出しなど）は無視する。
struct HolidayTable: Equatable {
    /// 年・月・日 → 名称。
    private(set) var names: [Int: String] = [:]

    init(text: String) {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let comma = line.firstIndex(of: ",") else { continue }
            let datePart = line[..<comma].trimmingCharacters(in: .whitespaces)
            let name = line[line.index(after: comma)...].trimmingCharacters(in: .whitespaces)
            let fields = datePart.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count == 3, !name.isEmpty,
                  let year = Int(fields[0]), let month = Int(fields[1]), let day = Int(fields[2]) else { continue }
            names[Self.key(year, month, day)] = name
        }
    }

    var isEmpty: Bool { names.isEmpty }

    func name(year: Int, month: Int, day: Int) -> String? {
        names[Self.key(year, month, day)]
    }

    private static func key(_ year: Int, _ month: Int, _ day: Int) -> Int {
        year * 10_000 + month * 100 + day
    }
}

enum HolidayInfoProvider {
    /// 祝日表を探す場所。ユーザーが置いた表（calendar/）を同梱の表より優先する。
    struct Sources {
        var userDirectory: URL?
        var bundle: Bundle?

        static var standard: Sources {
            Sources(userDirectory: try? OurinPaths.subdirectory("calendar"), bundle: .main)
        }
    }

    /// 地域設定の国別の表（holidays-XX.txt）、無ければ既定の表（holidays.txt）から今日の祝日名を引く。
    /// 祝日でない日、表が無い日、名前の載っていない祝日では nil（SSP と同じく何も送らない）。
    static func today(
        now: Date = Date(),
        calendar: Calendar = .current,
        regionCode: String? = Locale.current.regionCode,
        sources: Sources = .standard
    ) -> HolidayInfo? {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }

        var candidates: [(file: String, country: String)] = []
        if let region = regionCode?.uppercased(), !region.isEmpty {
            candidates.append(("holidays-\(region)", region))
        }
        candidates.append(("holidays", ""))

        for candidate in candidates {
            guard let text = loadTable(named: candidate.file, sources: sources) else { continue }
            let table = HolidayTable(text: text)
            // 国別の表が見つかったら、その表に載っていなくても既定の表へは進まない。
            guard let name = table.name(year: year, month: month, day: day) else { return nil }
            return HolidayInfo(
                name: name,
                date: String(format: "%04d,%02d,%02d", year, month, day),
                countryCode: candidate.country
            )
        }
        return nil
    }

    private static func loadTable(named name: String, sources: Sources) -> String? {
        if let directory = sources.userDirectory {
            let url = directory.appendingPathComponent("\(name).txt")
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        }
        guard let bundle = sources.bundle else { return nil }
        let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: "Holidays")
            ?? bundle.url(forResource: name, withExtension: "txt")
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
}

extension GhostManager {
    /// 起動時に、今日が祝日ならその名前を NOTIFY する（OnNotifyUserInfo の直後）。
    func sendHolidayInfoNotify() {
        guard let info = HolidayInfoProvider.today() else { return }
        EventBridge.shared.notify(.OnNotifyHolidayInfo, params: info.parameters)
    }
}
