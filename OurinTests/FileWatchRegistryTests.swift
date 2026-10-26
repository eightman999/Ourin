import Foundation
import Testing
@testable import Ourin

private final class FileWatchRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(name: String, params: [String: String])] = []

    func record(_ name: String, _ params: [String: String]) {
        lock.lock(); storage.append((name, params)); lock.unlock()
    }

    var events: [(name: String, params: [String: String])] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func kinds(_ name: String = FileWatchRegistry.changeEvent) -> [String] {
        events.filter { $0.name == name }.compactMap { $0.params["Reference2"] }
    }
}

private func waitForFileWatch(timeout: TimeInterval = 6, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try await Task.sleep(nanoseconds: 50_000_000)
    }
}

/// FSEvents は登録直後のイベントを取りこぼすことがあるため、監視開始後に少し待つ。
private func settle() async throws {
    try await Task.sleep(nanoseconds: 400_000_000)
}

@Suite(.serialized)
struct FileWatchRegistryTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-filewatch-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test
    func eventNamesFollowAsyncRule() {
        #expect(FileWatchRegistry.eventName(failure: false, asyncID: "") == "OnExecuteFileWatchChange")
        #expect(FileWatchRegistry.eventName(failure: true, asyncID: "abc") == "OnExecuteFileWatchFailure")
        #expect(FileWatchRegistry.eventName(failure: false, asyncID: "OnConfigChanged") == "OnConfigChanged")
        #expect(FileWatchRegistry.eventName(failure: true, asyncID: "OnConfigChanged") == "OnConfigChangedFailure")
    }

    @Test
    func fileIsCreatedModifiedAndDeleted() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = FileWatchRecorder()
        let registry = FileWatchRegistry(baseDirectory: root) { recorder.record($0, $1) }
        defer { registry.cancelAll() }

        // まだ存在しないファイルを相対パスで指定できる。
        registry.start(.init(path: "config.json", asyncID: "id1", debounceMilliseconds: 100), isExternalScript: false)
        try await settle()
        let file = root.appendingPathComponent("config.json")

        try Data("a".utf8).write(to: file)
        try await waitForFileWatch { recorder.kinds().contains("created") }
        try Data("ab".utf8).write(to: file)
        try await waitForFileWatch { recorder.kinds().contains("modified") }
        try FileManager.default.removeItem(at: file)
        try await waitForFileWatch { recorder.kinds().contains("deleted") }

        #expect(recorder.kinds() == ["created", "modified", "deleted"])
        let first = try #require(recorder.events.first?.params)
        #expect(first["Reference0"] == "id1")
        #expect(first["Reference1"] == "config.json")
        #expect(first["Reference3"] == file.standardizedFileURL.path)
    }

    @Test
    func rapidWritesAreDebouncedIntoOneNotification() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("log.txt")
        try Data().write(to: file)
        let recorder = FileWatchRecorder()
        let registry = FileWatchRegistry(baseDirectory: root) { recorder.record($0, $1) }
        defer { registry.cancelAll() }

        // デバウンス時間より長い間隔の書き込みは仕様上別の通知になるので、全体実行の負荷でも
        // 間隔が開かないよう、デバウンスを長めにして連続で書き込む。
        registry.start(.init(path: file.path, debounceMilliseconds: 1500), isExternalScript: false)
        try await settle()
        for i in 0..<5 {
            try Data("line \(i)".utf8).write(to: file)
        }
        try await waitForFileWatch(timeout: 8) { !recorder.kinds().isEmpty }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(recorder.kinds() == ["modified"])
    }

    @Test
    func directoryReportsChangedAndDeletedThenFails() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("watched", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let recorder = FileWatchRecorder()
        let registry = FileWatchRegistry(baseDirectory: root) { recorder.record($0, $1) }
        defer { registry.cancelAll() }

        registry.start(.init(path: "watched", asyncID: "OnDirWatch", debounceMilliseconds: 0), isExternalScript: false)
        try await settle()
        try Data("x".utf8).write(to: dir.appendingPathComponent("child.txt"))
        try await waitForFileWatch { recorder.kinds("OnDirWatch").contains("changed") }
        #expect(recorder.kinds("OnDirWatch").contains("changed"))

        try FileManager.default.removeItem(at: dir)
        try await waitForFileWatch { recorder.events.contains { $0.name == "OnDirWatchFailure" } }
        #expect(recorder.kinds("OnDirWatch").contains("deleted"))
        #expect(recorder.events.first { $0.name == "OnDirWatchFailure" }?.params["Reference2"] == "notfound")
        #expect(registry.watchedPaths.isEmpty)
    }

    @Test
    func invalidNotFoundAndExternalScriptsFail() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = FileWatchRecorder()
        let registry = FileWatchRegistry(baseDirectory: root) { recorder.record($0, $1) }
        defer { registry.cancelAll() }

        registry.start(.init(path: ""), isExternalScript: false)
        registry.start(.init(path: "missing-dir/file.txt"), isExternalScript: false)
        registry.start(.init(path: "file.txt"), isExternalScript: true)
        #expect(recorder.kinds(FileWatchRegistry.failureEvent) == ["invalid", "notfound", "notauthorized"])
        #expect(registry.watchedPaths.isEmpty)
    }

    @Test
    func samePathIsReplacedAndCancelStopsNotifications() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.txt")
        let recorder = FileWatchRecorder()
        let registry = FileWatchRegistry(baseDirectory: root) { recorder.record($0, $1) }
        defer { registry.cancelAll() }

        registry.start(.init(path: "a.txt", asyncID: "first", debounceMilliseconds: 0), isExternalScript: false)
        registry.start(.init(path: "a.txt", asyncID: "second", debounceMilliseconds: 0), isExternalScript: false)
        #expect(registry.watchedPaths.count == 1)
        try await settle()
        try Data("x".utf8).write(to: file)
        try await waitForFileWatch { !recorder.events.isEmpty }
        #expect(recorder.events.allSatisfy { $0.params["Reference0"] == "second" })

        registry.cancel(path: "a.txt")
        #expect(registry.watchedPaths.isEmpty)
        let count = recorder.events.count
        try Data("y".utf8).write(to: file)
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(recorder.events.count == count)
    }

    /// SSTP 由来のスクリプトは外部扱いになり、ゴースト自身のスクリプトは外部扱いにならない。
    @MainActor
    @Test
    func playbackRemembersWhetherScriptCameFromSSTP() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = GhostManager(ghostURL: root)
        defer { manager.shutdown() }

        manager.runScript("\\0external\\e", translationContext: ScriptTranslationContext(isSSTP: true))
        #expect(manager.currentPlaybackIsExternal)
        manager.runScript("\\0internal\\e")
        #expect(!manager.currentPlaybackIsExternal)
    }
}
