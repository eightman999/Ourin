import Foundation
import Testing
@testable import Ourin

private final class NumericTranslationRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        if id == "OnTranslate" {
            return .init(ok: true, status: 200, value: "0")
        }
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

@MainActor
struct NumericEventResponseTests {
    @Test
    func numericOnEventResponseIsIgnoredAtPlaybackBoundary() {
        #expect(GhostManager.shouldIgnoreNumericEventResponse("0", eventID: "OnMouseMove"))
        #expect(GhostManager.shouldIgnoreNumericEventResponse("-1.5", eventID: "OnExecute"))
        #expect(!GhostManager.shouldIgnoreNumericEventResponse("0", eventID: nil))
        #expect(!GhostManager.shouldIgnoreNumericEventResponse("\\0Text\\e", eventID: "OnMouseMove"))
    }

    @Test
    func numericOnTranslateResponseDoesNotReplaceSakuraScript() {
        #expect(!GhostManager.shouldAcceptTranslationResponse(original: "\\0Text\\e", candidate: "0"))
        #expect(GhostManager.shouldAcceptTranslationResponse(original: "0", candidate: "0"))
        #expect(GhostManager.shouldAcceptTranslationResponse(original: "\\0Text\\e", candidate: "\\0Translated\\e"))
    }

    @Test
    func runtimeReturningNumericTranslationLeavesOriginalScriptIntact() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-numeric-translation"))
        let runtime = NumericTranslationRuntime()
        manager.shioriRuntime = runtime
        defer {
            manager.shioriRuntime = nil
            manager.shutdown()
        }

        let source = "\\0こんにちは\\e"
        #expect(manager.translateForDisplay(source, context: .init(eventID: "OnBoot")) == source)
    }
}
