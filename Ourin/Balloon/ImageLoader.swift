import Foundation
import CoreGraphics
import CoreImage
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
    /// 同名の `.pna`（別アルファファイル）が存在すれば透過マスクとして適用する（BALLOON_1.0M_SPEC）。
    /// URL から画像を読み込んで CGImage を返す
    public static func load(url: URL) throws -> CGImage {
        let base = try loadRaw(url: url)
        // PNA（別アルファファイル）が隣にあれば適用する。拡張子を pna に差し替えた兄弟ファイル。
        let pnaURL = url.deletingPathExtension().appendingPathExtension("pna")
        if url.pathExtension.lowercased() != "pna",
           FileManager.default.fileExists(atPath: pnaURL.path),
           let masked = applyPNA(base: base, pnaURL: pnaURL) {
            return masked
        }
        return base
    }

    /// PNA を適用せず素の画像のみを読み込む（PNA 自体の読み込みにも使う）。
    private static func loadRaw(url: URL) throws -> CGImage {
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

    /// PNA マスク（白=不透明 / 黒=透明のグレースケール）を base のアルファとして合成する。
    /// BalloonImageLoader.applyPNAMask と同方式（CIBlendWithMask）。
    private static func applyPNA(base: CGImage, pnaURL: URL) -> CGImage? {
        guard let maskCG = try? loadRaw(url: pnaURL) else { return nil }
        let baseCI = CIImage(cgImage: base)
        let maskCI = CIImage(cgImage: maskCG)
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: baseCI.extent)
        guard let output = CIFilter(name: "CIBlendWithMask",
                                    parameters: [kCIInputImageKey: baseCI,
                                                 kCIInputBackgroundImageKey: clear,
                                                 kCIInputMaskImageKey: maskCI])?.outputImage else {
            return nil
        }
        return CIContext(options: nil).createCGImage(output, from: baseCI.extent)
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
