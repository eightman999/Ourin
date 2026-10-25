import AppKit
import Foundation
import Testing
@testable import Ourin

/// 入力ボックスはモーダルにせず、決定・取消・タイムアウトを後からイベントで返す（#185）。
/// モーダルのままだと、これらのテストは showInputBoxDialog から戻らずに止まる。
@MainActor
struct ModelessInputDialogTests {
    private final class RecordingRuntime: GhostShioriRuntime {
        let kind: ShioriRuntimeKind = .native
        var isLoaded = true
        var resourceManager: ResourceManager?
        var requests: [(id: String, refs: [String])] = []

        func load(context: ShioriRuntimeLoadContext) -> Bool { true }

        func request(
            method: String,
            id: String,
            headers: [String: String],
            refs: [String],
            timeout: TimeInterval
        ) -> ShioriRuntimeResponse? {
            requests.append((id, refs))
            return .init(ok: true, status: 204)
        }

        func unload() { isLoaded = false }

        func ids() -> [String] { requests.map(\.id) }
    }

    private func makeManager() -> (GhostManager, RecordingRuntime) {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-modeless-input"))
        let runtime = RecordingRuntime()
        manager.shioriRuntime = runtime
        return (manager, runtime)
    }

    @Test
    func inputBoxReturnsImmediatelyAndReportsTheEnteredText() throws {
        let (manager, runtime) = makeManager()
        manager.showInputBoxDialog(id: "NameID", timeoutMs: nil, initialText: "お兄さん")

        // 開いたまま戻ってくる（スクリプトの再生や SSTP を止めない）。
        let dialog = try #require(manager.activeInputDialogs.first)
        #expect(dialog.alert.window.isVisible)
        #expect(runtime.ids() == ["OnInputbox.autocomplete"])

        dialog.respond(.button(0))
        #expect(runtime.requests.last?.id == "OnUserInput")
        #expect(runtime.requests.last?.refs.prefix(2) == ["NameID", "お兄さん"])
        #expect(manager.activeInputDialogs.isEmpty)
        #expect(!dialog.alert.window.isVisible)
    }

    @Test
    func cancelAndCloseFromScript() throws {
        let (manager, runtime) = makeManager()
        manager.showPasswordInputDialog(id: "PassID", timeoutMs: nil, initialText: "")
        try #require(manager.activeInputDialogs.first).respond(.button(1))
        #expect(runtime.requests.last?.id == "OnUserInputCancel")
        #expect(runtime.requests.last?.refs.prefix(2) == ["PassID", "close"])

        // \![close,inputbox,ID] は結果のイベントを送らずに閉じる。
        manager.showIPInputDialog(id: "IPID", timeoutMs: nil, initialText: "127.0.0.1")
        let count = runtime.requests.count
        #expect(manager.closeInputDialog(id: "ipid"))
        #expect(manager.activeInputDialogs.isEmpty)
        #expect(runtime.requests.count == count)
        #expect(!manager.closeInputDialog(id: "IPID"))
    }

    @Test
    func timeoutReportsCancelWithTimeout() async throws {
        let (manager, runtime) = makeManager()
        manager.showInputBoxDialog(id: "TimeoutID", timeoutMs: 50, initialText: "")
        let deadline = Date().addingTimeInterval(10)
        while !manager.activeInputDialogs.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(manager.activeInputDialogs.isEmpty)
        let cancel = try #require(runtime.requests.last { $0.id == "OnUserInputCancel" })
        #expect(cancel.refs.prefix(2) == ["TimeoutID", "timeout"])
    }

    @Test
    func noCloseKeepsTheBoxOpenAndReopeningTheSameIDReplacesIt() throws {
        let (manager, runtime) = makeManager()
        let options = manager.inputDialogOptions(from: ["KeepID", "--option=noclose"])
        manager.showInputBoxDialog(id: "KeepID", timeoutMs: nil, initialText: "a", options: options)
        let dialog = try #require(manager.activeInputDialogs.first)
        dialog.respond(.button(0))
        dialog.respond(.button(0))
        #expect(runtime.ids().filter { $0 == "OnUserInput" }.count == 2)
        #expect(manager.activeInputDialogs.count == 1)

        // 同じ ID で開き直すと、前のものはイベントを送らずに閉じる。
        manager.showInputBoxDialog(id: "keepid", timeoutMs: nil, initialText: "b")
        #expect(manager.activeInputDialogs.count == 1)
        #expect(manager.activeInputDialogs.first !== dialog)
        #expect(!dialog.alert.window.isVisible)
        manager.closeInputDialog(id: "__SYSTEM_ALL_INPUT__")
        #expect(manager.activeInputDialogs.isEmpty)
    }

    @Test
    func choiceInputReportsTheChosenItem() throws {
        let (manager, runtime) = makeManager()
        manager.showChoiceInputDialog(id: "ChoiceID", timeoutMs: nil, choices: ["赤", "青"])
        try #require(manager.activeInputDialogs.first).respond(.button(1))
        #expect(runtime.requests.last?.id == "OnUserInput")
        #expect(runtime.requests.last?.refs.prefix(2) == ["ChoiceID", "青"])

        manager.showChoiceInputDialog(id: "ChoiceID", timeoutMs: nil, choices: ["赤", "青"])
        try #require(manager.activeInputDialogs.first).respond(.button(2))
        #expect(runtime.requests.last?.id == "OnUserInputCancel")
    }
}
