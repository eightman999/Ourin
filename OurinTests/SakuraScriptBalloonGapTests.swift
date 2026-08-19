import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Ourin

// MARK: - \n[half] / \n[パーセント] の可変改行送り状態

struct BalloonNewlineSpacingTests {
    @Test func newlineAdvanceMapping() {
        #expect(BalloonViewModel.newlineAdvance(for: "half") == 0.5)
        #expect(BalloonViewModel.newlineAdvance(for: "HALF") == 0.5)
        #expect(BalloonViewModel.newlineAdvance(for: "150") == 1.5)
        #expect(BalloonViewModel.newlineAdvance(for: "-250") == -2.5)
        #expect(BalloonViewModel.newlineAdvance(for: "150%") == 1.5)
        #expect(BalloonViewModel.newlineAdvance(for: "75%") == 0.75)
        #expect(BalloonViewModel.newlineAdvance(for: "") == 1.0)
        #expect(BalloonViewModel.newlineAdvance(for: "abc") == 1.0)
    }

    @MainActor
    @Test func appendNewlineRecordsTextAndAdvances() {
        let vm = BalloonViewModel()
        vm.text = "line1"
        vm.setTextAlignment(.right)
        vm.appendNewline(advance: 0.5)
        vm.text += "line2"
        vm.setTextAlignment(.center)
        vm.appendNewline(advance: 1.5)
        vm.text += "line3"

        #expect(vm.text == "line1\nline2\nline3")
        #expect(vm.lineAdvances == [0.5, 1.5])
        #expect(vm.lineAlignment(forLineIndex: 0) == .right)
        #expect(vm.lineAlignment(forLineIndex: 1) == .center)
        #expect(vm.lineAlignment(forLineIndex: 2) == .left)
    }

    @MainActor
    @Test func alignmentCommandUpdatesOnlyCurrentLine() {
        let vm = BalloonViewModel()
        vm.text = "first"
        vm.setTextAlignment(.right)
        vm.appendNewline(advance: 1.0)
        vm.text += "second"
        vm.setTextAlignment(.center)

        #expect(vm.lineAlignment(forLineIndex: 0) == .right)
        #expect(vm.lineAlignment(forLineIndex: 1) == .center)

        vm.resetCurrentLineAlignment()
        #expect(vm.lineAlignment(forLineIndex: 0) == .right)
        #expect(vm.lineAlignment(forLineIndex: 1) == .left)
    }

