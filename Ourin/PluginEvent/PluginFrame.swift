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
    /// Sender ヘッダ値。ゴーストの `\![raiseplugin]` / `\![notifyplugin]` 由来ならゴースト名、ホスト発なら既定値。
    var sender: String = PluginFrame.hostSender

    static let hostSender = "Ourin"
    static let protocolVersion = "PLUGIN/2.0"

    /// SSP の Language ヘッダ（data/language/*/descript.txt の locale）と同じ英語名を返す。
    static func languageHeader(preferred: [String] = Locale.preferredLanguages) -> String {
        let code = (preferred.first ?? "ja").lowercased()
        if code.hasPrefix("ja") { return "Japanese" }
        if code.hasPrefix("zh-hant") || code.hasPrefix("zh-tw") || code.hasPrefix("zh-hk") { return "Chinese-Traditional" }
        if code.hasPrefix("zh") { return "Chinese-Simplified" }
        if code.hasPrefix("ko") { return "Hangeoul" }
        return "English"
    }

    /// 文字列フレームを組み立てる
    func build() -> String {
        var lines: [String] = []
        let method = notify ? "NOTIFY" : "GET"
        // SSP 本体（sp_plugin）の要求行は "GET PLUGIN/2.0" / "NOTIFY PLUGIN/2.0"。
        // 要求行を完全一致で判定するプラグインがあるため "2.0M" は付けない。
        lines.append("\(method) \(PluginFrame.protocolVersion)")
        lines.append("Charset: \(charset)")
        lines.append("ID: \(id)")
        lines.append("Sender: \(sender)")
        lines.append("SecurityLevel: \(securityLevel.rawValue)")
        lines.append("Language: \(PluginFrame.languageHeader())")
        for (i, ref) in references.enumerated() {
            lines.append("Reference\(i): \(ref)")
        }
        lines.append("")
        // CRLF 区切りで末尾にも CRLF
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}
