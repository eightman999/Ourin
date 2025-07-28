import Testing
@testable import Ourin

struct PropertyTests {
    @Test
    func basewareName() async throws {
        let mgr = PropertyManager()
        #expect(mgr.get("baseware.name") == "Ourin")
    }

    @Test
    func ghostlistCount() async throws {
        let mgr = PropertyManager()
        #expect(mgr.get("ghostlist.count") == "1")
    }
}