    @MainActor
    @Test func alignCommandUpdatesCurrentLineThroughPlayback() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-line-align-command"))
        defer { _ = gm.shutdown() }
        let vm = gm.getBalloonVM(for: 0)
        vm.text = "already shown"

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "f", args: ["align", "right"]))
        gm.processNextUnit()

        #expect(vm.lineAlignment(forLineIndex: 0) == .right)
        #expect(vm.textAlign == .right)
    }

    @MainActor
    @Test func verticalAlignmentPersistsAcrossNewlinesAndUpdatesCurrentLine() {
        let vm = BalloonViewModel()
        vm.text = "first"
        vm.setVerticalTextAlignment(.bottom)
        vm.appendNewline(advance: 1.0)
        vm.text += "second"

        #expect(vm.lineVAlignment(forLineIndex: 0) == .bottom)
        #expect(vm.lineVAlignment(forLineIndex: 1) == .bottom)

        vm.setVerticalTextAlignment(.center)
        #expect(vm.lineVAlignment(forLineIndex: 0) == .bottom)
        #expect(vm.lineVAlignment(forLineIndex: 1) == .center)
    }

    @MainActor
    @Test func verticalAlignCommandUpdatesCurrentLineThroughPlayback() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-line-valign-command"))
        defer { _ = gm.shutdown() }
        let vm = gm.getBalloonVM(for: 0)
        vm.text = "already shown"

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "f", args: ["valign", "bottom"]))
        gm.processNextUnit()

        #expect(vm.lineVAlignment(forLineIndex: 0) == .bottom)
        #expect(vm.textVAlign == .bottom)
    }

    @MainActor
    @Test func fontDefaultRestoresCurrentLineAlignments() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-font-default-alignment"))
        defer { _ = gm.shutdown() }
        let vm = gm.getBalloonVM(for: 0)
        vm.text = "styled"
        vm.setTextAlignment(.right)
        vm.setVerticalTextAlignment(.bottom)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "f", args: ["default"]))
        gm.processNextUnit()

        #expect(vm.lineAlignment(forLineIndex: 0) == .left)
        #expect(vm.lineVAlignment(forLineIndex: 0) == .top)
    }

    @MainActor
    @Test func leadingAdvancePerLineIndex() {
        let vm = BalloonViewModel()
        vm.text = "a\nb\nc"
        vm.appendNewline(advance: 1.0)
        vm.appendNewline(advance: 2.0)

        #expect(vm.leadingAdvance(forLineIndex: 0) == 1.0)
        #expect(vm.leadingAdvance(forLineIndex: 1) == 1.0)
        #expect(vm.leadingAdvance(forLineIndex: 2) == 2.0)
        #expect(vm.leadingAdvance(forLineIndex: 99) == 1.0)
    }

    @MainActor
    @Test func variableNewlineIsQueuedUntilPlayback() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-newline-queue"))
        let vm = gm.getBalloonVM(for: gm.currentScope)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .newlineVariation("half"))

        #expect(vm.text.isEmpty)
        #expect(gm.playbackQueue.count == 1)
        if case .newlineVariation(let type) = gm.playbackQueue[0] {
            #expect(type == "half")
        } else {
            Issue.record("可変改行が再生キュー上の newlineVariation になっていない")
        }
    }

    @MainActor
    @Test func noWrapRangeTogglesAtPlaybackAndResetsAtScriptEnd() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-no-wrap"))
        let vm = gm.getBalloonVM(for: gm.currentScope)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "_n", args: []))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("No wrap"))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "_n", args: []))

        #expect(vm.wordWrapEnabled)
        gm.processNextUnit()
        #expect(!vm.wordWrapEnabled)

        gm.playbackQueue.removeAll()
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "_n", args: []))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .end)
        gm.processNextUnit()
        #expect(vm.wordWrapEnabled)
        _ = gm.shutdown()
    }

    @MainActor
    @Test func eventCommandWaitsForPrecedingTextPlayback() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-event-order"))
        defer { _ = gm.shutdown() }
        let runtime = InputOptionsRuntime()
        gm.shioriRuntime = runtime

        gm.sakuraEngine.run(script: "before\\![notify,OnTest,ref]")

        // 解析中にイベントを発火せず、本文と同じ再生キューへ登録する。
        #expect(runtime.requests.isEmpty)
        gm.processNextUnit()
        try await waitForRequest(runtime)

        #expect(runtime.requests.count == 1)
        guard let request = runtime.requests.first else {
            Issue.record("再生完了後もNOTIFYが発火しなかった")
            return
        }
        #expect(request.method == "NOTIFY")
        #expect(request.id == "OnTest")
        #expect(request.refs == ["ref"])
        #expect(gm.getBalloonVM(for: 0).text == "before")
    }

    @MainActor
    @Test func getCommandWaitsForPrecedingTextPlayback() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-get-order"))
        defer { _ = gm.shutdown() }
        let runtime = InputOptionsRuntime()
        gm.shioriRuntime = runtime

        gm.sakuraEngine.run(script: "before\\![get,word,lookup]")
        #expect(runtime.requests.isEmpty)
        gm.processNextUnit()
        try await waitForRequest(runtime)

        #expect(runtime.requests.count == 1)
        guard let request = runtime.requests.first else {
            Issue.record("再生完了後もGETが発火しなかった")
            return
        }
        #expect(request.method == "GET")
        #expect(request.id == "OnGetWord")
        #expect(request.refs == ["lookup"])
        #expect(gm.getBalloonVM(for: 0).text == "before")
    }

    @MainActor
    @Test func embedResponseIsInsertedBeforeFollowingText() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-embed-order"))
        defer { _ = gm.shutdown() }
        let runtime = InputOptionsRuntime()
        runtime.responses["OnEmbedTest"] = #"E\e"#
        gm.shioriRuntime = runtime

        gm.sakuraEngine.run(script: "before\\![embed,OnEmbedTest]after")
        gm.processNextUnit()
        try await waitForRequest(runtime)

        #expect(runtime.requests.count == 1)
        guard let request = runtime.requests.first else {
            Issue.record("再生完了後もembedイベントが発火しなかった")
            return
        }
        #expect(request.id == "OnEmbedTest")
        let vm = gm.getBalloonVM(for: 0)
        try await waitForBalloonText(vm, equals: "beforeEafter")
        #expect(vm.text == "beforeEafter")
    }

    @MainActor
    @Test func quickSectionsControlTextPlaybackRate() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-quick-section"))
        defer { _ = gm.shutdown() }
        let vm = gm.getBalloonVM(for: 0)

        gm.sakuraEngine.run(script: "\\_qFast\\_q\\![quicksection,true]Now\\![quicksection,false]Later")
        gm.processNextUnit()

        // クイック本文は即時、通常本文は最初の1文字だけ再生される。
        #expect(vm.text == "FastNowL")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(vm.text == "FastNowLater")
    }

    @MainActor
    @Test func voiceRangeCommandsRemainInPlaybackOrder() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-voice-range"))
        defer { _ = gm.shutdown() }

        gm.sakuraEngine.run(script: #"\__v[disable]Silent\__v\__v[alternate,ひらがな]漢字\__v"#)

        let order = gm.playbackQueue.compactMap { unit -> String? in
            switch unit {
            case .voiceCommand(let args):
                return "voice:" + args.joined(separator: ",")
            case .textToken(let text):
                return "text:" + text
            case .speakTextToken(let text):
                return "speak:" + text
            default:
                return nil
            }
        }
        #expect(order == [
            "voice:disable", "text:Silent", "speak:Silent", "voice:",
            "voice:alternate,ひらがな", "text:漢字", "speak:漢字", "voice:"
        ])
    }

    @MainActor
    @Test func visualAndMediaCommandsAreQueuedAfterPrecedingText() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-side-effect-order"))
        defer { _ = gm.shutdown() }

        gm.sakuraEngine.run(script: "before\\i[0,wait]\\4\\5\\6\\7\\8[sound.wav]after")

        let order = gm.playbackQueue.compactMap { unit -> String? in
            switch unit {
            case .textToken(let text):
                return "text:" + text
            case .speakTextToken(let text):
                return "speak:" + text
            case .startAnimation(let id, let wait):
                return "animation:\(id):\(wait)"
            case .moveAway:
                return "move-away"
            case .moveClose:
                return "move-close"
            case .executeSNTPApply:
                return "sntp-apply"
            case .executeSNTP:
                return "sntp"
            case .playSound(let filename):
                return "sound:" + filename
            default:
                return nil
            }
        }
        #expect(order == [
            "text:before", "speak:before", "animation:0:true", "move-away", "move-close",
            "sntp-apply", "sntp", "sound:sound.wav", "text:after", "speak:after"
        ])
    }

    @MainActor
    @Test func directCommandsAreQueuedAfterPrecedingText() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-command-order"))
        defer { _ = gm.shutdown() }
        let runtime = InputOptionsRuntime()
        gm.shioriRuntime = runtime

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("before"))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "f", args: ["align", "right"]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "_s", args: []))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "_l", args: ["10", "20"]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "_v", args: ["voice.wav"]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "m", args: ["100", "2", "3"]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "j", args: ["OnJump"]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("after"))

        let order = gm.playbackQueue.compactMap { unit -> String? in
            switch unit {
            case .textToken(let text):
                return "text:" + text
            case .speakTextToken(let text):
                return "speak:" + text
            case .deferredCommand:
                return "command"
            case .playSound(let filename):
                return "sound:" + filename
            default:
                return nil
            }
        }

        #expect(runtime.requests.isEmpty)
        #expect(order == [
            "text:before", "speak:before", "command", "command", "command",
            "sound:voice.wav", "command", "command", "text:after", "speak:after"
        ])
    }

    @MainActor
    @Test func soundCommandsAreQueuedAfterPrecedingText() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-sound-command-order"))
        defer { _ = gm.shutdown() }

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("before"))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "sound", "play", "tone.wav"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "sound", "pause", "tone.wav"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "sound", "stop", "tone.wav"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "sound", "wait"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("after"))

        let order = gm.playbackQueue.compactMap { unit -> String? in
            switch unit {
            case .textToken(let text):
                return "text:" + text
            case .speakTextToken(let text):
                return "speak:" + text
            case .deferredCommand:
                return "sound-command"
            case .waitForAudio:
                return "sound-wait"
            default:
                return nil
            }
        }

        #expect(order == [
            "text:before", "speak:before", "sound-command", "sound-command",
            "sound-command", "sound-wait", "text:after", "speak:after"
        ])
    }

    @MainActor
    @Test func settingsCommandsAreQueuedAfterPrecedingText() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-settings-command-order"))
        defer { _ = gm.shutdown() }

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("before"))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "set", "scaling", "80", "90", "100"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "set", "alpha", "75", "100"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "set", "timerinterval", "50"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "enter", "onlinemode"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "leave", "onlinemode"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("after"))

        let order = gm.playbackQueue.compactMap { unit -> String? in
            switch unit {
            case .textToken(let text):
                return "text:" + text
            case .speakTextToken(let text):
                return "speak:" + text
            case .setScaling:
                return "scaling"
            case .setAlpha:
                return "alpha"
            case .deferredCommand:
                return "command"
            default:
                return nil
            }
        }

        #expect(order == [
            "text:before", "speak:before", "scaling", "alpha", "command", "command",
            "command", "text:after", "speak:after"
        ])
    }

    @MainActor
    @Test func visualControlCommandsAreQueuedAfterPrecedingText() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-visual-command-order"))
        defer { _ = gm.shutdown() }

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("before"))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "anim", "stop"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "bind", "head", "ribbon", "1"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "effect", "fade", "1"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "filter", "blur", "100"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "move", "--X=10", "--Y=20"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "resize", "window", "100", "100"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "open", "https://example.com"
        ]))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("after"))

        let order = gm.playbackQueue.compactMap { unit -> String? in
            switch unit {
            case .textToken(let text):
                return "text:" + text
            case .speakTextToken(let text):
                return "speak:" + text
            case .deferredCommand:
                return "command"
            default:
                return nil
            }
        }

        #expect(order == [
            "text:before", "speak:before", "command", "command", "command",
            "command", "command", "command", "command", "text:after", "speak:after"
        ])
    }

    @MainActor
    @Test func windowAndOpenCommandsAreQueuedAfterPrecedingText() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-window-command-order"))
        defer { _ = gm.shutdown() }

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("before"))
        for args in [
            ["hide"], ["show"], ["focus"], ["b"], ["minimize"], ["maximize"], ["*"],
            ["open", "http", "https://example.com"],
            ["open", "send", "https://example.com", "body"]
        ] {
            gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: args))
        }
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("after"))

        let order = gm.playbackQueue.compactMap { unit -> String? in
            switch unit {
            case .textToken(let text):
                return "text:" + text
            case .speakTextToken(let text):
                return "speak:" + text
            case .deferredCommand:
                return "command"
            default:
                return nil
            }
        }

        #expect(order == [
            "text:before", "speak:before", "command", "command", "command", "command",
            "command", "command", "command", "command", "command", "text:after", "speak:after"
        ])
    }

    @MainActor
    @Test func systemCommandsAreQueuedAfterPrecedingText() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-system-command-order"))
        defer { _ = gm.shutdown() }

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("before"))
        let commands = [
            ["lock", "repaint"], ["unlock", "repaint"],
            ["execute", "ping", "localhost"], ["create", "shortcut", "/tmp/source", "/tmp/link"],
            ["clipboard", "set", "hello"], ["systemmessage", "title", "body"],
            ["quicksession", "true"], ["executesntp"], ["biff", "account"],
            ["update", "http", "https://example.com"], ["updatebymyself", "check"],
            ["updateother", "check"], ["vanishbymyself", "next", "--option=query"],
            ["reloadsurface"], ["reload", "descript", "ghost"],
            ["unload", "shiori"], ["load", "shiori"]
        ]
        for args in commands {
            gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: args))
        }
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .text("after"))

        let order = gm.playbackQueue.compactMap { unit -> String? in
            switch unit {
            case .textToken(let text):
                return "text:" + text
            case .speakTextToken(let text):
                return "speak:" + text
            case .deferredCommand:
                return "command"
            default:
                return nil
            }
        }

        #expect(order == ["text:before", "speak:before"]
            + Array(repeating: "command", count: commands.count)
            + ["text:after", "speak:after"])
    }

    @MainActor
    @Test func balloonOffsetCommandUsesXAndYArguments() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-balloon-offset-command"))
        let vm = gm.getBalloonVM(for: gm.currentScope)
        vm.balloonOffsetX = 10
        vm.balloonOffsetY = 20

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "set", "balloonoffset", "100", "-50"
        ]))
        gm.processNextUnit()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.balloonOffsetX == 100)
        #expect(vm.balloonOffsetY == -50)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "set", "balloonoffset", "@10", "@-5"
        ]))
        gm.processNextUnit()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.balloonOffsetX == 110)
        #expect(vm.balloonOffsetY == -55)
    }

    @MainActor
    @Test func autoscrollCommandAcceptsEnableAndDisableWords() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-autoscroll-command"))
        let vm = gm.getBalloonVM(for: gm.currentScope)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "set", "autoscroll", "enable"
        ]))
        gm.processNextUnit()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.autoscrollEnabled)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "set", "autoscroll", "disable"
        ]))
        gm.processNextUnit()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(!vm.autoscrollEnabled)
    }

    @MainActor
    @Test func onlineModeCommandTogglesForcedMarkerState() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-online-mode"))
        let vm = gm.getBalloonVM(for: gm.currentScope)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "enter", "onlinemode"
        ]))
        gm.processNextUnit()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(vm.onlineModeActive)
        #expect(vm.onlineMarkerIndex == 0)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "leave", "onlinemode"
        ]))
        gm.processNextUnit()
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(!vm.onlineModeActive)
        #expect(vm.onlineMarkerIndex == 0)
    }
}

