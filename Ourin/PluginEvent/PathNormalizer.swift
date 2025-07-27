import Foundation

/// Windows 由来のパスを POSIX 形式へ変換するユーティリティ
enum PathNormalizer {
    /// パス文字列を POSIX 形式へ変換
    static func posix(_ path: String) -> String {
        if path.hasPrefix("file://") {
            return path
        }
        // Windows 形式を file URL 経由で正規化
        return URL(fileURLWithPath: path).path
    }
}
