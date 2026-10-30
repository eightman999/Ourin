import Foundation
import Testing
@testable import Ourin

@MainActor
struct ShioriStatusHeaderTests {
    private final class Recorder: GhostShioriRuntime {
        let kind: ShioriRuntimeKind = .native
        var isLoaded = true
        var resourceManager: ResourceManager?
        var requests: [[String:String]] = []
        func load(context: ShioriRuntimeLoadContext) -> Bool { true }
        func unload() {}
        func request(method: String, id: String, headers: [String:String], refs: [String], timeout: TimeInterval) -> ShioriRuntimeResponse? {
            requests.append(headers)
            return .init(ok: true, status: 204)
        }
    }
    @Test func allDispatcherMethodsSendLiveStatusWithoutLeakingPreviousState() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/Ourin-Status-\(UUID().uuidString)"))
        defer { _ = manager.shutdown() }
        let runtime = Recorder(), dispatcher = ShioriDispatcher()
        dispatcher.ghostManager = manager; dispatcher.useRuntime(runtime)
        manager.isPlaying = true; manager.timeCriticalActive = true
        manager.passiveModeActive = true; manager.inductionModeActive = true
        manager.noUserBreakModeActive = true; manager.getBalloonVM(for: 0).onlineModeActive = true
        _ = dispatcher.sendGet(id: .OnSecondChange, params: [:])
        _ = dispatcher.sendGetCustom(eventName: "OnCustom", params: [:])
        dispatcher.sendNotify(id: .OnSecondChange, params: [:], ignoreResponseScript: true)
        dispatcher.sendNotifyCustom(eventName: "OnCustom", params: [:], ignoreResponseScript: true)
        _ = dispatcher.fetchDictionaryEntry("Test")
        #expect(runtime.requests.count == 5)
        for headers in runtime.requests {
            #expect(Set((headers["Status"] ?? "").split(separator: ",").map(String.init)) == Set(["talking","timecritical","passive","induction","nouserbreak","online"]))
            #expect(headers["SecurityLevel"] == "local")
        }
        manager.isPlaying = false; manager.timeCriticalActive = false
        manager.passiveModeActive = false; manager.inductionModeActive = false
        manager.noUserBreakModeActive = false; manager.getBalloonVM(for: 0).onlineModeActive = false
        _ = dispatcher.sendGet(id: .OnSecondChange, params: [:], security: .external(origin: "https://example.invalid"))
        #expect(runtime.requests.last?["Status"] == nil)
        #expect(runtime.requests.last?["SecurityLevel"] == "external")
        #expect(runtime.requests.last?["SecurityOrigin"] == "https://example.invalid")
    }
}
