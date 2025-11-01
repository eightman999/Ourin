import Foundation
import OSLog

// 外部 SSTP サーバ群の管理を行うクラス。
// モジュールの概要は docs/SSTP_Host_Modules_JA.md を参照。

/// 外部からの SSTP イベントを受信する TCP/HTTP/XPC サーバ群を管理するクラス。
public final class OurinExternalServer {
    /// TCP ベースの SSTP サーバ
    public let tcp = SstpTcpServer()
    /// HTTP ベースの SSTP サーバ
    public let http = SstpHttpServer()
    /// XPC 直接通信サーバ
    public let xpc = XpcDirectServer()
    /// リクエストを解釈して SHIORI へ転送するルーター
    private let router = SstpRouter()
    /// OSLog 用ロガー
    private let logger = CompatLogger(subsystem: "Ourin", category: "ExternalServer")

    /// サーバ群の初期設定を行う
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
