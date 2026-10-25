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
func loadSurfaceTableParsesFileFromShellDirectory() throws {
    let root = try TestGhostFixture.makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let shellURL = try TestGhostFixture.makeShell(in: root)
    try """
    charset,UTF-8
    version,1

    group,リン
    {
        scope,0
        0,素
        1,笑顔
    }
    """.write(to: shellURL.appendingPathComponent("surfacetable.txt"), atomically: true, encoding: .utf8)

    guard let table = SurfaceDefinitionLoader.loadSurfaceTable(from: shellURL) else {
        Issue.record("expected non-nil SurfaceTable for fixture shell")
        return
    }
    #expect(table.groups.first?.name == "リン")
    #expect(table.definedSurfaceIDs.contains(0))
    #expect(table.definedSurfaceIDs.contains(1))
}
