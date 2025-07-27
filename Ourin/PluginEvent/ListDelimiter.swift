import Foundation

/// 0x01 区切りで文字列を分割するユーティリティ
enum ListDelimiter {
    /// 0x01 区切りの文字列を配列に展開
    static func split(_ text: String) -> [String] {
        text.split(separator: "\u{1}").map { String($0) }
    }

    /// 文字列配列を 0x01 で連結
    static func join(_ items: [String]) -> String {
        items.joined(separator: "\u{1}")
    }
}
