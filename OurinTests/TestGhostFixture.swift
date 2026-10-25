import AppKit
import Foundation

/// 同梱ゴーストに依存せず、テストごとに最小の ghost/shell/balloon を一時ディレクトリへ組み立てる。
enum TestGhostFixture {
    struct Pixel { var r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255 }

    static func makeRoot(_ prefix: String = "ourin-fixture") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// `shell/master` を作って返す。
    static func makeShell(in root: URL) throws -> URL {
        let shell = root.appendingPathComponent("shell/master", isDirectory: true)
        try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
        return shell
    }

    /// `pixel(x, y)` で塗った PNG を書く（y は上から数える）。alpha 無しなら RGB で書く。
    static func writePNG(
        to url: URL, width: Int, height: Int, hasAlpha: Bool = false,
        pixel: (Int, Int) -> Pixel
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: hasAlpha ? 4 : 3, hasAlpha: hasAlpha,
            isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [],
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CocoaError(.fileWriteUnknown) }
        for y in 0..<height {
            for x in 0..<width {
                let p = pixel(x, y)
                var values = hasAlpha ? [Int(p.r), Int(p.g), Int(p.b), Int(p.a)] : [Int(p.r), Int(p.g), Int(p.b)]
                values.withUnsafeMutableBufferPointer { bitmap.setPixel($0.baseAddress!, atX: x, y: y) }
            }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }

    /// 純緑 (0,255,0) 背景に、左下寄りの非対称な赤ブロックを置いた RGB PNG（クロマキー・向きの検証用）。
    static func writeGreenKeyedPNG(to url: URL) throws {
        try writePNG(to: url, width: 12, height: 10) { x, y in
            (2...4).contains(x) && (6...8).contains(y)
                ? Pixel(r: 255, g: 0, b: 0)
                : Pixel(r: 0, g: 255, b: 0)
        }
    }

    /// 単色の不透明 PNG。
    static func writeSolidPNG(to url: URL, width: Int, height: Int, color: Pixel = Pixel(r: 200, g: 120, b: 160)) throws {
        try writePNG(to: url, width: width, height: height) { _, _ in color }
    }
}
