import Foundation

// MARK: - SSTPDispatcher ブリッジ注入境界（境界6）

/// `SSTPDispatcher` が SHIORI ブリッジへ要求を委譲するための注入可能な境界。
///
/// 実運用では `ShioriBridgeContext` がこのプロトコルへ直接適合し、プロセス既定の `.shared` を使う。
/// `SSTPDispatcher` / `OurinExternalServer` は `BridgeToSHIORI.shared` を直接参照せず、
/// この抽象を経由して SHIORI 応答を得る。これによりテストは `ShioriBridgeContext` の独立した
/// インスタンスを構築・注入でき、global な `BridgeToSHIORI` / `.shared` へ触れずに並列実行できる。
///
/// このプロトコルは SSTPDispatcher 境界でのみ使う。`BridgeToSHIORI` の public static API
/// （`handle` / `setResource` / `reset` 等、GhostManager/ResourceBridge/EventBridge 経由）は
/// 従来どおり `.shared` へ委譲し続けるため、本プロトコル追加による影響は SSTP ディスパッチ経路に閉じる。
///
/// - note: `SstpDispatcherHost`（UI 副作用の委譲先）と並列する依存境界。
///   新たな可変 global singleton や thread-local workaround は追加しない。
///   `Sendable` を要求するのは、TCP/HTTP/XPC の各ハンドラスレッドから安全に呼ばれるため。
protocol ShioriBridge: Sendable {
    /// SSTP ディスパッチャ向け: 完全な SHIORI/3.0 ワイヤ応答文字列を返す。
    /// `ReferenceN` / `Value` / `ValueNotify` / `Status` / `Surface` 等の応答ヘッダを保持する。
    ///
    /// - note: 実装はロックを保持したまま外部 IPC や resolver クロージャを呼んではならない
    ///   （デッドロック/再入リスク。`ShioriBridgeContext` はロック内で参照を捕捉し、
    ///   解放してから native/resolver を呼ぶ）。
    func handleResponse(
        event: String,
        references: [String],
        headers: [String: String],
        method: String
    ) -> String
}

// MARK: - ネイティブ SHIORI バンドル境界（境界1）

/// ネイティブ SHIORI バンドル（ローカル SHIORI モジュール）への要求境界。
///
/// ネイティブバンドルは SHIORI/3.0 ワイヤ応答文字列を返すため、`handleResponse` は
/// これを再直列化せずそのまま返す（Status / ReferenceN / Charset 等の応答ヘッダを保持）。
/// `handle` 側では ShioriBridgeWireCodec で Value のみを取り出す。
/// テストでは偽ソースを注入し、ShioriLoader / XPC に依存せずにルーティングを検証できる。
protocol NativeShioriSource: AnyObject {
    /// SHIORI/3.0 ワイヤ応答文字列を返す。応答不可の場合は nil。
    func wireResponse(method: String, event: String, references: [String], headers: [String: String]) -> String?
}

/// `ShioriLoader` を内包するネイティブ SHIORI バンドルの具象ソース。
/// 従来 BridgeToSHIORI が持っていた private ShioriHost と同等。環境変数 SHIORI_BUNDLE_PATH で設定される。
final class BundleNativeShioriSource: NativeShioriSource {
    private let host: ShioriHost

    init?(bundlePath: String) {
        guard let host = ShioriHost(bundlePath: bundlePath) else { return nil }
        self.host = host
    }

    func wireResponse(method: String, event: String, references: [String], headers: [String: String]) -> String? {
        host.request(event: event, references: references, headers: headers, method: method)
    }
}

// MARK: - 稼働中ゴーストリゾルバ境界（境界2）

/// 稼働中ゴースト（YAYA 等）への要求境界。
///
/// 構造化された SHIORI 応答を返す。Value は改行を含み得るため、`handle` では生値をそのまま返し
/// （切断しない）、`handleResponse` では ShioriBridgeWireCodec.serialize で sanitize 付き直列化を行う。
/// アプリ起動時に AppDelegate がクロージャ経由で設定し、SSTP バックグラウンド等から呼ばれる。
protocol ShioriGhostResolver: AnyObject {
    /// 構造化 SHIORI 応答を返す。宛先ゴーストが無い／応答できない場合は nil。
    func resolve(method: String, event: String, references: [String], headers: [String: String]) -> BridgeToSHIORI.BridgeShioriResponse?
}

/// `BridgeToSHIORI.liveGhostResolver` の public クロージャを `ShioriGhostResolver` へ橋渡しするラッパ。
/// 公開 API のクロージャ型を変えずに、プロトコル境界へ適合させる。
final class ClosureShioriGhostResolver: ShioriGhostResolver {
    let closure: (String, String, [String], [String: String]) -> BridgeToSHIORI.BridgeShioriResponse?

