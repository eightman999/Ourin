import Foundation
import OSLog

/// 外部からの SSTP イベントを受信する TCP/HTTP/XPC サーバ群を管理するクラス。
public final class OurinExternalServer {
    private let tcp = SstpTcpServer()
    private let http = SstpHttpServer()
    private let xpc = XpcDirectServer()
    private let router = SstpRouter()
    private let logger = Logger(subsystem: "Ourin", category: "ExternalServer")

    public init() {
        tcp.onRequest = { [weak self] in self?.router.handle(raw: $0) ?? "" }
        http.onRequest = { [weak self] in self?.router.handle(raw: $0) ?? "" }
        xpc.onRequest = { [weak self] in self?.router.handle(raw: $0) ?? "" }
    }

    /// すべてのリスナーを起動する。エラーは現状無視する。
    public func start() {
        try? tcp.start()
        try? http.start()
        xpc.start()
        logger.info("external servers started")
    }

    /// すべてのリスナーを停止する。
    public func stop() {
        tcp.stop()
        http.stop()
        xpc.stop()
        logger.info("external servers stopped")
    }
}
