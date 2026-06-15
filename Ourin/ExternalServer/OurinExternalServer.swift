import Foundation
import OSLog

// 外部 SSTP サーバ群の管理を行うクラス。
// モジュールの概要は docs/SSTP_Host_Modules_JA.md を参照。

/// 外部からの SSTP イベントを受信する TCP/HTTP/XPC サーバ群を管理するクラス。
/// 受信した生 SSTP は SSTPParser で解析し SSTPDispatcher へ一本化して処理する（P2-10）。
public final class OurinExternalServer {
    /// TCP/HTTP を 9801 単一ポートで多重化するリスナー（生 SSTP と HTTP を先頭行で振り分け）
    public let unified = UnifiedSstpListener()
    /// SSP 互換の副ポート(9821)で同じく生 SSTP/HTTP を多重化するリスナー
    public let unifiedCompat = UnifiedSstpListener()
    /// XPC 直接通信サーバ
    public let xpc = XpcDirectServer()
    /// OSLog 用ロガー
    private let logger = CompatLogger(subsystem: "Ourin", category: "ExternalServer")

    /// TCP(生 SSTP) が有効かつリスナー稼働中か（UI 表示・互換用）
    public var tcpRunning: Bool { unified.isRunning && config.enableTCP }
    /// HTTP が有効かつリスナー稼働中か（UI 表示・互換用）
    public var httpRunning: Bool { unified.isRunning && config.enableHTTP }

    public struct Config {
        var securityLocalOnly: Bool = true
        var maxPayloadSize: Int = 1024 * 1024
        var timeout: TimeInterval = 30
        var enableTCP: Bool = false
        var enableHTTP: Bool = false
        var enableXPC: Bool = true
        var enableDistributedIPC: Bool = true
    }

    private var config = Config()
    private var distributedObserver: NSObjectProtocol?

    /// サーバ群の初期設定を行う
    public init() {
        unified.onRequest = { [weak self] in self?.handleRaw($0) ?? "" }
        unifiedCompat.onRequest = { [weak self] in self?.handleRaw($0) ?? "" }
        xpc.onRequest = { [weak self] in self?.handleRaw($0) ?? "" }
        applyRuntimeConfig()
    }

    /// 設定を更新する
    public func updateConfig(_ config: Config) {
        self.config = config
        applyRuntimeConfig()
        applyListenerState()
    }

    /// 生の SSTP テキストを解析して SSTP ディスパッチャへ渡し、応答を返す。
    func handleRaw(_ raw: String) -> String {
        let start = Date()
        let request = SSTPParser.parseRequest(text: raw)
        guard !request.method.isEmpty else {
            logger.fault("parse failure")
            ServerMetrics.shared.record(duration: 0, error: true)
            return SSTPResponse(version: "SSTP/1.4", statusCode: 400).toWireFormat()
        }
        let response = SSTPDispatcher.dispatch(request: request, securityLocalOnly: config.securityLocalOnly)
        let duration = Date().timeIntervalSince(start)
        ServerMetrics.shared.record(duration: duration, error: isErrorResponse(response))
        return response
    }

    private func isErrorResponse(_ response: String) -> Bool {
        guard let statusLine = response.components(separatedBy: "\r\n").first else { return true }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let code = Int(parts[1]) else { return true }
        return code >= 400
    }

    private func applyRuntimeConfig() {
        let listenerConfig = UnifiedSstpListener.Config(
            timeout: config.timeout,
            maxSize: config.maxPayloadSize
        )
        unified.updateConfig(listenerConfig)
        unifiedCompat.updateConfig(listenerConfig)
        logger.info("external server runtime config updated")
    }

    private func applyListenerState() {
        // 生 SSTP / HTTP は同じ 9801 ポートで多重化する。どちらかが有効なら単一リスナーを起動。
        let wantUnified = config.enableTCP || config.enableHTTP
        if wantUnified {
            if !unified.isRunning {
                try? unified.start()
            }
            // SSP 互換: 副ポート 9821 でも待ち受ける
            if !unifiedCompat.isRunning {
                try? unifiedCompat.start(port: 9821)
            }
        } else {
            if unified.isRunning { unified.stop() }
            if unifiedCompat.isRunning { unifiedCompat.stop() }
        }

        if config.enableXPC {
            if !xpc.isRunning {
                xpc.start()
            }
        } else if xpc.isRunning {
            xpc.stop()
        }

        if config.enableDistributedIPC {
            startDistributedIpc()
        } else {
            stopDistributedIpc()
        }
    }

    /// すべてのリスナーを起動する。エラーは現状無視する。
    public func start() {
        applyRuntimeConfig()
        applyListenerState()
        logger.info("external servers started")
    }

    /// すべてのリスナーを停止する。
    public func stop() {
        unified.stop()
        unifiedCompat.stop()
        xpc.stop()
        stopDistributedIpc()
        logger.info("external servers stopped")
    }

    private func startDistributedIpc() {
        guard distributedObserver == nil else { return }
        let center = DistributedNotificationCenter.default()
        distributedObserver = center.addObserver(
            forName: NSNotification.Name("jp.ourin.sstp.request"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  let info = notification.userInfo,
                  let requestId = info["id"] as? String,
                  let raw = info["request"] as? String else {
                return
            }
            let response = self.handleRaw(raw)
            center.postNotificationName(
                NSNotification.Name("jp.ourin.sstp.response"),
                object: nil,
                userInfo: [
                    "id": requestId,
                    "response": response
                ],
                options: [.deliverImmediately]
            )
        }
        logger.info("distributed IPC started")
    }

    private func stopDistributedIpc() {
        guard let observer = distributedObserver else { return }
        DistributedNotificationCenter.default().removeObserver(observer)
        distributedObserver = nil
        logger.info("distributed IPC stopped")
    }
}
