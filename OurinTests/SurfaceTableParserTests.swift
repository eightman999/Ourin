import Testing
import Foundation
@testable import Ourin

@Test
func surfaceTableParsesBasicGroupsAndEntries() {
    let text = """
    charset,Shift_JIS
    version,1

    group,エミリ
    {
        scope,0

        0,素
        1,照れ
        3,不安
    }

    group,テディ
    {
        scope,1

        10,素
        11,笑
    }
    """
    let table = SurfaceTableParser.parse(text)
    #expect(table.disableNoDefineSurfaces == false)
    #expect(table.groups.count == 2)
    #expect(table.groups[0].name == "エミリ")
    #expect(table.groups[0].scope == 0)
    #expect(table.groups[0].entries.count == 3)
    #expect(table.groups[0].entries[0] == SurfaceEntry(surfaceID: 0, name: "素"))
    #expect(table.groups[0].entries[2] == SurfaceEntry(surfaceID: 3, name: "不安"))
    #expect(table.groups[1].name == "テディ")
    #expect(table.groups[1].scope == 1)
    #expect(table.groups[1].entries[0] == SurfaceEntry(surfaceID: 10, name: "素"))
}

@Test
func surfaceTableDetectsDisableNoDefineSurfacesOption() {
    let text = """
    charset,Shift_JIS
    version,1
    option,DisableNoDefineSurfaces

    group,本体
    {
        scope,0
        0,通常
    }
    """
    let table = SurfaceTableParser.parse(text)
    #expect(table.disableNoDefineSurfaces == true)
    #expect(table.definedSurfaceIDs == [0])
}

@Test
func surfaceTablePreservesDisabledGroupAndPartsMarker() {
    let text = """
    group,__disabled
    {
        4000,__parts
        4001,__parts
    }

    group,本体
    {
        scope,0
        0,通常
    }
    """
    let table = SurfaceTableParser.parse(text)
    #expect(table.groups.count == 2)
    #expect(table.groups[0].name == "__disabled")
    #expect(table.groups[0].entries[0] == SurfaceEntry(surfaceID: 4000, name: "__parts"))
    // __disabled グループのIDも定義済みID集合に含まれる（描画は許可）
    #expect(table.definedSurfaceIDs == [4000, 4001, 0])
}

@Test
func surfaceTableSkipsCommentsAndBlankEntries() {
    let text = """
    group,本体
    {
        scope,0
        // これはコメント
        0,通常
        //	124,魔法陣右閉じ
        5,笑
    }
    """
    let table = SurfaceTableParser.parse(text)
    #expect(table.groups[0].entries.count == 2)
    #expect(table.groups[0].entries.map { $0.surfaceID } == [0, 5])
}

@Test
func surfaceTableHandlesEmptyNameEntry() {
    let text = """
    group,本体
    {
        scope,0
        0,
        1,名前付き
    }
    """
    let table = SurfaceTableParser.parse(text)
    #expect(table.groups[0].entries[0] == SurfaceEntry(surfaceID: 0, name: ""))
    #expect(table.groups[0].entries[1] == SurfaceEntry(surfaceID: 1, name: "名前付き"))
}

@Test
func surfaceTableHandlesMissingScope() throws {
    let text = """
    group,その他
    {
        500,おやつ
    }
    """
    let table = SurfaceTableParser.parse(text)
    let group = try #require(table.groups.first)
    #expect(group.scope == nil)
    #expect(group.entries[0] == SurfaceEntry(surfaceID: 500, name: "おやつ"))
}

@Test
func loadSurfaceTableReturnsNilWhenAbsent() throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent("OurinSurfaceTableMissing-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    #expect(SurfaceDefinitionLoader.loadSurfaceTable(from: tmp) == nil)
}

@Test
func loadSurfaceTableParsesRealFile() throws {
    let shellURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("emily4")
        .appendingPathComponent("shell")
        .appendingPathComponent("master")
    guard FileManager.default.fileExists(atPath: shellURL.appendingPathComponent("surfacetable.txt").path) else {
        // emily4 サンプルシェルが無い環境では検証をスキップ（暗黙パス扱い）
        return
    }

    guard let table = SurfaceDefinitionLoader.loadSurfaceTable(from: shellURL) else {
        Issue.record("expected non-nil SurfaceTable for emily4 sample")
        return
    }
    // emily4 には __disabled / エミリ / テディ / エミリ王 / その他 の5グループがある
    #expect(table.groups.count == 5)
    #expect(table.groups[0].name == "__disabled")
    // __disabled グループの全エントリは __parts
    #expect(table.groups[0].entries.allSatisfy { $0.name == "__parts" })
    // scope=0 のグループ（エミリ）の先頭は素サーフェス (id=0)
    let sakura = table.groups.first { $0.scope == 0 && !$0.name.hasPrefix("__") }
    #expect(sakura?.scope == 0)
    #expect(sakura?.entries.first?.surfaceID == 0)
    // definedSurfaceIDs に主要サーフェスが含まれる
    #expect(table.definedSurfaceIDs.contains(0))
    #expect(table.definedSurfaceIDs.contains(4000))
}
