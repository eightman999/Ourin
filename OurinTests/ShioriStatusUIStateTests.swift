import AppKit
import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
@MainActor
struct ShioriStatusUIStateTests {
    @Test func visibleBalloonAndChoicesFollowTheirOwnGhostWindows() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/Ourin-StatusUI-\(UUID().uuidString)"))
        let other = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/Ourin-OtherStatusUI-\(UUID().uuidString)"))
        defer { _ = manager.shutdown(); _ = other.shutdown() }
        let first = window(), second = window()
        let vm0 = manager.getBalloonVM(for: 0), vm1 = manager.getBalloonVM(for: 1)
        manager.balloonWindows[1]?.close(); manager.balloonWindows[0]?.close()
        manager.balloonWindows[1] = second; manager.balloonWindows[0] = first
        vm0.balloonID = 2; vm1.balloonID = 0
        manager.pendingChoices = [(title: "選択", action: .event(id: "OnChoice", references: []), pluginOrigin: false)]
        #expect(!manager.shioriStatusFlags().contains("choosing"))
        #expect(!manager.shioriStatusFlags().contains(where: { $0.hasPrefix("balloon(") }))
        first.orderFront(nil); second.orderFront(nil)
        #expect(manager.shioriStatusFlags().contains("balloon(0=2/1=0)"))
        #expect(!manager.shioriStatusFlags().contains("choosing")) // queued, not displayed
        vm0.text = "選択"
        vm0.anchors = [.init(id: "OnChoice", references: [], text: "選択", range: NSRange(location: 0,length: 2), choiceIndex: 0)]
        #expect(manager.shioriStatusFlags().contains("choosing"))
        #expect(other.shioriStatusFlags().isEmpty)
        first.orderOut(nil)
        #expect(!manager.shioriStatusFlags().contains("choosing"))
        #expect(manager.shioriStatusFlags().contains("balloon(1=0)"))
        second.orderOut(nil)
        #expect(!manager.shioriStatusFlags().contains(where: { $0.hasPrefix("balloon(") }))
    }

    @Test func minimizingIsDifferentFromHidingACharacterWindow() async throws {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/Ourin-MinimizeStatus-\(UUID().uuidString)"))
        defer { _ = manager.shutdown() }
        let character = window()
        manager.characterWindows[0] = character
        character.orderFront(nil)
        #expect(!manager.shioriStatusFlags().contains("minimizing"))
        var didMiniaturize = false, didDeminiaturize = false
        let center = NotificationCenter.default
        let miniObserver = center.addObserver(forName: NSWindow.didMiniaturizeNotification, object: character, queue: .main) { _ in
            didMiniaturize = true
        }
        let restoreObserver = center.addObserver(forName: NSWindow.didDeminiaturizeNotification, object: character, queue: .main) { _ in
            didDeminiaturize = true
        }
        defer { center.removeObserver(miniObserver); center.removeObserver(restoreObserver) }
        character.miniaturize(nil)
        var deadline = ProcessInfo.processInfo.systemUptime + 5
        while !didMiniaturize || !character.isMiniaturized {
            try #require(ProcessInfo.processInfo.systemUptime < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(manager.shioriStatusFlags().contains("minimizing"))
        character.deminiaturize(nil)
        deadline = ProcessInfo.processInfo.systemUptime + 5
        while !didDeminiaturize || character.isMiniaturized {
            try #require(ProcessInfo.processInfo.systemUptime < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        character.orderOut(nil)
        #expect(!manager.shioriStatusFlags().contains("minimizing"))
    }

    @Test func openingFlagsRequireVisibleOwnedWindowsAndClearOnClose() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/Ourin-OpeningStatus-\(UUID().uuidString)"))
        defer { _ = manager.shutdown() }
        let input = ModelessInputDialog(id: "status-probe", alert: NSAlert())
        let communicate = NSAlert(), choices = NSAlert()
        let teach = window(), dialog = window()
        defer { input.dismiss(); communicate.window.orderOut(nil); choices.window.orderOut(nil); dialog.close() }
        manager.activeInputDialogs = [input]; manager.activeCommunicateAlert = communicate; manager.activeChoiceAlert = choices
        manager.utilityWindows["teachbox"] = teach; manager.activeSystemDialogWindow = dialog
        #expect(manager.shioriStatusFlags().isEmpty)
        input.present(timeoutMs: nil) { _ in true }; communicate.window.orderFront(nil)
        teach.orderFront(nil); dialog.orderFront(nil); choices.window.orderFront(nil)
        #expect(manager.shioriStatusFlags().contains("opening(communicate/input/teach/dialog)"))
        #expect(manager.shioriStatusFlags().contains("choosing"))
        input.alert.window.orderOut(nil); communicate.window.orderOut(nil)
        teach.orderOut(nil); dialog.orderOut(nil); choices.window.orderOut(nil)
        #expect(manager.shioriStatusFlags().isEmpty) // stale references are not a displayed dialog
    }

    @Test func realModelessInputReportsOpeningThenClearsIt() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/Ourin-LiveInputStatus-\(UUID().uuidString)"))
        defer { _ = manager.shutdown() }
        manager.showInputBoxDialog(id: "status-probe", timeoutMs: 2500, initialText: "test")
        #expect(manager.activeInputDialogs.contains(where: { $0.isOpen && $0.alert.window.isVisible }))
        #expect(manager.shioriStatusFlags().contains("opening(input)"))
        #expect(manager.closeInputDialog(id: "status-probe"))
        #expect(!manager.shioriStatusFlags().contains(where: { $0.hasPrefix("opening(") }))
    }

    @Test func sharedColorPanelStatusMovesToTheGhostThatOpenedIt() {
        let first = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/Ourin-ColorFirst-\(UUID().uuidString)"))
        let second = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/Ourin-ColorSecond-\(UUID().uuidString)"))
        defer { NSColorPanel.shared.close(); _ = first.shutdown(); _ = second.shutdown() }
        first.showSystemDialog(type: "color", parameters: [])
        #expect(first.shioriStatusFlags().contains("opening(dialog)"))
        #expect(!second.shioriStatusFlags().contains("opening(dialog)"))
        second.showSystemDialog(type: "color", parameters: [])
        #expect(!first.shioriStatusFlags().contains("opening(dialog)"))
        #expect(second.shioriStatusFlags().contains("opening(dialog)"))
        NSColorPanel.shared.close()
        #expect(!second.shioriStatusFlags().contains("opening(dialog)"))
    }

    private func window() -> NSWindow {
        let result = NSWindow(contentRect: NSRect(x: 20,y: 20,width: 80,height: 60),
            styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
        result.isReleasedWhenClosed = false
        return result
    }
}
