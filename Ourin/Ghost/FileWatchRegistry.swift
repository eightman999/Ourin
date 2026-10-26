import CoreServices
import Foundation

/// `\![execute,filewatch]` / `\![cancel,filewatch]` の監視（UKADOC 2.8.91）。
///
/// OnExecuteFileWatchChange   R0=--async の文字列（無ければ空） R1=指定したパス R2=変化の種類 R3=フルパス
///   ファイル: modified / created / deleted、ディレクトリ: changed（直下の変化）/ deleted（自身の消失）
/// OnExecuteFileWatchFailure  R0=--async R1=指定したパス R2=notauthorized / invalid / notfound / limit
/// `--async` が "On" で始まる場合、Change はその ID、Failure は ID+"Failure" がイベント名になる。
final class FileWatchRegistry {
    static let changeEvent = "OnExecuteFileWatchChange"
    static let failureEvent = "OnExecuteFileWatchFailure"
    /// SSP 全体で監視しているディレクトリの種類の上限。
    static let directoryLimit = 63

    /// 全ゴースト（全レジストリ）で監視しているディレクトリの種類を数える。
    private static let globalLock = NSLock()
    private static var globalDirectoryUse: [String: Int] = [:]

    struct Request {
        var path: String
        var asyncID: String = ""
        var debounceMilliseconds: Int = 500
    }

    private let baseDirectory: URL
    private let emit: (String, [String: String]) -> Void
    private let queue = DispatchQueue(label: "jp.ourin.filewatch")
    private var watches: [String: Watch] = [:]

    /// - Parameters:
    ///   - baseDirectory: 相対パスの基準（ghost/master）。
    ///   - emit: イベント名と ReferenceN の送出先。
    init(baseDirectory: URL, emit: @escaping (String, [String: String]) -> Void) {
        self.baseDirectory = baseDirectory
        self.emit = emit
        queue.setSpecific(key: Self.queueKey, value: ())
    }

    /// 監視キュー上で実行中かを判定する（キュー上からの同期呼び出しでのデッドロックを避ける）。
    fileprivate static let queueKey = DispatchSpecificKey<Void>()

    deinit {
        cancelAll()
    }

    /// 監視対象のフルパスを決める（相対パスは ghost/master 基準）。
    func resolve(_ path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = trimmed.hasPrefix("/")
            ? URL(fileURLWithPath: trimmed)
            : baseDirectory.appendingPathComponent(trimmed)
        return url.standardizedFileURL
    }

    /// パス比較用の正規形。`standardizedFileURL` は実在するパスでだけ `/private/tmp` を
    /// `/tmp` へ縮めるため、FSEvents が返すパスと監視対象を同じ形に揃えてから比べる。
    static func canonicalPath(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        for prefix in ["/private/var/", "/private/tmp/", "/private/etc/"] where standardized.hasPrefix(prefix) {
            return String(standardized.dropFirst("/private".count))
        }
        return standardized
    }

    static func eventName(failure: Bool, asyncID: String) -> String {
        guard asyncID.hasPrefix("On") else { return failure ? failureEvent : changeEvent }
        return failure ? asyncID + "Failure" : asyncID
    }