struct BalloonScalingLayoutTests {
    @Test func scaledSizeUsesAbsoluteDimensionsForFlippedBalloons() {
        let size = BalloonView.scaledSize(
            for: CGSize(width: 400, height: 150),
            scaleX: -0.5,
            scaleY: 2.0
        )

        #expect(size.width == 200)
        #expect(size.height == 300)
    }

    @Test func scaledSizeFallsBackForNonFiniteScale() {
        let size = BalloonView.scaledSize(
            for: CGSize(width: 400, height: 150),
            scaleX: .nan,
            scaleY: .infinity
        )

        #expect(size.width == 400)
        #expect(size.height == 150)
    }
}

struct BalloonTextLayoutTests {
    @Test func descriptorCoordinatesAndMarginsDefineTextRegion() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("emily4/balloon/descript.txt")
            .path
        guard let config = BalloonConfig.load(from: path) else {
            Issue.record("Emily balloon descript.txt could not be loaded")
            return
        }

        let rect = BalloonView.textLayoutRect(
            for: config,
            size: CGSize(width: 400, height: 150)
        )

        // origin=(20,10), wordwrappoint.x=-34 => x=366, validrect.bottom=-10 => y=140.
        #expect(rect == CGRect(x: 20, y: 10, width: 346, height: 130))
    }

    @Test func rightAlignmentUsesRightWordWrapAndMargins() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ourin-balloon-layout-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let descriptor = """
        charset,UTF-8
        name,layout-test
        origin.x,10
        origin.y,8
        validrect.left,4
        validrect.top,6
        validrect.right,-12
        validrect.bottom,-14
        wordwrappoint.x,-30
        wordwrappointright,-20
        marginx,5
        marginy,3
        """
        try descriptor.write(
            to: directory.appendingPathComponent("descript.txt"),
            atomically: true,
            encoding: .utf8
        )
        guard let config = BalloonConfig.load(from: directory.appendingPathComponent("descript.txt").path) else {
            Issue.record("Temporary balloon descript.txt could not be loaded")
            return
        }

        let rect = BalloonView.textLayoutRect(
            for: config,
            size: CGSize(width: 400, height: 150),
            alignment: .right
        )

        // right wrap=-20 => x=380; origin + margin=(15,11); right margin=5.
        #expect(rect == CGRect(x: 15, y: 11, width: 360, height: 122))
    }
}

