import Foundation

/// Windows 由来のパスを POSIX 形式へ変換するユーティリティ
enum PathNormalizer {
    /// パス文字列を POSIX/`file://` 形式へ変換
    /// - Parameters:
    ///   - path: 元のパス文字列（Windows 形式や相対パスを許容）
    ///   - base: 相対パス解決に用いる基準 URL
    /// - Returns: POSIX 形式に正規化したパス文字列
    static func posix(_ path: String, relativeTo base: URL? = nil) -> String {
        // 既に file:// 形式ならそのまま返す
        if path.hasPrefix("file://") { return path }

        // 絶対パスであればそのまま
        if path.hasPrefix("/") {
            return path
        }

        // 相対パスは基準 URL があればそこから解決
        if let base = base {
            return base.appendingPathComponent(path).path
        }

        // Windows 形式のドライブレターを含む場合などは URL 経由で解決
        return URL(fileURLWithPath: path).path
    }
}
