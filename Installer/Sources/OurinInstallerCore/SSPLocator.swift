import Foundation

/// Mac 上の Wine 系環境に置かれた SSP を探す。
///
/// SSP はインストール先を問わないポータブルアプリなので、既知の bottle の
/// `drive_c` 配下を浅く走査し、`ghost/` を持つフォルダに `ssp.exe` があるものを SSP とみなす。
public struct SSPLocator {
    public struct Candidate: Hashable {
        public let root: URL
        /// どの環境で見つけたか（表示用）。
        public let source: String
    }

    let home: URL
    let fileManager: FileManager
    /// drive_c からの最大走査深さ。`Program Files/SSP` や `users/<name>/Desktop/ssp` まで届く値。
    let maxDepth: Int

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                fileManager: FileManager = .default,
                maxDepth: Int = 4) {
        self.home = home
        self.fileManager = fileManager
        self.maxDepth = maxDepth
    }

    /// 走査対象の `drive_c` と、その環境名。
    func driveRoots() -> [(URL, String)] {
        var roots: [(URL, String)] = []
        let wine = home.appendingPathComponent(".wine/drive_c", isDirectory: true)
        if isDirectory(wine) { roots.append((wine, "Wine")) }

        let bottleParents: [(String, String)] = [
            ("Library/Application Support/CrossOver/Bottles", "CrossOver"),
            ("Library/Containers/com.isaacmarovitz.Whisky/Bottles", "Whisky"),
        ]
        for (relative, label) in bottleParents {
            let parent = home.appendingPathComponent(relative, isDirectory: true)
            let bottles = (try? fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles])) ?? []
            for bottle in bottles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let drive = bottle.appendingPathComponent("drive_c", isDirectory: true)
                if isDirectory(drive) { roots.append((drive, "\(label)（\(bottle.lastPathComponent)）")) }
            }
        }
        return roots
    }

    public func locate() -> [Candidate] {
        var found: [Candidate] = []
        for (drive, label) in driveRoots() {
            for root in scan(drive, depth: 0) {
                found.append(Candidate(root: root, source: label))
            }
        }
        return found
    }

    private func scan(_ dir: URL, depth: Int) -> [URL] {
        if Self.isSSPRoot(dir, fileManager: fileManager) { return [dir] }
        guard depth < maxDepth else { return [] }
        let children = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                             options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
        var result: [URL] = []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // Wine は dosdevices などでホームや / へのリンクを張るので、リンクは辿らない。
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if Self.skippedDirectoryNames.contains(child.lastPathComponent.lowercased()) { continue }
            result.append(contentsOf: scan(child, depth: depth + 1))
        }
        return result
    }

    /// SSP 本体があるフォルダか。手動で選ばれたフォルダの検証にも使う。
    public static func isSSPRoot(_ dir: URL, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: dir.appendingPathComponent("ghost").path, isDirectory: &isDir),
              isDir.boolValue else { return false }
        let names = (try? fileManager.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.contains { $0.lowercased() == "ssp.exe" }
    }

    /// 手動選択用：SSP 本体が無くても、ゴースト／バルーンのフォルダがあれば移行元として受け付ける。
    public static func isMigratableRoot(_ dir: URL, fileManager: FileManager = .default) -> Bool {
        ["ghost", "balloon"].contains { name in
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: dir.appendingPathComponent(name).path, isDirectory: &isDir)
                && isDir.boolValue
        }
    }

    /// 走査しても SSP が見つからない巨大フォルダ。
    static let skippedDirectoryNames: Set<String> = ["windows", "programdata", "dosdevices", "appdata"]

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