    init(closure: @escaping (String, String, [String], [String: String]) -> BridgeToSHIORI.BridgeShioriResponse?) {
        self.closure = closure
    }

    func resolve(method: String, event: String, references: [String], headers: [String: String]) -> BridgeToSHIORI.BridgeShioriResponse? {
        closure(method, event, references, headers)
    }
}

// MARK: - テスト用 Resource マップ境界（境界3）

/// テスト用 Resource 返値を保持するストア。
///
/// 実運用時は共有マップ（NSLock 保護）、XCTest/Swift Testing 実行時はスレッドローカルなマップを使う。
/// スレッドローカル化は Resource マップ（テスト固有の静的なデータ）に限定した既存の分離技法であり、
/// クロススレッドで呼ばれる ghost resolver へは適用しない（後述の競合理由を参照）。
///
/// `threadMapKey` はインスタンス毎に固有の UUID を含む。これにより `ShioriBridgeContext` の
/// インスタンスを複数作った場合でも、それぞれの `ResourceTestStore` は独立したスレッドローカル
/// スロットを使い、インスタンステスト同士や `.shared` との間で Resource マップを共有しない。
final class ResourceTestStore {
    private let threadMapKey: String

    init() {
        self.threadMapKey = "BridgeToSHIORI.threadResourceMap.\(UUID().uuidString)"
    }

    private var sharedMap: [String: String] = [:]
    private let lock = NSLock()

    private var isRunningTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
    }

    /// テスト用に返値を登録する。
    func set(key: String, value: String) {
        if isRunningTests {
            var map = currentThreadMap() ?? [:]
            map[key] = value
            setCurrentThreadMap(map)
            return
        }
        lock.lock()
        sharedMap[key] = value
        lock.unlock()
    }

    /// テスト/明示登録された Resource 値があれば返す（無ければ nil）。
    /// Resource 疑似イベント以外、あるいは Reference0 が無ければ nil。
    func registeredValue(event: String, references: [String]) -> String? {
        guard event == "Resource", let key = references.first else { return nil }
        if isRunningTests, let map = currentThreadMap() {
            return map[key]
        }
        lock.lock()
        let val = sharedMap[key]
        lock.unlock()
        return val
    }

    /// 登録値をすべて消去する（テスト間で静的な Resource 依存が漏れないように）。
    func reset() {
        if isRunningTests {
            // Swift Testing はスイートを並列実行する。共有 static state によるスイート間干渉を避けるため、
            // テスト時はスレッドローカルなマップを使う。
            setCurrentThreadMap([:])
        } else {
            lock.lock()
            sharedMap.removeAll()
            lock.unlock()
        }
    }

    private func currentThreadMap() -> [String: String]? {
        Thread.current.threadDictionary[threadMapKey] as? [String: String]
    }

    private func setCurrentThreadMap(_ map: [String: String]) {
        Thread.current.threadDictionary[threadMapKey] = map
    }
}

// MARK: - static mutable lifecycle 境界 + 合成（境界5）

/// SHIORI ブリッジの解決状態とルーティングを保持する注入可能なインスタンス。
///
/// 従来 `BridgeToSHIORI` の enum static storage に散在していた可変状態（ネイティブソース／
/// ゴーストリゾルバ／テスト Resource マップ）を一つのインスタンスへ集約し、単一のロックで保護する。
/// 新たな可変 global singleton の追加ではなく、既存の static 可変状態を一箇所に整理したもの。
///
/// アクセス構成:
/// - 実運用の全アクセスは `shared`（プロセス固有の single source of truth）へ集約され、
///   `BridgeToSHIORI` の public static API がこれへ委譲する。
/// - テストは internal initializer から `shared` とは独立したインスタンスを構築し、
///   fake `NativeShioriSource` / `ShioriGhostResolver` を明示的に注入できる。
///   これにより global な `BridgeToSHIORI` を触らず、他スイートと並列競合しない。
///
/// スレッド安全性の基本方針:
/// - `handle` / `handleResponse` は **ロック内で native/resolver の参照を捕捉し、ロックを解放してから
///   ネイティブ IPC やリゾルバクロージャを実行する**。外部 SHIORI 実行をロック保持中に行わない。
/// - `configure` / `reset` / 各 setter で ShioriHost 構築やラッパ生成は **ロック外** で行い、
///   差し替えのみをロック内で行う。更に **旧 source/resolver の強参照をロック内で local へ退避し、
///   unlock 後まで `withExtendedLifetime` で生存させる**。これにより旧 `BundleNativeShioriSource` の
///   deinit（`ShioriHost.deinit` → `loader.unload()`）がロック保持中に走るのを防ぐ。
///
/// `@unchecked Sendable`: すべての可変状態が `lock`（NSLock）で保護されており、
/// `ResourceTestStore` も内部ロック/スレッド辞書で自己同期するため、Swift Testing の
/// 並列ワーカーから `Sendable` として安全に扱える（コンパイラ自動準拠は final class のため効かない）。
final class ShioriBridgeContext: @unchecked Sendable {
    private let lock = NSLock()
    private var nativeSourceValue: NativeShioriSource?
    private var ghostResolverValue: ShioriGhostResolver?
    private let resources = ResourceTestStore()

