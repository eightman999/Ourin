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

    /// 名前で決まらない Windows の DLL は、DLL と同じフォルダの `<DLL名>.txt` が YAYA の設定なら
    /// YAYA とみなす。YAYA は自分のファイル名から設定ファイル名を決めるため、YAYA を
    /// aya.dll などの別名で同梱したゴースト（Taromati2 の shiori/aya.dll など）がある。
    static func kind(for moduleName: String, ghostRoot: URL) -> ShioriRuntimeKind {
        let byName = kind(for: normalizedModulePath(moduleName))
        guard byName == .native, moduleName.lowercased().hasSuffix(".dll") else { return byName }
        return isYayaConfig(at: yayaConfigURL(for: moduleName, ghostRoot: ghostRoot)) ? .yaya : .native
    }

    /// YAYA の基準フォルダ。SHIORI の load にはモジュール（DLL）のあるフォルダを渡す（UKADOC spec_dll）。
    static func yayaBaseURL(for moduleName: String, ghostRoot: URL) -> URL {
        ghostRoot.appendingPathComponent(normalizedModulePath(moduleName)).deletingLastPathComponent()
    }

    /// YAYA の設定ファイル。yaya.dll なら yaya.txt、aya.dll なら aya.txt。
    static func yayaConfigURL(for moduleName: String, ghostRoot: URL) -> URL {
        let module = URL(fileURLWithPath: normalizedModulePath(moduleName))
        return yayaBaseURL(for: moduleName, ghostRoot: ghostRoot)
            .appendingPathComponent(module.deletingPathExtension().lastPathComponent + ".txt")
    }

    /// 辞書を読む指定（dic・dicdir・include）がある設定ファイルを YAYA（AYA 互換）の設定とみなす。
    /// 値の文字コードは問わないので、キーだけを Latin-1 で読む。
    static func isYayaConfig(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .isoLatin1) else { return false }
        return text.components(separatedBy: .newlines).contains { line in
            let body = line.components(separatedBy: "//")[0]
            guard let comma = body.firstIndex(of: ",") else { return false }
            let key = body[..<comma].trimmingCharacters(in: .whitespaces).lowercased()
            return ["dic", "dicdir", "include"].contains(key)
        }
    }

    /// descript.txt の `shiori,shiori\aya.dll` のような Windows 区切りも受け付ける。
    private static func normalizedModulePath(_ moduleName: String) -> String {
        moduleName.replacingOccurrences(of: "\\", with: "/")
    }

    /// ゴーストのフォルダも見て、名前で決まらない YAYA を判定したうえでランタイムを生成する。
    static func makeRuntime(for moduleName: String, ghostRoot: URL) -> GhostShioriRuntime? {
        switch kind(for: moduleName, ghostRoot: ghostRoot) {
        case .yaya:
            return YayaAdapter()
        case .satori:
            return SatoriAdapter()
        case .native:
            return NativeShioriRuntime()
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
