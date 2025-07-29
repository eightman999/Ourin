import Foundation
import OSLog

/// Network routing helper with logger compatible to 10.15

/// 解析済みの SSTP メッセージを SHIORI ブリッジへルーティングする。
public final class SstpRouter {
    private let logger = CompatLogger(subsystem: "Ourin", category: "ExternalSSTP")
    public init() {}

    /// 生の SSTP 文字列を処理し、SSTP 形式の応答を返す。
    public func handle(raw: String) -> String {
        let start = Date()
        guard let msg = SstpParser.parse(raw) else {
            logger.fault("parse failure")
            ServerMetrics.shared.record(duration: 0, error: true)
            return "SSTP/1.1 400 Bad Request\r\n\r\n"
        }
        let charset = msg.headers["Charset"] ?? "UTF-8"
        let event = msg.headers["Event"] ?? ""
        var refs: [String] = []
        for i in 0..<16 {
            if let v = msg.headers["Reference\(i)"] { refs.append(v) } else { break }
        }
        let script = BridgeToSHIORI.handle(event: event, references: refs)
        let isNotify = msg.method.uppercased() == "NOTIFY"
        let duration = Date().timeIntervalSince(start)
        let resp: String
        if isNotify {
            resp = "SSTP/1.1 204 No Content\r\n\r\n"
        } else {
            let lines = [
                "SSTP/1.1 200 OK",
                "Charset: \(charset)",
                "Sender: Ourin",
                "Script: \(script)",
                "",
                ""
            ]
            resp = lines.joined(separator: "\r\n")
        }
        logger.info("event=\(event) duration=\(duration)")
        ServerMetrics.shared.record(duration: duration, error: false)
        return resp
    }
}
