import Foundation

// Function pointer types for PLUGIN/2.0M
public typealias PluginRequestFn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<Int>) -> UnsafePointer<UInt8>?
public typealias PluginLoadFn = @convention(c) (UnsafePointer<CChar>) -> Int32
public typealias PluginUnloadFn = @convention(c) () -> Void

/// Single native plugin module wrapper (`.plugin` / `.bundle` / `.dylib`).
///
/// request の呼び出し規約は 2 種類を扱う。
/// - `.ourin`（既定）: `request(const uchar*, size_t, size_t*)`。戻り値はモジュール所有（ホストは複製するだけ）。
/// - `.ukagaka`: Windows DLL と同じ `request(HGLOBAL, long*)`。Info.plist の `OurinModuleABI` で宣言するか、
///   単体 `.dylib`（DLL ソースをそのままビルドしたもの）の場合に選ぶ。
public struct Plugin: Hashable {
    /// ロード対象のモジュール（`.plugin` / `.bundle` / `.dylib`）。
    public let url: URL
    let bundle: Bundle?
    let convention: UkagakaModuleABI.Convention
    let request: PluginRequestFn?
    let ukagakaRequest: UkagakaModuleABI.RequestFn?
    let loadEntry: UkagakaModuleABI.LoadFn?
    let unloadEntry: PluginUnloadFn?
    /// DLL 変換で作った `.plugin`（`OurinPluginEngine` 指定）を内蔵エンジンで処理するホスト。
    let engine: PluginEngineHost?

    public init(url: URL) throws {
        if let kind = DLLPluginConverter.engineKind(ofBundleAt: url) {
            let info = Bundle(url: url)?.infoDictionary
            let moduleName = info?[DLLPluginConverter.originalModuleKey] as? String ?? url.lastPathComponent
            self.url = url
            self.bundle = Bundle(url: url)
            self.convention = .ourin
            self.request = nil
            self.ukagakaRequest = nil
            self.loadEntry = nil
            self.unloadEntry = nil
            self.engine = PluginEngineHost(
                kind: kind,
                moduleDirectory: url.deletingLastPathComponent(),
                moduleFileName: URL(fileURLWithPath: moduleName.replacingOccurrences(of: "\\", with: "/")).lastPathComponent
            )
            return
        }
        guard let executableURL = UkagakaModuleABI.executableURL(forModuleAt: url) else {
            throw NSError(domain: "Plugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid bundle"])
        }
        // CFBundle の識別子検索に頼らず実行体を直接開く（CFBundleIdentifier の無い移植 bundle や単体 dylib を扱うため）。
        guard let handle = dlopen(executableURL.path, RTLD_NOW | RTLD_LOCAL) else {
            let detail = dlerror().map { String(cString: $0) } ?? "unknown"
            throw NSError(domain: "Plugin", code: -1, userInfo: [NSLocalizedDescriptionKey: "dlopen failed: \(detail)"])
        }
        func sym<T>(_ names: String...) -> T? {
            for name in names {
                if let fp = dlsym(handle, name) { return unsafeBitCast(fp, to: T.self) }
            }
            return nil
        }

        let isBundle = executableURL != url
        self.url = url
        self.bundle = isBundle ? Bundle(url: url) : nil
        self.convention = UkagakaModuleABI.convention(
            declaredIn: bundle?.infoDictionary,
            fallback: isBundle ? .ourin : .ukagaka
        )
        switch convention {
        case .ourin:
            self.request = sym("request", "plugin_request")
            self.ukagakaRequest = nil
        case .ukagaka:
            self.request = nil
            self.ukagakaRequest = sym("request", "plugin_request")
        }
        guard request != nil || ukagakaRequest != nil else {
            throw NSError(domain: "Plugin", code: -2, userInfo: [NSLocalizedDescriptionKey: "request not found"])
        }
        // ukagaka DLL 規約: `loadu` は UTF-8 パス版 load。存在すれば優先（macOS のパスは UTF-8）。
        self.loadEntry = sym("loadu", "load", "plugin_loadu", "plugin_load")
        self.unloadEntry = sym("unloadu", "unload", "plugin_unloadu", "plugin_unload")
        self.engine = nil
    }

    /// `unload` を呼ぶ（内蔵エンジンならエンジンを停止する）。
    public func unload() {
        if let engine {
            engine.unload()
            return
        }
        unloadEntry?()
    }

    /// `load` / `loadu` を呼ぶ。引数はモジュールのディレクトリ（末尾区切り付き、malloc 確保で所有権はモジュールへ）。
    /// 旧来の `int load(const char*)` にも同じポインタで互換。エントリが無い場合は成功扱い。
    @discardableResult
    public func load(directoryURL: URL) -> Bool {
        if let engine { return engine.load() }
        guard let loadEntry else { return true }
        return UkagakaModuleABI.callLoad(loadEntry, directoryURL: directoryURL)
    }

    /// Send raw wire text to plugin and return response string decoded by PLUGIN Charset semantics.
    public func send(_ text: String, charset: String = "UTF-8") -> String {
        let requestData = PluginWireCodec.encodeRequest(text, charset: charset)
        guard let responseData = send(requestData) else { return "" }
        return PluginWireCodec.decodeResponse(responseData, requestCharset: charset) ?? ""
    }

    /// Send raw wire bytes to plugin and return raw response bytes.
    public func send(_ data: Data) -> Data? {
        if let engine {
            return engine.request(data)
        }
        if let ukagakaRequest {
            return UkagakaModuleABI.callRequest(ukagakaRequest, data: data)
        }
        guard let request else { return nil }
        var outLen: Int = 0
        var bytes = Array(data)
        if bytes.isEmpty { bytes = [0] }
        let byteCount = data.count

        let respPtr = bytes.withUnsafeMutableBytes { raw -> UnsafePointer<UInt8>? in
            return request(raw.bindMemory(to: UInt8.self).baseAddress!, byteCount, &outLen)
        }
        guard let p = respPtr else { return nil }
        return Data(bytes: p, count: max(outLen, 0))
    }

    /// Send structured PLUGIN/2.0M request to plugin and parse response
    public func sendRequest(_ request: PluginRequest) throws -> PluginResponse {
        let wireText = PluginProtocolBuilder.buildRequest(request)
        let responseText = send(wireText, charset: request.charset)
        return try PluginProtocolParser.parseResponse(responseText)
    }

    /// Convenient method to send GET request with ID
    public func get(id: String, charset: String = "UTF-8", sender: String? = "Host", references: [String: String] = [:]) throws -> PluginResponse {
        let request = PluginRequest(
            method: .get,
            id: id,
            charset: charset,
            sender: sender,
            references: references
        )
        return try sendRequest(request)
    }

    /// Convenient method to send NOTIFY request with ID
    public func notify(id: String, charset: String = "UTF-8", sender: String? = "Host", references: [String: String] = [:]) throws -> PluginResponse {
        let request = PluginRequest(
            method: .notify,
            id: id,
            charset: charset,
            sender: sender,
            references: references
        )
        return try sendRequest(request)
    }

    /// Get plugin version
    public func version() throws -> String? {
        let response = try get(id: "version")
        return response.value
    }
}

extension Plugin {
    public static func == (lhs: Plugin, rhs: Plugin) -> Bool {
        lhs.url == rhs.url
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
