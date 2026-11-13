import AppKit
import Foundation

/// YAYA の EXECUTE / EXECUTE_WAIT をホスト側で扱う。
/// シェルは使わない。実行ファイルと引数を分けて `Process` で起動するか、URL・書類を `NSWorkspace` で開く。
/// ゴーストごとの許可リストに載った「対象＋引数」の組だけをその場で実行する。
/// 未許可の要求はその場で拒否し、ユーザーに確認して許可されたときだけ実行する（IPC はブロックしない）。
final class YayaExecutionGate {
    enum Target: Equatable {
        case executable(URL, [String])
        case open(URL)
    }

    enum Decision {
        case deny
        case allowOnce
        case allowAlways
    }

    struct Invocation: Equatable {
        let target: Target
        let ghostRoot: URL

        /// 許可リストのキー。ゴースト・対象・引数がすべて一致したときだけ許可済みとみなす。
        var allowKey: String {
            switch target {
            case let .executable(url, args):
                return ([ghostRoot.path, "exec", url.path] + args).joined(separator: "\u{1}")
            case let .open(url):
                return [ghostRoot.path, "open", url.absoluteString].joined(separator: "\u{1}")
            }
        }
    }

    enum ParseError: Error, Equatable {
        case emptyCommand
        case notFound(String)
        case argumentsForDocument
    }

    static let shared = YayaExecutionGate()
    static let allowlistDefaultsKey = "OurinYayaExecuteAllowlist"
    /// 名前だけの実行ファイル（例: `open`）を探す場所。PATH 環境変数は使わない。
    static let searchDirectories = ["/usr/bin", "/bin", "/usr/sbin", "/sbin", "/usr/local/bin", "/opt/homebrew/bin"]

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var pendingConfirmations = Set<String>()
    /// EXECUTE_WAIT で終了を待つ上限。SHIORI 要求の既定タイムアウト（10 秒）より短くする。
    var waitLimit: TimeInterval = 8
    /// 確認 UI。completion はどのスレッドから呼んでもよい。テストで差し替える。
    var confirm: (Invocation, @escaping (Decision) -> Void) -> Void = YayaExecutionGate.presentConfirmation
    /// URL・書類を開く処理。テストで差し替える。
    var openURL: (URL) -> Void = { url in
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - yaya_core host_op "execute"

    func handle(params: [String: Any], ghostRoot: URL?) -> [String: Any] {
        guard let ghostRoot else {
            return ["ok": false, "status": 403, "error": "no ghost loaded"]
        }
        let command = params["command"] as? String ?? ""
        let arguments = params["arguments"] as? String ?? ""
        let wait = params["wait"] as? Bool ?? false
        let invocation: Invocation
        do {
            invocation = Invocation(
                target: try Self.resolve(command: command, arguments: arguments, ghostRoot: ghostRoot),
                ghostRoot: ghostRoot.standardizedFileURL)
        } catch {
            NSLog("[YayaExecutionGate] EXECUTE rejected: \(error)")
            return ["ok": false, "status": 400, "error": "\(error)"]
        }

        if isAllowed(invocation) {
            return run(invocation, wait: wait)
        }
        requestConfirmation(for: invocation)
        return ["ok": false, "status": 403, "error": "execution requires user confirmation"]
    }

    // MARK: - Allowlist

    func isAllowed(_ invocation: Invocation) -> Bool {
        (defaults.stringArray(forKey: Self.allowlistDefaultsKey) ?? []).contains(invocation.allowKey)
    }

    func allow(_ invocation: Invocation) {
        lock.lock(); defer { lock.unlock() }
        var list = defaults.stringArray(forKey: Self.allowlistDefaultsKey) ?? []
        guard !list.contains(invocation.allowKey) else { return }
        list.append(invocation.allowKey)
        defaults.set(list, forKey: Self.allowlistDefaultsKey)
    }

    private func requestConfirmation(for invocation: Invocation) {
        let key = invocation.allowKey
        lock.lock()
        let inserted = pendingConfirmations.insert(key).inserted
        lock.unlock()
        guard inserted else { return }
        confirm(invocation) { [weak self] decision in
            guard let self else { return }
            self.lock.lock()
            self.pendingConfirmations.remove(key)
            self.lock.unlock()
            switch decision {
            case .deny:
                return
            case .allowAlways:
                self.allow(invocation)
                fallthrough
            case .allowOnce:
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = self.run(invocation, wait: false)
                }
            }
        }
    }

    // MARK: - Execution (no shell)