struct SakuraScriptSystemCommandTests {
    @MainActor
    @Test func syncObjectSetAndResetCommands() {
        let name = "ourin-sync-\(UUID().uuidString)"
        SyncCenter.shared.reset(name: name)
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-sync-command"))

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "set", "syncobject", name
        ]))
        gm.processNextUnit()
        let signaledDelay = SyncCenter.shared.wait(name: name, timeout: 0.1)
        #expect(signaledDelay < 0.05)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "reset", "syncobject", name
        ]))
        gm.processNextUnit()
        let resetStart = Date()
        _ = SyncCenter.shared.wait(name: name, timeout: 0.02)
        #expect(Date().timeIntervalSince(resetStart) >= 0.01)
        SyncCenter.shared.reset(name: name)
    }

    @MainActor
    @Test func syncObjectWaitDoesNotBlockScriptParsing() async throws {
        let name = "ourin-sync-wait-\(UUID().uuidString)"
        SyncCenter.shared.reset(name: name)
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-sync-wait"))
        defer {
            SyncCenter.shared.reset(name: name)
            _ = gm.shutdown()
        }

        let start = Date()
        gm.runScript("\\![wait,syncobject,\(name),200]")
        #expect(Date().timeIntervalSince(start) < 0.1)

        try await waitForPlaybackToStop(gm)
        #expect(!gm.isPlaying)
    }

    @MainActor
    @Test func resetBalloonPositionCommandClearsPersistedScopes() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-reset-balloon-position"))
        gm.resourceManager.setBalloonLeft(scope: 0, value: 123)
        gm.resourceManager.setBalloonTop(scope: 0, value: 456)
        gm.resourceManager.setBalloonLeft(scope: 3, value: 789)
        gm.resourceManager.setBalloonTop(scope: 3, value: 987)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "!", args: [
            "execute", "resetballoonpos"
        ]))
        gm.processNextUnit()
        try await Task.sleep(nanoseconds: 50_000_000)

        #expect(gm.resourceManager.getBalloonLeft(scope: 0) == nil)
        #expect(gm.resourceManager.getBalloonTop(scope: 0) == nil)
        #expect(gm.resourceManager.getBalloonLeft(scope: 3) == nil)
        #expect(gm.resourceManager.getBalloonTop(scope: 3) == nil)
    }
}

struct BasewareCommandSemanticsTests {
    @Test
    func sequentialGhostOrderIsStableAndWraps() {
        let items = [
            NarPackageItem(type: "ghost", name: "Zeta", path: URL(fileURLWithPath: "/tmp/Zeta")),
            NarPackageItem(type: "ghost", name: "alpha", path: URL(fileURLWithPath: "/tmp/alpha")),
            NarPackageItem(type: "ghost", name: "Beta", path: URL(fileURLWithPath: "/tmp/Beta"))
        ]

        #expect(NarRegistry.sequentialGhostName(items: items, currentName: "alpha") == "Beta")
        #expect(NarRegistry.sequentialGhostName(items: items, currentName: "Zeta") == "alpha")
        #expect(NarRegistry.sequentialGhostName(items: items, currentName: nil) == "alpha")
        #expect(NarRegistry.sequentialGhostName(items: [items[0]], currentName: "Zeta") == nil)
    }

    @MainActor
    @Test
    func inputDialogOptionsReachUserInputReferences() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-input-options"))
        let runtime = InputOptionsRuntime()
        manager.shioriRuntime = runtime
        let options = manager.inputDialogOptions(from: [
            "InputID", "--limit=4", "--option=noclose", "--option=noclear",
            "--reference=first", "--reference=second"
        ])

        manager.emitUserInput(id: "InputID", value: "abcdef", options: options)
        #expect(runtime.lastRequest?.method == "GET")
        #expect(runtime.lastRequest?.id == "OnUserInput")
        #expect(runtime.lastRequest?.refs == ["InputID", "abcd", "", "first", "second"])
    }
}

private final class InputOptionsRuntime: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .native
    var isLoaded = true
    var resourceManager: ResourceManager?
    var lastRequest: (method: String, id: String, refs: [String])?
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
        lastRequest = (method, id, refs)
        requests.append((method, id, refs))
        if let response = responses[id] {
            return .init(ok: true, status: 200, value: response)
        }
        return .init(ok: true, status: 204)
    }

    func unload() { isLoaded = false }
}