    /// プロセス固有の既定コンテキスト。BridgeToSHIORI の public static API はこれへ委譲する。
    /// 実運用で参照される実体はこの `shared` 一つのみ。
    static let shared = ShioriBridgeContext(nativeSource: makeEnvNativeSource())

    /// テスト/内部利用向け: ネイティブソース・ゴーストリゾルバを明示的に注入して構築する。
    /// 両引数とも省略時は nil（空のコンテキスト）。`shared` とは独立したインスタンスになるため、
    /// fake を注入したテストが global 状態（`.shared` / `BridgeToSHIORI`）へ触れない。
    init(nativeSource: NativeShioriSource? = nil, ghostResolver: ShioriGhostResolver? = nil) {
        self.nativeSourceValue = nativeSource
        self.ghostResolverValue = ghostResolver
    }

    // MARK: - Resolution（ルーティング判断。テストで差し替え可能）

    /// SHIORI 互換イベントを処理し、応答の「値」（Value / スクリプト）を返す。
    /// 解決順序は従来どおり (1) 登録済み Resource 値、(2) ネイティブ SHIORI バンドル、(3) 稼働中ゴースト。
    func handle(event: String, references: [String], headers: [String: String], method: String) -> String {
        if let registered = resources.registeredValue(event: event, references: references) {
            return registered
        }
        let (native, resolver) = snapshotSources()
        // ネイティブ SHIORI バンドルはワイヤ文字列を返すため Value を取り出す。
        if let nativeWire = native?.wireResponse(method: method, event: event, references: references, headers: headers) {
            return ShioriBridgeWireCodec.value(fromWire: nativeWire)
        }
        // 稼働中ゴーストは構造化応答を返す。値は改行を含み得るためそのまま返す（切断しない）。
        if let resp = resolver?.resolve(method: method, event: event, references: references, headers: headers) {
            return resp.value ?? ""
        }
        return ""
    }

    /// SSTP ディスパッチャ向け: 完全な SHIORI/3.0 ワイヤ応答文字列を返す。
    /// ReferenceN / Value / ValueNotify / Status / Surface 等を保持できるよう、値でなく応答全体を返す。
    func handleResponse(event: String, references: [String], headers: [String: String], method: String) -> String {
        if let registered = resources.registeredValue(event: event, references: references) {
            // テスト／明示登録値が既に完全なSHIORI応答なら二重包装しない。
            // `Value: SHIORI/3.0 ...` にすると Status や ReferenceN 等の応答ヘッダを失う。
            if registered.uppercased().hasPrefix("SHIORI/") {
                return registered
            }
            return ShioriBridgeWireCodec.synthesizeWire(value: registered)
        }
        let (native, resolver) = snapshotSources()
        if let nativeWire = native?.wireResponse(method: method, event: event, references: references, headers: headers) {
            return nativeWire
        }
        if let resp = resolver?.resolve(method: method, event: event, references: references, headers: headers) {
            return ShioriBridgeWireCodec.serialize(resp)
        }
        return ""
    }

    /// ロック内で native/resolver の参照を捕捉し、呼び出し元がロック外で実行できるようにする。
    /// これにより外部 IPC（ネイティブ）やクロージャ（ゴースト）をロック保持中に呼ばない。
    private func snapshotSources() -> (NativeShioriSource?, ShioriGhostResolver?) {
        lock.lock()
        let native = nativeSourceValue
        let resolver = ghostResolverValue
        lock.unlock()
        return (native, resolver)
    }

    // MARK: - Test resource map

    func setResource(_ key: String, value: String) {
        resources.set(key: key, value: value)
    }

    // MARK: - Lifecycle（境界5: static mutable lifecycle）

