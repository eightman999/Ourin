import Foundation

/// SHIORI/3.0 wire 形式と構造化応答の相互変換を行うステートレスな codec。
///
/// 責務分離の境界の一つで、プロセス内のいかなる状態も持たない純関数群のみ。
/// BridgeToSHIORI.handle / handleResponse のルーティング結果（ネイティブ wire／構造化応答／
/// 登録済み Resource 値）を最終的な文字列へ整形するために使われる。
///
/// 出力は従来の BridgeToSHIORI 実装とバイト互換（ReferenceN は数値順、その他ヘッダはキー順、
/// 行注入対策の CR/LF 除去を含む）。SakuraScript の改行は `\n` トークンで表すため、
/// 生の改行除去は表示上安全。
///
/// - note: Ourin/USL/ShioriRuntime.swift の `ShioriWireCodec` とは別物。あちらは SHIORI ランタイム
///   (YAYA/native) の要求生成・応答解析の境界。本型は BridgeToSHIORI の応答直列化専用。
enum ShioriBridgeWireCodec {
    /// SHIORI/3.0 ワイヤ応答から Value ヘッダ（スクリプト値）を取り出す。
    /// 既にワイヤ形式でない（生の値）場合はそのまま返す。ネイティブ SHIORI バンドルの応答用。
    static func value(fromWire response: String) -> String {
        guard response.uppercased().hasPrefix("SHIORI/") else { return response }
        for line in response.components(separatedBy: "\r\n").dropFirst() where !line.isEmpty {
            guard let idx = line.firstIndex(of: ":") else { continue }
            if String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased() == "value" {
                return String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    /// 構造化された SHIORI 応答を SHIORI/3.0 ワイヤ応答文字列へ直列化する。
    /// 各ヘッダ値・Value から CR/LF を除去し、行注入・スクリプト切断を防ぐ（ワイヤは行指向）。
    /// ReferenceN は数値順、その他ヘッダはキー順で安定出力する（mapShioriResponse は順不同で解釈可能）。
    static func serialize(_ resp: BridgeToSHIORI.BridgeShioriResponse) -> String {
        var hdrs = resp.headers
        let lowerKeys = Set(hdrs.keys.map { $0.lowercased() })
        // Value が未設定なら応答値を Value ヘッダとして出す（空文字でも 200 の有無を区別するため出力）。
        if let value = resp.value, !lowerKeys.contains("value") {
            hdrs["Value"] = value
        }
        let refPairs = hdrs.compactMap { (k, v) -> (Int, String, String)? in
            guard k.lowercased().hasPrefix("reference"),
                  let n = Int(k.dropFirst("reference".count)), n >= 0 else { return nil }
            return (n, k, v)
        }.sorted { $0.0 < $1.0 }
        let refKeys = Set(refPairs.map { $0.1 })

        var lines = ["SHIORI/3.0 \(resp.status) \(statusMessage(resp.status))"]
        if !lowerKeys.contains("charset") {
            lines.append("Charset: UTF-8")
        }
        for (k, v) in hdrs.sorted(by: { $0.key < $1.key }) where !refKeys.contains(k) {
            lines.append("\(sanitizeHeader(k)): \(sanitizeHeader(v))")
        }
        for (_, k, v) in refPairs {
            lines.append("\(sanitizeHeader(k)): \(sanitizeHeader(v))")
        }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }

    /// 生の値を最小限の SHIORI/3.0 ワイヤ応答へ包む（登録済み Resource 値を handleResponse で返す時に使用）。
    static func synthesizeWire(value: String) -> String {
        return "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: \(sanitizeHeader(value))\r\n\r\n"
    }

    /// ヘッダ行に混入し得る CR/LF を除去する（行注入・スクリプト切断対策）。
    static func sanitizeHeader(_ s: String) -> String {
        return s.replacingOccurrences(of: "\r\n", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
    }

    static func statusMessage(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 311: return "Communicate"
        case 312: return "Not Enough"
        case 400: return "Bad Request"
        case 500: return "Internal Server Error"
        default: return status < 300 ? "OK" : "Error"
        }
    }
}
