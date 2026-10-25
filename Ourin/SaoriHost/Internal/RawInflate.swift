import Foundation

/// 生の deflate（RFC 1951）の展開。入力のどこまで使ったかが分かる。
///
/// OS の圧縮フレームワークのデコーダは入力を先読みして、終端の位置を教えてくれない。
/// gzip の複数メンバーや、zlib / gzip の末尾のチェックサムを正確に扱うため、ここで実装する。
struct RawInflate {
    private let input: [UInt8]
    private var position: Int
    private var bitBuffer: UInt32 = 0
    private var bitCount = 0
    private let limit: Int
    private(set) var output: [UInt8] = []

    /// 長さと距離の符号の基数と、追加ビット数（RFC 1951 3.2.5）。
    private static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private struct Huffman {
        var count = [Int](repeating: 0, count: 16)
        var symbol: [Int]

        /// 符号長から正規ハフマン符号を作る。過剰なら負、不完全なら正を返す。
        init(lengths: [Int], result: inout Int) {
            symbol = [Int](repeating: 0, count: lengths.count)
            for length in lengths { count[length] += 1 }
            var left = 1
            for length in 1...15 {
                left <<= 1
                left -= count[length]
                if left < 0 { result = left; return }
            }
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<15 { offsets[length + 1] = offsets[length] + count[length] }
            for (index, length) in lengths.enumerated() where length != 0 {
                symbol[offsets[length]] = index
                offsets[length] += 1
            }
            result = left
        }
    }

    private static let fixedLiteral: Huffman = {
        var lengths = [Int](repeating: 8, count: 288)
        for index in 144..<256 { lengths[index] = 9 }
        for index in 256..<280 { lengths[index] = 7 }
        var result = 0
        return Huffman(lengths: lengths, result: &result)
    }()

    private static let fixedDistance: Huffman = {
        var result = 0
        return Huffman(lengths: [Int](repeating: 5, count: 30), result: &result)
    }()

    /// - Parameters:
    ///   - input: 圧縮データ。
    ///   - start: 展開を始める位置。
    ///   - limit: 展開後の大きさの上限（超えたら too large）。
    init(input: [UInt8], start: Int, limit: Int) {
        self.input = input
        self.position = start
        self.limit = limit
    }

    /// 最後のブロックまで展開する。入力のうち使い終わった位置（次のバイト）を返す。
    mutating func run() throws -> Int {
        var last = false
        repeat {
            last = try readBits(1) == 1
            switch try readBits(2) {
            case 0: try stored()
            case 1: try codes(literal: Self.fixedLiteral, distance: Self.fixedDistance)
            case 2: try dynamic()
            default: throw InternalSaoriError.invalidEncoding
            }
        } while !last
        // 読み進めた分のうち、使っていないビットは捨てる（バイト境界へ戻る）。
        return position - bitCount / 8
    }

    private mutating func readBits(_ need: Int) throws -> Int {
        var value = bitBuffer
        while bitCount < need {
            guard position < input.count else { throw InternalSaoriError.invalidEncoding } // 途中で切れている
            value |= UInt32(input[position]) << UInt32(bitCount)
            position += 1
            bitCount += 8
        }
        bitBuffer = need == 32 ? 0 : value >> UInt32(need)
        bitCount -= need
        return Int(value & ((1 << UInt32(need)) - 1))
    }

    private mutating func stored() throws {
        bitBuffer = 0
        bitCount = 0
        guard position + 4 <= input.count else { throw InternalSaoriError.invalidEncoding }
        let length = Int(input[position]) | Int(input[position + 1]) << 8
        let complement = Int(input[position + 2]) | Int(input[position + 3]) << 8
        guard length == (~complement & 0xFFFF) else { throw InternalSaoriError.invalidEncoding }
        position += 4
        guard position + length <= input.count else { throw InternalSaoriError.invalidEncoding }
        guard output.count + length <= limit else { throw InternalSaoriError.tooLarge }
        output.append(contentsOf: input[position..<(position + length)])
        position += length
    }

    private mutating func decode(_ huffman: Huffman) throws -> Int {
        var code = 0, first = 0, index = 0
        for length in 1...15 {
            code |= try readBits(1)
            let count = huffman.count[length]
            if code - count < first { return huffman.symbol[index + (code - first)] }
            index += count
            first += count
            first <<= 1
            code <<= 1
        }
        throw InternalSaoriError.invalidEncoding
    }

    private mutating func codes(literal: Huffman, distance: Huffman) throws {
        while true {
            let symbol = try decode(literal)
            if symbol < 256 {
                guard output.count < limit else { throw InternalSaoriError.tooLarge }
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let index = symbol - 257
                guard index < Self.lengthBase.count else { throw InternalSaoriError.invalidEncoding }
                let length = Self.lengthBase[index] + (try readBits(Self.lengthExtra[index]))
                let distanceSymbol = try decode(distance)
                guard distanceSymbol < Self.distanceBase.count else { throw InternalSaoriError.invalidEncoding }
                let back = Self.distanceBase[distanceSymbol] + (try readBits(Self.distanceExtra[distanceSymbol]))
                guard back <= output.count else { throw InternalSaoriError.invalidEncoding }
                guard output.count + length <= limit else { throw InternalSaoriError.tooLarge }
                let from = output.count - back
                for offset in 0..<length { output.append(output[from + offset]) }
            }
        }
    }

    private mutating func dynamic() throws {
        let literalCount = try readBits(5) + 257
        let distanceCount = try readBits(5) + 1
        let codeLengthCount = try readBits(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else { throw InternalSaoriError.invalidEncoding }

        var lengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount { lengths[Self.codeLengthOrder[index]] = try readBits(3) }
        var result = 0
        let codeLengthCode = Huffman(lengths: lengths, result: &result)
        guard result == 0 else { throw InternalSaoriError.invalidEncoding } // 完全な符号でなければならない

        var all = [Int](repeating: 0, count: literalCount + distanceCount)
        var index = 0
        while index < literalCount + distanceCount {
            let symbol = try decode(codeLengthCode)
            if symbol < 16 {
                all[index] = symbol
                index += 1
            } else {
                var value = 0
                var repeatCount = 0
                switch symbol {
                case 16:
                    guard index > 0 else { throw InternalSaoriError.invalidEncoding }
                    value = all[index - 1]
                    repeatCount = 3 + (try readBits(2))
                case 17: repeatCount = 3 + (try readBits(3))
                default: repeatCount = 11 + (try readBits(7))
                }
                guard index + repeatCount <= literalCount + distanceCount else { throw InternalSaoriError.invalidEncoding }
                for _ in 0..<repeatCount { all[index] = value; index += 1 }
            }
        }
        // ブロックの終端符号（256）が無いものは不正。
        guard all[256] != 0 else { throw InternalSaoriError.invalidEncoding }

        var literalResult = 0
        let literal = Huffman(lengths: Array(all[0..<literalCount]), result: &literalResult)
        // 不完全な符号は、符号が 1 種類だけのときに限って許す。
        guard literalResult == 0 || (literalResult > 0 && literalCount - literal.count[0] == 1) else { throw InternalSaoriError.invalidEncoding }
        var distanceResult = 0
        let distance = Huffman(lengths: Array(all[literalCount...]), result: &distanceResult)
        guard distanceResult == 0 || (distanceResult > 0 && distanceCount - distance.count[0] == 1) else { throw InternalSaoriError.invalidEncoding }
        try codes(literal: literal, distance: distance)
    }
}
