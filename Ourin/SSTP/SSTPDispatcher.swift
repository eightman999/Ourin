import Foundation

/// SSTP メソッドを受け取り適切な処理へ振り分ける簡易ディスパッチャ
public enum SSTPDispatcher {
    public static func dispatch(request: SSTPRequest) -> String {
        let charset = request.headers["Charset"] ?? "UTF-8"
        switch request.method.uppercased() {
        case "SEND", "NOTIFY", "COMMUNICATE", "EXECUTE":
            let script = "\\h\\s0OK"
            return "SSTP/1.4 200 OK\r\nCharset: \(charset)\r\nScript: \(script)\r\n\r\n"
        default:
            return "SSTP/1.4 400 Bad Request\r\nCharset: UTF-8\r\n\r\n"
        }
    }
}