@MainActor
private func waitForRequest(
    _ runtime: InputOptionsRuntime,
    timeoutNanoseconds: UInt64 = 3_000_000_000
) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while runtime.requests.isEmpty {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if elapsed >= timeoutNanoseconds {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
private func waitForRequestID(
    _ runtime: InputOptionsRuntime,
    equals expected: String,
    timeoutNanoseconds: UInt64 = 3_000_000_000
) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while runtime.lastRequest?.id != expected {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if elapsed >= timeoutNanoseconds {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
private func waitForPlaybackToStop(
    _ manager: GhostManager,
    timeoutNanoseconds: UInt64 = 3_000_000_000
) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while manager.isPlaying {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if elapsed >= timeoutNanoseconds {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

@MainActor
private func waitForBalloonText(
    _ viewModel: BalloonViewModel,
    equals expected: String,
    timeoutNanoseconds: UInt64 = 5_000_000_000
) async throws {
    let start = DispatchTime.now().uptimeNanoseconds
    while viewModel.text != expected {
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if elapsed >= timeoutNanoseconds {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
}

// MARK: - \_a[...]...\_a の範囲アンカーとクリック時ルーティング

struct BalloonAnchorRangeTests {
    @MainActor
    @Test func anchorSegmentsSplitSingleLineRanges() {
        let vm = BalloonViewModel()
        vm.text = "Click here and there now."
        // "here"(index 6, len 4) と "there"(index 15, len 5)
        vm.anchors = [
            BalloonAnchorRange(id: "one", references: ["r0"], text: "here", range: NSRange(location: 6, length: 4)),
            BalloonAnchorRange(id: "two", references: ["r0"], text: "there", range: NSRange(location: 15, length: 5))
        ]

        let segments = vm.anchorSegments(lineIndex: 0)
        #expect(segments == [
            BalloonTextSegment(text: "Click ", isAnchor: false, anchorIndex: nil),
            BalloonTextSegment(text: "here", isAnchor: true, anchorIndex: 0),
            BalloonTextSegment(text: " and ", isAnchor: false, anchorIndex: nil),
            BalloonTextSegment(text: "there", isAnchor: true, anchorIndex: 1),
            BalloonTextSegment(text: " now.", isAnchor: false, anchorIndex: nil)
        ])
    }

    @MainActor
    @Test func anchorSegmentsSpanMultipleLines() {
        let vm = BalloonViewModel()
        vm.text = "a\nb\nc"
        vm.anchors = [
            BalloonAnchorRange(id: "mid", references: [], text: "b", range: NSRange(location: 2, length: 1))
        ]

        #expect(vm.anchorSegments(lineIndex: 0) == [BalloonTextSegment(text: "a", isAnchor: false, anchorIndex: nil)])
        #expect(vm.anchorSegments(lineIndex: 1) == [BalloonTextSegment(text: "b", isAnchor: true, anchorIndex: 0)])
        #expect(vm.anchorSegments(lineIndex: 2) == [BalloonTextSegment(text: "c", isAnchor: false, anchorIndex: nil)])
    }

    @MainActor
    @Test func nestedAnchorsUseLaterAddedIndex() {
        let vm = BalloonViewModel()
        vm.text = "abcdef"
        vm.anchors = [
            BalloonAnchorRange(id: "outer", references: [], text: "abcdef", range: NSRange(location: 0, length: 6)),
            BalloonAnchorRange(id: "inner", references: [], text: "bcde", range: NSRange(location: 1, length: 4))
        ]

        let segments = vm.anchorSegments(lineIndex: 0)
        #expect(segments == [
            BalloonTextSegment(text: "a", isAnchor: true, anchorIndex: 0),
            BalloonTextSegment(text: "bcde", isAnchor: true, anchorIndex: 1),
            BalloonTextSegment(text: "f", isAnchor: true, anchorIndex: 0)
        ])
    }

    @MainActor
    @Test func openAndCloseAnchorBuildsRangeWithActionData() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-anchor-range"))
        let vm = gm.getBalloonVM(for: gm.currentScope)
        vm.text = "Hello "

        gm.openAnchorRange(id: "gorilla", references: ["r2", "r3"])
        vm.text += "target"
        gm.closeAnchorRange()

        #expect(vm.anchors.count == 1)
        let anchor = vm.anchors[0]
        #expect(anchor.id == "gorilla")
        #expect(anchor.references == ["r2", "r3"])
        #expect(anchor.text == "target")
        #expect(anchor.range.location == 6)
        #expect(anchor.range.length == 6)
        #expect(anchor.pluginOrigin == false)
        #expect(vm.anchorActive == true)
    }

    @MainActor
    @Test func anchorPreservesPluginOriginForDeferredOpen() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-anchor-plugin-origin"))
        let vm = gm.getBalloonVM(for: gm.currentScope)

        gm.openAnchorRange(id: "plugin-link", references: [], pluginOrigin: true)
        vm.text = "plugin target"
        gm.closeAnchorRange()

        #expect(vm.anchors.count == 1)
        #expect(vm.anchors[0].pluginOrigin == true)
    }

    @MainActor
    @Test func unclosedAnchorFinalizedAtScriptEnd() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-anchor-finalize"))
        let vm = gm.getBalloonVM(for: gm.currentScope)
        vm.text = "xx"

        gm.openAnchorRange(id: "OnBottomClick", references: ["A"])
        vm.text += "yy"
        gm.finalizePendingAnchorIfNeeded()

        #expect(vm.anchors.count == 1)
        let anchor = vm.anchors[0]
        #expect(anchor.id == "OnBottomClick")
        #expect(anchor.references == ["A"])
        #expect(anchor.text == "yy")
        #expect(anchor.range == NSRange(location: 2, length: 2))

        // 確定済みのアンカーが再確定されないこと。
        gm.finalizePendingAnchorIfNeeded()
        #expect(vm.anchors.count == 1)
    }

    @Test func routeAnchorClickMapsOnPrefixToDirectEvent() {
        let anchor = BalloonAnchorRange(id: "OnClickMe", references: ["r0", "r1"], text: "here", range: NSRange(location: 0, length: 4))
        #expect(routeAnchorClick(anchor) == .directEvent(id: "OnClickMe", references: ["r0", "r1"]))
    }

    @Test func routeAnchorClickMapsPlainIdToAnchorSelect() {
        let anchor = BalloonAnchorRange(id: "link", references: ["r2", "r3"], text: "here", range: NSRange(location: 0, length: 4))
        #expect(routeAnchorClick(anchor) == .anchorSelect(id: "link", clickedText: "here", selectedReferences: ["r2", "r3"]))
    }

    @Test func anchorEventParametersUseLabelIDAndExtendedReferences() {
        let anchor = BalloonAnchorRange(
            id: "link",
            references: ["r2", "r3"],
            text: "表示",
            range: NSRange(location: 0, length: 2)
        )
        #expect(anchorEventParameters(for: anchor) == [
            "Reference0": "表示",
            "Reference1": "link",
            "Reference2": "r2",
            "Reference3": "r3"
        ])
    }

    @MainActor
    @Test func renderedAnchorHoverUsesGETAndSelectionFallsBackFromEx() async throws {
        EventBridge.shared.stop()
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-anchor-events"))
        let runtime = InputOptionsRuntime()
        manager.shioriRuntime = runtime
        let token = EventBridge.shared.register(runtime: runtime, ghostManager: manager)
        defer {
            EventBridge.shared.unregister(token)
            EventBridge.shared.stop()
        }

        let anchor = BalloonAnchorRange(
            id: "link",
            references: ["r2"],
            text: "表示",
            range: NSRange(location: 0, length: 2)
        )
        manager.onBalloonAnchorHover(anchor, fromScope: 0, hovering: true)
        #expect(runtime.lastRequest?.method == "GET")
        #expect(runtime.lastRequest?.id == "OnAnchorEnter")
        #expect(runtime.lastRequest?.refs == ["表示", "link", "r2"])

        try await waitForRequestID(runtime, equals: "OnAnchorHover")
        #expect(runtime.lastRequest?.id == "OnAnchorHover")
        #expect(runtime.lastRequest?.refs == ["表示", "link", "r2"])

        manager.onBalloonAnchorHover(anchor, fromScope: 0, hovering: false)
        #expect(runtime.lastRequest?.id == "OnAnchorEnter")
        #expect(runtime.lastRequest?.refs == [])

        runtime.responses["OnAnchorSelectEx"] = #"\0handled\e"#
        manager.onBalloonAnchorClicked(anchor, fromScope: 0)
        let firstSelectionIDs = runtime.requests
            .filter { $0.id == "OnAnchorSelectEx" || $0.id == "OnAnchorSelect" }
            .map(\.id)
        #expect(firstSelectionIDs.last == "OnAnchorSelectEx")
        #expect(firstSelectionIDs.contains("OnAnchorSelect") == false)

        runtime.responses.removeValue(forKey: "OnAnchorSelectEx")
        manager.onBalloonAnchorClicked(anchor, fromScope: 0)
        let lastIDs = runtime.requests
            .filter { $0.id == "OnAnchorSelectEx" || $0.id == "OnAnchorSelect" }
            .map(\.id)
            .suffix(2)
        #expect(lastIDs == ["OnAnchorSelectEx", "OnAnchorSelect"])
    }
}

// MARK: - \c[…] クリア／短縮時の状態同期

struct BalloonClearTruncationTests {
    @MainActor
    @Test func clearCharactersAtExplicitStartRemovesMiddleTextAndShiftsInlineImages() {
        let vm = BalloonViewModel()
        vm.text = "ab\(BalloonViewModel.inlineImagePlaceholder)cdef"
        vm.balloonImages = [
            BalloonViewModel.BalloonImage(
                filepath: "inline.png", x: 0, y: 0, isInline: true,
                isOpaque: true, useSelfAlpha: false, clipping: nil,
                isForeground: false, isFixed: false, inlineTextOffset: 2,
                image: nil
            ),
            BalloonViewModel.BalloonImage(
                filepath: "inline-2.png", x: 0, y: 0, isInline: true,
                isOpaque: true, useSelfAlpha: false, clipping: nil,
                isForeground: false, isFixed: false, inlineTextOffset: 5,
                image: nil
            )
        ]
        vm.clearCharacters(2, start: 1)

        #expect(vm.text == "acdef")
        #expect(vm.balloonImages.count == 1)
        #expect(vm.balloonImages.first?.inlineTextOffset == 3)
    }

