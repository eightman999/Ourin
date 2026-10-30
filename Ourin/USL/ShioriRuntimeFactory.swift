import Foundation

/// SHIORIモジュール名からOurin内のランタイム種別を決める。
struct ShioriRuntimeFactory {
    /// 通常起動と再ロードで共有する、唯一のSHIORIモジュール選択規則。
    /// descript.txtを読めない旧ゴーストだけは従来互換でYAYAへフォールバックする。
    static func moduleName(for configuration: GhostConfiguration?) -> String {
        if let native = nativeOverride(for: configuration) { return native }
        return configuration?.shiori ?? "yaya.dll"
    }

    private static func nativeOverride(for configuration: GhostConfiguration?) -> String? {
        guard let native = configuration?.shioriMacOS?.trimmingCharacters(in: .whitespacesAndNewlines),
              !native.isEmpty else { return nil }
        return native
    }

    static func usesNativeOverride(moduleName: String, configuration: GhostConfiguration?) -> Bool {
        guard let native = nativeOverride(for: configuration) else { return false }
        return normalizedModulePath(native) == normalizedModulePath(moduleName)
    }

    static func kind(for moduleName: String) -> ShioriRuntimeKind {
        let rawName = URL(fileURLWithPath: normalizedModulePath(moduleName)).deletingPathExtension().lastPathComponent.lowercased()
        let name = rawName.hasPrefix("lib") ? String(rawName.dropFirst(3)) : rawName
        switch name {
        case "yaya", "yaya_core":
            return .yaya
        case "satori", "satoriya", "satori_core":
            return .satori
        case "shiolink", "shiolink_core":
            return .shiolink
        case "rishu_proxy":
            return .rishu
        default:
            return .native
        }
    }

    /// 名前で決まらない Windows の DLL は、DLL と同じフォルダの `<DLL名>.txt` が YAYA の設定なら
    /// YAYA とみなす。YAYA は自分のファイル名から設定ファイル名を決めるため、YAYA を
    /// aya.dll などの別名で同梱したゴースト（Taromati2 の shiori/aya.dll など）がある。
    static func kind(for moduleName: String, ghostRoot: URL,
                     configuration: GhostConfiguration? = nil) -> ShioriRuntimeKind {
        if usesNativeOverride(moduleName: moduleName, configuration: configuration) { return .native }
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
    static func makeRuntime(for moduleName: String, ghostRoot: URL,
                            configuration: GhostConfiguration? = nil) -> GhostShioriRuntime? {
        switch kind(for: moduleName, ghostRoot: ghostRoot, configuration: configuration) {
        case .yaya:
            return YayaAdapter()
        case .satori:
            return SatoriAdapter()
        case .shiolink:
            return ShiolinkAdapter()
        case .rishu:
            return RishuProxyAdapter()
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
        case .shiolink:
            return ShiolinkAdapter()
        case .rishu:
            return RishuProxyAdapter()
        case .native:
            return NativeShioriRuntime()
        }
    }

    /// Explicit per-ghost port selection preserves the original Windows descriptor.
    static func makeRuntime(context: ShioriRuntimeLoadContext) -> GhostShioriRuntime? {
        if context.nativeModuleOverride { return NativeShioriRuntime() }
        if let directory = ShioriEnginePlugins.dictionaryDirectory(for: context),
           UkagakaModuleABI.resolveCaseInsensitive("SHIOLINK.ourin.ini", in: directory) != nil {
            if let configuration = try? ShiolinkConfiguration.loadExplicit(context: context) {
                if let selected = configuration.moduleOverride {
                    if selected.caseInsensitiveCompare(URL(fileURLWithPath: context.moduleName
                        .replacingOccurrences(of: "\\", with: "/")).lastPathComponent) == .orderedSame {
                        return ShiolinkAdapter()
                    }
                    // A port for a different DLL must not change this module's normal route.
                    return makeRuntime(for: context.moduleName, ghostRoot: context.ghostRoot)
                }
                if kind(for: context.moduleName) == .shiolink { return ShiolinkAdapter() }
            }
            // Native modules keep their existing lookup path. Built-in engines must
            // not hide an invalid explicit transport by running a different VM.
            return kind(for: context.moduleName) == .native ? NativeShioriRuntime() : nil
        }
        if ShioriEnginePlugins.ghostProvidedNativeModule(context: context) != nil {
            return NativeShioriRuntime()
        }
        switch ShioriEnginePlugins.resolution(context: context) {
        case .selected(let engine):
            if engine.descriptor.kind == "native" { return NativeShioriRuntime() }
            return ShiolinkAdapter()
        case .unavailableSelection, .ambiguous:
            return nil
        case .noMatch:
            return makeRuntime(for: context.moduleName, ghostRoot: context.ghostRoot)
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

    init(loaderFactory: @escaping LoaderFactory = NativeShioriRuntime.defaultLoaderFactory) {
        self.loaderFactory = loaderFactory
    }

    private static func defaultLoaderFactory(context: ShioriRuntimeLoadContext) -> ShioriRequesting? {
        let loadDirectory = ShioriEnginePlugins.dictionaryDirectory(for: context) ?? context.ghostRoot
            .appendingPathComponent(context.moduleName.replacingOccurrences(of: "\\", with: "/"))
            .deletingLastPathComponent()
        if context.nativeModuleOverride {
            // An explicit platform module is authoritative, including when it is missing.
            let relative = context.moduleName.replacingOccurrences(of: "\\", with: "/")
            guard let url = UkagakaModuleABI.resolveCaseInsensitive(relative, in: context.ghostRoot,
                                                                    fileManager: .default) else { return nil }
            return ShioriLoader(moduleURL: url, communication: context.communication, loadDirectory: loadDirectory)
        }
        if let url = ShioriEnginePlugins.ghostProvidedNativeModule(context: context) {
            return ShioriLoader(moduleURL: url, communication: context.communication, loadDirectory: loadDirectory)
        }
        if let url = ShioriEnginePlugins.nativeModule(context: context) {
            return ShioriLoader(moduleURL: url, communication: context.communication, loadDirectory: loadDirectory)
        }
        if let url = BundledShioriEngine.resolveModuleURL(
            moduleName: context.moduleName, ghostURL: context.ghostURL, ghostRoot: context.ghostRoot
        ) {
            return ShioriLoader(moduleURL: url, communication: context.communication, loadDirectory: loadDirectory)
        }
        return ShioriLoader(module: context.moduleName, base: context.ghostURL,
                            communication: context.communication, loadDirectory: loadDirectory)
    }

    @discardableResult
    func load(context: ShioriRuntimeLoadContext) -> Bool {
        unload()
        var options = context.communication
        if !context.nativeModuleOverride,
           ShioriEnginePlugins.ghostProvidedNativeModule(context: context) == nil,
           options.encoding == nil, options.forceEncoding == nil,
           let plugin = ShioriEnginePlugins.matching(context: context), plugin.descriptor.kind == "native",
           let charset = plugin.descriptor.charset {
            options.encoding = charset
        }
        let effectiveContext = ShioriRuntimeLoadContext(
            ghostURL: context.ghostURL, ghostRoot: context.ghostRoot, moduleName: context.moduleName,
            nativeModuleOverride: context.nativeModuleOverride,
            dictionaryEntries: context.dictionaryEntries, dictionaryEncoding: context.dictionaryEncoding,
            functionDepthLimit: context.functionDepthLimit, communication: options)
        guard let loaded = loaderFactory(effectiveContext) else {
            NSLog("[NativeShioriRuntime] Failed to load %@", context.moduleName)
            return false
        }
        loader = loaded
        communication = options
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
