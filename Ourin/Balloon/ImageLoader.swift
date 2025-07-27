import Foundation
import CoreGraphics
import ImageIO

/// 画像ファイルを読み込むためのユーティリティ。
#if canImport(AppKit)
import AppKit
#endif

public enum ImageLoader {
    /// Image I/O が対応している形式を列挙
    private static let supportedUTIs: Set<String> = {
        guard let ids = CGImageSourceCopyTypeIdentifiers() as? [String] else { return [] }
        return Set(ids)
    }()

    /// Load image at given url. Supports PNG/JPEG/GIF/BMP via Image I/O and ICO/CUR via builtin parser.
    /// URL から画像を読み込んで CGImage を返す
    public static func load(url: URL) throws -> CGImage {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        if ext == "ico" || ext == "cur" {
            let img = try parseICO(data: data)
            return img
        }
        if let src = CGImageSourceCreateWithData(data as CFData, nil),
           let uti = CGImageSourceGetType(src),
           supportedUTIs.contains(uti as String),
           let image = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return image
        }
        throw NSError(domain: "OurinImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey:"Unsupported image format"])
    }

    /// 内蔵の ICO/CUR 解析を利用して CGImage を生成する
    private static func parseICO(data: Data) throws -> CGImage {
        let ico = try parseICOorCUR(data)
        if let png = ico.pngPayload {
            guard let src = CGImageSourceCreateWithData(png as CFData, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw NSError(domain: "OurinImageLoader", code: -2, userInfo: [NSLocalizedDescriptionKey:"Invalid PNG payload"])
            }
            return cg
        }
        guard let rgba = ico.rgba else {
            throw NSError(domain: "OurinImageLoader", code: -3, userInfo: [NSLocalizedDescriptionKey:"Missing image data"])
        }
        let provider = CGDataProvider(data: rgba as CFData)!
        let cg = CGImage(width: ico.width, height: ico.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: ico.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return cg
    }
}