    private func run(_ invocation: Invocation, wait: Bool) -> [String: Any] {
        switch invocation.target {
        case let .open(url):
            openURL(url)
            return ["ok": true, "status": 200, "exit_code": 0]
        case let .executable(url, args):
            let process = Process()
            process.executableURL = url
            process.arguments = args
            process.currentDirectoryURL = invocation.ghostRoot
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            do {
                try process.run()
            } catch {
                NSLog("[YayaExecutionGate] failed to launch \(url.path): \(error)")
                return ["ok": false, "status": 500, "error": "\(error)"]
            }
            guard wait else { return ["ok": true, "status": 200] }
            guard finished.wait(timeout: .now() + waitLimit) == .success else {
                return ["ok": false, "status": 504, "error": "process did not finish in time"]
            }
            return ["ok": true, "status": 200, "exit_code": Int(process.terminationStatus)]
        }
    }

    // MARK: - Command resolution

    /// EXECUTE の引数を、シェルを介さない「実行ファイル＋引数」または「開く対象」へ変換する。
    static func resolve(command rawCommand: String, arguments: String, ghostRoot: URL) throws -> Target {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw ParseError.emptyCommand }

        if let url = URL(string: command), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host != nil {
            guard arguments.trimmingCharacters(in: .whitespaces).isEmpty else { throw ParseError.argumentsForDocument }
            return .open(url)
        }

        var path = command
        var args = tokenize(arguments)
        var fileURL = locate(path, ghostRoot: ghostRoot)
        if fileURL == nil, args.isEmpty {
            // EXECUTE("prog arg1 arg2") 形式。先頭を実行ファイル、残りを引数として扱う（シェル展開はしない）。
            let tokens = tokenize(command)
            if tokens.count > 1, let first = tokens.first {
                path = first
                args = Array(tokens.dropFirst())
                fileURL = locate(path, ghostRoot: ghostRoot)
            }
        }
        guard let url = fileURL else { throw ParseError.notFound(path) }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: url.path) {
            return .executable(url, args)
        }
        guard args.isEmpty else { throw ParseError.argumentsForDocument }
        return .open(url)
    }

    private static func locate(_ rawPath: String, ghostRoot: URL) -> URL? {
        var path = rawPath.replacingOccurrences(of: "\\", with: "/")
        if path.hasPrefix("file://"), let url = URL(string: path), url.isFileURL { path = url.path }
        if path.hasPrefix("~/") { path = NSHomeDirectory() + String(path.dropFirst(1)) }
        let candidates: [URL]
        if path.hasPrefix("/") {
            candidates = [URL(fileURLWithPath: path)]
        } else if !path.contains("/") {
            candidates = [ghostRoot.appendingPathComponent(path)]
                + searchDirectories.map { URL(fileURLWithPath: $0).appendingPathComponent(path) }
        } else {
            candidates = [ghostRoot.appendingPathComponent(path)]
        }
        return candidates
            .map { $0.standardizedFileURL.resolvingSymlinksInPath() }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 空白区切り。"..." の中の空白は区切りにしない。変数展開・メタ文字の解釈は一切しない。
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        var hasToken = false
        for ch in text {
            if ch == "\"" {
                inQuotes.toggle()
                hasToken = true
            } else if !inQuotes, ch.isWhitespace {
                if hasToken { tokens.append(current) }
                current = ""
                hasToken = false
            } else {
                current.append(ch)
                hasToken = true
            }
        }
        if hasToken { tokens.append(current) }
        return tokens
    }

    // MARK: - Confirmation UI

    private static func presentConfirmation(_ invocation: Invocation, completion: @escaping (Decision) -> Void) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = NSLocalizedString("ゴーストがプログラムの実行を要求しています", comment: "YAYA EXECUTE")
            let detail: String
            switch invocation.target {
            case let .executable(url, args):
                detail = String(format: NSLocalizedString("実行ファイル: %@\n引数: %@", comment: "YAYA EXECUTE"),
                                url.path, args.isEmpty ? "-" : args.map { "\"\($0)\"" }.joined(separator: " "))
            case let .open(url):
                detail = String(format: NSLocalizedString("開く対象: %@", comment: "YAYA EXECUTE"),
                                url.isFileURL ? url.path : url.absoluteString)
            }
            alert.informativeText = String(format: NSLocalizedString("ゴースト: %@\n%@\n\n信頼できるゴーストの場合だけ許可してください。", comment: "YAYA EXECUTE"),
                                           invocation.ghostRoot.path, detail)
            alert.addButton(withTitle: NSLocalizedString("拒否", comment: "YAYA EXECUTE"))
            alert.addButton(withTitle: NSLocalizedString("今回だけ許可", comment: "YAYA EXECUTE"))
            alert.addButton(withTitle: NSLocalizedString("常に許可", comment: "YAYA EXECUTE"))
            switch alert.runModal() {
            case .alertSecondButtonReturn: completion(.allowOnce)
            case .alertThirdButtonReturn: completion(.allowAlways)
            default: completion(.deny)
            }
        }
    }
}