    @MainActor
    @Test func clearLinesAtExplicitStartPreservesRemainingLineSeparatorsAndAdvances() {
        let vm = BalloonViewModel()
        vm.text = "line0\nline1\nline2"
        vm.lineAdvances = [0.5, 1.5]
        vm.lineAlignments = [.left, .center, .right]
        vm.lineVAlignments = [.top, .center, .bottom]

        vm.clearLines(1, start: 1)

        #expect(vm.text == "line0\nline2")
        #expect(vm.lineAdvances == [0.5])
        #expect(vm.lineAlignment(forLineIndex: 0) == .left)
        #expect(vm.lineAlignment(forLineIndex: 1) == .right)
        #expect(vm.lineVAlignment(forLineIndex: 0) == .top)
        #expect(vm.lineVAlignment(forLineIndex: 1) == .bottom)
    }

    @MainActor
    @Test func cursorMoveResetsCurrentLineAlignment() {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-cursor-alignment"))
        defer { _ = gm.shutdown() }
        let vm = gm.getBalloonVM(for: 0)
        vm.text = "line"
        vm.setTextAlignment(.right)

        gm.handleCursorMove(x: "10", y: "20")

        #expect(vm.lineAlignment(forLineIndex: 0) == .left)
    }

    @MainActor
    @Test func clearCommandRunsAfterQueuedText() async throws {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-clear-order-test"))
        defer { _ = manager.shutdown() }
        let vm = manager.getBalloonVM(for: manager.currentScope)

        manager.sakuraEngine(manager.sakuraEngine, didEmit: .text("abc"))
        manager.sakuraEngine(manager.sakuraEngine, didEmit: .command(name: "c", args: ["char", "3"]))

        #expect(vm.text.isEmpty)
        manager.processNextUnit()
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(vm.text.isEmpty)
    }

    @MainActor
    @Test func truncateCharactersClampsAdvancesAndAnchors() {
        let vm = BalloonViewModel()
        vm.text = "ab"
        vm.appendNewline(advance: 0.5)
        vm.text += "cd"
        vm.anchors = [BalloonAnchorRange(id: "a1", references: [], text: "ab\ncd", range: NSRange(location: 0, length: 5))]

        vm.truncateSuffixCharacters(2)
        #expect(vm.text == "ab\n")
        #expect(vm.lineAdvances == [0.5])
        #expect(vm.anchors.count == 1)
        #expect(vm.anchors[0].range == NSRange(location: 0, length: 3))
    }

    @MainActor
    @Test func truncateCharactersRemovingNewlineRemovesAdvance() {
        let vm = BalloonViewModel()
        vm.text = "a"
        vm.appendNewline(advance: 1.0)
        vm.text += "b"

        vm.truncateSuffixCharacters(2)
        #expect(vm.text == "a")
        #expect(vm.lineAdvances.isEmpty)
    }

    @MainActor
    @Test func truncateLinesRemovesAdvancesAndAnchors() {
        let vm = BalloonViewModel()
        vm.text = "a"
        vm.appendNewline(advance: 0.5)
        vm.text += "b"
        vm.appendNewline(advance: 2.0)
        vm.text += "c"
        vm.anchors = [BalloonAnchorRange(id: "a1", references: [], text: "c", range: NSRange(location: 4, length: 1))]

        vm.truncateSuffixLines(2)
        #expect(vm.text == "a")
        #expect(vm.lineAdvances.isEmpty)
        #expect(vm.anchors.isEmpty)
    }

    @MainActor
    @Test func truncateBeyondTextDoesNotCrash() {
        let vm = BalloonViewModel()
        vm.text = "x"
        vm.truncateSuffixCharacters(10)
        #expect(vm.text.isEmpty)
        #expect(vm.lineAdvances.isEmpty)

        let vm2 = BalloonViewModel()
        vm2.text = "x"
        vm2.truncateSuffixLines(10)
        #expect(vm2.text.isEmpty)
    }

    @MainActor
    @Test func resetBalloonContentClearsAllState() {
        let vm = BalloonViewModel()
        vm.text = "abc\nxyz"
        vm.appendNewline(advance: 0.5)
        vm.anchors = [BalloonAnchorRange(id: "a1", references: [], text: "xyz", range: NSRange(location: 4, length: 3))]
        vm.anchorActive = true

        vm.resetBalloonContent()
        #expect(vm.text.isEmpty)
        #expect(vm.lineAdvances.isEmpty)
        #expect(vm.anchors.isEmpty)
        #expect(vm.anchorActive == false)
    }
}

// MARK: - \C 追記モード

struct SakuraScriptAppendModeTests {
    @MainActor
    @Test func leadingAppendModePreservesPreviousBalloonAndReturnsToScopeZero() async throws {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-append-mode-test"))
        defer { _ = manager.shutdown() }
        let vm = manager.getBalloonVM(for: 0)
        vm.text = "previous"
        manager.currentScope = 1

        manager.runTranslatedScript("\\Cnext")
        #expect(vm.text == "previous")
        #expect(manager.currentScope == 0)

        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(vm.text == "previousnext")
    }

    @MainActor
    @Test func normalScriptStillClearsPreviousBalloon() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-normal-script-clear-test"))
        defer { _ = manager.shutdown() }
        let vm = manager.getBalloonVM(for: 0)
        vm.text = "previous"

        manager.runTranslatedScript("next")

        #expect(vm.text.isEmpty)
    }
}

// MARK: - \b 再生順序

struct SakuraScriptBalloonSwitchOrderTests {
    @MainActor
    @Test func balloonSwitchWaitsForPreviousTextAndUsesPlaybackScope() async throws {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-balloon-switch-order-test"))
        defer { _ = manager.shutdown() }
        manager.setupWindows()
        let vm = manager.getBalloonVM(for: manager.currentScope)
        guard let characterVM = manager.characterViewModels[manager.currentScope] else {
            Issue.record("character view model was not created")
            return
        }
        let originalID = characterVM.currentBalloonID

        manager.sakuraEngine(manager.sakuraEngine, didEmit: .text("before"))
        manager.sakuraEngine(manager.sakuraEngine, didEmit: .balloon(2))

        #expect(characterVM.currentBalloonID == originalID)
        manager.processNextUnit()
        try await Task.sleep(nanoseconds: 700_000_000)

        #expect(vm.text == "before")
        #expect(characterVM.currentBalloonID == 2)
        #expect(vm.balloonID == 2)
    }
}

// MARK: - アンカー装飾（anchorstyle / anchorvisitedstyle / anchornotselectstyle）の状態と描画解決

