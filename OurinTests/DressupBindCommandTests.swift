import Foundation
import AppKit
import Testing
@testable import Ourin

private final class CapturingDressupRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var requests: [(method: String, id: String, refs: [String])] = []

    func load(context: ShioriRuntimeLoadContext) -> Bool { true }

    func request(
        method: String,
        id: String,
        headers: [String: String],
        refs: [String],
        timeout: TimeInterval
    ) -> ShioriRuntimeResponse? {
        requests.append((method, id, refs))
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

// MARK: - Recording harness

/// OnDressupChanged / OnNotifyDressupInfo の送出を捕捉するテスト専用サブクラス。
/// 実 SHIORI メディアに依存せずに、bind のイベント順序と bind-noevent のイベント抑止を検証するための最小レコーダ。
private final class RecordingGhostManager: GhostManager {
    var eventLog: [String] = []
    var infoScopes: [Int] = []
    var changedRequestResponses: [Bool] = []
    var infoRequestResponses: [Bool] = []

    override func notifyDressupChanged(
        category: String,
        part: String,
        value: String,
        scope: Int,
        source: String,
        requestResponse: Bool
    ) {
        changedRequestResponses.append(requestResponse)
        eventLog.append("changed:\(category):\(part):\(value)")
    }

    override func notifyDressupInfo(scope: Int, requestResponse: Bool) {
        infoRequestResponses.append(requestResponse)
        infoScopes.append(scope)
        eventLog.append("info")
    }
}

// MARK: - Tests

struct DressupBindTests {

    // MARK: - コマンド解析・計画（純粋ヘルパー）

    @Test
    func bindParsesSingleTupleWithWearValue() throws {
        let plans = GhostManager.parseDressupBindPlans(args: ["bind", "head", "ribbon", "1"])
        let plan = try #require(plans.first)
        #expect(plan == DressupBindPlan(category: "head", part: "ribbon", value: "1", emitsEvents: true))
        #expect(!plan.isCategoryWide)
        #expect(!plan.isToggle)
    }

    @Test
    func bindParsesCategoryWideDisable() throws {
        let plans = GhostManager.parseDressupBindPlans(args: ["bind", "arm", "", "0"])
        let plan = try #require(plans.first)
        #expect(plan.category == "arm")
        #expect(plan.isCategoryWide)
        #expect(plan.value == "0")
        #expect(plan.emitsEvents)
    }

    @Test
    func bindOmittedValuePlansToggle() throws {
        let plan = try #require(GhostManager.parseDressupBindPlans(args: ["bind", "head", "ribbon"]).first)
        #expect(plan.value == nil)
        #expect(plan.isToggle)
    }

    @Test
    func bindEmptyValuePlansToggle() throws {
        let plan = try #require(GhostManager.parseDressupBindPlans(args: ["bind", "head", "ribbon", ""]).first)
        #expect(plan.value == "")
        #expect(plan.isToggle)
    }

    @Test
    func bindNoEventPlansWithSuppressedEvents() throws {
        let plan = try #require(GhostManager.parseDressupBindPlans(args: ["bind-noevent", "head", "ribbon", "1"]).first)
        #expect(plan.value == "1")
        #expect(!plan.emitsEvents)
    }

    @Test
    func bindParsesRepeatedTuples() throws {
        let plans = GhostManager.parseDressupBindPlans(args: ["bind", "a", "b", "1", "c", "d", "0"])
        #expect(plans.count == 2)
        #expect(plans[0] == DressupBindPlan(category: "a", part: "b", value: "1", emitsEvents: true))
        #expect(plans[1] == DressupBindPlan(category: "c", part: "d", value: "0", emitsEvents: true))
    }

    @MainActor @Test
    func bindRepeatedTuplesEmitOneInfoAfterAllChanges() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-repeated"))
        let vm = CharacterViewModel()
        manager.characterViewModels[0] = vm

        manager.executeBindCommand(args: ["bind", "head", "ribbon", "1", "arm", "ring", "0"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.dressupBindings["head"]?["ribbon"] == "1")
        #expect(vm.dressupBindings["arm"]?["ring"] == nil)
        #expect(manager.eventLog == [
            "changed:head:ribbon:1",
            "changed:arm:ring:0",
            "info"
        ])
        #expect(manager.changedRequestResponses == [false, true])
        #expect(manager.infoRequestResponses == [false])
        #expect(manager.infoScopes == [0])
    }

    @Test
    func bindTrailingTupleWithoutValuePlansToggle() throws {
        let plans = GhostManager.parseDressupBindPlans(args: ["bind", "a", "b", "1", "c", "d"])
        #expect(plans.count == 2)
        #expect(plans[1] == DressupBindPlan(category: "c", part: "d", value: nil, emitsEvents: true))
        #expect(plans[1].isToggle)
    }

    @Test
    func bindCategoryNameIsParsedAsNormalCategory() throws {
        let plans = GhostManager.parseDressupBindPlans(args: ["bind", "category", "part", "1"])
        let plan = try #require(plans.first)
        #expect(plan == DressupBindPlan(category: "category", part: "part", value: "1", emitsEvents: true))
    }

    @Test
    func bindUnknownFirstArgumentProducesNoPlans() {
        #expect(GhostManager.parseDressupBindPlans(args: ["binds", "x", "y", "1"]).isEmpty)
        #expect(GhostManager.parseDressupBindPlans(args: ["bind"]).isEmpty)
    }

    // MARK: - さくらスクリプトからの実際の引数抽出

    @Test
    func scriptBindExtractsEmptyPartAndValue() {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![bind,arm,,0]\\e")
        #expect(tokens.first == .command(name: "!", args: ["bind", "arm", "", "0"]))
    }

    @Test
    func scriptBindOmittedValueKeepsTrailingEmptyArg() {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![bind,head,ribbon,]\\e")
        #expect(tokens.first == .command(name: "!", args: ["bind", "head", "ribbon", ""]))
    }

    @Test
    func scriptBindNoEventPlansWithSuppression() throws {
        let engine = SakuraScriptEngine()
        let tokens = engine.parse(script: "\\![bind-noevent,head,ribbon,1]\\e")
        guard case .command(_, let args) = tokens.first else {
            Issue.record("Expected command token")
            return
        }
        let plans = GhostManager.parseDressupBindPlans(args: args)
        let plan = try #require(plans.first)
        #expect(plan.category == "head")
        #expect(plan.part == "ribbon")
        #expect(plan.value == "1")
        #expect(!plan.emitsEvents)
    }

    // MARK: - 状態変更（トグル・カテゴリ単位）とイベント

    @MainActor @Test
    func bindValueOneWearsPartAndEmitsChangedThenInfo() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-1"))
        let vm = CharacterViewModel()
        manager.characterViewModels[0] = vm

        manager.executeBindCommand(args: ["bind", "head", "ribbon", "1"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.dressupBindings["head"]?["ribbon"] == "1")
        #expect(manager.eventLog == ["changed:head:ribbon:1", "info"])
        #expect(manager.changedRequestResponses == [true])
        #expect(manager.infoRequestResponses == [false])
    }

    @MainActor @Test
    func bindValueZeroDisablesPartAndEmitsChangedThenInfo() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-2"))
        let vm = CharacterViewModel()
        vm.dressupBindings["head"] = ["ribbon": "1"]
        manager.characterViewModels[0] = vm

        manager.executeBindCommand(args: ["bind", "head", "ribbon", "0"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.dressupBindings["head"]?["ribbon"] == nil)
        #expect(manager.eventLog == ["changed:head:ribbon:0", "info"])
    }

    @MainActor @Test
    func bindOmittedValueTogglesCurrentState() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-3"))
        let vm = CharacterViewModel()
        vm.dressupBindings["head"] = ["ribbon": "1"]
        manager.characterViewModels[0] = vm

        // 装着済み → トグルで外れる
        manager.executeBindCommand(args: ["bind", "head", "ribbon"])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.dressupBindings["head"]?["ribbon"] == nil)
        #expect(manager.eventLog.last == "info")

        // 外れている状態 → トグルで着る
        manager.executeBindCommand(args: ["bind", "head", "ribbon", ""])
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(vm.dressupBindings["head"]?["ribbon"] == "1")
    }

    @MainActor @Test
    func bindEmptyPartDisablesWholeCategory() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-4"))
        let vm = CharacterViewModel()
        vm.dressupBindings["arm"] = ["ring": "1", "bracelet": "1"]
        manager.characterViewModels[0] = vm

        manager.executeBindCommand(args: ["bind", "arm", "", "0"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.dressupBindings["arm"] == nil)
        #expect(manager.eventLog == [
            "changed:arm:bracelet:0",
            "changed:arm:ring:0",
            "info"
        ])
        #expect(manager.changedRequestResponses == [false, true])
    }

    @MainActor @Test
    func bindCategoryWideEmitsOneChangedPerConfiguredPart() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-category"))
        let vm = CharacterViewModel()
        manager.characterViewModels[0] = vm
        manager.dressupConfigurations = [
            GhostManager.DressupConfig(category: "head", parts: [
                GhostManager.DressupPartBinding(partName: "ribbon", surfaceID: 10, x: 0, y: 0, overlay: true),
                GhostManager.DressupPartBinding(partName: "hat", surfaceID: 11, x: 1, y: 2, overlay: true)
            ])
        ]

        manager.executeBindCommand(args: ["bind", "head", "", "1"])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.dressupBindings["head"]?["ribbon"] == "1")
        #expect(vm.dressupBindings["head"]?["hat"] == "1")
        #expect(manager.eventLog == [
            "changed:head:ribbon:1",
            "changed:head:hat:1",
            "info"
        ])
        #expect(manager.changedRequestResponses == [false, true])
    }

    @MainActor @Test
    func bindLargeCategoryUsesInfoInsteadOfChangedBurst() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-large-category"))
        let vm = CharacterViewModel()
        manager.characterViewModels[0] = vm
        let parts = (0..<100).map { index in
            GhostManager.DressupPartBinding(
                partName: "part\(index)",
                surfaceID: index,
                x: 0,
                y: 0,
                overlay: true
            )
        }
        manager.dressupConfigurations = [GhostManager.DressupConfig(category: "wide", parts: parts)]

        manager.executeBindCommand(args: ["bind", "wide", "", "1"])
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(vm.dressupBindings["wide"]?.count == 100)
        #expect(manager.changedRequestResponses.isEmpty)
        #expect(manager.eventLog == ["info"])
    }

    @MainActor @Test
    func bindEmptyPartWithEmptyValueTogglesCategory() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-5"))
        let vm = CharacterViewModel()
        vm.dressupBindings["arm"] = ["": "1"]
        manager.characterViewModels[0] = vm

        manager.executeBindCommand(args: ["bind", "arm", "", ""])
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.dressupBindings["arm"] == nil)

        manager.executeBindCommand(args: ["bind", "arm", ""])
        try await Task.sleep(nanoseconds: 100_000_000)

        // 設定なしカテゴリは空パーツで有効として記録される（トグル判定用）
        #expect(vm.dressupBindings["arm"]?[""] == "1")
    }

    @MainActor @Test
    func bindNoEventMutatesStateButSuppressesEvents() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-6"))
        let vm = CharacterViewModel()
        manager.characterViewModels[0] = vm

        manager.executeBindCommand(args: ["bind-noevent", "head", "ribbon", "1"])
        try await Task.sleep(nanoseconds: 100_000_000)

        // 状態・描画操作は bind と同じ
        #expect(vm.dressupBindings["head"]?["ribbon"] == "1")
        // イベントは送出されない
        #expect(manager.eventLog.isEmpty)
    }

    @MainActor @Test
    func bindExplicitScopeUsesTargetScopeForStateAndInfo() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-scope"))
        let primary = CharacterViewModel()
        let companion = CharacterViewModel()
        manager.characterViewModels[0] = primary
        manager.characterViewModels[1] = companion
        manager.currentScope = 0

        manager.handleBindDressup(
            category: "head",
            part: "ribbon",
            value: "1",
            scope: 1,
            source: "user",
            requestChangedResponse: true,
            requestInfoResponse: true
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(primary.dressupBindings["head"]?["ribbon"] == nil)
        #expect(companion.dressupBindings["head"]?["ribbon"] == "1")
        #expect(manager.changedRequestResponses == [true])
        #expect(manager.infoRequestResponses == [true])
        #expect(manager.infoScopes == [1])
    }

    @MainActor @Test
    func dressupGetEventsReachRuntimeWithOfficialReferences() async throws {
        let runtime = CapturingDressupRuntime()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-runtime"))
        let vm = CharacterViewModel()
        vm.dressupBindings["head"] = ["ribbon": "1"]
        manager.characterViewModels[2] = vm
        manager.dressupConfigurations = [
            .init(category: "head", parts: [
                .init(partName: "ribbon", surfaceID: 1, x: 0, y: 0, overlay: true)
            ])
        ]
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer { EventBridge.shared.unregister(token) }

        manager.notifyDressupChanged(
            category: "head",
            part: "ribbon",
            value: "1",
            scope: 2,
            source: "user",
            requestResponse: true
        )
        manager.notifyDressupInfo(scope: 2, requestResponse: true)
        try await Task.sleep(nanoseconds: 100_000_000)

        let first = try #require(runtime.requests.first)
        let second = try #require(runtime.requests.dropFirst().first)
        #expect(runtime.requests.count == 2)
        #expect(first.method == "GET")
        #expect(first.id == "OnDressupChanged")
        #expect(first.refs == ["2", "ribbon", "1", "head", "user"])
        #expect(second.method == "GET")
        #expect(second.id == "OnNotifyDressupInfo")
        #expect(second.refs == ["2\u{1}head\u{1}ribbon\u{1}\u{1}1\u{1}"])
    }

    @MainActor @Test
    func scriptBindNoEventViaEngineSuppressesEvents() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-7"))
        let vm = CharacterViewModel()
        manager.characterViewModels[0] = vm

        // 実際のディスパッチ経路（bind-noevent の分岐）を経由する
        manager.sakuraEngine.run(script: "\\![bind-noevent,head,ribbon,1]\\e")
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.dressupBindings["head"]?["ribbon"] == "1")
        #expect(manager.eventLog.isEmpty)
    }

    @MainActor @Test
    func scriptBindViaEngineEmitsEvents() async throws {
        let manager = RecordingGhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-bind-8"))
        let vm = CharacterViewModel()
        manager.characterViewModels[0] = vm

        manager.sakuraEngine.run(script: "\\![bind,head,ribbon,1]\\e")
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.dressupBindings["head"]?["ribbon"] == "1")
        #expect(manager.eventLog == ["changed:head:ribbon:1", "info"])
    }
}
