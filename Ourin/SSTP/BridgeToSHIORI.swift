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
        // SHIORI/2.x はバイナリ IPC ベースで 3.0 と全く互換性がない。
        // 過去の「3.0 形式ヘッダで 2.6 を名乗る」フォールバックは 2.x 実装には届かないため削除し、
        // 3.0 一本に統一する（旧式 SHIORI が必要な場合は別途 ShioriLoader を拡張する）。
        var lines = [
            "GET SHIORI/3.0",
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
        let req = lines.joined(separator: "\r\n") + "\r\n"
        return loader.request(req)
    }
}
