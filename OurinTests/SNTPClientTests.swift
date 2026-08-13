import Foundation
import Testing
@testable import Ourin

private final class SNTPCapturingRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var requests: [(method: String, id: String, refs: [String])] = []

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        requests.append((method, id, refs))
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

struct SNTPClientTests {
    @Test
    func requestUsesNTPv4ClientHeaderAndTimestamp() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.25)
        let packet = [UInt8](SNTPPacket.request(transmitDate: date))

        #expect(packet.count == SNTPPacket.packetLength)
        #expect(packet[0] == 0x23)
        #expect(packet[SNTPPacket.transmitTimestampOffset..<SNTPPacket.transmitTimestampOffset + 8].contains { $0 != 0 })
    }

    @Test
    func decodeCalculatesClockOffsetFromFourNTPTimestamps() throws {
        let sent = Date(timeIntervalSince1970: 1_700_000_000.25)
        let received = sent.addingTimeInterval(0.25)
        let serverReceived = sent.addingTimeInterval(0.10)
        let serverTransmitted = sent.addingTimeInterval(0.11)
        let request = [UInt8](SNTPPacket.request(transmitDate: sent))
        var response = [UInt8](repeating: 0, count: SNTPPacket.packetLength)
        response[0] = 0x24 // LI=0, VN=4, Mode=4 (server)
        response[1] = 1 // stratum 1
        response[24..<32] = request[40..<48]
        writeTimestamp(serverReceived, into: &response, at: 32)
        writeTimestamp(serverTransmitted, into: &response, at: 40)

        let measurement = try SNTPPacket.decode(
            Data(response),
            server: "time.example.test",
            sentAt: sent,
            receivedAt: received
        )

        #expect(measurement.server == "time.example.test")
        #expect(abs(measurement.offset - (-0.02)) < 0.001)
        #expect(measurement.offsetMilliseconds == -20)
        #expect(abs(measurement.serverDate.timeIntervalSince(received) - (-0.02)) < 0.001)
    }

    @Test
    func decodeRejectsClientModeAndShortPackets() {
        let sent = Date(timeIntervalSince1970: 1_700_000_000)
        let received = sent.addingTimeInterval(0.1)
        #expect(throws: SNTPClientError.self) {
            try SNTPPacket.decode(
                Data(repeating: 0, count: 10),
                server: "time.example.test",
                sentAt: sent,
                receivedAt: received
            )
        }

        var clientResponse = [UInt8](repeating: 0, count: SNTPPacket.packetLength)
        clientResponse[0] = 0x23
        #expect(throws: SNTPClientError.self) {
            try SNTPPacket.decode(
                Data(clientResponse),
                server: "time.example.test",
                sentAt: sent,
                receivedAt: received
            )
        }
    }

    @Test
    func clockAdjusterConvertsDateToNormalizedTimeval() {
        let value = SNTPClockAdjuster.timeValue(
            for: Date(timeIntervalSince1970: 1_700_000_000.123456)
        )

        #expect(value.tv_sec == 1_700_000_000)
        #expect(value.tv_usec == 123_456)
    }

    @Test
    func clockAdjusterClassifiesPermissionAndSystemFailures() {
        if case .failure(.permissionDenied) = SNTPClockAdjuster.result(for: -1, errorCode: EPERM) {
            // expected
        } else {
            Issue.record("EPERM が permissionDenied に分類されていない")
        }
        if case .failure(.systemFailure(5)) = SNTPClockAdjuster.result(for: -1, errorCode: 5) {
            // expected
        } else {
            Issue.record("一般エラーが systemFailure に分類されていない")
        }
        if case .success = SNTPClockAdjuster.result(for: 0, errorCode: 0) {
            // expected
        } else {
            Issue.record("成功コードが success に分類されていない")
        }
    }

    @MainActor
    @Test
    func successfulCorrectionEmitsExtendedAndStandardEvents() {
        EventBridge.shared.stop()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sntp-correction-test"))
        let runtime = SNTPCapturingRuntime()
        manager.shioriRuntime = runtime
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
            _ = manager.shutdown()
        }

        let localDate = Date()
        let serverDate = localDate.addingTimeInterval(1.5)
        manager.lastSntpMeasurement = SNTPMeasurement(
            server: "time.example.test",
            serverDate: serverDate,
            localDate: localDate,
            offset: 1.5
        )
        manager.lastSntpServerDate = serverDate
        manager.lastSntpServer = "time.example.test"
        var adjustedDate: Date?

        let corrected = manager.executeSNTPApply { date in
            adjustedDate = date
            return .success(())
        }

        #expect(corrected)
        #expect(adjustedDate != nil)
        #expect(runtime.requests.map(\.id) == ["OnSNTPCorrectEx", "OnSNTPCorrect"])
        #expect(runtime.requests.allSatisfy { $0.method == "NOTIFY" })
        #expect(runtime.requests.allSatisfy { $0.refs.count == 5 })
        #expect(runtime.requests[0].refs[0] == "time.example.test")
        #expect(Double(runtime.requests[0].refs[3]) ?? 0 > 1.0)
    }

    @MainActor
    @Test
    func failedCorrectionEmitsFailureOnly() {
        EventBridge.shared.stop()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sntp-correction-failure-test"))
        let runtime = SNTPCapturingRuntime()
        manager.shioriRuntime = runtime
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
            _ = manager.shutdown()
        }

        let serverDate = Date().addingTimeInterval(1)
        manager.lastSntpServerDate = serverDate
        manager.lastSntpServer = "time.example.test"

        let corrected = manager.executeSNTPApply { _ in
            .failure(.permissionDenied)
        }

        #expect(!corrected)
        #expect(runtime.requests.map(\.id) == ["OnSNTPFailure"])
        #expect(runtime.requests[0].refs == ["time.example.test"])
    }

    @MainActor
    @Test
    func pendingCorrectionAfterQueryEmitsCorrectionEvents() {
        EventBridge.shared.stop()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-sntp-pending-correction-test"))
        let runtime = SNTPCapturingRuntime()
        manager.shioriRuntime = runtime
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
            _ = manager.shutdown()
        }

        manager.pendingSntpCorrection = true
        let localDate = Date()
        let measurement = SNTPMeasurement(
            server: "time.example.test",
            serverDate: localDate.addingTimeInterval(0.75),
            localDate: localDate,
            offset: 0.75
        )

        let corrected = manager.processSNTPMeasurement(measurement) { _ in
            .success(())
        }

        #expect(corrected)
        #expect(!manager.pendingSntpCorrection)
        #expect(runtime.requests.map(\.id) == [
            "OnSNTPCompareEx", "OnSNTPCompare", "OnSNTPCorrectEx", "OnSNTPCorrect"
        ])
    }

    private func writeTimestamp(_ date: Date, into bytes: inout [UInt8], at offset: Int) {
        let ntpSeconds = date.timeIntervalSince1970 + SNTPPacket.unixEpochOffset
        let seconds = UInt64(ntpSeconds)
        let fraction = UInt64((ntpSeconds - Double(seconds)) * 4_294_967_296.0)
        writeUInt32(UInt32(seconds), into: &bytes, at: offset)
        writeUInt32(UInt32(fraction), into: &bytes, at: offset + 4)
    }

    private func writeUInt32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8((value >> 24) & 0xff)
        bytes[offset + 1] = UInt8((value >> 16) & 0xff)
        bytes[offset + 2] = UInt8((value >> 8) & 0xff)
        bytes[offset + 3] = UInt8(value & 0xff)
    }
}

struct MailBiffClientTests {
    @Test
    func scriptQueriesUnreadMailAndSupportsAccountSelection() {
        let script = MailBiffClient.appleScript(account: "personal\"account")

        #expect(script.contains("read status is false"))
        #expect(script.contains("set accountName to \"personal\\\"account\""))
        #expect(script.contains("return {unreadCount, unreadBytes, senderAndSubject}"))
        #expect(!script.contains("runningApplications"))
    }
}
