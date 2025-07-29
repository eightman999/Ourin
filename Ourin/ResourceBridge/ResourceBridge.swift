import Foundation
import AppKit
import OSLog

private extension String.Encoding {
    /// Windows 互換の Shift_JIS コードページ (CP932)
    static let shiftJIS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
}

/// SHIORI の Resource キーを取得してキャッシュするブリッジ。
/// 仕様は `docs/PROPERTY_Resource_3.0M_SPEC.md` を参照。
@available(macOS 11.0, *)
public final class ResourceBridge {
    /// シングルトンインスタンス
    public static let shared = ResourceBridge()
    private init() {}

    /// Cached value with timestamp
    private struct Entry {
        var value: String?
        var time: Date
    }
    private var cache: [String: Entry] = [:]
    /// キャッシュ保持時間（秒）
    private let ttl: TimeInterval = 5
    /// ロガー
    private let logger = Logger(subsystem: "Ourin", category: "ResourceBridge")

    /// Get resource value for given key via SHIORI. Uses cache if valid.
    public func get(_ key: String) -> String? {
        let now = Date()
        if let entry = cache[key], now.timeIntervalSince(entry.time) < ttl {
            return entry.value
        }
        let value = query(key: key)
        cache[key] = Entry(value: value, time: now)
        logger.debug("query \(key) -> \(value ?? \"nil\")")
        return value
    }

    /// Force invalidate all cached values
    public func invalidateAll() {
        cache.removeAll()
    }

    /// 指定キーのみキャッシュを無効化する
    public func invalidate(keys: [String]) {
        for k in keys { cache.removeValue(forKey: k) }
    }

    // MARK: - Parsing helpers
    public func boolValue(for key: String) -> Bool? {
        guard let raw = get(key) else { return nil }
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["1", "true", "on"].contains(lower) ? true : (["0", "false", "off"].contains(lower) ? false : nil)
    }

    public func intValue(for key: String) -> Int? {
        guard let raw = get(key) else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func pointValue(for key: String) -> (Int, Int)? {
        guard let raw = get(key) else { return nil }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) else { return nil }
        return (x, y)
    }

    /// 画面左上基準の座標を AppKit の左下基準に変換して取得する
    public func screenPointValue(for key: String) -> CGPoint? {
        guard let (x, yTop) = pointValue(for: key) else { return nil }
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let convY = Int(union.height) - 1 - yTop
        return CGPoint(x: x, y: convY)
    }

    /// 区切り文字で分割した文字列配列を返す
    public func listValue(for key: String, separator: Character = "|") -> [String]? {
        guard let raw = get(key) else { return nil }
        return raw.split(separator: separator).map { String($0) }
    }

    /// `menu.*.color` 系の RGB 値を NSColor として取得する
    public func colorValue(for prefix: String) -> NSColor? {
        guard let r = intValue(for: "\(prefix).r"),
              let g = intValue(for: "\(prefix).g"),
              let b = intValue(for: "\(prefix).b") else { return nil }
        // 0-255 の範囲に丸めて sRGB 0-1 へ変換
        let rf = min(max(r, 0), 255)
        let gf = min(max(g, 0), 255)
        let bf = min(max(b, 0), 255)
        return NSColor(red: CGFloat(rf) / 255.0,
                       green: CGFloat(gf) / 255.0,
                       blue: CGFloat(bf) / 255.0,
                       alpha: 1)
    }

    /// おすすめ/ポータルサイト一覧を解析する構造体
    public struct RecommendSite {
        public var title: String
        public var url: String
        public var banner: URL?
        public var talk: String
    }

    /// `recommendsites` / `portalsites` を配列に展開する
    public func recommendSites(for key: String, base: URL?) -> [RecommendSite]? {
        guard let raw = get(key) else { return nil }
        let records = splitEscaped(raw, separator: "\u{02}")
        return records.compactMap { record in
            if record.isEmpty { return nil }
            let parts = splitEscaped(record, separator: "\u{01}")
            let title = parts.indices.contains(0) ? parts[0] : ""
            let url = parts.indices.contains(1) ? parts[1] : ""
            let bannerRaw = parts.indices.contains(2) ? parts[2] : ""
            let talk = parts.indices.contains(3) ? parts[3] : ""
            let banner = urlValue(fromRaw: bannerRaw, relativeTo: base)
            return RecommendSite(title: title, url: url, banner: banner, talk: talk)
        }
    }

    /// パス系リソースを URL として解釈する（相対パスは基準URLからの相対）
    public func urlValue(for key: String, relativeTo base: URL?) -> URL? {
        guard let raw = get(key) else { return nil }
        return urlValue(fromRaw: raw, relativeTo: base)
    }

    /// 生のパス文字列を URL として解釈する
    private func urlValue(fromRaw raw: String, relativeTo base: URL?) -> URL? {
        if raw.hasPrefix("file://") { return URL(string: raw) }
        if raw.hasPrefix("/") { return URL(fileURLWithPath: raw) }
        // Windows 形式を POSIX に変換
        if raw.contains("\\") || raw.contains(":") {
            let path = raw.replacingOccurrences(of: "\\", with: "/")
            return URL(fileURLWithPath: path)
        }
        guard let base = base else { return URL(fileURLWithPath: raw) }
        return base.appendingPathComponent(raw)
    }

    /// メニューキャプションとショートカット情報をまとめて取得する
    public func menuItem(for captionKey: String) -> (title: String, shortcut: Character?, visible: Bool)? {
        guard var caption = get(captionKey) else { return nil }
        var shortcut: Character? = nil
        if let amp = caption.firstIndex(of: "&"), caption.index(after: amp) < caption.endIndex {
            shortcut = caption[caption.index(after: amp)]
            caption.remove(at: amp)
        }
        let visibleKey = captionKey.replacingOccurrences(of: ".caption", with: ".visible")
        let visible = boolValue(for: visibleKey) ?? true
        return (caption, shortcut, visible)
    }

    /// 区切り文字をエスケープ考慮で分割する内部ユーティリティ
    private func splitEscaped(_ text: String, separator: Character) -> [String] {
        var result: [String] = []
        var current = ""
        var escape = false
        for ch in text {
            if escape {
                current.append(ch)
                escape = false
            } else if ch == "\\" {
                escape = true
            } else if ch == separator {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }

    // MARK: - Internal query
    /// SHIORI へ Resource 取得を問い合わせる
    private func query(key: String) -> String? {
        let res = BridgeToSHIORI.handle(event: "Resource", references: [key])
        return res.isEmpty ? nil : res
    }
}
