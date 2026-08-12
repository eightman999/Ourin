import AppKit
import Darwin
import Foundation

/// 実行中の Ourin を終了した後に、ステージ済みの .app を差し替えるための引数。
/// helper は同じアプリケーション実行ファイルを別プロセスで起動するため、
/// 専用の未署名ヘルパーをアプリバンドルへ追加する必要がない。
struct BasewareUpdateRequest: Equatable {
    static let helperArgument = "--ourin-baseware-update-helper"

    let parentPID: Int32
    let targetAppURL: URL
    let stagedAppURL: URL
    let markerURL: URL
    let version: String

    var helperArguments: [String] {
        [
            Self.helperArgument,
            String(parentPID),
            targetAppURL.path,
            stagedAppURL.path,
            markerURL.path,
            version
        ]
    }

    init(parentPID: Int32, targetAppURL: URL, stagedAppURL: URL, markerURL: URL, version: String) {
        self.parentPID = parentPID
        self.targetAppURL = targetAppURL
        self.stagedAppURL = stagedAppURL
        self.markerURL = markerURL
        self.version = version
    }

    init?(commandLine arguments: [String]) {
        guard let index = arguments.firstIndex(of: Self.helperArgument),
              arguments.count > index + 5,
              let parentPID = Int32(arguments[index + 1]),
              parentPID > 0 else {
            return nil
        }
        self.init(
            parentPID: parentPID,
            targetAppURL: URL(fileURLWithPath: arguments[index + 2], isDirectory: true),
            stagedAppURL: URL(fileURLWithPath: arguments[index + 3], isDirectory: true),
            markerURL: URL(fileURLWithPath: arguments[index + 4]),
            version: arguments[index + 5]
        )
    }
}

/// helper と起動後のアプリが共有する更新状態。
enum BasewareUpdateMarker {
    private struct Payload: Codable {
        var status: String
        var version: String
        var targetAppPath: String
    }

    static func defaultURL() throws -> URL {
        try OurinPaths.subdirectory("temp")
            .appendingPathComponent("baseware-update.json", isDirectory: false)
    }

    static func writePending(_ request: BasewareUpdateRequest) throws {
        try write(
            Payload(status: "pending", version: request.version, targetAppPath: request.targetAppURL.path),
            to: request.markerURL
        )
    }

    static func markApplied(at url: URL) throws {
        let current = try readPayload(at: url)
        try write(
            Payload(status: "applied", version: current.version, targetAppPath: current.targetAppPath),
            to: url
        )
    }

    static func appliedVersion(at url: URL) -> String? {
        guard let payload = try? readPayload(at: url), payload.status == "applied" else { return nil }
        return payload.version
    }

    static func appliedVersion() -> String? {
        guard let url = try? defaultURL() else { return nil }
        return appliedVersion(at: url)
    }

    static func remove(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private static func readPayload(at url: URL) throws -> Payload {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Payload.self, from: data)
    }

    private static func write(_ payload: Payload, to url: URL) throws {
        let data = try JSONEncoder().encode(payload)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// 更新記述子を完全コピー済みのアプリへ適用し、helper 起動用の request を作る。
final class BasewareUpdateCoordinator {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidTarget
        case archiveEntry(String)
        case stagingDirectoryCreationFailed(String)
        case appCopyFailed(String)
        case markerFailed(String)

        var description: String {
            switch self {
            case .invalidTarget:
                return "更新対象の Ourin.app が見つからないか、アプリバンドルではありません"
            case .archiveEntry(let filename):
                return "ベースウェア更新にアーカイブは使えません: \(filename)"
            case .stagingDirectoryCreationFailed(let path):
                return "ベースウェア更新のステージング領域を作成できません: \(path)"
            case .appCopyFailed(let reason):
                return "ベースウェア更新用のアプリコピーに失敗しました: \(reason)"
            case .markerFailed(let reason):
                return "ベースウェア更新状態を保存できません: \(reason)"
            }
        }
    }

    private let installer: NarInstaller

    init(installer: NarInstaller = NarInstaller()) {
        self.installer = installer
    }

    func prepare(entries: [UpdateDescriptorEntry], homeURLString: String,
                 targetAppURL: URL = Bundle.main.bundleURL,
                 onMD5Compare: ((UpdateMD5Comparison) -> Void)? = nil,
                 completion: @escaping (Result<BasewareUpdateRequest, Swift.Error>) -> Void) {
        let fm = FileManager.default
        let target = targetAppURL.standardizedFileURL
        guard target.pathExtension.lowercased() == "app",
              fm.fileExists(atPath: target.path) else {
            completion(.failure(Error.invalidTarget))
            return
        }
        if let archive = entries.first(where: {
            let ext = $0.url.pathExtension.lowercased()
            return ext == "nar" || ext == "zip"
        }) {
            completion(.failure(Error.archiveEntry(archive.filename)))
            return
        }

        let updateRoot = target.deletingLastPathComponent()
            .appendingPathComponent(".OurinUpdate-\(UUID().uuidString)", isDirectory: true)
        let staged = updateRoot.appendingPathComponent(target.lastPathComponent, isDirectory: true)
        let marker: URL
        do {
            try fm.createDirectory(at: updateRoot, withIntermediateDirectories: true)
        } catch {
            try? fm.removeItem(at: updateRoot)
            completion(.failure(Error.stagingDirectoryCreationFailed(error.localizedDescription)))
            return
        }
        do {
            try fm.copyItem(at: target, to: staged)
        } catch let error as Error {
            try? fm.removeItem(at: updateRoot)
            completion(.failure(error))
            return
        } catch {
            try? fm.removeItem(at: updateRoot)
            completion(.failure(Error.appCopyFailed(error.localizedDescription)))
            return
        }

        do {
            marker = try BasewareUpdateMarker.defaultURL()
        } catch {
            try? fm.removeItem(at: updateRoot)
            completion(.failure(Error.markerFailed(error.localizedDescription)))
            return
        }
        installer.downloadAndStage(entries: entries, homeURLString: homeURLString, targetRoot: staged,
                                    onMD5Compare: onMD5Compare) { result in
            switch result {
            case .success:
                // Info.plist 自体を更新した場合も、更新後のバージョンを OnBasewareUpdated へ渡す。
                let version = Self.bundleVersion(at: staged) ?? Self.bundleVersion(at: target) ?? "unknown"
                let request = BasewareUpdateRequest(
                    parentPID: ProcessInfo.processInfo.processIdentifier,
                    targetAppURL: target,
                    stagedAppURL: staged,
                    markerURL: marker,
                    version: version
                )
                do {
                    try BasewareUpdateMarker.writePending(request)
                    completion(.success(request))
                } catch {
                    try? fm.removeItem(at: updateRoot)
                    completion(.failure(Error.markerFailed(error.localizedDescription)))
                }
            case .failure(let error):
                try? fm.removeItem(at: updateRoot)
                completion(.failure(error))
            }
        }
    }

    static func discard(_ request: BasewareUpdateRequest) {
        BasewareUpdateMarker.remove(at: request.markerURL)
        try? FileManager.default.removeItem(at: request.stagedAppURL.deletingLastPathComponent())
    }

    static func bundleVersion(at appURL: URL) -> String? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let info = object as? [String: Any] else {
            return nil
        }
        return (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
    }
}

/// Ourin 終了後にステージ済みアプリを差し替え、同じアプリを再起動する処理。
enum BasewareUpdateHelper {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidRequest
        case helperLaunchFailed(String)
        case parentDidNotExit
        case replacementFailed(String)
        case relaunchFailed

