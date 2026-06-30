import Foundation

/// `surfacetable.txt` のパース結果（UKADOC: Shell設定 - surfacetable.txt）。
///
/// `surfacetable.txt` はサーフィステストダイアログ（`\![open,surfacetest]`）で表示する
/// サーフェス一覧のグループ分けメタデータであり、`surfaces.txt`（SERIKO 描画定義）とは別物。
/// 描画 element / animation / collision は持たない。
public struct SurfaceTable: Equatable {
    /// `option,DisableNoDefineSurfaces` の有無。
    /// true の場合、`surfaces.txt` にも `surfacetable.txt` にも定義がないサーフェスIDは
    /// 描画対象から除外する（UKADOC）。
    public let disableNoDefineSurfaces: Bool
    /// グループリスト（出現順）。
    public let groups: [SurfaceGroup]

    public init(disableNoDefineSurfaces: Bool, groups: [SurfaceGroup]) {
        self.disableNoDefineSurfaces = disableNoDefineSurfaces
        self.groups = groups
    }

    /// 全グループの全エントリのサーフェスIDを集約した集合。
    /// `DisableNoDefineSurfaces` 判定等に使用。
    public var definedSurfaceIDs: Set<Int> {
        Set(groups.flatMap { $0.entries.map { $0.surfaceID } })
    }
}

/// `surfacetable.txt` のグループ（`group,NAME { ... }`）。
public struct SurfaceGroup: Equatable {
    /// グループ名。`__disabled` は「使用されていない」ことを示すマーカー。
    public let name: String
    /// `scope,N`（0=sakura, 1=kero, ...）。未指定の場合 nil。
    public let scope: Int?
    /// グループ内のサーフェスエントリ（出現順）。
    public let entries: [SurfaceEntry]

    public init(name: String, scope: Int?, entries: [SurfaceEntry]) {
        self.name = name
        self.scope = scope
        self.entries = entries
    }
}

/// `surfacetable.txt` のエントリ（`id,name`）。
public struct SurfaceEntry: Equatable {
    public let surfaceID: Int
    /// サーフェス表示名。`__parts` はアニメーション/着せ替えパーツであることを示すマーカー。
    /// 名前省略時は空文字。
    public let name: String

    public init(surfaceID: Int, name: String) {
        self.surfaceID = surfaceID
        self.name = name
    }
}

/// `surfacetable.txt` パーサー。
///
/// 対応フォーマット（UKADOC 準拠）:
/// ```
/// charset,Shift_JIS
/// version,1
/// option,DisableNoDefineSurfaces
///
/// group,__disabled
/// {
///     4000,__parts
/// }
///
/// group,エミリ
/// {
///     scope,0
///     0,素
///     1,照れ
/// }
/// ```
public enum SurfaceTableParser {
    /// `surfacetable.txt` 形式のテキストをパースする。
    public static func parse(_ text: String) -> SurfaceTable {
        var disableNoDefineSurfaces = false
        var groups: [SurfaceGroup] = []
        var currentName: String? = nil
        var currentScope: Int? = nil
        var currentEntries: [SurfaceEntry] = []
        var inBlock = false

        func flushGroup() {
            guard let name = currentName else { return }
            groups.append(SurfaceGroup(name: name, scope: currentScope, entries: currentEntries))
            currentName = nil
            currentScope = nil
            currentEntries = []
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("//") { continue }

            if !inBlock {
                if line.hasPrefix("charset,") { continue }
                if line.hasPrefix("version,") { continue }
                if line.hasPrefix("option,") {
                    let opts = line.dropFirst("option,".count)
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                    if opts.contains("disablenodefinesurfaces") {
                        disableNoDefineSurfaces = true
                    }
                    continue
                }
                if line.hasPrefix("group,") {
                    flushGroup()
                    currentName = String(line.dropFirst("group,".count)).trimmingCharacters(in: .whitespaces)
                    continue
                }
                if line == "{" {
                    if currentName != nil { inBlock = true }
                    continue
                }
                continue
            }

            // ブロック内
            if line == "}" {
                inBlock = false
                flushGroup()
                continue
            }
            if line.hasPrefix("scope,") {
                let raw = String(line.dropFirst("scope,".count)).trimmingCharacters(in: .whitespaces)
                currentScope = Int(raw)
                continue
            }
            if let commaIdx = line.firstIndex(of: ",") {
                let idStr = String(line[..<commaIdx]).trimmingCharacters(in: .whitespaces)
                let nameStr = String(line[line.index(after: commaIdx)...]).trimmingCharacters(in: .whitespaces)
                if let id = Int(idStr) {
                    currentEntries.append(SurfaceEntry(surfaceID: id, name: nameStr))
                    continue
                }
            }
        }
        flushGroup()
        return SurfaceTable(disableNoDefineSurfaces: disableNoDefineSurfaces, groups: groups)
    }
}
