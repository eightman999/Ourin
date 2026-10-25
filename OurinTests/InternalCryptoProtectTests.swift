import Foundation
import Testing
@testable import Ourin

private struct ProtectOutcome {
    var status: Int
    var result: String?
    var error: String?
}

private func protect(_ function: String, _ arguments: [String]) -> ProtectOutcome {
    var lines = ["EXECUTE SAORI/1.0", "Charset: UTF-8", "Sender: test", "Module: internal_crypto", "Argument0: \(function)"]
    for (index, value) in arguments.enumerated() { lines.append("Argument\(index + 1): \(value)") }
    let response = try! SaoriProtocol.parseResponse(InternalSaoriRegistry.shared.handle(requestText: lines.joined(separator: "\r\n") + "\r\n\r\n", context: .none))
    return ProtectOutcome(status: response.statusCode, result: response.headerValue("Result"), error: response.headerValue("ErrorDescription"))
}

struct InternalCryptoProtectTests {
    @Test
    func protectedDataRoundTripsForBothScopes() throws {
        for scope in ["user", "machine"] {
            let wrapped = protect("Protect", ["token-桜", "--scope=\(scope)"])
            #expect(wrapped.status == 200, "\(wrapped.error ?? "")")
            let blob = try InternalSaoriCodec.decodeBase64(wrapped.result ?? "")
            #expect(blob.count == 2 + 12 + "token-桜".utf8.count + 16)
            #expect(blob[1] == (scope == "user" ? 1 : 2))
            #expect(protect("Unprotect", [wrapped.result ?? ""]).result == "token-桜")
            // nonce は毎回違う。
            #expect(protect("Protect", ["token-桜", "--scope=\(scope)"]).result != wrapped.result)
        }
        // 既定は user。形式の指定。
        let hex = protect("Protect", ["00ff10", "--data-in=hex", "--out=hex"])
        #expect(protect("Unprotect", [hex.result ?? "", "--data-in=hex", "--out=hex"]).result == "00ff10")
        #expect(protect("Unprotect", [protect("Protect", [""]).result ?? ""]).status == 204 || protect("Unprotect", [protect("Protect", [""]).result ?? ""]).result == "")
    }

    @Test
    func tamperedOrForeignDataCannotBeRestored() throws {
        let wrapped = try #require(protect("Protect", ["secret"]).result)
        var blob = try InternalSaoriCodec.decodeBase64(wrapped)
        // 範囲の書き換え・暗号文の書き換え・短すぎる・知らない版。
        for index in [0, 1, 5, blob.count - 1] {
            var changed = blob
            changed[index] ^= (index == 1 ? 3 : 1)
            let outcome = protect("Unprotect", [changed.base64EncodedString()])
            #expect(outcome.status == 500 && outcome.error == "authentication failed", "index \(index): \(outcome.status) \(outcome.error ?? "")")
        }
        blob.removeLast(20)
        #expect(protect("Unprotect", [blob.base64EncodedString()]).error == "authentication failed")
        #expect(protect("Unprotect", ["AAAA"]).error == "authentication failed")
        #expect(protect("Unprotect", ["not base64!"]).error == "invalid encoding")
        #expect(protect("Protect", ["x", "--scope=everyone"]).error == "invalid parameter")
    }
}