struct BalloonAnchorDecorationTests {
    @Test func anchorStyleParsing() {
        // 型を明示（`.none` は Optional.none と曖昧になるため）
        #expect(AnchorDecorationStyle(shape: "none") == AnchorDecorationStyle.none)
        #expect(AnchorDecorationStyle(shape: "underline") == AnchorDecorationStyle.underline)
        #expect(AnchorDecorationStyle(shape: "square") == AnchorDecorationStyle.square)
        #expect(AnchorDecorationStyle(shape: "square+underline") == AnchorDecorationStyle.squareUnderline)
        // 大文字小文字・前後空白は無視する
        #expect(AnchorDecorationStyle(shape: "SQUARE+UNDERLINE") == AnchorDecorationStyle.squareUnderline)
        #expect(AnchorDecorationStyle(shape: "  Square  ") == AnchorDecorationStyle.square)
        // default / 未知値は nil（現状維持）
        #expect(AnchorDecorationStyle(shape: "default") == nil)
        #expect(AnchorDecorationStyle(shape: "strike") == nil)
        #expect(AnchorDecorationStyle(shape: "") == nil)
    }

    @MainActor
    @Test func decorationDefaultsToNotSelectStyle() {
        let vm = BalloonViewModel()
        vm.anchors = [BalloonAnchorRange(id: "a", references: [], text: "x", range: NSRange(location: 0, length: 1))]
        vm.anchornotselectStyle = .square
        vm.anchorvisitedStyle = .squareUnderline

        // 訪問済みでなければ非選択装飾が適用される
        let decoration = vm.decoration(forAnchorAt: 0)
        #expect(decoration.style == .square)
    }

    @MainActor
    @Test func decorationUsesVisitedStyleAfterVisited() {
        let vm = BalloonViewModel()
        vm.anchors = [BalloonAnchorRange(id: "a", references: [], text: "x", range: NSRange(location: 0, length: 1))]
        vm.anchornotselectStyle = .square
        vm.anchorvisitedStyle = .squareUnderline

        vm.markAnchorVisited(at: 0)
        #expect(vm.anchors[0].visited == true)
        let decoration = vm.decoration(forAnchorAt: 0)
        #expect(decoration.style == .squareUnderline)
    }

    @MainActor
    @Test func decorationPrefersActiveAnchorStyle() {
        let vm = BalloonViewModel()
        vm.anchors = [BalloonAnchorRange(id: "a", references: [], text: "x", range: NSRange(location: 0, length: 1))]
        vm.anchornotselectStyle = .square
        vm.anchorvisitedStyle = .squareUnderline
        vm.anchorStyle = .none

        vm.markAnchorVisited(at: 0)
        vm.activeAnchorIndex = 0
        // ホバー中のアンカーは訪問済みより選択中装飾が優先される
        #expect(vm.decoration(forAnchorAt: 0).style == .none)
        vm.activeAnchorIndex = nil
        #expect(vm.decoration(forAnchorAt: 0).style == .squareUnderline)
    }

    @MainActor
    @Test func decorationUsesFontColorForEachAnchorState() {
        let vm = BalloonViewModel()
        let active = NSColor.systemRed
        let notSelect = NSColor.systemGreen
        let visited = NSColor.systemBlue
        vm.anchorFontColor = active
        vm.anchorNotSelectFontColor = notSelect
        vm.anchorVisitedFontColor = visited
        vm.anchors = [
            BalloonAnchorRange(id: "plain", references: [], text: "x", range: NSRange(location: 0, length: 1)),
            BalloonAnchorRange(id: "visited", references: [], text: "y", range: NSRange(location: 1, length: 1), visited: true)
        ]

        #expect(vm.decoration(forAnchorAt: 0).fontColor == notSelect)
        #expect(vm.decoration(forAnchorAt: 1).fontColor == visited)
        vm.activeAnchorIndex = 0
        #expect(vm.decoration(forAnchorAt: 0).fontColor == active)
    }

    @MainActor
    @Test func markAnchorVisitedMatchesByIdAndRange() {
        let vm = BalloonViewModel()
        vm.anchors = [
            BalloonAnchorRange(id: "one", references: [], text: "abc", range: NSRange(location: 0, length: 3)),
            BalloonAnchorRange(id: "two", references: [], text: "def", range: NSRange(location: 4, length: 3))
        ]
        vm.markAnchorVisited(id: "two", range: NSRange(location: 4, length: 3))
        #expect(vm.anchors[0].visited == false)
        #expect(vm.anchors[1].visited == true)
    }

    @MainActor
    @Test func clampAnchorsPreservesVisitedState() {
        let vm = BalloonViewModel()
        vm.text = "abcdef"
        vm.anchors = [BalloonAnchorRange(id: "a", references: [], text: "abc", range: NSRange(location: 0, length: 3), visited: true)]
        vm.truncateSuffixCharacters(2)
        #expect(vm.anchors.count == 1)
        #expect(vm.anchors[0].visited == true)
    }

    @MainActor
    @Test func configDefaultsApplyAnchorPenColors() {
        let vm = BalloonViewModel()
        let pen = NSColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let font = NSColor(red: 0.0, green: 0.0, blue: 1.0, alpha: 1)
        let notSelectFont = NSColor(red: 0.0, green: 1.0, blue: 0.0, alpha: 1)
        let notSelectPen = NSColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1)
        let visitedFont = NSColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1)
        let visitedPen = NSColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1)
        let config = BalloonConfig(
            name: "test", charset: "UTF-8", craftman: "", craftmanUrl: "",
            originX: 0, originY: 0, wordwrapPointX: 0, wordwrapPointY: 0,
            fontHeight: 12, fontColor: .black,
            anchorFontColor: font, anchorPenColor: pen,
            anchorStyle: .underline, anchorBrushColor: .clear,
            anchorNotSelectStyle: .square, anchorNotSelectFontColor: notSelectFont,
            anchorNotSelectPenColor: notSelectPen, anchorNotSelectBrushColor: .clear,
            anchorVisitedStyle: .squareUnderline, anchorVisitedFontColor: visitedFont,
            anchorVisitedPenColor: visitedPen, anchorVisitedBrushColor: .clear,
            anchorBlendMethod: .xorPen,
            anchorNotSelectBlendMethod: .xorPen,
            anchorVisitedBlendMethod: .xorPen,
            cursorBlendMethod: "", cursorStyle: "", cursorBrushColor: .clear, cursorPenColor: .clear, cursorFontColor: .clear,
            numberFontHeight: 10, numberFontColor: .black, numberXR: 0, numberY: 0,
            onlineMarkerX: 0, onlineMarkerY: 0, sstpMarkerX: 0, sstpMarkerY: 0,
            sstpMessageX: 0, sstpMessageY: 0, sstpMessageFontHeight: 10, sstpMessageFontColor: .black,
            arrow0X: 0, arrow0Y: 0, arrow1X: 0, arrow1Y: 0,
            validRectLeft: 0, validRectTop: 0, validRectRight: 0, validRectBottom: 0,
            maxWidth: 0, maxHeight: 0, marginX: 0, marginY: 0, wordwrapPointRight: 0,
            communicateBoxX: 0, communicateBoxY: 0, communicateBoxWidth: 0, communicateBoxHeight: 0
        )
        vm.applyBalloonConfigAnchorDefaults(config: config)
        #expect(vm.anchorPenColor == pen)
        #expect(vm.anchorStyle == .underline)
        #expect(vm.anchornotselectStyle == .square)
        #expect(vm.anchornotselectPenColor == notSelectPen)
        #expect(vm.anchorNotSelectFontColor == notSelectFont)
        #expect(vm.anchorvisitedStyle == .squareUnderline)
        #expect(vm.anchorvisitedPenColor == visitedPen)
        #expect(vm.anchorVisitedFontColor == visitedFont)
        #expect(vm.anchorFontColor == font)
        #expect(vm.anchorMethod == .xorPen)
        #expect(vm.anchornotselectMethod == .xorPen)
        #expect(vm.anchorvisitedMethod == .xorPen)
    }

    @Test func anchorRangeEquatableIncludesVisited() {
        let base = BalloonAnchorRange(id: "a", references: [], text: "x", range: NSRange(location: 0, length: 1))
        let visited = BalloonAnchorRange(id: "a", references: [], text: "x", range: NSRange(location: 0, length: 1), visited: true)
        #expect(base != visited)
    }
}

