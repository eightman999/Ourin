import Foundation

/// PLUGIN/2.0M フレーム構築用構造体
struct PluginFrame {
    /// イベント ID
    var id: String
    /// Reference パラメータ群
    var references: [String] = []
    /// 送信時の文字コード（既定 UTF-8）
    var charset: String = "UTF-8"
    /// GET か NOTIFY かを示す
    var notify: Bool = false

    /// 文字列フレームを組み立てる
    func build() -> String {
        var lines: [String] = []
        let method = notify ? "NOTIFY" : "GET"
        lines.append("\(method) PLUGIN/2.0M")
        lines.append("Charset: \(charset)")
        lines.append("ID: \(id)")
        lines.append("Sender: Ourin")
        for (i, ref) in references.enumerated() {
            lines.append("Reference\(i): \(ref)")
        }
        lines.append("")
        // CRLF 区切りで末尾にも CRLF
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
