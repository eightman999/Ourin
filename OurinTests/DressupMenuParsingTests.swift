import Foundation
import Testing
@testable import Ourin

struct DressupMenuParsingTests {
    @Test
    func parseBindGroupMenuItemAndDefault() throws {
        let descript = """
        sakura.bindgroup0.name,衣装,標準,thumb/default.png
        sakura.bindgroup0.default,1
        sakura.bindgroup1.name,帽子,赤帽子,thumb/red.png
        sakura.bindgroup1.default,0
        sakura.menuitem0,1
        sakura.menuitem1,0
        """

        let parsed = GhostManager.parseDressupMetadata(content: descript)
        let groups = parsed.bindGroupNameByScope[0]
        #expect(groups?.count == 2)
        #expect(groups?[0]?.category == "衣装")
        #expect(groups?[0]?.part == "標準")
        #expect(groups?[0]?.thumbnail == "thumb/default.png")
        #expect(parsed.bindGroupDefaultByScope[0]?[0] == true)
        #expect(groups?[1]?.category == "帽子")
        #expect(parsed.bindGroupDefaultByScope[0]?[1] == false)
        #expect(parsed.menuItemsByScope[0]?[0] == 1)
        #expect(parsed.menuItemsByScope[0]?[1] == 0)
    }

    @Test
    func menuEntriesFollowMenuItemOrder() throws {
        let descript = """
        sakura.bindgroup0.name,衣装,標準
        sakura.bindgroup1.name,帽子,赤帽子
        sakura.bindgroup2.name,靴,ブーツ
        sakura.menuitem0,2
        sakura.menuitem1,0
        """

        let parsed = GhostManager.parseDressupMetadata(content: descript)
        let groups = parsed.bindGroupNameByScope[0] ?? [:]
        let menu = parsed.menuItemsByScope[0] ?? [:]
        var used: Set<Int> = []
        var order: [Int] = []
        for (_, bindID) in menu.sorted(by: { $0.key < $1.key }) {
            if groups[bindID] != nil {
                order.append(bindID)
                used.insert(bindID)
            }
        }
        order.append(contentsOf: groups.keys.filter { !used.contains($0) }.sorted())
        #expect(order == [2, 0, 1])
    }
}
