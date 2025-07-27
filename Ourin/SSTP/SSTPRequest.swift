import Foundation

/// SSTP リクエストを表す構造体
public struct SSTPRequest {
    /// メソッド名 (SEND/NOTIFY 等)
    public var method: String
    /// プロトコルバージョン
    public var version: String
    /// ヘッダー集合
    public var headers: [String: String]
    /// 追加データ
    public var body: Data

    public init(method: String = "", version: String = "", headers: [String: String] = [:], body: Data = Data()) {
        self.method = method
        self.version = version
        self.headers = headers
        self.body = body
    }
}
