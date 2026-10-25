import Foundation
import Testing
@testable import Ourin

struct InternalArgon2CoreTests {
    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    @Test
    func matchesRFC9106Argon2idVector() {
        // RFC 9106 §5.3: 秘密鍵と関連データ付き。p=4、m=32 KiB、t=3、タグ 32 バイト。
        let tag = InternalArgon2Core.deriveID(
            password: Data(repeating: 0x01, count: 32), salt: Data(repeating: 0x02, count: 16), iterations: 3, memoryKiB: 32, lanes: 4, length: 32,
            secret: Data(repeating: 0x03, count: 8), associatedData: Data(repeating: 0x04, count: 12))
        #expect(hex(tag) == "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659")
    }
}
