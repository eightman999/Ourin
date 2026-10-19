import Testing
@testable import Ourin

struct DisplayHandoverTests {
    @Test
    func startupReferencesUseInitAndEmptyPreviousDisplay() {
        let params = EventReferenceTable.params(forEvent: "OnDisplayHandover", refs: [
            "state": "init",
            "scopeID": "1",
            "previousDisplay": "",
            "currentDisplay": "0,0,1920,1080,32,1"
        ])

        #expect(params == [
            "Reference0": "init",
            "Reference1": "1",
            "Reference2": "",
            "Reference3": "0,0,1920,1080,32,1"
        ])
    }

    @Test
    func updateReferencesPreservePreviousAndCurrentMonitorRecords() {
        let params = EventReferenceTable.params(forEvent: "OnDisplayHandover", refs: [
            "state": "update",
            "scopeID": "0",
            "previousDisplay": "0,0,1920,1080,32,1",
            "currentDisplay": "1920,0,3840,1080,32,0"
        ])

        #expect(params["Reference0"] == "update")
        #expect(params["Reference1"] == "0")
        #expect(params["Reference2"] == "0,0,1920,1080,32,1")
        #expect(params["Reference3"] == "1920,0,3840,1080,32,0")
    }
}