    /// テスト用登録値をすべて消去し、環境変数ベースのホスト設定へ戻す。
    /// 稼働中ゴーストへのリゾルバも解除する（テスト間で実ゴースト依存が漏れないように）。
    func reset() {
        resources.reset()
        // 環境変数からネイティブソースを再構築するのはロック外（IPC/ファイルアクセスを伴い得るため）。
        let newNative = Self.makeEnvNativeSource()
        var oldNative: NativeShioriSource?
        var oldResolver: ShioriGhostResolver?
        lock.lock()
        oldNative = nativeSourceValue
        oldResolver = ghostResolverValue
        nativeSourceValue = newNative
        ghostResolverValue = nil
        lock.unlock()
        // 旧 source/resolver の deinit（ShioriHost.deinit -> loader.unload 等）をロック外へ追い出す。
        // Swift の最適化で早期解放され得るため withExtendedLifetime で unlock 後まで生存を保証する。
        withExtendedLifetime(oldNative) { _ in }
        withExtendedLifetime(oldResolver) { _ in }
    }

    /// 明示的に SHIORI バンドルを設定する。nil の場合はホストを無効化する。
    @discardableResult
    func configure(bundlePath: String?) -> Bool {
        guard let bundlePath, !bundlePath.isEmpty else {
            var old: NativeShioriSource?
            lock.lock()
            old = nativeSourceValue
            nativeSourceValue = nil
            lock.unlock()
            withExtendedLifetime(old) { _ in }
            return true
        }
        // ShioriHost 構築は IPC/ファイルアクセスを伴う可能性があるためロック外で行う。
        guard let source = BundleNativeShioriSource(bundlePath: bundlePath) else {
            return false
        }
        var old: NativeShioriSource?
        lock.lock()
        old = nativeSourceValue
        nativeSourceValue = source
        lock.unlock()
        withExtendedLifetime(old) { _ in }
        return true
    }

    /// public static な `liveGhostResolver` クロージャの実体。
    /// クロージャを `ShioriGhostResolver` プロトコル境界へ橋渡しし、取得時は元のクロージャへ戻す。
    var liveGhostResolver: ((String, String, [String], [String: String]) -> BridgeToSHIORI.BridgeShioriResponse?)? {
        get {
            lock.lock()
            let resolver = ghostResolverValue
            lock.unlock()
            if let closure = resolver as? ClosureShioriGhostResolver {
                return closure.closure
            }
            guard let resolver else { return nil }
            // クロージャ以外（テストでプロトコル実体を直接注入した場合）は呼び出しラッパを返す。
            return { method, event, references, headers in
                resolver.resolve(method: method, event: event, references: references, headers: headers)
            }
        }
        set {
            // ラッパ生成（メモリ確保）はロック外で行う。
            let newWrapper: ShioriGhostResolver? = newValue.map { ClosureShioriGhostResolver(closure: $0) }
            var old: ShioriGhostResolver?
            lock.lock()
            old = ghostResolverValue
            ghostResolverValue = newWrapper
            lock.unlock()
            withExtendedLifetime(old) { _ in }
        }
    }

    /// テスト／内部利用向け: プロトコル実体のリゾルバを直接注入する。
    /// public クロージャ API を経由せずにルーティングを差し替えたい場合に使う。
    func setGhostResolver(_ resolver: ShioriGhostResolver?) {
        var old: ShioriGhostResolver?
        lock.lock()
        old = ghostResolverValue
        ghostResolverValue = resolver
        lock.unlock()
        withExtendedLifetime(old) { _ in }
    }

    /// テスト向け: プロトコル実体のネイティブソースを直接注入する。
    func setNativeSource(_ source: NativeShioriSource?) {
        var old: NativeShioriSource?
        lock.lock()
        old = nativeSourceValue
        nativeSourceValue = source
        lock.unlock()
        withExtendedLifetime(old) { _ in }
    }

    private static func makeEnvNativeSource() -> NativeShioriSource? {
        guard let path = ProcessInfo.processInfo.environment["SHIORI_BUNDLE_PATH"] else {
            return nil
        }
        return BundleNativeShioriSource(bundlePath: path)
    }
}

// MARK: - Internal SHIORI host bridge

/// ネイティブ SHIORI バンドルを ShioriLoader（XPC/dylib）へ接続する内部ホスト。
/// BundleNativeShioriSource の実装詳細。従来 BridgeToSHIORI.swift にあった private クラスと同等。
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
        // SHIORI/3.0 ワイヤは ShioriWireCodec に集約（ID=イベント名、SecurityOrigin:null 既定など SSP 互換）。
        let req = ShioriWireCodec.makeRequest(
            method: method,
            id: event,
            headers: headers,
            refs: references
        )
        return loader.request(req)
    }
}

// MARK: - ShioriBridge 適合（境界6）

/// `ShioriBridgeContext` は既に `handleResponse` を実装しているため、プロトコル適合は
/// 宣言のみで完結する。`SSTPDispatcher` / `OurinExternalServer` はこの境界経由で
/// SHIORI 応答を得る（`.shared` の直接参照を排除）。
extension ShioriBridgeContext: ShioriBridge {}
