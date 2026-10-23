import Foundation

/// Argon2id（RFC 9106、バージョン 1.3）。メモリ・パスの上限は呼び出し側で決める。
enum InternalArgon2Core {
    private static let blockWords = 128

    static func deriveID(password: Data, salt: Data, iterations: Int, memoryKiB: Int, lanes: Int, length: Int,
                         secret: Data = Data(), associatedData: Data = Data()) -> Data {
        func le32(_ value: Int) -> Data { Data((0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }) }
        var seed = le32(lanes) + le32(length) + le32(memoryKiB) + le32(iterations) + le32(0x13) + le32(2)
        seed += le32(password.count) + password + le32(salt.count) + salt + le32(secret.count) + secret + le32(associatedData.count) + associatedData
        let h0 = Blake2b.hash(seed, outputLength: 64)

        let blocks = 4 * lanes * (memoryKiB / (4 * lanes))
        let laneLength = blocks / lanes
        let segmentLength = laneLength / 4
        var memory = [UInt64](repeating: 0, count: blocks * blockWords)

        func load(_ data: Data, into block: Int) {
            data.withUnsafeBytes { raw in
                for word in 0..<blockWords { memory[block * blockWords + word] = UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: word * 8, as: UInt64.self)) }
            }
        }
        for lane in 0..<lanes {
            load(variableHash(h0 + le32(0) + le32(lane), 1024), into: lane * laneLength)
            load(variableHash(h0 + le32(1) + le32(lane), 1024), into: lane * laneLength + 1)
        }

        var scratchA = [UInt64](repeating: 0, count: blockWords)
        var scratchB = [UInt64](repeating: 0, count: blockWords)
        var zero = [UInt64](repeating: 0, count: blockWords)
        for pass in 0..<iterations {
            for slice in 0..<4 {
                for lane in 0..<lanes {
                    let independent = pass == 0 && slice < 2
                    var input = [UInt64](repeating: 0, count: blockWords)
                    var address = [UInt64](repeating: 0, count: blockWords)
                    if independent {
                        input[0] = UInt64(pass); input[1] = UInt64(lane); input[2] = UInt64(slice)
                        input[3] = UInt64(blocks); input[4] = UInt64(iterations); input[5] = 2
                    }
                    func nextAddresses() {
                        input[6] += 1
                        compress(prev: zero, ref: input, into: &address, xor: false, tmp: &scratchA, tmp2: &scratchB)
                        let copy = address
                        compress(prev: zero, ref: copy, into: &address, xor: false, tmp: &scratchA, tmp2: &scratchB)
                    }
                    var start = 0
                    if pass == 0 && slice == 0 {
                        start = 2
                        if independent { nextAddresses() }
                    }
                    for index in start..<segmentLength {
                        let current = lane * laneLength + slice * segmentLength + index
                        let previous = current % laneLength == 0 ? current + laneLength - 1 : current - 1
                        let random: UInt64
                        if independent {
                            if index % blockWords == 0 { nextAddresses() }
                            random = address[index % blockWords]
                        } else {
                            random = memory[previous * blockWords]
                        }
                        let j1 = Int(random & 0xFFFF_FFFF), j2 = Int(random >> 32)
                        let refLane = (pass == 0 && slice == 0) ? lane : j2 % lanes
                        let sameLane = refLane == lane
                        let area: Int
                        if pass == 0 {
                            if slice == 0 { area = index - 1 }
                            else if sameLane { area = slice * segmentLength + index - 1 }
                            else { area = slice * segmentLength + (index == 0 ? -1 : 0) }
                        } else if sameLane {
                            area = laneLength - segmentLength + index - 1
                        } else {
                            area = laneLength - segmentLength + (index == 0 ? -1 : 0)
                        }
                        let squared = (UInt64(j1) * UInt64(j1)) >> 32
                        let relative = area - 1 - Int((UInt64(area) * squared) >> 32)
                        var startPosition = 0
                        if pass != 0 { startPosition = slice == 3 ? 0 : (slice + 1) * segmentLength }
                        let refIndex = refLane * laneLength + (startPosition + relative) % laneLength

                        let prevBlock = Array(memory[(previous * blockWords)..<((previous + 1) * blockWords)])
                        let refBlock = Array(memory[(refIndex * blockWords)..<((refIndex + 1) * blockWords)])
                        var out = Array(memory[(current * blockWords)..<((current + 1) * blockWords)])
                        compress(prev: prevBlock, ref: refBlock, into: &out, xor: pass != 0, tmp: &scratchA, tmp2: &scratchB)
                        memory.replaceSubrange((current * blockWords)..<((current + 1) * blockWords), with: out)
                    }
                }
            }
        }
        zero = []

        var final = [UInt64](repeating: 0, count: blockWords)
        for lane in 0..<lanes {
            let last = lane * laneLength + laneLength - 1
            for word in 0..<blockWords { final[word] ^= memory[last * blockWords + word] }
        }
        var bytes = Data(capacity: 1024)
        for word in final { for shift in 0..<8 { bytes.append(UInt8(truncatingIfNeeded: word >> UInt64(8 * shift))) } }
        return variableHash(bytes, length)
    }

    /// H'（可変長の出力）。
    private static func variableHash(_ input: Data, _ length: Int) -> Data {
        let prefix = Data((0..<4).map { UInt8(truncatingIfNeeded: length >> (8 * $0)) })
        if length <= 64 { return Blake2b.hash(prefix + input, outputLength: length) }
        var output = Data()
        var block = Blake2b.hash(prefix + input, outputLength: 64)
        output.append(block.prefix(32))
        var remaining = length - 32
        while remaining > 64 {
            block = Blake2b.hash(block, outputLength: 64)
            output.append(block.prefix(32))
            remaining -= 32
        }
        output.append(Blake2b.hash(block, outputLength: remaining))
        return output
    }

    /// 圧縮関数 G。`next = P(ref ^ prev) ^ ref ^ prev`（`xor` なら更に `next` を XOR）。
    private static func compress(prev: [UInt64], ref: [UInt64], into next: inout [UInt64], xor: Bool, tmp: inout [UInt64], tmp2: inout [UInt64]) {
        var r = [UInt64](repeating: 0, count: blockWords)
        for index in 0..<blockWords { r[index] = ref[index] ^ prev[index] }
        var mixed = r
        if xor { for index in 0..<blockWords { mixed[index] ^= next[index] } }
        for row in 0..<8 {
            let base = row * 16
            permute(&r, [Int](base..<(base + 16)))
        }
        for column in 0..<8 {
            var indices: [Int] = []
            for row in 0..<8 {
                let base: Int = 2 * column + 16 * row
                indices.append(base)
                indices.append(base + 1)
            }
            permute(&r, indices)
        }
        for index in 0..<blockWords { next[index] = r[index] ^ mixed[index] }
    }

    private static func permute(_ v: inout [UInt64], _ i: [Int]) {
        func rotr(_ x: UInt64, _ n: UInt64) -> UInt64 { x >> n | x << (64 - n) }
        func mix(_ x: UInt64, _ y: UInt64) -> UInt64 {
            let product: UInt64 = (x & 0xFFFF_FFFF) &* (y & 0xFFFF_FFFF)
            return x &+ y &+ (product &* 2)
        }
        func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            let (a, b, c, d) = (i[a], i[b], i[c], i[d])
            v[a] = mix(v[a], v[b]); v[d] = rotr(v[d] ^ v[a], 32)
            v[c] = mix(v[c], v[d]); v[b] = rotr(v[b] ^ v[c], 24)
            v[a] = mix(v[a], v[b]); v[d] = rotr(v[d] ^ v[a], 16)
            v[c] = mix(v[c], v[d]); v[b] = rotr(v[b] ^ v[c], 63)
        }
        g(0, 4, 8, 12); g(1, 5, 9, 13); g(2, 6, 10, 14); g(3, 7, 11, 15)
        g(0, 5, 10, 15); g(1, 6, 11, 12); g(2, 7, 8, 13); g(3, 4, 9, 14)
    }
}