struct AnchorRasterOperationTests {
    @Test func parsesAllSetROP2Names() {
        let names = AnchorRasterOperation.allCases.map(\.rawValue)
        #expect(names.count == 17) // 16 SetROP2 operators + `none`.
        for name in names {
            #expect(AnchorRasterOperation(name: name) != nil)
            #expect(AnchorRasterOperation(name: "R2_\(name)") != nil)
        }
        #expect(AnchorRasterOperation(name: "default") == nil)
        #expect(AnchorRasterOperation(name: "unknown") == nil)
    }

    @Test func appliesSetROP2TruthTablePerChannel() {
        let source: UInt8 = 0x3c
        let destination: UInt8 = 0xa5
        let expected: [AnchorRasterOperation: UInt8] = [
            .none: 0xa5,
            .black: 0x00,
            .notMergePen: 0x42,
            .maskNotPen: 0x81,
            .notCopyPen: 0xc3,
            .maskPenNot: 0x18,
            .not: 0x5a,
            .xorPen: 0x99,
            .notMaskPen: 0xdb,
            .maskPen: 0x24,
            .notXorPen: 0x66,
            .nop: 0xa5,
            .mergeNotPen: 0xe7,
            .copyPen: 0x3c,
            .mergePenNot: 0x7e,
            .mergePen: 0xbd,
            .white: 0xff
        ]

        for operation in AnchorRasterOperation.allCases {
            #expect(operation.apply(source: source, destination: destination) == expected[operation])
        }
    }

    @MainActor
    @Test func rendererAppliesOperationToBalloonPixels() {
        var bytes = [UInt8](repeating: 0, count: 4 * 4 * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            bytes[index] = 0x10
            bytes[index + 1] = 0x20
            bytes[index + 2] = 0x30
            bytes[index + 3] = 0xff
        }
        let patch = AnchorRasterImageRenderer.renderPatch(
            surfacePixels: bytes,
            surfaceSize: CGSize(width: 4, height: 4),
            rect: CGRect(x: 1, y: 1, width: 2, height: 2),
            operation: .xorPen,
            brushColor: NSColor(red: 0xa0 / 255.0, green: 0xb0 / 255.0, blue: 0xc0 / 255.0, alpha: 1)
        )
        #expect(patch != nil)
        #expect(patch?.size == CGSize(width: 2, height: 2))

        guard let patch,
              let tiff = patch.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else {
            Issue.record("ROP2 patch could not be read back as a bitmap")
            return
        }
        var pixel = [Int](repeating: 0, count: 4)
        representation.getPixel(&pixel, atX: 0, y: 0)
        #expect(pixel[0] == 0xb0)
        #expect(pixel[1] == 0x90)
        #expect(pixel[2] == 0xf0)
        #expect(pixel[3] == 255)
    }

    @MainActor
    @Test func balloonViewLaysOutRasterAnchorDecoration() {
        let vm = BalloonViewModel()
        vm.text = "anchor"
        vm.fontSize = 16
        vm.anchorStyle = .square
        vm.anchorMethod = .xorPen
        vm.anchorBrushColor = NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        vm.anchorPenColor = .white
        vm.anchors = [BalloonAnchorRange(
            id: "anchor",
            references: [],
            text: "anchor",
            range: NSRange(location: 0, length: 6)
        )]

        let host = NSHostingView(rootView: BalloonView(viewModel: vm))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 150)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            Issue.record("BalloonView did not produce a display bitmap")
            window.orderOut(nil)
            return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0)
        #expect(bitmap.pixelsHigh > 0)
        window.orderOut(nil)
    }
}

@MainActor
struct FontCommandExecutionTests {
    private func apply(_ manager: GhostManager, _ args: [String]) {
        manager.sakuraEngine(manager.sakuraEngine, didEmit: .command(name: "f", args: args))
        manager.processNextUnit()
    }

    @Test func individualDefaultValuesRestoreBalloonStyles() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-font-defaults"))
        defer { _ = manager.shutdown() }
        let vm = manager.getBalloonVM(for: 0)

        apply(manager, ["name", "Helvetica"])
        apply(manager, ["name", "default"])
        #expect(vm.fontName.isEmpty)

        apply(manager, ["height", "20"])
        apply(manager, ["height", "default"])
        #expect(vm.fontSize == 12)

        apply(manager, ["color", "red"])
        apply(manager, ["color", "default"])
        #expect(vm.fontColor == .textColor)

        apply(manager, ["bold", "1"])
        apply(manager, ["bold", "default"])
        #expect(vm.fontWeight == .regular)

        apply(manager, ["italic", "1"])
        apply(manager, ["italic", "default"])
        #expect(!vm.fontItalic)

        apply(manager, ["strike", "1"])
        apply(manager, ["strike", "default"])
        #expect(!vm.fontStrike)

        apply(manager, ["underline", "1"])
        apply(manager, ["underline", "default"])
        #expect(!vm.fontUnderline)

        apply(manager, ["sub", "1"])
        apply(manager, ["sub", "default"])
        #expect(!vm.fontSubscript)

        apply(manager, ["sup", "1"])
        apply(manager, ["sup", "default"])
        #expect(!vm.fontSuperscript)

        apply(manager, ["shadowcolor", "#ff0000"])
        apply(manager, ["shadowcolor", "default"])
        #expect(vm.shadowColor == .clear)

        apply(manager, ["outline", "2"])
        #expect(vm.outlineWidth == 2)
        apply(manager, ["shadowstyle", "default"])
        #expect(vm.shadowStyle == .none)
        #expect(vm.outlineWidth == 0)
    }

    @Test func disabledTriStateUsesDisabledAppearance() {
        let manager = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-font-disable"))
        defer { _ = manager.shutdown() }
        let vm = manager.getBalloonVM(for: 0)

        apply(manager, ["bold", "disable"])
        apply(manager, ["italic", "disable"])
        apply(manager, ["strike", "disable"])
        apply(manager, ["underline", "disable"])
        #expect(vm.fontWeight == .regular)
        #expect(!vm.fontItalic)
        #expect(vm.fontStrike)
        #expect(!vm.fontUnderline)
    }
}
