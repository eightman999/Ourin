import Foundation

/// PLUGIN/2.0M の SecurityLevel ヘッダ値
/// - local: アプリ内部で発生したイベント（既定）
/// - external: SSTP 経由など外部由来で中継されたイベント
enum PluginSecurityLevel: String {
    case local
    case external
}

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
    /// SecurityLevel ヘッダ値（既定 local。SSTP 中継等では external を指定）
    var securityLevel: PluginSecurityLevel = .local

    /// 文字列フレームを組み立てる
    func build() -> String {
        var lines: [String] = []
        let method = notify ? "NOTIFY" : "GET"
        lines.append("\(method) PLUGIN/2.0M")
        lines.append("Charset: \(charset)")
        lines.append("ID: \(id)")
        lines.append("Sender: Ourin")
        lines.append("SecurityLevel: \(securityLevel.rawValue)")
        for (i, ref) in references.enumerated() {
            lines.append("Reference\(i): \(ref)")
        }
        lines.append("")
        // CRLF 区切りで末尾にも CRLF
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
