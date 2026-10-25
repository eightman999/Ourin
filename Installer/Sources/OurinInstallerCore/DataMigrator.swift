import Foundation

/// SSP のゴースト・バルーンを Ourin のデータフォルダへコピーする。
///
/// 元データには一切手を加えない（移動ではなくコピー）。移行先に同名フォルダが
/// あれば Ourin 側が正として上書きしない。
public struct DataMigrator {
    public enum Outcome: Equatable {
        case copied(URL)
        case skippedExisting(URL)
        case failed(String)
    }

    public struct Result: Equatable {
        public let item: MigrationItem
        public let outcome: Outcome
    }

    let location: OurinDataLocation
    let fileManager: FileManager

    public init(location: OurinDataLocation, fileManager: FileManager = .default) {
        self.location = location
        self.fileManager = fileManager
    }

    public func destination(for item: MigrationItem) -> URL {
        let parent = item.kind == .ghost ? location.ghostDirectory : location.balloonDirectory
        return parent.appendingPathComponent(item.directory, isDirectory: true)
    }

    public func migrate(_ items: [MigrationItem]) -> [Result] {
        items.map { item in Result(item: item, outcome: migrate(item)) }
    }

    func migrate(_ item: MigrationItem) -> Outcome {
        // ディレクトリ名は SSP 側の実フォルダ名だが、念のため逸脱を拒否する。
        guard !item.directory.isEmpty, !item.directory.contains("/"),
              item.directory != ".", item.directory != ".." else {
            return .failed("不正なフォルダ名: \(item.directory)")
        }
        let target = destination(for: item)
        if fileManager.fileExists(atPath: target.path) { return .skippedExisting(target) }

        // 途中で失敗しても半端なフォルダを残さないよう、隣の一時名へコピーしてから改名する。
        let staging = target.deletingLastPathComponent()
            .appendingPathComponent(".\(item.directory).ourin-migrating-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: item.source, to: staging)
            try fileManager.moveItem(at: staging, to: target)
            return .copied(target)
        } catch {
            try? fileManager.removeItem(at: staging)
            return .failed(error.localizedDescription)
        }
    }
}
