import Foundation
import OSLog

/// XPC 経由で SSTP メッセージを受信するサーバ。
@objc public protocol OurinExternalSstpXPC {
    func deliverSSTP(_ request: Data, with reply: @escaping (Data) -> Void)
}

public final class XpcDirectServer: NSObject, NSXPCListenerDelegate, OurinExternalSstpXPC {
    private let listener: NSXPCListener
    public var onRequest: ((String) -> String)?
    private let logger = CompatLogger(subsystem: "Ourin", category: "SSTP_XPC")
    private let maxSize = 512 * 1024
    private var _isRunning = false

    public init(machServiceName: String = "jp.ourin.sstp") {
        self.listener = NSXPCListener(machServiceName: machServiceName)
        super.init()
        self.listener.delegate = self
    }

    /// サーバーが稼働中かどうかを返す
    public var isRunning: Bool {
        return _isRunning
    }

    public func start() {
        listener.resume()
        _isRunning = true
        logger.info("xpc started")
    }

    public func stop() {
        listener.invalidate()
        _isRunning = false
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: OurinExternalSstpXPC.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    /// XPC クライアントから SSTP データを受け取り応答する。
    public func deliverSSTP(_ request: Data, with reply: @escaping (Data) -> Void) {
        guard request.count <= maxSize else {
            logger.fault("xpc oversized")
            ServerMetrics.shared.record(duration: 0, error: true)
            reply(Data("SSTP/1.1 400 Bad Request\r\n\r\n".utf8))
            return
        }
        let str = String(data: request, encoding: .utf8) ?? String(data: request, encoding: .shiftJIS) ?? ""
        let start = Date()
        let resp = onRequest?(str) ?? "SSTP/1.1 204 No Content\r\n\r\n"
        let duration = Date().timeIntervalSince(start)
        logger.info("xpc size=\(request.count) duration=\(duration)")
        ServerMetrics.shared.record(duration: duration, error: false)
        reply(Data(resp.utf8))
    }
}
