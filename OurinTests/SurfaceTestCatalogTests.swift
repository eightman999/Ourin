import Testing
import Foundation
@testable import Ourin

@Test
func surfaceTestCatalogRecognizesCommonAndScopeOneImageNames() {
    let ids = SurfaceTestCatalog.imageSurfaceIDs(fileNames: [
        "surface0.png",
        "surface0001.png",
        "surface10.png",
        "surface100@2x.png",
        "surface1abc.png",
        "surface2.pna",
        "thumbnail.png"
    ])

    #expect(ids == [0, 1, 10, 100])
}

@Test
func surfaceTestCatalogHidesDisabledGroupsAndAddsUnlistedImages() {
    let table = SurfaceTable(
        disableNoDefineSurfaces: true,
        groups: [
            SurfaceGroup(name: "__disabled", scope: nil, entries: [SurfaceEntry(surfaceID: 4000, name: "__parts")]),
            SurfaceGroup(name: "本体", scope: 0, entries: [SurfaceEntry(surfaceID: 0, name: "通常")])
        ]
    )

    let groups = SurfaceTestCatalog.makeGroups(
        surfaceTable: table,
        definitionIDs: [0, 1],
        imageIDs: [0, 2],
        nameAliases: ["smile": 1]
    )

    #expect(groups.map(\.name) == ["本体", "未分類（実ファイル・定義）"])
    #expect(groups[0].entries.map(\.surfaceID) == [0])
    #expect(groups[1].entries.map(\.surfaceID) == [1, 2])
    #expect(groups[1].entries[0].name == "smile")
}
