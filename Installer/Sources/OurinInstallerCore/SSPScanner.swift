import Foundation

/// SSP フォルダ内の移行できるゴースト・バルーン。
public struct MigrationItem: Identifiable, Hashable {
    public enum Kind: String {
        case ghost
        case balloon
    }

    /// Ourin で動くかの見込み。
    public enum Compatibility: Hashable {
        /// 内蔵の YAYA／里々で動く。
        case supported(String)
        /// Windows 用 DLL の SHIORI。Ourin ではそのまま動かない可能性が高い。
        case windowsShiori(String)
        /// バルーンなど SHIORI と関係ないもの。
        case notApplicable
    }

    public var id: String { "\(kind.rawValue)/\(directory)" }
    public let kind: Kind
    /// SSP 側のディレクトリ名。移行先でも同じ名前を使う。
    public let directory: String
    public let name: String
    public let source: URL
    public let compatibility: Compatibility
}

public enum SSPScanner {
    public static func scan(root: URL, fileManager fm: FileManager = .default) -> [MigrationItem] {
        ghosts(in: root, fileManager: fm) + balloons(in: root, fileManager: fm)
    }

    static func ghosts(in root: URL, fileManager fm: FileManager) -> [MigrationItem] {
        subdirectories(of: root.appendingPathComponent("ghost", isDirectory: true), fileManager: fm).compactMap { dir in
            let master = dir.appendingPathComponent("ghost/master", isDirectory: true)
            guard let descript = DescriptReader.read(master.appendingPathComponent("descript.txt")) else {
                return nil
            }
            let name = descript["name"].flatMap { $0.isEmpty ? nil : $0 } ?? dir.lastPathComponent
            return MigrationItem(kind: .ghost, directory: dir.lastPathComponent, name: name,
                                 source: dir, compatibility: compatibility(shiori: descript["shiori"]))
        }
    }

    static func balloons(in root: URL, fileManager fm: FileManager) -> [MigrationItem] {
        subdirectories(of: root.appendingPathComponent("balloon", isDirectory: true), fileManager: fm).compactMap { dir in
            guard let descript = DescriptReader.read(dir.appendingPathComponent("descript.txt")) else {
                return nil
            }
            let name = descript["name"].flatMap { $0.isEmpty ? nil : $0 } ?? dir.lastPathComponent
            return MigrationItem(kind: .balloon, directory: dir.lastPathComponent, name: name,
                                 source: dir, compatibility: .notApplicable)
        }
    }

    /// Ourin 本体の ShioriRuntimeFactory と同じ規則で、内蔵ランタイムが使えるかを判定する。
    /// shiori 指定が無いゴーストは本体と同じく yaya.dll 扱い。
    public static func compatibility(shiori: String?) -> MigrationItem.Compatibility {
        let module = (shiori?.isEmpty == false ? shiori! : "yaya.dll")
        var base = URL(fileURLWithPath: module).deletingPathExtension().lastPathComponent.lowercased()
        if base.hasPrefix("lib") { base = String(base.dropFirst(3)) }
        switch base {
        case "yaya", "yaya_core":
            return .supported("YAYA")
        case "satori", "satoriya", "satori_core":
            return .supported("里々")
        default:
            return .windowsShiori(module)
        }
    }

    private static func subdirectories(of dir: URL, fileManager fm: FileManager) -> [URL] {
        let children = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                    options: [.skipsHiddenFiles])) ?? []
        return children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
