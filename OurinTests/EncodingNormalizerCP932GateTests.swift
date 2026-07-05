import Foundation
import Testing
@testable import Ourin

/// "OurinAcceptCP932" 設定によるShift_JISフォールバックのゲート挙動を検証する。
struct EncodingNormalizerCP932GateTests {
    private let key = "OurinAcceptCP932"

    @Test
    func defaultsToAcceptingCP932() throws {
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        #expect(EncodingNormalizer.acceptsCP932 == true)
    }

    @Test
    func acceptsShiftJISFallbackWhenEnabled() throws {
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let sjis = "こんにちは".data(using: .shiftJIS)!
        let decoded = EncodingNormalizer.decode(sjis, charset: nil)
        #expect(decoded == "こんにちは")
    }

    @Test
    func rejectsShiftJISFallbackWhenDisabled() throws {
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let sjis = "こんにちは".data(using: .shiftJIS)!
        // UTF-8として解釈できないShift_JISバイト列は、CP932拒否設定下ではデコード失敗になる
        let decoded = EncodingNormalizer.decode(sjis, charset: nil)
        #expect(decoded == nil)
    }

    @Test
    func utf8StillAcceptedWhenCP932Disabled() throws {
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let utf8 = "こんにちは".data(using: .utf8)!
        let decoded = EncodingNormalizer.decode(utf8, charset: nil)
        #expect(decoded == "こんにちは")
    }

    @Test
    func explicitCharsetBypassesGate() throws {
        UserDefaults.standard.set(false, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // charsetが明示された場合はゲートの対象外（EncodingAdapter.decodeへ直行）
        let sjis = "こんにちは".data(using: .shiftJIS)!
        let decoded = EncodingNormalizer.decode(sjis, charset: "Shift_JIS")
        #expect(decoded == "こんにちは")
    }
}
