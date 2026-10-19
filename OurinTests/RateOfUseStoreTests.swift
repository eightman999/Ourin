import Foundation
import Testing
@testable import Ourin

struct RateOfUseStoreTests {
    @Test
    func recordsSessionAndTalkData() throws {
        let suiteName = "OurinTests.RateOfUse.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RateOfUseStore(defaults: defaults)
        let identifier = "/tmp/ourin-rateofuse-\(UUID().uuidString)"
        store.beginSession(
            identifier: identifier,
            name: "Test Ghost",
            sakuraname: "Sakura",
            keroname: "Kero"
        )
        store.recordTalk(
            identifier: identifier,
            name: "Test Ghost",
            sakuraname: "Sakura",
            keroname: "Kero",
            characterCount: 12
        )

        let snapshot = try #require(store.snapshots().first)
        #expect(snapshot.id == identifier)
        #expect(snapshot.bootCount == 1)
        #expect(snapshot.talkCount == 1)
        #expect(snapshot.characterCount == 12)
        #expect(snapshot.percent == 100)

        store.endSession(identifier: identifier)
        let entry = try #require(store.entries().first)
        #expect(entry.boottime == 1)
        #expect(entry.bootminute == 0)
        #expect(entry.percent == 100)
    }
}
