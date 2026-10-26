import AppKit
import Foundation
import Testing
@testable import Ourin

/// #118 scriptbox 互換の回帰テスト。
///
/// scriptbox は SSP 2.8.35f 固有の入力種別（CInputWnd::GetTypeText case 1、UKADOC 未収録）。
/// SSP では inputbox 同族として扱われ、決定で OnUserInput、取消／タイムアウトで
/// OnUserInputCancel、`\![close,scriptbox]` ではキャンセルイベント無しで閉じる。
/// かつては open 用ロジックが close 分岐の switch に誤配置され、
/// `\![close,scriptbox]` が新しい入力窓を開き、`\![open,scriptbox]` は
/// openURL の default へ落ちる状態だった。この回帰を防ぐ。
@Suite(.serialized)
struct ScriptBoxTests {
    let engine = SakuraScriptEngine()

    private func makeManager() -> GhostManager {
        GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-scriptbox-tests-\(UUID().uuidString)"))
    }

    /// playbackQueue 末尾の deferredCommand を実行する。
    @MainActor
    private func runLastDeferredCommand(_ gm: GhostManager) {
        guard case .deferredCommand(let command) = gm.playbackQueue.last else {
            Issue.record("expected a deferredCommand")
            return
        }
        command()
    }

    // MARK: - 引数解析

    @MainActor
    @Test
    func parsePositionalFormMatchesInputboxPrecedence() {
        let gm = makeManager()
        let command = gm.parseInputBoxCommand(["sb1", "1200", "\\0hello"], defaultID: "scriptbox")
        #expect(command.id == "sb1")
        #expect(command.timeoutMs == 1200)
        #expect(command.initialText == "\\0hello")
        #expect(command.placeholder == "")
    }

    @MainActor
    @Test
    func parseOptionForm() {
        let gm = makeManager()
        let command = gm.parseInputBoxCommand(
            ["--id=scriptbox2", "--timeout=0", "--text=\\_qset", "--placeholder=type here"],
            defaultID: "scriptbox"
        )
        #expect(command.id == "scriptbox2")
        #expect(command.timeoutMs == 0)
        #expect(command.initialText == "\\_qset")
        #expect(command.placeholder == "type here")
    }

    @MainActor
    @Test
    func parseWithoutArgumentsFallsBackToDefaultID() {
        let gm = makeManager()
        let command = gm.parseInputBoxCommand([], defaultID: "scriptbox")
        #expect(command.id == "scriptbox")
        #expect(command.timeoutMs == nil)
        #expect(command.initialText == "")
    }

    @MainActor
    @Test
    func parsePositionalTakesPrecedenceOverIdOption() {
        // 既存 inputbox と同じ優先度: 位置指定が --id より優先される。
        let gm = makeManager()
        let command = gm.parseInputBoxCommand(["pos1", "--id=opt"], defaultID: "scriptbox")
        #expect(command.id == "pos1")
    }

    // MARK: - open 配線

    @MainActor
    @Test
    func openScriptBoxPresentsInputboxStyleDialog() async throws {
        let gm = makeManager()
        let id = "sb-open-\(UUID().uuidString)"
        gm.openScriptBox(fromCommandArguments: [id, "10000", "initial"])
        runLastDeferredCommand(gm)
        let dialog = gm.activeInputDialogs.first { $0.id == id }
        #expect(dialog?.isOpen == true)
        gm.closeInputDialog(id: id)
        #expect(gm.activeInputDialogs.contains { $0.id == id } == false)
    }

    @MainActor
    @Test
    func openScriptBoxThroughEngineOpensDialogInsteadOfURLOpen() {
        // 誤配置当時は \![open,scriptbox] が default へ落ちて openURL されていた。
        let gm = makeManager()
        let id = "sb-engine-open-\(UUID().uuidString)"
        gm.sakuraEngine(engine, didEmit: .command(name: "!", args: ["open", "scriptbox", id, "10000", ""]))

        runLastDeferredCommand(gm)
        #expect(gm.activeInputDialogs.contains { $0.id == id })
        gm.closeInputDialog(id: id)
    }

    // MARK: - close 配線（open 誤発火の回帰）

    @MainActor
    @Test
    func closeScriptBoxClosesDialogWithoutOpeningNewOne() {
        let gm = makeManager()
        let id = "sb-close-\(UUID().uuidString)"
        gm.openScriptBox(fromCommandArguments: [id, "10000", ""])
        runLastDeferredCommand(gm)
        let openedCount = gm.activeInputDialogs.count
        #expect(openedCount == 1)

        // \![close,scriptbox,ID] は既存の窓を閉じるだけで、新しい窓を開いてはいけない。
        gm.sakuraEngine(engine, didEmit: .command(name: "!", args: ["close", "scriptbox", id]))
        runLastDeferredCommand(gm)

        #expect(gm.activeInputDialogs.isEmpty)
        #expect(gm.activeInputDialogs.count < openedCount)
    }

    @MainActor
    @Test
    func closeScriptBoxWithUnknownIDDoesNotOpenAnything() {
        let gm = makeManager()
        gm.sakuraEngine(engine, didEmit: .command(name: "!", args: ["close", "scriptbox", "never-opened"]))
        runLastDeferredCommand(gm)
        #expect(gm.activeInputDialogs.isEmpty)
    }

    // MARK: - textareabox（open は UI を伴うため解析のみ検証）

    @MainActor
    @Test
    func parseTextAreaBoxCommandCarriesPlaceholder() {
        let gm = makeManager()
        let command = gm.parseInputBoxCommand(
            ["ta1", "0", "line1\\nline2", "--placeholder=p"],
            defaultID: "textareabox"
        )
        #expect(command.id == "ta1")
        #expect(command.initialText == "line1\\nline2")
        #expect(command.placeholder == "p")
    }
}
