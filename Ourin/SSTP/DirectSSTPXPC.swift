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
        guard let text = String(data: request, encoding: .utf8) else { return reply(Data()) }
        let req = SSTPParser.parseRequest(text: text)
        let resp = SSTPDispatcher.dispatch(request: req)
        reply(resp.data(using: .utf8) ?? Data())
    }
}
