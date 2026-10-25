import AppKit
import Foundation
import Testing
@testable import Ourin

@MainActor
@Suite(.serialized)
struct DesktopWallpaperObserverTests {
    @Test
    func styleMapsNSWorkspaceOptionsToUkadocNames() {
        typealias O = DesktopWallpaperObserver
        #expect(O.style(scaling: nil, allowClipping: nil) == "fill")
        #expect(O.style(scaling: .scaleProportionallyUpOrDown, allowClipping: true) == "fill")
        #expect(O.style(scaling: .scaleProportionallyUpOrDown, allowClipping: false) == "fit")
        #expect(O.style(scaling: .scaleAxesIndependently, allowClipping: nil) == "stretch")
        #expect(O.style(scaling: .scaleNone, allowClipping: nil) == "center")
        #expect(O.colorString(NSColor(deviceRed: 1, green: 0.5, blue: 0, alpha: 1)) == "255,128,0")
        #expect(O.colorString(nil) == "0,0,0")
    }

    @Test
    func referencesListEveryMonitorAfterReference6() {
        let current = [
            WallpaperScreenState(path: "/a.jpg", style: "fill", color: "1,2,3"),
            WallpaperScreenState(path: "/b.jpg", style: "fit", color: "4,5,6")
        ]
        let previous = [WallpaperScreenState(path: "/old.jpg", style: "fill", color: "0,0,0")]
        let refs = DesktopWallpaperObserver.references(initial: false, cause: "self", current: current, previous: previous)
        #expect(refs["Reference0"] == "update")
        #expect(refs["Reference1"] == "self")
        #expect(refs["Reference2"] == "/a.jpg")
        #expect(refs["Reference3"] == "/old.jpg")
        #expect(refs["Reference4"] == "fill")
        #expect(refs["Reference5"] == "1,2,3")
        #expect(refs["Reference6"] == "0\u{1}/a.jpg\u{1}fill")
        #expect(refs["Reference7"] == "1\u{1}/b.jpg\u{1}fit")

        let initial = DesktopWallpaperObserver.references(initial: true, cause: "unknown", current: current, previous: nil)
        #expect(initial["Reference0"] == "init")
        #expect(initial["Reference3"] == "")
    }

    @Test
    func startSendsInitNotifyAndChangesSendUpdateGet() {
        let observer = DesktopWallpaperObserver()
        var state = [WallpaperScreenState(path: "/first.jpg", style: "fill", color: "0,0,0")]
        observer.readState = { state }
        var events: [ShioriEvent] = []
        observer.start { events.append($0) }
        defer { observer.stop() }

        #expect(events.count == 1)
        #expect(events[0].id == .OnDesktopWallpaperChange)
        #expect(events[0].delivery == .notify)
        #expect(events[0].params["Reference0"] == "init")

        // 変化が無ければ送らない。
        observer.check()
        #expect(events.count == 1)

        state = [WallpaperScreenState(path: "/second.jpg", style: "fit", color: "0,0,0")]
        observer.check()
        #expect(events.count == 2)
        #expect(events[1].delivery == .get)
        #expect(events[1].params["Reference0"] == "update")
        #expect(events[1].params["Reference1"] == "unknown")
        #expect(events[1].params["Reference2"] == "/second.jpg")
        #expect(events[1].params["Reference3"] == "/first.jpg")
    }

    @Test
    func changeRightAfterOurinSetsWallpaperIsSelf() {
        let observer = DesktopWallpaperObserver()
        var state = [WallpaperScreenState(path: "/first.jpg", style: "fill", color: "0,0,0")]
        observer.readState = { state }
        var events: [ShioriEvent] = []
        observer.start { events.append($0) }
        defer { observer.stop() }

        let now = Date()
        observer.noteSelfChange(at: now)
        state = [WallpaperScreenState(path: "/ghost.jpg", style: "fill", color: "0,0,0")]
        observer.check(now: now.addingTimeInterval(1))
        #expect(events.last?.params["Reference1"] == "self")

        // self の記録は1回で消費し、猶予を過ぎた変化は unknown。
        observer.noteSelfChange(at: now)
        state = [WallpaperScreenState(path: "/user.jpg", style: "fill", color: "0,0,0")]
        observer.check(now: now.addingTimeInterval(DesktopWallpaperObserver.selfChangeWindow + 5))
        #expect(events.last?.params["Reference1"] == "unknown")
    }
}
