import Foundation
import Testing
@testable import Ourin

private final class CapturingUtilityRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var requests: [(method: String, id: String, refs: [String])] = []
    var responses: [String: String] = [:]

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        requests.append((method, id, refs))
        if let value = responses[id] {
            return .init(ok: true, status: 200, value: value)
        }
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

@Suite(.serialized)
struct GhostUtilityCommandTests {
    @Test
    func displayTextRemovesControlTagsAndKeepsNewlines() {
        let engine = SakuraScriptEngine()
        let script = #"\0Hello\n[half]World\![sound,cdplay,7]\e"#

        #expect(engine.displayText(from: script) == "Hello\nWorld")
    }

    @Test @MainActor
    func multiDigitWaitDoesNotBecomeSpokenText() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-multi-digit-wait-test"))

        manager.sakuraEngine(manager.sakuraEngine, didEmit: .command(name: "w", args: ["10"]))

        #expect(manager.playbackQueue.count == 1)
        guard let unit = manager.playbackQueue.first else {
            Issue.record("Expected a wait unit for \\w10")
            return
        }
        if case .wait(let seconds) = unit {
            #expect(abs(seconds - 0.5) < 0.0001)
        } else {
            Issue.record("\\w10 must enqueue a wait, not a text unit")
        }
    }

    @Test @MainActor
    func backlogKeepsVisibleTextAndCapsHistory() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-backlog-test"))

        manager.recordBacklog(from: #"\0Control-only\![sound,cdplay,7]\e"#)
        #expect(manager.backlogEntries.count == 1)
        #expect(manager.backlogEntries[0].text == "Control-only")

        for index in 1...200 {
            manager.recordBacklog(from: "\\0Entry \(index)\\e")
        }

        #expect(manager.backlogEntries.count == 200)
        #expect(manager.backlogEntries.first?.text == "Entry 1")
        #expect(manager.backlogEntries.last?.text == "Entry 200")
    }

    @Test @MainActor
    func cdplayReportsUnsupportedMediaThroughOnSoundError() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-cdplay-test"))
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.runScript(#"\![sound,cdplay,7]"#)

        let error = runtime.requests.first { $0.id == "OnSoundError" }
        #expect(error?.method == "NOTIFY")
        #expect(error?.refs == ["cdplay", "-2", "audio-cd-track-7", "audio_cd_unsupported"])
    }

    @Test @MainActor
    func raiseUsesGetAndNotifyUsesNotify() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-raise-command-test"))
        let runtime = CapturingUtilityRuntime()
        runtime.responses["OnBoot"] = #"\0standard raise response\e"#
        runtime.responses["OnRaiseTest"] = #"\0custom raise response\e"#
        manager.shioriRuntime = runtime
        let otherManager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-raise-command-other-test"))
        let otherRuntime = CapturingUtilityRuntime()
        otherManager.shioriRuntime = otherRuntime
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        let otherToken = EventBridge.shared.register(runtime: otherRuntime, ghostManager: otherManager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.unregister(otherToken)
            EventBridge.shared.stop()
        }

        manager.runScript(#"\![raise,OnBoot,standard]\![raise,OnRaiseTest,custom]\![notify,OnNotifyTest,notify]"#)

        let standardRaise = runtime.requests.first { $0.id == "OnBoot" }
        let customRaise = runtime.requests.first { $0.id == "OnRaiseTest" }
        let notify = runtime.requests.first { $0.id == "OnNotifyTest" }
        #expect(standardRaise?.method == "GET")
        #expect(standardRaise?.refs == ["standard"])
        #expect(customRaise?.method == "GET")
        #expect(customRaise?.refs == ["custom"])
        #expect(notify?.method == "NOTIFY")
        #expect(notify?.refs == ["notify"])
        #expect(otherRuntime.requests.isEmpty)
    }

    @Test @MainActor
    func ghostLifecycleCommandsUseGetDelivery() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-ghost-lifecycle-event-test"))
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.callGhost(named: "missing-ghost", options: ["--option=raise-event"])

        let lifecycleIDs = ["OnGhostCalling", "OnGhostCalled", "OnGhostCallComplete"]
        for id in lifecycleIDs {
            let request = runtime.requests.first { $0.id == id }
            #expect(request?.method == "GET", "\(id) must be delivered as GET")
        }

        runtime.requests.removeAll()
        manager.switchGhost(named: "missing-ghost", options: ["--option=raise-event"])

        for id in ["OnGhostChanging", "OnGhostChanged"] {
            let request = runtime.requests.first { $0.id == id }
            #expect(request?.method == "GET", "\(id) must be delivered as GET")
        }
    }

    @Test @MainActor
    func resetWindowPositionRaisesEventBeforeDefaultReset() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-reset-window-event-test"))
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.runScript(#"\![execute,resetwindowpos]"#)

        let resetEvent = runtime.requests.first { $0.id == EventID.OnResetWindowPos.rawValue }
        #expect(resetEvent?.method == "GET")
        #expect(resetEvent?.refs.isEmpty == true)
    }

    @Test @MainActor
    func balloonTimeoutNotifiesDisplayedScriptAndZeroRemainingTime() async throws {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-balloon-timeout-event-test"))
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        let balloon = manager.getBalloonVM(for: manager.currentScope)
        balloon.balloonTimeout = 0.01
        manager.appendText("timed out")

        for _ in 0..<20 where runtime.requests.first(where: { $0.id == EventID.OnBalloonTimeout.rawValue }) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let timeout = runtime.requests.first { $0.id == EventID.OnBalloonTimeout.rawValue }
        #expect(timeout?.method == "NOTIFY")
        #expect(timeout?.refs == ["timed out", "0"])

        let close = runtime.requests.first { $0.id == EventID.OnBalloonClose.rawValue }
        #expect(close?.method == "NOTIFY")
        #expect(close?.refs == ["timed out"])
        #expect(balloon.text.isEmpty)
    }

    @Test @MainActor
    func scalingCommandRaisesShellScalingWithBeforeAndAfterPercentages() async throws {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-shell-scaling-event-test"))
        _ = manager.ensureCharacterWindow(for: 0)
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        let otherManager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-shell-scaling-event-other-test"))
        let otherRuntime = CapturingUtilityRuntime()
        let otherToken = EventBridge.shared.register(runtime: otherRuntime, ghostManager: otherManager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.unregister(otherToken)
            EventBridge.shared.stop()
        }

        manager.executeSetScalingCommand(args: ["set", "scaling", "50", "75"])

        for _ in 0..<20 where runtime.requests.first(where: { $0.id == EventID.OnShellScaling.rawValue }) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let event = runtime.requests.first { $0.id == EventID.OnShellScaling.rawValue }
        #expect(event?.method == "GET")
        #expect(event?.refs == ["50.0", "100.0", "75.0", "100.0"])
        #expect(manager.characterViewModels[0]?.userScaleX == 0.5)
        #expect(manager.characterViewModels[0]?.userScaleY == 0.75)
        #expect(otherRuntime.requests.isEmpty)
    }

    @Test @MainActor
    func scalingCommandSynchronizesBalloonAndRaisesBalloonScalingEvent() async throws {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-balloon-scaling-event-test"))
        _ = manager.ensureCharacterWindow(for: 0)
        var config = GhostConfiguration(name: "BalloonScalingTest")
        config.balloonSyncScale = true
        manager.ghostConfig = config
        let balloon = manager.getBalloonVM(for: 0)
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.executeSetScalingCommand(args: ["set", "scaling", "50", "75"])

        for _ in 0..<20 where runtime.requests.first(where: { $0.id == EventID.OnBalloonScaling.rawValue }) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let event = runtime.requests.first { $0.id == EventID.OnBalloonScaling.rawValue }
        #expect(event?.method == "GET")
        #expect(event?.refs == ["50.0", "100.0", "75.0", "100.0"])
        #expect(balloon.scaleX == 0.5)
        #expect(balloon.scaleY == 0.75)
    }

    @Test @MainActor
    func otherSurfaceChangeIsSentOnlyToOptedInOtherGhosts() {
        EventBridge.shared.stop()

        let source = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-other-surface-source"))
        var sourceConfig = GhostConfiguration(name: "SourceGhost")
        sourceConfig.sakuraName = "Source Sakura"
        source.ghostConfig = sourceConfig
        let sourceRuntime = CapturingUtilityRuntime()
        let sourceToken = EventBridge.shared.register(runtime: sourceRuntime, ghostManager: source)

        let observer = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-other-surface-observer"))
        let observerRuntime = CapturingUtilityRuntime()
        let observerToken = EventBridge.shared.register(runtime: observerRuntime, ghostManager: observer)
        observer.setOtherSurfaceChange(enabled: true)

        let disabled = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-other-surface-disabled"))
        let disabledRuntime = CapturingUtilityRuntime()
        let disabledToken = EventBridge.shared.register(runtime: disabledRuntime, ghostManager: disabled)
        defer {
            EventBridge.shared.unregister(sourceToken)
            EventBridge.shared.unregister(observerToken)
            EventBridge.shared.unregister(disabledToken)
            EventBridge.shared.stop()
        }

        EventBridge.shared.notifyOtherSurfaceChange(
            from: source,
            scope: 0,
            newSurfaceID: 17,
            oldSurfaceID: 3,
            newSurfaceSize: CGSize(width: 100, height: 200)
        )

        let event = observerRuntime.requests.first { $0.id == EventID.OnOtherSurfaceChange.rawValue }
        #expect(event?.method == "GET")
        #expect(event?.refs == ["SourceGhost", "Source Sakura", "0", "17", "3", "0,0,100,200"])
        #expect(sourceRuntime.requests.isEmpty)
        #expect(disabledRuntime.requests.isEmpty)
    }

    @Test @MainActor
    func headlineRSSDispatchUsesStandardEventsAndFallback() {
        EventBridge.shared.stop()

        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-headline-rss-event-test"))
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        #expect(!manager.dispatchRSSBegin(siteName: "Feed", url: "https://example.test/feed"))
        #expect(runtime.requests.map(\.id) == ["OnRSSBegin", "OnHeadlinesenseBegin"])
        #expect(runtime.requests.allSatisfy { $0.method == "GET" })
        #expect(runtime.requests.allSatisfy { $0.refs == ["Feed", "https://example.test/feed"] })

        runtime.requests.removeAll()
        runtime.responses["OnRSSBegin"] = #"\0RSS begin handled\e"#
        #expect(manager.dispatchRSSBegin(siteName: "Feed", url: "https://example.test/feed"))
        #expect(runtime.requests.map(\.id) == ["OnRSSBegin"])
        runtime.responses.removeValue(forKey: "OnRSSBegin")

        let item = RSSFeedItem(
            title: "Title",
            url: "https://example.test/item",
            publishedAt: nil,
            author: "Author",
            summary: "Summary"
        )
        runtime.requests.removeAll()
        #expect(!manager.dispatchRSSComplete(siteName: "Feed", url: "https://example.test/feed", items: [item]))
        let complete = runtime.requests.first { $0.id == "OnRSSComplete" }
        #expect(complete?.method == "GET")
        #expect(complete?.refs == ["Feed", "https://example.test/feed", item.wireValue])
        let find = runtime.requests.first { $0.id == "OnHeadlinesense.OnFind" }
        #expect(find?.method == "GET")
        #expect(find?.refs == ["Feed", "https://example.test/feed", "First and Last", "Summary"])
        #expect(runtime.requests.contains { $0.id == "OnHeadlinesenseComplete" } == false)

        runtime.requests.removeAll()
        #expect(!manager.dispatchRSSComplete(siteName: "Feed", url: "https://example.test/feed", items: []))
        let noUpdateRSS = runtime.requests.first { $0.id == "OnRSSComplete" }
        #expect(noUpdateRSS?.method == "GET")
        #expect(noUpdateRSS?.refs == ["no update"])
        let noUpdateHeadline = runtime.requests.first { $0.id == "OnHeadlinesenseComplete" }
        #expect(noUpdateHeadline?.method == "GET")
        #expect(noUpdateHeadline?.refs == ["no update"])

        runtime.requests.removeAll()
        #expect(!manager.dispatchRSSFailure(reason: "can't analyze"))
        let rssFailure = runtime.requests.first { $0.id == "OnRSSFailure" }
        #expect(rssFailure?.method == "GET")
        #expect(rssFailure?.refs == ["can't analyze"])
        let headlineFailure = runtime.requests.first { $0.id == "OnHeadlinesenseFailure" }
        #expect(headlineFailure?.method == "GET")
        #expect(headlineFailure?.refs == ["can't analyze"])
    }

    @Test @MainActor
    func archiveCommandsDispatchStandardReferencesAndCustomEvent() async throws {
        EventBridge.shared.stop()

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("ourin-archive-command-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let sourceFile = source.appendingPathComponent("payload.txt")
        let archive = root.appendingPathComponent("payload.zip")
        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        let payload = Data("archive payload".utf8)
        try payload.write(to: sourceFile)
        defer { try? fileManager.removeItem(at: root) }

        let manager = GhostManager(ghostURL: root)
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.executeCompressArchive(params: [
            source.path,
            archive.path,
            "--event=OnArchiveCompressTest"
        ])
        for _ in 0..<100 where runtime.requests.first(where: { $0.id == "OnArchiveCompressTest" }) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let compress = runtime.requests.first { $0.id == "OnArchiveCompressTest" }
        #expect(compress?.method == "GET")
        let compressRefs = compress?.refs ?? []
        #expect(compressRefs.count == 4)
        if compressRefs.count == 4 {
            #expect(compressRefs[0] == "OnArchiveCompressTest")
            #expect(compressRefs[1] == "1")
            #expect((Int64(compressRefs[2]) ?? 0) > 0)
            #expect(compressRefs[3] == String(payload.count))
        }
        #expect(fileManager.fileExists(atPath: archive.path))

        manager.executeExtractArchive(params: [
            archive.path,
            extracted.path,
            "--event=OnArchiveExtractTest"
        ])
        for _ in 0..<100 where runtime.requests.first(where: { $0.id == "OnArchiveExtractTest" }) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let extract = runtime.requests.first { $0.id == "OnArchiveExtractTest" }
        #expect(extract?.method == "GET")
        let extractRefs = extract?.refs ?? []
        #expect(extractRefs.count == 4)
        if extractRefs.count == 4 {
            #expect(extractRefs[0] == "OnArchiveExtractTest")
            #expect(extractRefs[1] == "1")
            #expect(extractRefs[2] == String(ArchiveTestSupport.fileSize(at: archive)))
            #expect(extractRefs[3] == String(payload.count))
        }
        #expect(try Data(contentsOf: extracted.appendingPathComponent("source/payload.txt")) == payload)

        let passwordArchive = root.appendingPathComponent("password.zip")
        let passwordExtracted = root.appendingPathComponent("password-extracted", isDirectory: true)
        manager.executeCompressArchive(params: [
            source.path,
            passwordArchive.path,
            "--password=secret",
            "--event=OnArchivePasswordCompressTest"
        ])
        for _ in 0..<100 where runtime.requests.first(where: { $0.id == "OnArchivePasswordCompressTest" }) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(runtime.requests.first(where: { $0.id == "OnArchivePasswordCompressTest" })?.method == "GET")

        manager.executeExtractArchive(params: [
            passwordArchive.path,
            passwordExtracted.path,
            "--password=secret",
            "--event=OnArchivePasswordExtractTest"
        ])
        for _ in 0..<100 where runtime.requests.first(where: { $0.id == "OnArchivePasswordExtractTest" }) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(runtime.requests.first(where: { $0.id == "OnArchivePasswordExtractTest" })?.method == "GET")
        #expect(try Data(contentsOf: passwordExtracted.appendingPathComponent("source/payload.txt")) == payload)
    }

    @Test @MainActor
    func archiveFailureUsesDefaultGetEventAndErrorReference() async throws {
        EventBridge.shared.stop()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-archive-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = GhostManager(ghostURL: root)
        let runtime = CapturingUtilityRuntime()
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        manager.executeExtractArchive(params: [
            root.appendingPathComponent("missing.zip").path,
            root.appendingPathComponent("destination", isDirectory: true).path
        ])
        for _ in 0..<100 where runtime.requests.first(where: { $0.id == EventID.OnExtractArchiveFailure.rawValue }) == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        let event = runtime.requests.first { $0.id == EventID.OnExtractArchiveFailure.rawValue }
        #expect(event?.method == "GET")
        #expect(event?.refs == ["", "file not found"])
    }
}

private enum ArchiveTestSupport {
    static func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return Int64(values.fileSize ?? 0)
    }
}
