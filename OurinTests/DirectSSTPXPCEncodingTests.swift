import Foundation
import Testing
@testable import Ourin

/// DirectSSTP の XPC 入口が他の SSTP 入口と同じ文字コード互換性を持つことを検証する。
struct DirectSSTPXPCEncodingTests {
    private let key = "OurinAcceptCP932"

    @Test
    func decodesCp932WhenCharsetIsOmitted() throws {
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let request = "SEND SSTP/1.1\r\nSender: テスト\r\n\r\n".data(using: .shiftJIS)!
        #expect(DirectSSTPXPC.decodeRequest(request) == "SEND SSTP/1.1\r\nSender: テスト\r\n\r\n")
    }

    @Test
    func honorsDeclaredCharset() throws {
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let request = "SEND SSTP/1.1\r\nCharset: Shift_JIS\r\nSender: テスト\r\n\r\n".data(using: .shiftJIS)!
        #expect(DirectSSTPXPC.decodeRequest(request)?.contains("Sender: テスト") == true)
    }

    @Test
    func rejectsCp932WhenDisabledAndCharsetIsOmitted() throws {
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let request = "SEND SSTP/1.1\r\nSender: テスト\r\n\r\n".data(using: .shiftJIS)!
        #expect(DirectSSTPXPC.decodeRequest(request) == nil)
    }
}
