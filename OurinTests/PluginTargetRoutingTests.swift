import Foundation
import Testing
@testable import Ourin

struct PluginTargetRoutingTests {
    @Test
    func ghostManagerMatchesNameIDPathAndWindowTarget() {
        let root = URL(fileURLWithPath: "/tmp/target-ghost")
        let manager = GhostManager(ghostURL: root)
        var config = GhostConfiguration(name: "Target Ghost", sakuraName: "Sakura", keroName: "Kero")
        config.id = "owned-id"
        manager.ghostConfig = config

        #expect(manager.matchesPluginTarget("Target Ghost"))
        #expect(manager.matchesPluginTarget("owned-id"))
        #expect(manager.matchesPluginTarget("/tmp/target-ghost"))
        #expect(manager.matchesPluginTarget("target-ghost"))
        #expect(manager.matchesPluginTarget("other") == false)
    }

    @Test
    func transportActionKeepsRawTargetForResolver() {
        let response = PluginResponse(
            statusCode: 200,
            statusMessage: "OK",
            script: "\\0Hello\\e",
            target: "Target Ghost"
        )

        let action = OurinPluginEventBridge.transportAction(from: response, notifyOnly: false)
        #expect(action?.target == "Target Ghost")
    }
}
