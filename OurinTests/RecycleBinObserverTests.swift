import Foundation
import Testing
@testable import Ourin

struct RecycleBinObserverTests {
    @Test
    func aggregatesTopLevelItemsAndDescendantSizes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinRecycleBinTest-\(UUID().uuidString)", isDirectory: true)
        let nested = directory.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let rootFile = directory.appendingPathComponent("root.txt")
        let nestedFile = nested.appendingPathComponent("nested.txt")
        try Data(repeating: 0x41, count: 7).write(to: rootFile)
        try Data(repeating: 0x42, count: 11).write(to: nestedFile)

        let snapshot = RecycleBinObserver.snapshot(at: [directory])
        #expect(snapshot.count == 2)
        #expect(snapshot.size >= 18)
    }

    @Test
    func statusUpdateReferencesUseStatusUpdateCompatibilityFields() {
        let params = EventReferenceTable.params(forEvent: "OnRecycleBinStatusUpdate", refs: [
            "count": "2",
            "size": "18",
            "countDelta": "1",
            "sizeDelta": "11",
            "success": "1",
            "ghostName": ""
        ])

        #expect(params == [
            "Reference0": "2",
            "Reference1": "18",
            "Reference2": "1",
            "Reference3": "11",
            "Reference4": "1",
            "Reference5": ""
        ])
    }
}
