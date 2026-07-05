import Foundation

enum Log {
    static var verbose: Bool {
        // Temporarily enabled for debugging backslash issue
        return true
        // Off by default; enable by setting defaults key "OurinVerboseLogging" = true
        // return UserDefaults.standard.bool(forKey: "OurinVerboseLogging")
    }

    static func info(_ message: String) {
        NSLog(message)
        LogFileSink.shared.write(level: "INFO", message: message)
    }

    static func debug(_ message: String) {
        if verbose { NSLog(message) }
        LogFileSink.shared.write(level: "DEBUG", message: message)
    }

    static func error(_ message: String) {
        NSLog(message)
        LogFileSink.shared.write(level: "ERROR", message: message)
    }
}

/// "OurinEnableFileLogging" が有効な場合に、ログをファイルへ追記するシンク。
/// 遅延 FileHandle を保持し、スレッド安全にアクセスする。
final class LogFileSink {
    static let shared = LogFileSink()

    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private var resolvedPath: String?

    private init() {}

    /// "OurinEnableFileLogging" が true の場合のみファイルへ追記する。
    /// パスは "OurinLogOutputPath"、未設定時は既定の ~/Library/Logs/Ourin/ourin.log を使う。
    func write(level: String, message: String) {
        guard UserDefaults.standard.bool(forKey: "OurinEnableFileLogging") else { return }

        lock.lock()
        defer { lock.unlock() }

        guard let handle = resolvedFileHandle() else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
    }

    /// "OurinLogOutputPath" 未設定時のデフォルトパス（~/Library/Logs/Ourin/ourin.log 相当）。
    static var defaultLogPath: String {
        NSHomeDirectory() + "/Library/Logs/Ourin/ourin.log"
    }

    /// 設定に応じたログファイルパスを解決する（テストからも参照できるよう公開）。
    static func currentLogPath() -> String {
        let saved = UserDefaults.standard.string(forKey: "OurinLogOutputPath")
        if let saved, !saved.isEmpty { return saved }
        return defaultLogPath
    }

    /// テストや設定変更時にキャッシュされた FileHandle を破棄する。
    func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        fileHandle?.closeFile()
        fileHandle = nil
        resolvedPath = nil
    }

    private func resolvedFileHandle() -> FileHandle? {
        let path = LogFileSink.currentLogPath()

        if let handle = fileHandle, resolvedPath == path {
            return handle
        }

        // パスが変わった場合は既存ハンドルを閉じて開き直す
        fileHandle?.closeFile()
        fileHandle = nil
        resolvedPath = nil

        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            fileHandle = handle
            resolvedPath = path
            return handle
        } catch {
            NSLog("LogFileSink: failed to open log file at \(path): \(error.localizedDescription)")
            return nil
        }
    }
}
