import Foundation

@objc public protocol OurinSSTPXPC {
    /// SSTP テキスト(UTF-8)を受け取り、応答テキスト(UTF-8)を返す
    func executeSSTP(_ request: Data, withReply reply: @escaping (Data) -> Void)
}

/// XPC 経由で DirectSSTP を提供するサービスエンドポイント
public final class DirectSSTPXPC: NSObject, NSXPCListenerDelegate, OurinSSTPXPC {
    /// 実際の XPC リスナー
    private let listener: NSXPCListener

    public override init() {
        listener = NSXPCListener.service()
        super.init()
        listener.delegate = self
    }

    /// リスナーを開始する
    public func resume() {
        listener.resume()
    }

    // MARK: - NSXPCListenerDelegate
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: OurinSSTPXPC.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - OurinSSTPXPC
    /// SSTP リクエストを解析し応答を返す
    public func executeSSTP(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        guard let text = Self.decodeRequest(request) else {
            reply(Data("SSTP/1.1 400 Bad Request\r\n\r\n".utf8))
            return
        }
        let req = SSTPParser.parseRequest(text: text)
        let resp = SSTPDispatcher.dispatchExternal(
            request: req,
            origin: req.headerValue("SecurityOrigin")
        )
        reply(resp.data(using: .utf8) ?? Data())
    }

    /// DirectSSTP の入力を、宣言された Charset を優先して UTF-8 の文字列へ変換する。
    /// Charset 未指定時は UTF-8、設定で許可されている場合のみ CP932 を試行する。
    static func decodeRequest(_ data: Data) -> String? {
        EncodingNormalizer.decode(data, charset: EncodingAdapter.declaredCharset(in: data))
    }
}
