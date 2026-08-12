import Foundation
import Testing
@testable import Ourin

struct OSUpdateObserverTests {
    @Test
    func parsesSoftwareUpdateHistoryAndSortsNewestFirst() {
        let output = """
        Display Name                                       Version    Date
        ------------                                       -------    ----
        Command Line Tools for Xcode                       16.2       2025/07/17 21:24:08
        macOS Tahoe 26.5.1                                 26.5.1     2026/06/11 0:19:29
        """

        let history = OSUpdateObserver.parseHistory(output)

        #expect(history.count == 2)
        #expect(history[0].title == "macOS Tahoe 26.5.1")
        #expect(history[0].version == "26.5.1")
        #expect(history[0].status == "success")
        #expect(history[0].errorCode == "0")
        #expect(history[0].executedAt > history[1].executedAt)
    }

    @Test
    func startupUsesNotifyAndUpdateUsesGetWithHistoryReferences() {
        let executedAt = Date(timeIntervalSince1970: 1_754_953_169)
        let checkedAt = Date(timeIntervalSince1970: 1_754_953_200)
        let record = OSUpdateHistoryRecord(
            title: "macOS Tahoe 26.5.1",
            version: "26.5.1",
            executedAt: executedAt,
            status: "success",
            errorCode: "0"
        )
        let snapshot = OSUpdateSnapshot(checkedAt: checkedAt, history: [record])

        let initial = OSUpdateObserver.event(for: snapshot, initial: true)
        #expect(initial.id == .OnOSUpdateInfo)
        #expect(initial.delivery == .notify)
        #expect(initial.ignoreResponseScript)
        #expect(initial.params["Reference0"] == OSUpdateObserver.wireDate(checkedAt))
        #expect(initial.params["Reference1"] == OSUpdateObserver.wireDate(executedAt))
        #expect(initial.params["Reference2"] == record.wireValue)

        let update = OSUpdateObserver.event(for: snapshot, initial: false)
        #expect(update.delivery == .get)
        #expect(!update.ignoreResponseScript)
        #expect(update.params == initial.params)
    }

    @Test
    func missingHistoryProducesEmptyExecutionAndHistoryReferences() {
        let snapshot = OSUpdateSnapshot(checkedAt: nil, history: [])
        let event = OSUpdateObserver.event(for: snapshot, initial: true)

        #expect(event.params["Reference0"] == "")
        #expect(event.params["Reference1"] == "")
        #expect(event.params["Reference2"] == nil)
    }
}
