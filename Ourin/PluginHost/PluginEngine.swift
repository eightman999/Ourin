import Foundation

/// SHIORI エンジンの DLL（yaya.dll / kagari.dll 等）をプラグインとして使うパッケージを、
/// Ourin 内蔵の macOS 版エンジンで動かすための種別。
///
/// 伺かのプラグインには、本体 DLL が汎用エンジンで処理は同梱の辞書・スクリプトに書かれているものが多い。
/// その DLL は x86 の Windows コードなので macOS では実行できないが、同じエンジンの macOS 版へ
/// 要求文（PLUGIN/2.0 のワイヤテキスト）をそのまま渡せば同じ辞書が同じように動く。
public enum PluginEngineKind: String, CaseIterable {
    case yaya
    case kagari

    /// DLL のファイル名（`yaya.dll`、`system\aya.dll` 等）から内蔵エンジンを判定する。
    public static func recognize(moduleName: String) -> PluginEngineKind? {
        let normalized = moduleName.replacingOccurrences(of: "\\", with: "/")
        var stem = URL(fileURLWithPath: normalized).deletingPathExtension().lastPathComponent.lowercased()
        if stem.hasPrefix("lib") { stem.removeFirst(3) }
        switch stem {
        case "yaya", "aya", "aya5": return .yaya
        case "kagari": return .kagari
        default: return nil
        }
    }
}

/// 内蔵エンジンでプラグイン要求を処理するホスト。`Plugin` から参照型として共有される。
final class PluginEngineHost {
    let kind: PluginEngineKind
    /// エンジンに渡すモジュールのフォルダ（元 DLL の置き場所。辞書の相対パスの基準）。
    let moduleDirectory: URL
    /// 元 DLL のファイル名（YAYA の設定ファイル名 `<stem>.txt` を決めるのに使う）。
    let moduleFileName: String

    private let lock = NSLock()
    private var yaya: YayaAdapter?
    private var native: NativeShioriModule?

    init(kind: PluginEngineKind, moduleDirectory: URL, moduleFileName: String) {
        self.kind = kind
        self.moduleDirectory = moduleDirectory
        self.moduleFileName = moduleFileName
    }

    /// エンジンを起動し、DLL の `load` 相当（辞書の読み込みと `load` 関数）を行う。
    @discardableResult
    func load() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard yaya == nil, native == nil else { return true }
        switch kind {
        case .yaya:
            guard let adapter = YayaAdapter() else { return false }
            let stem = URL(fileURLWithPath: moduleFileName.replacingOccurrences(of: "\\", with: "/"))
                .deletingPathExtension().lastPathComponent
            guard adapter.loadModule(root: moduleDirectory, configName: stem + ".txt") else {
                adapter.unload()
                return false
            }
            yaya = adapter
            return true
        case .kagari:
            guard let engineURL = BundledShioriEngine.bundledURL(for: .kagari),
                  let module = try? NativeShioriModule(url: engineURL, loadDirectory: moduleDirectory) else {
                return false
            }
            native = module
            return true
        }
    }

    /// 要求のワイヤバイト列を処理して応答バイト列を返す。
    func request(_ data: Data) -> Data? {
        if yaya == nil && native == nil, !load() { return nil }
        lock.lock(); defer { lock.unlock() }
        if let native {
            return native.request(data)
        }
        guard let yaya else { return nil }
        // yaya_core は UTF-8 で処理する。要求の Charset で読み、応答は応答自身の Charset で書き戻す。
        let requestCharset = EncodingAdapter.detectCharset(in: data, default: "Shift_JIS")
        guard let text = EncodingAdapter.decode(data, charset: requestCharset),
              let response = yaya.rawRequest(text) else { return nil }
        let responseCharset = Self.declaredCharset(in: response) ?? requestCharset
        return EncodingAdapter.encode(response, charset: responseCharset)
    }

    func unload() {
        lock.lock(); defer { lock.unlock() }
        yaya?.unload()
        yaya = nil
        native?.unload()
        native = nil
    }

    static func declaredCharset(in response: String) -> String? {
        for line in response.components(separatedBy: "\r\n").dropFirst() {
            if line.isEmpty { break }
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Charset") == .orderedSame {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
