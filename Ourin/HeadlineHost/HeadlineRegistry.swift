import Foundation

/// Parsed metadata from headline descript.txt
public struct HeadlineMeta {
    public let name: String
    public let filename: String
    public let url: String
    public let openurl: String
    public let charset: String.Encoding
}

/// Registry for discovering HEADLINE modules
public final class HeadlineRegistry {
    public private(set) var modules: [HeadlineModule] = []
    public private(set) var metas: [HeadlineModule: HeadlineMeta] = [:]

    public init() {}

    /// Discover modules and load them.
    ///
    /// - 検索パス直下の `.plugin` / `.bundle`（descript.txt は bundle の Resources）。
    /// - SSP と同じ `headline/<name>/descript.txt` 形式のディレクトリ。`filename`（`dllname`）の
    ///   元 DLL 名に対応する `.dylib` / `.plugin` / `.bundle` をロードする。
    public func discoverAndLoad() {
        for dir in HeadlineRegistry.searchPaths() {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for item in items {
                if item.pathExtension == "plugin" || item.pathExtension == "bundle" {
                    loadModule(at: item,
                               directoryURL: item,
                               descriptURL: Bundle(url: item)?.url(forResource: "descript", withExtension: "txt"))
                    continue
                }
                let descriptURL = item.appendingPathComponent("descript.txt")
                guard FileManager.default.fileExists(atPath: descriptURL.path),
                      let meta = HeadlineRegistry.readMeta(from: descriptURL),
                      let moduleURL = HeadlineRegistry.resolveNativeModule(named: meta.filename, in: item) else { continue }
                loadModule(at: moduleURL, directoryURL: item, descriptURL: descriptURL)
            }
        }
    }

    private func loadModule(at moduleURL: URL, directoryURL: URL, descriptURL: URL?) {
        guard !modules.contains(where: { $0.url.standardizedFileURL == moduleURL.standardizedFileURL }) else { return }
        do {
            let mod = try HeadlineModule(url: moduleURL)
            if !mod.load(directoryURL: directoryURL) {
                NSLog("Headline module load() returned failure: \(moduleURL.lastPathComponent)")
            }
            modules.append(mod)
            if let descriptURL, let meta = HeadlineRegistry.readMeta(from: descriptURL) {
                metas[mod] = meta
            }
        } catch {
            NSLog("Headline module load failed: \(error)")
        }
    }

    static func resolveNativeModule(named filename: String, in directoryURL: URL) -> URL? {
        for candidate in UkagakaModuleABI.nativeModuleCandidates(forDLLName: filename) {
            if let url = UkagakaModuleABI.resolveCaseInsensitive(candidate, in: directoryURL),
               !UkagakaModuleABI.isWindowsPortableExecutable(at: url) {
                return url
            }
        }
        return nil
    }

    public func unloadAll() {
        for m in modules { m.unload?() }
        modules.removeAll()
        metas.removeAll()
    }

    // MARK: - Utilities
    private static func searchPaths() -> [URL] {
        var urls: [URL] = []
        if let builtIn = Bundle.main.builtInPlugInsURL?.appendingPathComponent("Headline", isDirectory: true) {
            urls.append(builtIn)
        }
        // 公開リソースの headline/（SSP 標準・小文字）を NAR 設置先と一致させて探索する。
        if let headlineDir = try? OurinPaths.subdirectory("headline") {
            urls.append(headlineDir)
        }
        return urls
    }

    static func readMeta(from url: URL) -> HeadlineMeta? {
        guard let raw = try? Data(contentsOf: url) else { return nil }
        // determine charset
        var encoding: String.Encoding = .utf8
        if let first = String(data: raw.prefix(128), encoding: .utf8)?.split(whereSeparator: { $0.isNewline }).first {
            let lower = first.lowercased()
            if lower.starts(with: "charset") {
                let value = lower.split(separator: ",", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? ""
                if ["shift_jis","windows-31j","cp932","ms932","sjis"].contains(value) {
                    encoding = .shiftJIS
                }
            }
        }
        guard let text = String(data: raw, encoding: encoding) else { return nil }
        var name = ""
        var filename = ""
        var dllname = ""
        var urlStr = ""
        var openurl = ""
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1]
            switch key {
            case "name": name = value
            case "filename": filename = value
            case "dllname": dllname = value
            case "url": urlStr = value
            case "openurl": openurl = value
            case "charset":
                if ["shift_jis","windows-31j","cp932","ms932","sjis"].contains(value.lowercased()) {
                    encoding = .shiftJIS
                }
            default: break
            }
        }
        // Prefer filename over dllname (2.0M spec), but accept dllname for 2.0 compatibility
        let finalFilename = !filename.isEmpty ? filename : dllname
        guard !name.isEmpty, !finalFilename.isEmpty else { return nil }
        return HeadlineMeta(name: name, filename: finalFilename, url: urlStr, openurl: openurl, charset: encoding)
    }
}
