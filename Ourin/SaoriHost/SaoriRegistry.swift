import Foundation

public final class SaoriRegistry {
    public private(set) var searchPaths: [URL]
    private var cache: [URL: SaoriLoader] = [:]
    private let fm: FileManager

    public init(searchPaths: [URL] = [], fileManager: FileManager = .default) {
        self.fm = fileManager
        self.searchPaths = searchPaths.isEmpty ? Self.defaultSearchPaths() : searchPaths
    }

    public func setSearchPaths(_ paths: [URL]) {
        searchPaths = paths
    }

    /// - Parameter prioritized: true ならゴースト固有のパスとして既定パスより先に探す。
    public func addSearchPath(_ path: URL, prioritized: Bool = false) {
        if prioritized {
            searchPaths.removeAll { $0 == path }
            searchPaths.insert(path, at: 0)
            return
        }
        guard !searchPaths.contains(path) else { return }
        searchPaths.append(path)
    }

    public func discoverSaoriDirectory(under base: URL) {
        let candidates = [
            base.appendingPathComponent(".saori", isDirectory: true),
            base.appendingPathComponent("ghost/master/.saori", isDirectory: true),
            base.appendingPathComponent("ghost/master/saori", isDirectory: true)
        ]
        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            addSearchPath(candidate)
        }
    }

    /// SAORI 名（ゴーストが LOADLIB 等に渡す Windows 形式の相対パス）を macOS のモジュールへ解決する。
    ///
    /// 優先順:
    /// 1. 各検索パスからの相対パス（`saori\foo.dll` の区切りを保つ）で、macOS ネイティブ候補
    ///    （`.dylib` / `lib*.dylib` / `.plugin` / `.bundle` / `.so`）。大小文字は区別しない。
    /// 2. 同じくファイル名だけでの候補（旧来の basename 解決）。
    /// 3. 指定名そのもの。ただし Windows PE 形式（`MZ`）の `.dll` は読み込めないので除外する。
    public func resolveModuleURL(named name: String) -> URL? {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") {
            return resolveAbsolute(normalized)
        }
        let relativeCandidates = UkagakaModuleABI.nativeModuleCandidates(forDLLName: normalized)
        let basename = (normalized as NSString).lastPathComponent
        let basenameCandidates = UkagakaModuleABI.nativeModuleCandidates(forDLLName: basename)
        for variants in [relativeCandidates, basenameCandidates] {
            for path in searchPaths {
                for variant in variants {
                    if let candidate = UkagakaModuleABI.resolveCaseInsensitive(variant, in: path, fileManager: fm) {
                        return candidate
                    }
                }
            }
        }
        for path in searchPaths {
            for variant in [normalized, basename] {
                if let candidate = UkagakaModuleABI.resolveCaseInsensitive(variant, in: path, fileManager: fm),
                   !UkagakaModuleABI.isWindowsPortableExecutable(at: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func resolveAbsolute(_ path: String) -> URL? {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        for variant in UkagakaModuleABI.nativeModuleCandidates(forDLLName: url.lastPathComponent) {
            if let candidate = UkagakaModuleABI.resolveCaseInsensitive(variant, in: directory, fileManager: fm) {
                return candidate
            }
        }
        if fm.fileExists(atPath: url.path), !UkagakaModuleABI.isWindowsPortableExecutable(at: url) {
            return url
        }
        return nil
    }

    public func loadModule(named name: String) throws -> SaoriLoader {
        if resolveModuleURL(named: name) == nil, let builtin = builtinLoader(named: name) {
            return builtin
        }
        guard let url = resolveModuleURL(named: name) else {
            throw NSError(
                domain: "SaoriRegistry",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "SAORI module not found: \(name)"]
            )
        }
        let key = cacheKey(for: url)
        if let cached = cache[key] {
            return cached
        }
        let loader = try SaoriLoader(url: url)
        cache[key] = loader
        return loader
    }

    /// macOS 版が無い汎用 SAORI（proxy_ex 等）を内蔵実装で用意する。
    /// 本家と同じく、Windows 版 DLL が置かれたフォルダをモジュールのフォルダとして扱う。
    private func builtinLoader(named name: String) -> SaoriLoader? {
        guard let kind = BuiltinSaori.kind(forModuleName: name) else { return nil }
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        var moduleURL: URL?
        if normalized.hasPrefix("/") {
            moduleURL = URL(fileURLWithPath: normalized)
        } else {
            let basename = (normalized as NSString).lastPathComponent
            outer: for variant in [normalized, basename] {
                for path in searchPaths {
                    if let found = UkagakaModuleABI.resolveCaseInsensitive(variant, in: path, fileManager: fm) {
                        moduleURL = found
                        break outer
                    }
                }
            }
        }
        guard let moduleURL else { return nil }
        let key = cacheKey(for: moduleURL)
        if let cached = cache[key] { return cached }
        guard let handler = BuiltinSaori.makeHandler(kind: kind, moduleDirectory: moduleURL.deletingLastPathComponent()) else {
            return nil
        }
        let loader = SaoriLoader(builtinModuleURL: moduleURL, handler: handler)
        cache[key] = loader
        return loader
    }

    /// 既にロード済みのローダー（未ロードなら nil）。
    public func loadedModule(named name: String) -> SaoriLoader? {
        guard let url = resolveModuleURL(named: name) else { return nil }
        return cache[cacheKey(for: url)]
    }

    public func unloadModule(named name: String) {
        guard let url = resolveModuleURL(named: name) else { return }
        let key = cacheKey(for: url)
        guard let loader = cache.removeValue(forKey: key) else { return }
        loader.unload()
    }

    public func unloadAll() {
        for loader in cache.values {
            loader.unload()
        }
        cache.removeAll()
    }

    private func cacheKey(for url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func defaultSearchPaths() -> [URL] {
        var paths: [URL] = []
        // baseware 既定の SAORI フォールバックは公開リソースの saori/ を見る。
        if let saoriDir = try? OurinPaths.subdirectory("saori") {
            paths.append(saoriDir)
        }
        if let appURL = Bundle.main.bundleURL as URL? {
            paths.append(appURL.appendingPathComponent("Contents/Resources/saori", isDirectory: true))
        }
        return paths
    }
}
