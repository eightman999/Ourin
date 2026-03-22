import Foundation
import Testing
@testable import Ourin

struct SSTPExecuteMoveAsyncTests {
    @Test
    func executeMoveAsyncReturns200NoScript() async throws {
        // Command: moveasync scope x y time method ignoreSticky
        let req = SSTPRequest(
            method: "EXECUTE",
            version: "SSTP/1.4",
            headers: [
                "Command": "moveasync",
                "Reference0": "0",
                "Reference1": "120",
                "Reference2": "160",
                "Reference3": "250",
                "Reference4": "ease",
                "Reference5": "0"
            ]
        )
        let resp = SSTPDispatcher.dispatch(request: req)
        #expect(resp.contains("SSTP/1.4 200 OK"))
        #expect(!resp.contains("Script:"))
    }
}

