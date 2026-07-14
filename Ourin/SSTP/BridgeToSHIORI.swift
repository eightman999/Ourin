import Foundation

// SHIORI イベントパイプラインへのブリッジ実装。
// docs/OURIN_SHIORI_EVENTS_3.0M_SPEC.md に沿ったイベント名を使用する。

/// SHIORI/3.0M 互換イベントへ橋渡しするブリッジ
public enum BridgeToSHIORI {
    /// Resource 用のテスト返値を保持するマップ
    private static var resourceMap: [String: String] = [:]
    private static let resourceMapLock = NSLock()
    private static let threadResourceMapKey = "BridgeToSHIORI.threadResourceMap"
    /// 実際の SHIORI ホスト（ネイティブ SHIORI バンドル。環境変数 SHIORI_BUNDLE_PATH 等で設定）
    private static var host: ShioriHost? = {
        guard let path = ProcessInfo.processInfo.environment["SHIORI_BUNDLE_PATH"] else {
            return nil
        }
        return ShioriHost(bundlePath: path)
    }()

    /// 稼働中ゴーストからの SHIORI 応答（構造化）。
    /// 文字列ワイヤへ一度直列化して再パースすると、Value に含まれる CRLF が
    /// 行注入・スクリプト切断を起こすため、ブリッジ内部では構造化したまま受け渡す。
    public struct BridgeShioriResponse {
        public let status: Int
        /// 応答ヘッダ（ReferenceN / Surface / Status / ValueNotify 等。Value は別途 `value` で保持）。
        public let headers: [String: String]
        /// 応答の値（スクリプト）。改行を含み得る。
        public let value: String?

        public init(status: Int, headers: [String: String], value: String?) {
            self.status = status
            self.headers = headers
            self.value = value
        }
    }

    /// 稼働中のゴースト（YAYA 等）へ SHIORI 要求を橋渡しするリゾルバ。
    /// ネイティブ SHIORI バンドルが未設定のとき、`handle` / `handleResponse` はこのリゾルバを通じて
    /// 実際にロードされたゴーストへ要求を送り、その応答を返す。アプリ起動時に AppDelegate が設定する。
    /// - 引数: (method, event, references, headers)
    /// - 戻り値: 構造化された SHIORI 応答。宛先ゴーストが無い／応答できない場合は nil。
    public static var liveGhostResolver: ((String, String, [String], [String: String]) -> BridgeShioriResponse?)?

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
        // 稼働中ゴーストへのリゾルバも解除する（テスト間で実ゴースト依存が漏れないように）。
        liveGhostResolver = nil
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

    /// SHIORI 互換イベントを処理し、応答の「値」（Value / スクリプト）を返す。
    /// `GhostManager` / `ResourceBridge` / `WebHandler` など、応答を直接スクリプト値として使う呼び出し向け。
    /// - Parameters:
    ///   - event: イベント名
    ///   - references: 参照引数
    ///   - headers: 追加ヘッダー（例: SecurityLevel）
    ///   - method: SHIORI メソッド（既定 "GET"。NOTIFY イベントは "NOTIFY" を渡す）
    /// - Returns: 登録済み Resource 値、または応答の Value（無ければ空文字列）

    public static func handle(event: String, references: [String], headers: [String: String] = [:], method: String = "GET") -> String {
        if let registered = registeredResourceValue(event: event, references: references) {
            return registered
        }
        // ネイティブ SHIORI バンドルはワイヤ文字列を返すため Value を取り出す。
        if let nativeWire = host?.request(event: event, references: references, headers: headers, method: method) {
            return valueFromWire(nativeWire)
        }
        // 稼働中ゴーストは構造化応答を返す。値は改行を含み得るためそのまま返す（切断しない）。
        if let resp = liveGhostResolver?(method, event, references, headers) {
            return resp.value ?? ""
        }
        return ""
    }

    /// SSTP ディスパッチャ向け: 完全な SHIORI/3.0 ワイヤ応答文字列を返す。
    /// `SSTPDispatcher.mapShioriResponse` が ReferenceN / Value / ValueNotify / Status / Surface 等を
    /// 保持できるよう、値だけでなく応答ヘッダを含む応答全体を返す。
    public static func handleResponse(event: String, references: [String], headers: [String: String] = [:], method: String = "GET") -> String {
        if let registered = registeredResourceValue(event: event, references: references) {
            // テスト／明示登録値が既に完全なSHIORI応答なら二重包装しない。
            // `Value: SHIORI/3.0 ...` にするとStatusやReferenceN等の応答ヘッダを失う。
            if registered.uppercased().hasPrefix("SHIORI/") {
                return registered
            }
            return synthesizeWire(value: registered)
        }
        if let nativeWire = host?.request(event: event, references: references, headers: headers, method: method) {
            return nativeWire
        }
        if let resp = liveGhostResolver?(method, event, references, headers) {
            return serializeWire(resp)
        }
        return ""
    }

