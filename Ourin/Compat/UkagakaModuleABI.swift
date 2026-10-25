import Foundation
import Darwin

/// 伺か DLL（SHIORI / SAORI / PLUGIN / HEADLINE）共通のエクスポート規約を macOS ネイティブモジュールで扱う補助。
///
/// Windows 版の共通 ABI は次の形で、引数バッファの所有権は呼び出し先へ移り、戻り値の所有権はホストへ移る。
/// ```c
/// BOOL    load(HGLOBAL h, long len);      // h: モジュールのあるディレクトリ（末尾区切り付き）
/// HGLOBAL request(HGLOBAL h, long *len);  // len: 入力長 → 出力長
/// BOOL    unload(void);
/// ```
/// macOS では HGLOBAL を `malloc` 確保のポインタ、`long` を 64bit 整数として読み替える。
public enum UkagakaModuleABI {
    /// モジュールの request 関数の呼び出し規約。
    public enum Convention: String {
        /// Ourin 独自の C ABI（`request(const uchar*, size_t, size_t*)`、戻り値はモジュール所有）。
        case ourin
        /// Windows DLL と同じ `request(HGLOBAL, long*)`（入力はモジュールが free、戻り値はホストが free）。
        case ukagaka
    }

    /// Info.plist で規約を指定するキー。値は `ukagaka`（別名 `hglobal` / `dll`）または `ourin`。
    public static let conventionInfoKey = "OurinModuleABI"

    public typealias LoadFn = @convention(c) (UnsafeMutableRawPointer?, Int) -> Int32
    public typealias RequestFn = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Int>?) -> UnsafeMutableRawPointer?

    /// Info.plist の宣言から規約を決める。宣言がなければ `fallback`。
    public static func convention(declaredIn infoDictionary: [String: Any]?, fallback: Convention) -> Convention {
        guard let raw = (infoDictionary?[conventionInfoKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else { return fallback }
        switch raw {
        case "ukagaka", "hglobal", "dll", "windows":
            return .ukagaka
        case "ourin", "native":
            return .ourin
        default:
            return fallback
        }
    }

    /// `load` に渡すディレクトリ表記。SSP と同じく末尾に区切り文字を付ける。
    public static func directoryArgument(for directoryURL: URL) -> String {
        let path = directoryURL.path
        return path.hasSuffix("/") ? path : path + "/"
    }

    /// `malloc` で確保した NUL 終端バッファを作る。所有権は受け取ったモジュールへ移る。
    ///
    /// 長さは NUL を含まない。`load(const char*)` しか受けない旧来のモジュールにも同じポインタを渡せる
    /// （余分な長さ引数は C の呼び出し規約上無視される）。
    public static func makeOwnedBuffer(_ data: Data) -> (pointer: UnsafeMutableRawPointer, length: Int)? {
        guard let buffer = malloc(data.count + 1) else { return nil }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: data.count + 1)
        if !data.isEmpty {
            data.withUnsafeBytes { raw in
                buffer.copyMemory(from: raw.baseAddress!, byteCount: data.count)
            }
        }
        return (buffer, data.count)
    }

    /// 共通 ABI の `load` / `loadu` を呼ぶ。戻り値 0 を失敗とみなす。
    @discardableResult
    public static func callLoad(_ load: LoadFn, directoryURL: URL) -> Bool {
        let argument = directoryArgument(for: directoryURL)
        guard let buffer = makeOwnedBuffer(Data(argument.utf8)) else { return false }
        return load(buffer.pointer, buffer.length) != 0
    }

    /// 共通 ABI の `request` を呼び、応答を複製してからモジュールの確保した領域を解放する。
    public static func callRequest(_ request: RequestFn, data: Data) -> Data? {
        guard let buffer = makeOwnedBuffer(data) else { return nil }
        var length = buffer.length
        guard let response = request(buffer.pointer, &length) else { return nil }
        defer { free(response) }
        guard length >= 0 else { return nil }
        return Data(bytes: response, count: length)
    }

    /// Windows 向けの `.dll` 名から、macOS で探すネイティブモジュールの相対パス候補を優先順に返す。
    ///
    /// `saori\foo.dll` のような区切り付き相対パスも扱い、元の `.dll` そのものは候補に含めない
    /// （PE 形式は macOS で読み込めないため）。
    public static func nativeModuleCandidates(forDLLName name: String) -> [String] {
        let normalized = name
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        let directory = (normalized as NSString).deletingLastPathComponent
        let base = (normalized as NSString).lastPathComponent
        let ext = (base as NSString).pathExtension.lowercased()
        let stem = (base as NSString).deletingPathExtension

        var names: [String] = []
        if Self.nativeExtensions.contains(ext) {
            names.append(base)
        }
        names += [
            "\(stem).dylib",
            "lib\(stem).dylib",
            "\(stem).plugin",
            "\(stem).bundle",
            "\(stem).so",
            "lib\(stem).so"
        ]
        var seen: Set<String> = []
        return names.compactMap { candidate in
            let relative = directory.isEmpty ? candidate : (directory as NSString).appendingPathComponent(candidate)
            return seen.insert(relative).inserted ? relative : nil
        }
    }

    static let nativeExtensions: Set<String> = ["dylib", "so", "plugin", "bundle"]

    /// `directory` 配下の相対パスを、大文字小文字を区別しないファイルシステム規則で解決する。
    /// Windows 向けゴーストは記述と実ファイルの大小文字が一致しないことがあるため。
    public static func resolveCaseInsensitive(_ relativePath: String, in directory: URL, fileManager: FileManager = .default) -> URL? {
        let exact = directory.appendingPathComponent(relativePath)
        if fileManager.fileExists(atPath: exact.path) {
            return exact
        }
        var current = directory
        for component in relativePath.split(separator: "/").map(String.init) where !component.isEmpty {
            if component == "." { continue }
            if component == ".." {
                current = current.deletingLastPathComponent()
                continue
            }
            let direct = current.appendingPathComponent(component)
            if fileManager.fileExists(atPath: direct.path) {
                current = direct
                continue
            }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: current.path),
                  let match = entries.first(where: { $0.caseInsensitiveCompare(component) == .orderedSame }) else {
                return nil
            }
            current = current.appendingPathComponent(match)
        }
        return current
    }

    /// Windows の PE 実行形式（`MZ` ヘッダ）かどうか。
    public static func isWindowsPortableExecutable(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 2)) ?? Data()
        return header == Data([0x4D, 0x5A])
    }

    /// `.plugin` / `.bundle` ならバンドル内の実行体、それ以外はそのままのパスを dlopen 用に返す。
    public static func executableURL(forModuleAt url: URL) -> URL? {
        let ext = url.pathExtension.lowercased()
        guard ext == "plugin" || ext == "bundle" else { return url }
        return Bundle(url: url)?.executableURL
    }

    /// `.plugin` / `.bundle` の Info.plist。単体 dylib では nil。
    public static func infoDictionary(forModuleAt url: URL) -> [String: Any]? {
        let ext = url.pathExtension.lowercased()
        guard ext == "plugin" || ext == "bundle" else { return nil }
        return Bundle(url: url)?.infoDictionary
    }
}
