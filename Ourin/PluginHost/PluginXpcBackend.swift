import Foundation
import OSLog

/// プラグインを別プロセス(XPC サービス)で実行するためのワーカープロトコル。
///
/// SHIORI の `OurinShioriXPC` と同じ設計。ワーカー側は `bundlePath` の `.plugin`/`.bundle` を
/// 自プロセスでロードし、PLUGIN/2.0M のワイヤテキスト(`request`)を受けて応答テキストを返す。
/// `reply` の Data が nil の場合は失敗（ホスト側はインプロセスにフォールバックしない＝XPC固定）。
@objc public protocol OurinPluginXPC {
    func executePlugin(_ request: Data, bundlePath: String, withReply reply: @escaping (Data?) -> Void)
}

/// プラグイン用 XPC クライアント。`machServiceName` のワーカーへ `Data->Data` で橋渡しする。
/// 同期 API（`send`）で、内部はセマフォ＋タイムアウト（SHIORI XpcBackend と同方式）。
public final class PluginXpcClient {
    private let connection: NSXPCConnection
    private let timeout: TimeInterval
    private let logger = CompatLogger(subsystem: "Ourin", category: "PluginXPC")

    public init(serviceName: String, timeout: TimeInterval = 5.0) {
        self.connection = NSXPCConnection(machServiceName: serviceName, options: [])
        self.connection.remoteObjectInterface = NSXPCInterface(with: OurinPluginXPC.self)
        self.connection.resume()
        self.timeout = timeout
    }

    deinit { connection.invalidate() }

    /// ワイヤテキストをワーカーへ送り、応答テキストを返す（失敗時 nil）。
    /// - Parameters:
    ///   - text: PLUGIN/2.0M リクエスト本文
    ///   - bundlePath: ロード対象プラグインの bundle パス
    public func send(_ text: String, bundlePath: String) -> String? {
        let requestData = Data(text.utf8)
        let sem = DispatchSemaphore(value: 0)
        var responseData: Data?
        var connectionError: Error?

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            connectionError = error
            sem.signal()
        }) as? OurinPluginXPC else {
            logger.fault("failed to create plugin XPC proxy")
            return nil
        }

        proxy.executePlugin(requestData, bundlePath: bundlePath) { data in
            responseData = data
            sem.signal()
        }

        if sem.wait(timeout: .now() + timeout) == .timedOut {
            logger.fault("plugin XPC request timed out")
            return nil
        }
        if let connectionError {
            logger.fault("plugin XPC error: \(connectionError.localizedDescription)")
            return nil
        }
        guard let responseData else { return nil }
        return String(data: responseData, encoding: .utf8)
    }
}

/// プラグインのプロセス分離モード解決（環境変数ベース。SHIORI の resolvedXpcServiceName と同方針）。
public enum PluginIsolation {
    /// XPC 分離を使う場合の mach サービス名を返す。インプロセス実行時は nil。
    /// - `OURIN_PLUGIN_XPC_SERVICE` を最優先。
    /// - `OURIN_PLUGIN_ISOLATION_MODE=xpc` の場合は既定名 `jp.ourin.plugin`。
    public static func resolvedXpcServiceName(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let explicit = environment["OURIN_PLUGIN_XPC_SERVICE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        if environment["OURIN_PLUGIN_ISOLATION_MODE"]?.lowercased() == "xpc" {
            return "jp.ourin.plugin"
        }
        return nil
    }
}