    /// テスト/明示登録された Resource 値があれば返す（無ければ nil）。
    private static func registeredResourceValue(event: String, references: [String]) -> String? {
        guard event == "Resource", let key = references.first else { return nil }
        if isRunningTests, let map = currentThreadResourceMap() {
            return map[key]
        }
        resourceMapLock.lock()
        let val = resourceMap[key]
        resourceMapLock.unlock()
        return val
    }

    /// SHIORI/3.0 ワイヤ応答から Value ヘッダ（スクリプト値）を取り出す。
    /// 既にワイヤ形式でない（生の値）場合はそのまま返す。ネイティブ SHIORI バンドルの応答用。
    private static func valueFromWire(_ response: String) -> String {
        guard response.uppercased().hasPrefix("SHIORI/") else { return response }
        for line in response.components(separatedBy: "\r\n").dropFirst() where !line.isEmpty {
            guard let idx = line.firstIndex(of: ":") else { continue }
            if String(line[..<idx]).trimmingCharacters(in: .whitespaces).lowercased() == "value" {
                return String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    /// 構造化された SHIORI 応答を SHIORI/3.0 ワイヤ応答文字列へ直列化する。
    /// 各ヘッダ値・Value から CR/LF を除去し、行注入・スクリプト切断を防ぐ（ワイヤは行指向）。
    /// SakuraScript の改行は `\n` トークンで表すため、生の改行除去は表示上安全。
    /// ReferenceN は数値順、その他ヘッダはキー順で安定出力する（`mapShioriResponse` は順不同で解釈可能）。
    private static func serializeWire(_ resp: BridgeShioriResponse) -> String {
        var hdrs = resp.headers
        let lowerKeys = Set(hdrs.keys.map { $0.lowercased() })
        // Value が未設定なら応答値を Value ヘッダとして出す（空文字でも 200 の有無を区別するため出力）。
        if let value = resp.value, !lowerKeys.contains("value") {
            hdrs["Value"] = value
        }
        let refPairs = hdrs.compactMap { (k, v) -> (Int, String, String)? in
            guard k.lowercased().hasPrefix("reference"),
                  let n = Int(k.dropFirst("reference".count)), n >= 0 else { return nil }
            return (n, k, v)
        }.sorted { $0.0 < $1.0 }
        let refKeys = Set(refPairs.map { $0.1 })

        var lines = ["SHIORI/3.0 \(resp.status) \(shioriStatusMessage(resp.status))"]
        if !lowerKeys.contains("charset") {
            lines.append("Charset: UTF-8")
        }
        for (k, v) in hdrs.sorted(by: { $0.key < $1.key }) where !refKeys.contains(k) {
            lines.append("\(sanitizeHeader(k)): \(sanitizeHeader(v))")
        }
        for (_, k, v) in refPairs {
            lines.append("\(sanitizeHeader(k)): \(sanitizeHeader(v))")
        }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }

    /// ヘッダ行に混入し得る CR/LF を除去する（行注入・スクリプト切断対策）。
    private static func sanitizeHeader(_ s: String) -> String {
        return s.replacingOccurrences(of: "\r\n", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
    }

    private static func shioriStatusMessage(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 311: return "Communicate"
        case 312: return "Not Enough"
        case 400: return "Bad Request"
        case 500: return "Internal Server Error"
        default: return status < 300 ? "OK" : "Error"
        }
    }

    /// 生の値を最小限の SHIORI/3.0 ワイヤ応答へ包む（登録済み Resource 値を `handleResponse` で返す時に使用）。
    private static func synthesizeWire(value: String) -> String {
        return "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: \(sanitizeHeader(value))\r\n\r\n"
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

    func request(event: String, references: [String], headers: [String: String] = [:], method: String = "GET") -> String? {
        // SHIORI/2.x はバイナリ IPC ベースで 3.0 と全く互換性がない。
        // 過去の「3.0 形式ヘッダで 2.6 を名乗る」フォールバックは 2.x 実装には届かないため削除し、
        // 3.0 一本に統一する（旧式 SHIORI が必要な場合は別途 ShioriLoader を拡張する）。
        // method は GET / NOTIFY を切り替える。NOTIFY は返値を期待しないイベントで使う（UKADOC SHIORI method 仕様）。
        let verb = method.uppercased() == "NOTIFY" ? "NOTIFY" : "GET"
        var lines = [
            "\(verb) SHIORI/3.0",
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