    /// 監視を始める。同じパスの監視があれば置き換える。
    func start(_ request: Request, isExternalScript: Bool) {
        let rawPath = request.path
        // fail は Watch の onLost からも呼ぶので、self（レジストリ）を強く捕まえない。
        let emit = self.emit
        func fail(_ reason: String) {
            emit(Self.eventName(failure: true, asyncID: request.asyncID), [
                "Reference0": request.asyncID,
                "Reference1": rawPath,
                "Reference2": reason
            ])
        }
        if isExternalScript {
            fail("notauthorized")
            return
        }
        guard !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail("invalid")
            return
        }
        let target = resolve(rawPath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory)
        let watchesDirectory = exists && isDirectory.boolValue
        let streamRoot = watchesDirectory ? target : target.deletingLastPathComponent()
        var rootIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: streamRoot.path, isDirectory: &rootIsDirectory),
              rootIsDirectory.boolValue else {
            fail("notfound")
            return
        }

        onQueue {
            if let old = watches.removeValue(forKey: target.path) {
                old.stop()
                Self.releaseDirectory(old.streamRoot.path)
            }
        }
        guard Self.acquireDirectory(streamRoot.path) else {
            fail("limit")
            return
        }
        let watch = Watch(
            request: request,
            target: target,
            streamRoot: streamRoot,
            isDirectory: watchesDirectory,
            queue: queue
        ) { [weak self] kind in
            self?.emitChange(request: request, target: target, kind: kind)
        } onLost: { [weak self] in
            guard let self else { return }
            self.queue.async {
                if let current = self.watches[target.path], current.streamRoot == streamRoot {
                    self.watches.removeValue(forKey: target.path)?.stop()
                    Self.releaseDirectory(streamRoot.path)
                }
            }
            fail("notfound")
        }
        guard watch.begin() else {
            Self.releaseDirectory(streamRoot.path)
            fail("notfound")
            return
        }
        onQueue { watches[target.path] = watch }
    }

    /// `\![cancel,filewatch,パス]` — 該当が無ければ何もしない。
    func cancel(path: String) {
        let target = resolve(path)
        onQueue {
            if let watch = watches.removeValue(forKey: target.path) {
                watch.stop()
                Self.releaseDirectory(watch.streamRoot.path)
            }
        }
    }

    /// ゴースト終了時にすべて解除する。
    func cancelAll() {
        let current: [Watch] = onQueue {
            let values = Array(watches.values)
            watches.removeAll()
            return values
        }
        for watch in current {
            watch.stop()
            Self.releaseDirectory(watch.streamRoot.path)
        }
    }

    var watchedPaths: [String] {
        onQueue { Array(watches.keys) }
    }

    /// 監視キュー上で同期実行する。すでにキュー上（FSEvents のコールバック中など）なら直接実行する。
    private func onQueue<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return body()
        }
        return queue.sync(execute: body)
    }

    private func emitChange(request: Request, target: URL, kind: String) {
        emit(Self.eventName(failure: false, asyncID: request.asyncID), [
            "Reference0": request.asyncID,
            "Reference1": request.path,
            "Reference2": kind,
            "Reference3": target.path
        ])
    }

    private static func acquireDirectory(_ path: String) -> Bool {
        globalLock.lock(); defer { globalLock.unlock() }
        if globalDirectoryUse[path] == nil, globalDirectoryUse.count >= directoryLimit {
            return false
        }
        globalDirectoryUse[path, default: 0] += 1
        return true
    }

    private static func releaseDirectory(_ path: String) {
        globalLock.lock(); defer { globalLock.unlock() }
        guard let count = globalDirectoryUse[path] else { return }
        if count <= 1 {
            globalDirectoryUse.removeValue(forKey: path)
        } else {
            globalDirectoryUse[path] = count - 1
        }
    }

    // MARK: - 1件の監視

    private final class Watch {
        let request: Request
        let target: URL
        let streamRoot: URL
        let isDirectory: Bool
        private let queue: DispatchQueue
        private let onChange: (String) -> Void
        private let onLost: () -> Void
        private var stream: FSEventStreamRef?
        private var pendingWork: DispatchWorkItem?
        private var firstPendingAt: Date?
        private var lastSignature: FileSignature?
        private var stopped = false

        /// 通知の要否を決めるファイルの状態。前回の通知から変わっていなければ通知しない。
        struct FileSignature: Equatable {
            var size: Int64
            var modified: Date?
            var inode: Int64

            init?(path: String) {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
                size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                modified = attributes[.modificationDate] as? Date
                inode = (attributes[.systemFileNumber] as? NSNumber)?.int64Value ?? 0
            }
        }

        init(request: Request,
             target: URL,
             streamRoot: URL,
             isDirectory: Bool,
             queue: DispatchQueue,
             onChange: @escaping (String) -> Void,
             onLost: @escaping () -> Void) {
            self.request = request
            self.target = target
            self.streamRoot = streamRoot
            self.isDirectory = isDirectory
            self.queue = queue
            self.onChange = onChange
            self.onLost = onLost
            self.lastSignature = FileSignature(path: target.path)
        }

        func begin() -> Bool {
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                // ストリームが Watch を保持する。解放後にキューへ残ったコールバックが来ても安全にする。
                retain: { info in
                    guard let info else { return nil }
                    _ = Unmanaged<Watch>.fromOpaque(info).retain()
                    return info
                },
                release: { info in
                    guard let info else { return }
                    Unmanaged<Watch>.fromOpaque(info).release()
                },
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagWatchRoot
                    | kFSEventStreamCreateFlagUseCFTypes
            )
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, count, paths, eventFlags, _ in
                    guard let info else { return }
                    let watch = Unmanaged<Watch>.fromOpaque(info).takeUnretainedValue()
                    let list = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                    watch.handle(paths: list, flags: Array(UnsafeBufferPointer(start: eventFlags, count: count)))
                },
                &context,
                [streamRoot.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.05,
                flags
            ) else { return false }
            FSEventStreamSetDispatchQueue(stream, queue)
            guard FSEventStreamStart(stream) else {
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                return false
            }
            self.stream = stream
            return true
        }

        func stop() {
            let teardown = {
                guard !self.stopped else { return }
                self.stopped = true
                self.pendingWork?.cancel()
                self.pendingWork = nil
                if let stream = self.stream {
                    FSEventStreamStop(stream)
                    FSEventStreamInvalidate(stream)
                    FSEventStreamRelease(stream)
                    self.stream = nil
                }
            }
            if DispatchQueue.getSpecific(key: FileWatchRegistry.queueKey) != nil {
                teardown()
            } else {
                queue.sync(execute: teardown)
            }
        }

        /// FSEvents のコールバック（queue 上）。
        private func handle(paths: [String], flags: [FSEventStreamEventFlags]) {
            guard !stopped else { return }
            let rootPath = FileWatchRegistry.canonicalPath(streamRoot.path)
            let targetPath = FileWatchRegistry.canonicalPath(target.path)
            var relevant = false
            for (path, flag) in zip(paths, flags) {
                let standardized = FileWatchRegistry.canonicalPath(path)
                if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                    rootLost()
                    return
                }
                if isDirectory {
                    let parent = FileWatchRegistry.canonicalPath(
                        (standardized as NSString).deletingLastPathComponent
                    )
                    if standardized == rootPath {
                        if !FileManager.default.fileExists(atPath: streamRoot.path) {
                            rootLost()
                            return
                        }
                    } else if parent == rootPath {
                        relevant = true
                    }
                } else if standardized == targetPath {
                    relevant = true
                }
            }
            if !FileManager.default.fileExists(atPath: streamRoot.path) {
                rootLost()
                return
            }
            if relevant { scheduleNotify() }
        }

        private func rootLost() {
            if isDirectory {
                // ディレクトリ自体が無くなった → deleted を通知してから監視を終える。
                onChange("deleted")
            }
            stopped = true
            pendingWork?.cancel()
            onLost()
        }

        private func scheduleNotify() {
            let debounce = max(0, request.debounceMilliseconds)
            if debounce == 0 {
                fire()
                return
            }
            let now = Date()
            if firstPendingAt == nil { firstPendingAt = now }
            pendingWork?.cancel()
            // 変化が止まないまま最初の変化から debounce の3倍が経ったら通知する。
            if let first = firstPendingAt, now.timeIntervalSince(first) * 1000 >= Double(debounce * 3) {
                fire()
                return
            }
            let work = DispatchWorkItem { [weak self] in self?.fire() }
            pendingWork = work
            queue.asyncAfter(deadline: .now() + .milliseconds(debounce), execute: work)
        }

        private func fire() {
            guard !stopped else { return }
            pendingWork = nil
            firstPendingAt = nil
            if isDirectory {
                onChange("changed")
                return
            }
            let current = FileSignature(path: target.path)
            defer { lastSignature = current }
            switch (lastSignature, current) {
            case (nil, .some): onChange("created")
            case (.some, nil): onChange("deleted")
            case let (.some(previous), .some(now)) where previous != now: onChange("modified")
            default: break // 変化なし（遅れて届いた古いイベント）、または作成直後に削除された
            }
        }
    }
}

// MARK: - GhostManager

extension GhostManager {
    /// \![execute,filewatch,パス,--async=...,--debounce=...]
    func executeFileWatch(params: [String], isExternal: Bool) {
        var request = FileWatchRegistry.Request(path: params.first ?? "")
        for argument in params.dropFirst() {
            let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("--"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<separator].lowercased()
            let value = String(trimmed[trimmed.index(after: separator)...])
            switch key {
            case "async":
                request.asyncID = value
            case "debounce":
                if let ms = Int(value), ms >= 0 { request.debounceMilliseconds = ms }
            default:
                break
            }
        }
        if fileWatchRegistry == nil {
            let base = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
            fileWatchRegistry = FileWatchRegistry(baseDirectory: base) { name, params in
                if let id = EventID(rawValue: name) {
                    EventBridge.shared.notify(id, params: params)
                } else {
                    EventBridge.shared.notifyCustom(name, params: params)
                }
            }
        }
        fileWatchRegistry?.start(request, isExternalScript: isExternal)
    }
}
