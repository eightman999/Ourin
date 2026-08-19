import Foundation
import Testing
@testable import Ourin

/// DirectSSTP の XPC 入口が他の SSTP 入口と同じ文字コード互換性を持つことを検証する。
@Suite(.serialized)
struct DirectSSTPXPCEncodingTests {
    private let key = "OurinAcceptCP932"

    @Test
    func decodesCp932WhenCharsetIsOmitted() throws {
        cp932TestIsolationLock.lock()
        defer { cp932TestIsolationLock.unlock() }
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let request = "SEND SSTP/1.1\r\nSender: テスト\r\n\r\n".data(using: .shiftJIS)!
        #expect(DirectSSTPXPC.decodeRequest(request) == "SEND SSTP/1.1\r\nSender: テスト\r\n\r\n")
    }

    @Test
    func honorsDeclaredCharset() throws {
        cp932TestIsolationLock.lock()
        defer { cp932TestIsolationLock.unlock() }
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let request = "SEND SSTP/1.1\r\nCharset: Shift_JIS\r\nSender: テスト\r\n\r\n".data(using: .shiftJIS)!
        #expect(DirectSSTPXPC.decodeRequest(request)?.contains("Sender: テスト") == true)
    }

    @Test
    func rejectsCp932WhenDisabledAndCharsetIsOmitted() throws {
        cp932TestIsolationLock.lock()
        defer { cp932TestIsolationLock.unlock() }
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let request = "SEND SSTP/1.1\r\nSender: テスト\r\n\r\n".data(using: .shiftJIS)!
        #expect(DirectSSTPXPC.decodeRequest(request) == nil)
    }

    @Test
    func xpcRejectsCp932WhenDisabledAndCharsetIsOmitted() throws {
        cp932TestIsolationLock.lock()
        defer { cp932TestIsolationLock.unlock() }
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let request = "SEND SSTP/1.1\r\nSender: テスト\r\n\r\n".data(using: .shiftJIS)!
        #expect(XpcDirectServer.decodeRequest(request) == nil)
    }

    @Test
    func xpcAcceptsDeclaredShiftJISWhenCp932FallbackIsDisabled() throws {
        cp932TestIsolationLock.lock()
        defer { cp932TestIsolationLock.unlock() }
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let request = "SEND SSTP/1.1\r\nCharset: Shift_JIS\r\nSender: テスト\r\n\r\n".data(using: .shiftJIS)!
        #expect(XpcDirectServer.decodeRequest(request)?.contains("Sender: テスト") == true)
    }

    @Test
    func xpcReturnsBadRequestForInvalidEncoding() throws {
        cp932TestIsolationLock.lock()
        defer { cp932TestIsolationLock.unlock() }
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let request = "SEND SSTP/1.1\r\nSender: テスト\r\n\r\n".data(using: .shiftJIS)!
        let server = XpcDirectServer(machServiceName: "jp.ourin.tests.\(UUID().uuidString)")
        var response = Data()
        server.onRequest = { _ in
            "SSTP/1.1 500 Internal Server Error\r\n\r\n"
        }
        server.executeSSTP(request) { response = $0 }

        #expect(String(data: response, encoding: .utf8) == "SSTP/1.1 400 Bad Request\r\n\r\n")
    }
}
