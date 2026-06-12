import Foundation
import Testing
@testable import Ourin

struct ReferenceOrderingTests {
    @Test
    func pluginRequestReferencesAreNumericallyOrdered() throws {
        let req = PluginRequest(
            method: .notify,
            id: "OnTest",
            references: [
                "Reference10": "ten",
                "Reference2": "two",
                "Reference0": "zero",
                "Reference1": "one"
            ]
        )
        let wire = PluginProtocolBuilder.buildRequest(req)
        let idx0 = try #require(wire.range(of: "Reference0: zero"))
        let idx1 = try #require(wire.range(of: "Reference1: one"))
        let idx2 = try #require(wire.range(of: "Reference2: two"))
        let idx10 = try #require(wire.range(of: "Reference10: ten"))
        #expect(idx0.lowerBound < idx1.lowerBound)
        #expect(idx1.lowerBound < idx2.lowerBound)
        #expect(idx2.lowerBound < idx10.lowerBound)
    }
}