        var description: String {
            switch self {
            case .invalidRequest: return "ベースウェア更新ヘルパーの引数が不正です"
            case .helperLaunchFailed(let reason): return "ベースウェア更新ヘルパーを起動できません: \(reason)"
            case .parentDidNotExit: return "更新元の Ourin が終了しませんでした"
            case .replacementFailed(let reason): return "ベースウェア更新の差し替えに失敗しました: \(reason)"
            case .relaunchFailed: return "更新後の Ourin を再起動できませんでした"
            }
        }
    }

    /// AppDelegate の最初に呼び出し、通常のアプリ初期化より先に helper モードへ入る。
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Bool {
        guard let request = BasewareUpdateRequest(commandLine: arguments) else { return false }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try waitForParentExit(pid: request.parentPID)
                try replace(request, relaunch: true)
            } catch {
                NSLog("[BasewareUpdateHelper] \(error)")
            }
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
        return true
    }

    /// 現在のアプリを終了させる前に、同じ実行ファイルを helper モードで起動する。
    static func launch(_ request: BasewareUpdateRequest) throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw Error.helperLaunchFailed("実行ファイルが見つかりません")
        }
        let process = Process()
        process.executableURL = executableURL
        process.arguments = request.helperArguments
        let nullDevice = FileHandle(forWritingAtPath: "/dev/null")
        process.standardOutput = nullDevice
        process.standardError = nullDevice
        do {
            try process.run()
        } catch {
            throw Error.helperLaunchFailed(error.localizedDescription)
        }
    }

    /// テスト可能な差し替え本体。`relaunch=false` はアプリを開かずに置換だけ行う。
    static func replace(_ request: BasewareUpdateRequest, relaunch: Bool) throws {
        let fm = FileManager.default
        let target = request.targetAppURL.standardizedFileURL
        let staged = request.stagedAppURL.standardizedFileURL
        guard target.pathExtension.lowercased() == "app",
              staged.pathExtension.lowercased() == "app",
              fm.fileExists(atPath: target.path),
              fm.fileExists(atPath: staged.path) else {
            throw Error.invalidRequest
        }

        let backup = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).OurinOld-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.moveItem(at: target, to: backup)
            try fm.moveItem(at: staged, to: target)
            try BasewareUpdateMarker.markApplied(at: request.markerURL)
            if relaunch, !NSWorkspace.shared.open(target) {
                throw Error.relaunchFailed
            }
            try? fm.removeItem(at: backup)
        } catch {
            try? fm.removeItem(at: target)
            try? fm.moveItem(at: backup, to: target)
            BasewareUpdateMarker.remove(at: request.markerURL)
            if let helperError = error as? Error {
                throw helperError
            }
            throw Error.replacementFailed(error.localizedDescription)
        }
    }

    private static func waitForParentExit(pid: Int32) throws {
        guard pid > 0 else { throw Error.invalidRequest }
        let deadline = Date().addingTimeInterval(120)
        while processIsAlive(pid) {
            guard Date() < deadline else { throw Error.parentDidNotExit }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private static func processIsAlive(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
