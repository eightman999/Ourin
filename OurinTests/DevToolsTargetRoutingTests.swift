import Testing
@testable import Ourin

struct DevToolsTargetRoutingTests {
    @Test
    func headlineBalloonSelectionInitializesFromInstalledData() {
        #expect(HeadlineBalloonSelection.initialGhost(
            current: "",
            installed: ["bonsyou", "emily4"]
        ) == "bonsyou")
        #expect(HeadlineBalloonSelection.initialGhost(
            current: "emily4",
            installed: ["bonsyou", "emily4"]
        ) == "emily4")
        #expect(HeadlineBalloonSelection.initialGhost(
            current: "missing",
            installed: ["bonsyou", "emily4"]
        ) == "bonsyou")
        #expect(HeadlineBalloonSelection.initialGhost(current: "", installed: []) == "")
    }

    @Test
    func selectionMatchesGhostConfigOrFolder() {
        #expect(AppDelegate.ghostSelectionMatches(
            "emily4",
            configName: "Emily/Phase4.5",
            folderName: "emily4"
        ))
        #expect(AppDelegate.ghostSelectionMatches(
            "Emily/Phase4.5",
            configName: "Emily/Phase4.5",
            folderName: "emily4"
        ))
        #expect(AppDelegate.ghostSelectionMatches(
            "%E3%81%95%E3%81%8F%E3%82%89",
            configName: "さくら",
            folderName: "sakura"
        ))
    }

    @Test
    func selectionDoesNotMatchDifferentGhostOrBlankValue() {
        #expect(!AppDelegate.ghostSelectionMatches(
            "bonsyou",
            configName: "Emily/Phase4.5",
            folderName: "emily4"
        ))
        #expect(!AppDelegate.ghostSelectionMatches(
            "   ",
            configName: "Emily/Phase4.5",
            folderName: "emily4"
        ))
    }
}
