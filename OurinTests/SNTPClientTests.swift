import Foundation
import Testing
@testable import Ourin

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
