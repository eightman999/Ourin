import Foundation

struct CalendarSkin {
    let name: String
    let path: URL
    let descriptor: [String: String]
    let iconMap: [String: String]
}

struct CalendarPluginMeta {
    let name: String
    let id: String
    let filename: String
    let path: URL
    let post: String?
}

final class CalendarRegistry {
    static let shared = CalendarRegistry()

    private let fm: FileManager

    init(fileManager: FileManager = .default) {
        self.fm = fileManager
    }

    func calendarDirectory() -> URL? {
        try? OurinPaths.subdirectory("calendar")
    }

    func installedSkins() -> [CalendarSkin] {
        guard let root = calendarDirectory()?.appendingPathComponent("skin", isDirectory: true),
              let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        return entries.compactMap { dir in
            guard isDirectory(dir) else { return nil }
            let descript = LegacyDescriptor.readDictionary(from: dir.appendingPathComponent("descript.txt")) ?? [:]
            let name = descript["name"]?.isEmpty == false ? descript["name"]! : dir.lastPathComponent
            return CalendarSkin(
                name: name,
                path: dir,
                descriptor: descript,
                iconMap: readIconMap(from: dir.appendingPathComponent("icon.txt"))
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func installedPlugins() -> [CalendarPluginMeta] {
        guard let root = calendarDirectory()?.appendingPathComponent("plugin", isDirectory: true),
              let entries = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        return entries.compactMap { dir in
            guard isDirectory(dir),
                  let descript = LegacyDescriptor.readDictionary(from: dir.appendingPathComponent("descript.txt")) else {
                return nil
            }
            let filename = descript["filename"] ?? descript["dllname"] ?? ""
            guard !filename.isEmpty else { return nil }
            return CalendarPluginMeta(
                name: descript["name"] ?? dir.lastPathComponent,
                id: descript["id"] ?? "",
                filename: filename,
                path: dir,
                post: descript["post"]
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func readIconMap(from url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let text = LegacyDescriptor.decode(data) else { return [:] }
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") { continue }
            let parts = line.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty && !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
