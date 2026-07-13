import Foundation

/// SHIORIモジュール名からOurin内のランタイム種別を決める。
struct ShioriRuntimeFactory {
    /// 通常起動と再ロードで共有する、唯一のSHIORIモジュール選択規則。
    /// descript.txtを読めない旧ゴーストだけは従来互換でYAYAへフォールバックする。
    static func moduleName(for configuration: GhostConfiguration?) -> String {
        configuration?.shiori ?? "yaya.dll"
    }

    static func kind(for moduleName: String) -> ShioriRuntimeKind {
        let rawName = URL(fileURLWithPath: moduleName).deletingPathExtension().lastPathComponent.lowercased()
        let name = rawName.hasPrefix("lib") ? String(rawName.dropFirst(3)) : rawName
        switch name {
        case "yaya", "yaya_core":
            return .yaya
        case "satori", "satoriya", "satori_core":
            return .satori
        default:
            return .native
        }
    }

    /// モジュール名に対応するランタイムを生成する。実ロードは共通のload(context:)で行う。
    static func makeRuntime(for moduleName: String) -> GhostShioriRuntime? {
        switch kind(for: moduleName) {
        case .yaya:
            return YayaAdapter()
        case .satori:
            return SatoriAdapter()
        case .native:
            return NativeShioriRuntime()
        }
    }

    /// 移行期間中の既存呼び出し互換。新規コードはmakeRuntime(for:)を使う。
    static func makeProcessRuntime(for moduleName: String) -> GhostShioriRuntime? {
        makeRuntime(for: moduleName)
    }
}

/// Bundle/Dylib/XPC SHIORIを共通ランタイム境界へ接続する。
final class NativeShioriRuntime: GhostShioriRuntime {
    typealias LoaderFactory = (_ context: ShioriRuntimeLoadContext) -> ShioriRequesting?

    let kind: ShioriRuntimeKind = .native
    private(set) var isLoaded = false
    var resourceManager: ResourceManager?

    private let loaderFactory: LoaderFactory
    private var loader: ShioriRequesting?
    private var communication = ShioriCommunicationOptions()

    init(loaderFactory: @escaping LoaderFactory = { context in
        ShioriLoader(module: context.moduleName, base: context.ghostURL, communication: context.communication)
    }) {
        self.loaderFactory = loaderFactory
    }

    @discardableResult
    func load(context: ShioriRuntimeLoadContext) -> Bool {
        unload()
        guard let loaded = loaderFactory(context) else {
            NSLog("[NativeShioriRuntime] Failed to load %@", context.moduleName)
            return false
        }
        loader = loaded
        communication = context.communication
        isLoaded = true
        return true
    }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        _ = timeout // 直接ロード型は同期ABI。隔離型XPCの期限はXpcBackendが管理する。
        guard isLoaded, let loader else { return nil }
        let request = ShioriWireCodec.makeRequest(
            method: method,
            id: id,
            headers: headers,
            refs: refs,
            protocolVersion: communication.version ?? "SHIORI/3.0",
            charset: communication.outboundCharset
        )
        guard let response = loader.request(request) else { return nil }
        return ShioriWireCodec.parseResponse(response)
    }

    func unload() {
        loader?.unload()
        loader = nil
        isLoaded = false
    }
}
