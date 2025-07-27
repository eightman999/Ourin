
import Foundation
import ImageIO

/// ICO/CUR 形式の最小デコーダ実装。

public struct OurinIcoCurImage {
    public var width: Int
    public var height: Int
    public var isCursor: Bool
    public var hotspotX: Int
    public var hotspotY: Int
    public var pngPayload: Data? // if present, decode via Image I/O
    public var rgba: Data?       // 32bpp DIB decoded to RGBA
}

struct ICONDIR { var reserved: UInt16; var type: UInt16; var count: UInt16 }
struct ICONDIRENTRY {
    var width: UInt8; var height: UInt8; var colorCount: UInt8; var reserved: UInt8
    var planes_or_hotspotX: UInt16; var bpp_or_hotspotY: UInt16
    var bytesInRes: UInt32; var imageOffset: UInt32
}
struct BITMAPINFOHEADER {
    var biSize: UInt32; var biWidth: Int32; var biHeight: Int32
    var biPlanes: UInt16; var biBitCount: UInt16; var biCompression: UInt32
    var biSizeImage: UInt32; var biXPelsPerMeter: Int32; var biYPelsPerMeter: Int32
    var biClrUsed: UInt32; var biClrImportant: UInt32
}

@inline(__always) private func loadLE<T>(_ data: Data, _ off: Int) -> T { data.withUnsafeBytes { $0.baseAddress!.advanced(by: off).load(as: T.self) } }
private let pngSig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

public enum OurinICOError: Error { case invalid, unsupported }

/// ICO または CUR ファイルを解析して画像データを取得する。
public func parseICOorCUR(_ data: Data) throws -> OurinIcoCurImage {
    guard data.count >= 6 else { throw OurinICOError.invalid }
    let dir: ICONDIR = loadLE(data, 0)
    guard dir.reserved == 0, (dir.type == 1 || dir.type == 2), dir.count > 0 else { throw OurinICOError.invalid }
    let isCursor = (dir.type == 2)

    var bestIndex = -1
    var bestScore = -1
    let eSize = MemoryLayout<ICONDIRENTRY>.size
    for i in 0..<Int(dir.count) {
        let off = 6 + i * eSize
        guard off + eSize <= data.count else { throw OurinICOError.invalid }
        let e: ICONDIRENTRY = loadLE(data, off)
        let io = Int(e.imageOffset), il = Int(e.bytesInRes)
        guard io >= 0, il >= 0, io + il <= data.count else { continue }
        let isPNG = data[io..<io+min(il,8)].elementsEqual(pngSig)
        let w = (e.width == 0) ? 256 : Int(e.width)
        let h = (e.height == 0) ? 256 : Int(e.height)
        let bpp = isCursor ? 32 : Int(e.bpp_or_hotspotY)
        let score = (isPNG ? 1_000_000 : 0) + w*h*bpp
        if score > bestScore { bestScore = score; bestIndex = i }
    }
    guard bestIndex >= 0 else { throw OurinICOError.invalid }
    let e: ICONDIRENTRY = loadLE(data, 6 + bestIndex * eSize)
    let io = Int(e.imageOffset), il = Int(e.bytesInRes)
    let payload = data[io..<io+il]
    let width = (e.width == 0) ? 256 : Int(e.width)
    let height = (e.height == 0) ? 256 : Int(e.height)
    let hotspotX = isCursor ? Int(e.planes_or_hotspotX) : 0
    let hotspotY = isCursor ? Int(e.bpp_or_hotspotY) : 0

    if payload.prefix(8).elementsEqual(pngSig) {
        return OurinIcoCurImage(width: width, height: height, isCursor: isCursor, hotspotX: hotspotX, hotspotY: hotspotY, pngPayload: Data(payload), rgba: nil)
    }
    // PNG でない場合は 32bpp BMP と仮定してデコードする
    if payload.count < 40 { throw OurinICOError.unsupported }
    let bih: BITMAPINFOHEADER = payload.withUnsafeBytes { $0.load(as: BITMAPINFOHEADER.self) }
    guard bih.biSize >= 40, bih.biCompression == 0, bih.biBitCount == 32 else { throw OurinICOError.unsupported }
    let w = Int(bih.biWidth)
    let h = Int(bih.biHeight) / 2
    guard w > 0, h > 0 else { throw OurinICOError.invalid }
    let row = w * 4
    let xorStart = Int(bih.biSize)
    let xorSize = row * h
    guard payload.count >= xorStart + xorSize else { throw OurinICOError.invalid }
    let andRow = ((w + 31) / 32) * 4
    let andStart = xorStart + xorSize
    guard payload.count >= andStart + andRow*h else { throw OurinICOError.invalid }

    var rgba = Data(count: xorSize)
    var hasAlpha = false
    rgba.withUnsafeMutableBytes { dstRaw in
        let dst = dstRaw.bindMemory(to: UInt8.self).baseAddress!
        payload.withUnsafeBytes { srcRaw in
            let src = srcRaw.bindMemory(to: UInt8.self).baseAddress!
            for y in 0..<h {
                let s = src + xorStart + (h-1-y)*row
                let d = dst + y*row
                for x in 0..<w {
                    let b = s[x*4+0], g = s[x*4+1], r = s[x*4+2], a = s[x*4+3]
                    d[x*4+0] = r; d[x*4+1] = g; d[x*4+2] = b; d[x*4+3] = a
                    if a != 0 { hasAlpha = true }
                }
            }
            if !hasAlpha {
                for y in 0..<h {
                    let m = src + andStart + (h-1-y)*andRow
                    let d = dst + y*row
                    for x in 0..<w {
                        let bit = 7 - (x & 7)
                        if ((m[x>>3] >> bit) & 1) != 0 { d[x*4+3] = 0 }
                    }
                }
            }
        }
    }
    return OurinIcoCurImage(width: w, height: h, isCursor: isCursor, hotspotX: hotspotX, hotspotY: hotspotY, pngPayload: nil, rgba: rgba)
}
