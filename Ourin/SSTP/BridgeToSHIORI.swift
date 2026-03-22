import Foundation

// SHIORI イベントパイプラインへのブリッジ実装。
// docs/OURIN_SHIORI_EVENTS_3.0M_SPEC.md に沿ったイベント名を使用する。

/// SHIORI/3.0M 互換イベントへ橋渡しするブリッジ
public enum BridgeToSHIORI {
    /// Resource 用のテスト返値を保持するマップ
    private static var resourceMap: [String: String] = [:]
    private static let resourceMapLock = NSLock()
    private static let threadResourceMapKey = "BridgeToSHIORI.threadResourceMap"
    /// 実際の SHIORI ホスト
    private static var host: ShioriHost? = {
        guard let path = ProcessInfo.processInfo.environment["SHIORI_BUNDLE_PATH"] else {
            return nil
        }
        return ShioriHost(bundlePath: path)
    }()

    private static var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
    }

    private static func currentThreadResourceMap() -> [String: String]? {
        Thread.current.threadDictionary[threadResourceMapKey] as? [String: String]
    }

    private static func setCurrentThreadResourceMap(_ map: [String: String]) {
        Thread.current.threadDictionary[threadResourceMapKey] = map
    }

    /// テスト用に返値を登録する
    /// - Parameters:
    ///   - key: Resource 名
    ///   - value: 応答として返す文字列
    public static func setResource(_ key: String, value: String) {
        if isRunningTests {
            var map = currentThreadResourceMap() ?? [:]
            map[key] = value
            setCurrentThreadResourceMap(map)
            return
        }
        resourceMapLock.lock()
        resourceMap[key] = value
        resourceMapLock.unlock()
    }

    /// テスト用登録値をすべて消去し、環境変数ベースのホスト設定へ戻す
    public static func reset() {
        if isRunningTests {
            // Swift Testing runs suites in parallel. Keep per-thread maps isolated to
            // avoid cross-suite interference from shared static state.
            setCurrentThreadResourceMap([:])
        } else {
            resourceMapLock.lock()
            resourceMap.removeAll()
            resourceMapLock.unlock()
        }
        if let path = ProcessInfo.processInfo.environment["SHIORI_BUNDLE_PATH"] {
            host = ShioriHost(bundlePath: path)
        } else {
            host = nil
        }
    }

    /// 明示的に SHIORI バンドルを設定する
    /// - Parameter bundlePath: SHIORI バンドルのパス。nil の場合はホストを無効化する
    /// - Returns: 設定に成功した場合 true
    @discardableResult
    public static func configure(bundlePath: String?) -> Bool {
        guard let bundlePath, !bundlePath.isEmpty else {
            host = nil
            return true
        }
        guard let configured = ShioriHost(bundlePath: bundlePath) else {
            return false
        }
        host = configured
        return true
    }
    /// 指定されたイベントを SHIORI へ送信し応答を返す。
    /// テスト用に登録されたリソースが存在する場合はそれを優先する。

    /// SHIORI 互換イベントを処理する
    /// - Parameters:
    ///   - event: イベント名
    ///   - references: 参照引数
    ///   - headers: 追加ヘッダー（例: SecurityLevel）
    /// - Returns: 登録済み値または固定文字列

    public static func handle(event: String, references: [String], headers: [String: String] = [:]) -> String {
        if event == "Resource", let key = references.first {
            if isRunningTests, let map = currentThreadResourceMap() {
                if let val = map[key] {
                    return val
                }
            } else {
                resourceMapLock.lock()
                let val = resourceMap[key]
                resourceMapLock.unlock()
                if let val {
                    return val
                }
            }
        }
        if let res = host?.request(event: event, references: references, headers: headers) {
            return res
        }
        return ""
    }
}

// MARK: - Internal SHIORI host bridge
private final class ShioriHost {
    private let loader: ShioriLoader
    private var negotiatedProtocol = "SHIORI/3.0"

    init?(bundlePath: String) {
        let moduleURL = URL(fileURLWithPath: bundlePath)
        let xpcServiceName = ShioriLoader.resolvedXpcServiceName()
        guard let loader = ShioriLoader(moduleURL: moduleURL, xpcServiceName: xpcServiceName) else {
            return nil
        }
        self.loader = loader
    }

    deinit { loader.unload() }

    func request(event: String, references: [String], headers: [String: String] = [:]) -> String? {
        func buildRequest(version: String) -> String {
            var lines = [
                "GET \(version)",
                "Charset: UTF-8",
                "Sender: Ourin",
                "ID: \(event)"
            ]
            for (i, ref) in references.enumerated() {
                lines.append("Reference\(i): \(ref)")
            }
            for (key, value) in headers {
                lines.append("\(key): \(value)")
            }
            lines.append("")
            return lines.joined(separator: "\r\n") + "\r\n"
        }

        func send(_ req: String) -> String? {
            loader.request(req)
        }

        func statusCode(_ response: String) -> Int? {
            guard let firstLine = response.components(separatedBy: "\r\n").first else { return nil }
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else { return nil }
            return Int(parts[1])
        }

        let response = send(buildRequest(version: negotiatedProtocol))
        if negotiatedProtocol == "SHIORI/3.0", let response, let code = statusCode(response), code == 400 || code == 505 {
            if let legacy = send(buildRequest(version: "SHIORI/2.6")) {
                negotiatedProtocol = "SHIORI/2.6"
                return legacy
            }
            return response
        }
        if response == nil, negotiatedProtocol == "SHIORI/3.0" {
            if let legacy = send(buildRequest(version: "SHIORI/2.6")) {
                negotiatedProtocol = "SHIORI/2.6"
                return legacy
            }
        }
        return response
    }
}
