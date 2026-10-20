import Foundation

/// インストーラーに同梱した Ourin.app を設置先へ置く（既存があれば差し替える）。
///
/// 本体の BasewareUpdate と同じく「退避 → 設置 → 失敗時は退避分を戻す」で、
/// 途中で失敗しても既存の Ourin.app を失わない。
public struct AppInstaller {
    public enum InstallError: Error, Equatable, CustomStringConvertible {
        case payloadMissing(String)
        case notWritable(String)
        case failed(String)

        public var description: String {
            switch self {
            case .payloadMissing(let path): return "インストールする Ourin.app が見つかりません: \(path)"
            case .notWritable(let path): return "\(path) に書き込む権限がありません"
            case .failed(let message): return message
            }
        }
    }

    public static let appName = "Ourin.app"

    let payload: URL
    let fileManager: FileManager

    public init(payload: URL, fileManager: FileManager = .default) {
        self.payload = payload
        self.fileManager = fileManager
    }

    public func target(in directory: URL) -> URL {
        directory.appendingPathComponent(Self.appName, isDirectory: true)
    }

    /// 管理者権限なしで設置できるか。
    public func canWrite(to directory: URL) -> Bool {
        if !fileManager.fileExists(atPath: directory.path) {
            return fileManager.isWritableFile(atPath: directory.deletingLastPathComponent().path)
        }
        let existing = target(in: directory)
        if fileManager.fileExists(atPath: existing.path),
           !fileManager.isWritableFile(atPath: existing.path) {
            return false
        }
        return fileManager.isWritableFile(atPath: directory.path)
    }

    /// 既に置かれている Ourin のバージョン（無ければ nil）。
    public func installedVersion(in directory: URL) -> String? {
        Self.bundleVersion(at: target(in: directory))
    }

    public var payloadVersion: String? {
        Self.bundleVersion(at: payload)
    }

    @discardableResult
    public func install(into directory: URL) throws -> URL {
        guard fileManager.fileExists(atPath: payload.appendingPathComponent("Contents/Info.plist").path) else {
            throw InstallError.payloadMissing(payload.path)
        }
        guard canWrite(to: directory) else { throw InstallError.notWritable(directory.path) }

        let target = target(in: directory)
        let token = UUID().uuidString
        let staged = directory.appendingPathComponent(".Ourin.app.installing-\(token)", isDirectory: true)
        let backup = directory.appendingPathComponent(".Ourin.app.previous-\(token)", isDirectory: true)

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // まず同じボリュームへ丸ごとコピーし、差し替えは rename だけで済ませる。
            try fileManager.copyItem(at: payload, to: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw InstallError.failed("Ourin.app のコピーに失敗しました: \(error.localizedDescription)")
        }

        let hadExisting = fileManager.fileExists(atPath: target.path)
        do {
            if hadExisting { try fileManager.moveItem(at: target, to: backup) }
            try fileManager.moveItem(at: staged, to: target)
        } catch {
            if hadExisting, !fileManager.fileExists(atPath: target.path) {
                try? fileManager.moveItem(at: backup, to: target)
            }
            try? fileManager.removeItem(at: staged)
            throw InstallError.failed("Ourin.app の差し替えに失敗しました: \(error.localizedDescription)")
        }
        if hadExisting { try? fileManager.removeItem(at: backup) }
        return target
    }

    /// 管理者権限で同じ手順を実行するシェルスクリプト。
    /// `/Applications` に書けない一般ユーザー向けに、AppleScript の
    /// `do shell script ... with administrator privileges` で実行する。
    public func privilegedInstallScript(into directory: URL) -> String {
        let target = target(in: directory)
        let token = UUID().uuidString
        let staged = directory.appendingPathComponent(".Ourin.app.installing-\(token)")
        let backup = directory.appendingPathComponent(".Ourin.app.previous-\(token)")
        let q = Self.shellQuote
        return [
            "set -e",
            "/bin/mkdir -p \(q(directory.path))",
            "/usr/bin/ditto \(q(payload.path)) \(q(staged.path))",
            "if [ -e \(q(target.path)) ]; then /bin/mv \(q(target.path)) \(q(backup.path)); fi",
            "if ! /bin/mv \(q(staged.path)) \(q(target.path)); then "
                + "if [ -e \(q(backup.path)) ]; then /bin/mv \(q(backup.path)) \(q(target.path)); fi; "
                + "/bin/rm -rf \(q(staged.path)); exit 1; fi",
            "/bin/rm -rf \(q(backup.path))",
        ].joined(separator: "\n")
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func bundleVersion(at app: URL) -> String? {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String)
    }
}
