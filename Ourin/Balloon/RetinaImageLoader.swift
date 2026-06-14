import Foundation
import AppKit

/// Retina(高DPI)対応の画像ローダ。
///
/// ukagaka のシェル/バルーン画像は通常 1x の PNG を出荷するが、Ourin 拡張として
/// `name@2x.png`（および `name@3x.png`）の高解像度バリアントがあれば取り込み、
/// `NSImage` に複数解像度の representation を持たせる。AppKit が表示時の
/// `backingScaleFactor` に応じて最適な representation を自動選択する。
///
/// 返す `NSImage.size` は常に**論理ポイント**（= 1x ピクセル相当）に揃えるため、
/// ウィンドウサイズ（`NSImage.size` を使用）は Retina でもズレない。
enum RetinaImageLoader {
    /// ファイル URL から画像を読み込み、`@2x`/`@3x` バリアントがあれば高解像度 rep として付与する。
    static func image(contentsOf url: URL) -> NSImage? {
        let fm = FileManager.default
        let baseExists = fm.fileExists(atPath: url.path)

        // 1x が存在する場合: それを基準サイズ（論理ポイント）とし、@2x/@3x を rep として追加。
        if baseExists, let base = NSImage(contentsOf: url) {
            let logicalSize = base.size
            for suffix in ["@2x", "@3x"] {
                guard let variantURL = variant(of: url, suffix: suffix),
                      fm.fileExists(atPath: variantURL.path),
                      let rep = bitmapRep(contentsOf: variantURL) else { continue }
                // representation の論理サイズを 1x と一致させると AppKit がスケールで使い分ける。
                rep.size = logicalSize
                base.addRepresentation(rep)
            }
            return base
        }

        // 1x が無く @2x/@3x のみある場合: 最高解像度を読み、論理ポイント（ピクセル/スケール）に縮める。
        for (suffix, scale) in [("@2x", CGFloat(2)), ("@3x", CGFloat(3))] {
            guard let variantURL = variant(of: url, suffix: suffix),
                  fm.fileExists(atPath: variantURL.path),
                  let img = NSImage(contentsOf: variantURL) else { continue }
            img.size = NSSize(width: img.size.width / scale, height: img.size.height / scale)
            return img
        }
        return nil
    }

    /// ファイルパス文字列版（`NSImage(contentsOfFile:)` の置き換え用）。
    static func image(contentsOfFile path: String) -> NSImage? {
        image(contentsOf: URL(fileURLWithPath: path))
    }

    /// `name.ext` → `name<suffix>.ext`（例: surface0.png → surface0@2x.png）
    private static func variant(of url: URL, suffix: String) -> URL? {
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        guard !stem.isEmpty else { return nil }
        let name = ext.isEmpty ? "\(stem)\(suffix)" : "\(stem)\(suffix).\(ext)"
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    private static func bitmapRep(contentsOf url: URL) -> NSImageRep? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSBitmapImageRep(data: data)
    }
}
