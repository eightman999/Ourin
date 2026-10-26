import Foundation

/// Windows 専用の汎用 SAORI を、Ourin 内で同じ振る舞いをする実装へ置き換える。
///
/// 対象は機能が OS に依存しない仲介系だけ。現在は `proxy_ex.dll`（ukatech/csaori の impl_saori/proxy_ex）。
enum BuiltinSaori {
    /// SAORI 名（`proxy_ex.dll`、`dll\proxy_ex.dll` 等）から内蔵実装の種類を判定する。
    static func kind(forModuleName name: String) -> String? {
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        let stem = URL(fileURLWithPath: normalized).deletingPathExtension().lastPathComponent.lowercased()
        return stem == "proxy_ex" ? "proxy_ex" : nil
    }

    static func makeHandler(kind: String, moduleDirectory: URL) -> ((String) -> String)? {
        switch kind {
        case "proxy_ex":
            let proxy = ProxyExSaori(moduleDirectory: moduleDirectory)
            return { proxy.handle($0) }
        default:
            return nil
        }
    }
}

/// proxy_ex 互換: Argument0 の実行ファイルを Argument1.. を引数として起動し、標準出力を Result で返す。
///
/// - `hwnd`: 何もしない（204）。
/// - `/delim, X`: 出力中の CRLF を置き換える区切り（既定は空白 1 個）。
/// - `/charset, X`: 出力の文字コード（既定は Windows の OEM コードページ相当の Shift_JIS）。
/// - それ以外: 実行ファイル名。モジュールのフォルダ基準の相対パス。Windows 向けの `foo.exe` は、
///   同じ場所にある macOS 向けの `foo`（拡張子なし）・`foo.command`・`foo.sh` に読み替える。
///   起動できなければ 400（本家と同じ）。
final class ProxyExSaori {
    let moduleDirectory: URL
    private var delimiter = " "
    private var charset = "Shift_JIS"
    private let lock = NSLock()

    init(moduleDirectory: URL) {
        self.moduleDirectory = moduleDirectory
    }

    func handle(_ requestText: String) -> String {
        guard let request = try? SaoriProtocol.parseRequest(requestText) else {
            return Self.response(400, "Bad Request")
        }
        if request.method.uppercased() == "GET", request.target?.lowercased() == "version" {
            return Self.response(200, "OK")
        }
        let arguments = (0..<64).compactMap { request.headerValue("Argument\($0)") }
        guard let command = arguments.first else { return Self.response(400, "Bad Request") }
        lock.lock(); defer { lock.unlock() }
        switch command {
        case "hwnd":
            return Self.response(204, "No Content")
        case "/delim":
            guard arguments.count >= 2 else { return Self.response(400, "Bad Request") }
            delimiter = arguments[1]
            return Self.response(204, "No Content")
        case "/charset":
            charset = arguments.count >= 2 && !arguments[1].isEmpty ? arguments[1] : "Shift_JIS"
            return Self.response(204, "No Content")
        default:
            guard let executable = resolveExecutable(command),
                  let output = run(executable, arguments: Array(arguments.dropFirst())) else {
                return Self.response(400, "Bad Request")
            }
            let text = (EncodingAdapter.decode(output, charset: charset) ?? String(decoding: output, as: UTF8.self))
                .replacingOccurrences(of: "\r\n", with: delimiter)
                // macOS 版の補助プログラムは LF で改行するので、Windows 版の CRLF と同じく区切りに置き換える。
                .replacingOccurrences(of: "\n", with: delimiter)
            return Self.response(200, "OK", result: text)
        }
    }

    /// `foo.exe` → macOS 版の実行ファイル。見つからなければ nil。
    func resolveExecutable(_ command: String) -> URL? {
        let normalized = command.replacingOccurrences(of: "\\", with: "/")
        let base = normalized.hasPrefix("/")
            ? URL(fileURLWithPath: normalized)
            : moduleDirectory.appendingPathComponent(normalized)
        let directory = base.deletingLastPathComponent()
        let name = base.lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        var candidates = [stem, stem + ".command", stem + ".sh"]
        if !name.lowercased().hasSuffix(".exe") { candidates.insert(name, at: 0) }
        for candidate in candidates {
            guard let url = UkagakaModuleABI.resolveCaseInsensitive(candidate, in: directory) else { continue }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
                  !UkagakaModuleABI.isWindowsPortableExecutable(at: url),
                  FileManager.default.isExecutableFile(atPath: url.path) else { continue }
            return url
        }
        return nil
    }

    private func run(_ executable: URL, arguments: [String]) -> Data? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = executable.deletingLastPathComponent()
        process.standardOutput = stdout
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("[proxy_ex] failed to launch \(executable.path): \(error)")
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    private static func response(_ code: Int, _ message: String, result: String? = nil) -> String {
        var lines = ["SAORI/1.0 \(code) \(message)", "Charset: UTF-8"]
        if let result { lines.append("Result: \(result.replacingOccurrences(of: "\r", with: ""))") }
        return lines.joined(separator: "\r\n") + "\r\n\r\n"
    }
}
