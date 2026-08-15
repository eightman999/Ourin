import Foundation
import Testing
@testable import Ourin

/// EventReferenceTable の回帰テスト。
///
/// `ShioriDispatcher.notifyReturnIgnored` が EventReferenceTable から派生するため、
/// 従来のハードコードセット（EventBridge.swift にあった38件）と完全一致することを検証する。
/// 1件でも欠けると、従来動いていたイベントの戻り値スクリプト処理が壊れる。

@Test
func eventReferenceTableNotifyReturnIgnoredMatchesLegacySet() {
    // 従来 EventBridge.swift にハードコードされていた UKADOC Notifyイベント（戻り値無視）セット。
    // 仕様原典: https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html
    let legacy: Set<String> = [
        "basewareversion", "hwnd", "uniqueid", "capability",
        "ownerghostname", "otherghostname",
        "installedsakuraname", "installedkeroname", "installedghostname",
        "installedshellname", "installedballoonname", "installedheadlinename",
        "installedplugin", "configuredbiffname",
        "ghostpathlist", "balloonpathlist", "headlinepathlist", "pluginpathlist",
        "calendarskinpathlist", "calendarpluginpathlist",
        "rateofusegraph", "enable_log", "enable_debug",
        "OnNotifySelfInfo", "OnNotifyBalloonInfo", "OnNotifyShellInfo",
        "OnNotifyDressupInfo", "OnNotifyUserInfo", "OnNotifyOSInfo",
        "OnNotifyFontInfo", "OnNotifyInternationalInfo",
        "OnLanguageChange",
    ]
    #expect(EventReferenceTable.notifyReturnIgnoredIDs == legacy)
}

@Test
func eventReferenceTableHasNoDuplicateIDs() {
    let ids = EventReferenceTable.allSpecs.map { $0.id }
    #expect(ids.count == Set(ids).count, "duplicate event IDs in EventReferenceTable.allSpecs")
}

@Test
func eventReferenceTableSpecsKeyedByID() {
    for spec in EventReferenceTable.allSpecs {
        let entry = EventReferenceTable.specs[spec.id]
        #expect(entry != nil, "missing specs entry for \(spec.id)")
        #expect(entry?.id == spec.id)
    }
}

@Test
func eventReferenceTableCoversMajorLifecycleEvents() {
    // 主要ライフサイクルイベントの Reference 定義が存在すること。
    let boot = EventReferenceTable.specs["OnBoot"]
    #expect(boot?.references.first == "shellName")

    let close = EventReferenceTable.specs["OnClose"]
    #expect(close?.references.first == "closeReason")

    let firstBoot = EventReferenceTable.specs["OnFirstBoot"]
    #expect(firstBoot?.references.first == "vanishCount")
}

@Test
func onBootReferencesIncludeCrashRecoveryOnlyWhenNeeded() {
    #expect(GhostManager.onBootReferences(shellName: "Classic", recovery: nil) == ["Classic"])

    let recovery = GhostBootRecovery(previousGhostName: "Emily")
    let references = GhostManager.onBootReferences(shellName: "Classic", recovery: recovery)
    #expect(references.count == 8)
    #expect(references[0] == "Classic")
    #expect(Array(references[1...5]) == ["", "", "", "", ""])
    #expect(references[6] == "halt")
    #expect(references[7] == "Emily")
}

@Test
func bootRecoveryMarkerDistinguishesCleanAndAbnormalSessions() {
    let suiteName = "OurinTests.BootRecovery.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(BootRecoveryMarker.beginSession(defaults: defaults) == nil)
    BootRecoveryMarker.recordActiveGhost(name: " Emily ", defaults: defaults)
    #expect(BootRecoveryMarker.beginSession(defaults: defaults) == GhostBootRecovery(previousGhostName: "Emily"))

    BootRecoveryMarker.clearSession(defaults: defaults)
    #expect(BootRecoveryMarker.beginSession(defaults: defaults) == nil)
}

@Test
func eventReferenceTableVanishLifecycleReferencesMatchUkadoc() {
    #expect(EventReferenceTable.specs["OnVanishSelecting"]?.references == [])
    #expect(EventReferenceTable.specs["OnVanishSelected"]?.references == [])
    #expect(EventReferenceTable.specs["OnVanishCancel"]?.references == [])
    #expect(EventReferenceTable.specs["OnVanishButtonHold"]?.references == [
        "displayedScript", "scope", "breakPosition"
    ])
    #expect(EventReferenceTable.specs["OnVanished"]?.references == [
        "ghostName", "vanishSelectedScript", "vanishedGhostName",
        "unused3", "unused4", "unused5", "unused6", "shellName"
    ])
    #expect(EventReferenceTable.specs["OnOtherGhostClosed"]?.references == [
        "ghostName", "lastScript", "closedGhostName",
        "unused3", "unused4", "unused5", "unused6", "shellName"
    ])
    #expect(EventReferenceTable.specs["OnOtherGhostVanished"]?.references == [
        "ghostName", "vanishSelectedScript", "vanishedGhostName",
        "unused3", "unused4", "unused5", "unused6", "shellName"
    ])
}

@Test
func eventReferenceTableVanishLifecyclePreservesSparseReferenceSeven() {
    let params = EventReferenceTable.params(forEvent: "OnVanished", refs: [
        "ghostName": "Sakura",
        "vanishSelectedScript": #"\0goodbye\e"#,
        "vanishedGhostName": "Emily",
        "shellName": "master"
    ])

    #expect(params == [
        "Reference0": "Sakura",
        "Reference1": #"\0goodbye\e"#,
        "Reference2": "Emily",
        "Reference7": "master"
    ])
}

@Test
func eventReferenceTableBalloonTimeoutReferencesMatchUkadoc() {
    #expect(EventReferenceTable.specs["OnBalloonTimeout"]?.references == [
        "displayedScript", "remainingTime"
    ])
}

@Test
func eventReferenceTableShellScalingReferencesMatchUkadoc() {
    #expect(EventReferenceTable.specs["OnShellScaling"]?.references == [
        "afterX", "beforeX", "afterY", "beforeY"
    ])
}

@Test
func eventReferenceTableBalloonScalingReferencesMatchUkadoc() {
    #expect(EventReferenceTable.specs["OnBalloonScaling"]?.references == [
        "afterX", "beforeX", "afterY", "beforeY"
    ])
}

@Test
func eventReferenceTableMouseEventReferencesMatchUkadoc() {
    // UKADOC: OnMouseClick R0=x R1=y R2=ホイール回転量 R3=キャラクターID
    //         R4=当たり判定識別子 R5=ボタン R6=デバイス種別
    let click = EventReferenceTable.specs["OnMouseClick"]
    #expect(click?.references == ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"])

    // OnMouseMultipleClick は R7=連続クリック回数を追加
    let multi = EventReferenceTable.specs["OnMouseMultipleClick"]
    #expect(multi?.references.count == 8)
    #expect(multi?.references.last == "clickCount")
}

@Test
func inputMonitorMouseReferencesRoundTripThroughEventReferenceTable() {
    let rawClick = [
        "Reference0": "10",
        "Reference1": "20",
        "Reference2": "0",
        "Reference3": "1",
        "Reference4": "Head",
        "Reference5": "0",
        "Reference6": "mouse"
    ]
    let clickRefs = InputMonitor.semanticMouseReferences(from: rawClick, includeButton: true)
    #expect(EventReferenceTable.params(forEvent: "OnMouseClick", refs: clickRefs) == rawClick)

    let rawMove = [
        "Reference0": "30",
        "Reference1": "40",
        "Reference2": "0",
        "Reference3": "0",
        "Reference4": "",
        "Reference6": "mouse"
    ]
    let moveRefs = InputMonitor.semanticMouseReferences(from: rawMove, includeButton: false)
    #expect(EventReferenceTable.params(forEvent: "OnMouseMove", refs: moveRefs) == rawMove)
}

@Test
func inputMonitorPointerAndSelectionReferencesRoundTripThroughEventReferenceTable() {
    let rawPointer = [
        "Reference0": "11",
        "Reference1": "22",
        "Reference2": "0",
        "Reference3": "1",
        "Reference4": "Head",
        "Reference6": "mouse"
    ]
    let pointerRefs = InputMonitor.pointerEventReferences(from: rawPointer)
    for eventID in ["OnMouseEnter", "OnMouseEnterAll", "OnMouseLeave", "OnMouseLeaveAll", "OnMouseHover"] {
        #expect(EventReferenceTable.params(forEvent: eventID, refs: pointerRefs) == rawPointer, "mismatch for \(eventID)")
    }

    let selectionRefs = [
        "scopeID": "2",
        "mode": "rect",
        "position": "100,200"
    ]
    let expectedSelection = [
        "Reference0": "2",
        "Reference1": "rect",
        "Reference2": "100,200"
    ]
    #expect(EventReferenceTable.params(forEvent: "OnSelectModeMouseDown", refs: selectionRefs) == expectedSelection)
    #expect(EventReferenceTable.params(forEvent: "OnSelectModeMouseUp", refs: selectionRefs) == expectedSelection)
}

@Test
func eventReferenceTableChoiceAndAnchorReferencesMatchUkadoc() {
    #expect(EventReferenceTable.specs["OnChoiceSelectEx"]?.references == [
        "label", "choiceID", "extInfo"
    ])
    #expect(EventReferenceTable.specs["OnAnchorEnter"]?.references == [
        "label", "anchorID", "extInfo"
    ])
    #expect(EventReferenceTable.specs["OnAnchorHover"]?.references == [
        "label", "anchorID", "extInfo"
    ])
    #expect(EventReferenceTable.specs["OnAnchorSelectEx"]?.references == [
        "label", "anchorID", "extInfo"
    ])
    #expect(EventReferenceTable.specs["OnChoiceTimeout"]?.references == [
        "timedOutScript"
    ])
}

@Test
func eventReferenceTableArchiveReferencesMatchUkadoc() {
    let complete = ["eventID", "fileCount", "compressedSize", "uncompressedSize"]
    let failure = ["eventID", "error"]
    for id in ["OnExtractArchiveComplete", "OnCompressArchiveComplete"] {
        #expect(EventReferenceTable.specs[id]?.references == complete, "mismatch for \(id)")
    }
    for id in ["OnExtractArchiveFailure", "OnCompressArchiveFailure"] {
        #expect(EventReferenceTable.specs[id]?.references == failure, "mismatch for \(id)")
    }
}

@Test
func eventReferenceTableCoversEmittedFailureAndWallpaperEvents() {
    #expect(EventReferenceTable.params(forEvent: "OnReadmeOpenFailure", refs: [
        "type": "ghost", "name": "readme.txt", "path": "/tmp/readme.txt"
    ]) == [
        "Reference0": "ghost", "Reference1": "readme.txt", "Reference2": "/tmp/readme.txt"
    ])
    #expect(EventReferenceTable.params(forEvent: "OnVanishFailure", refs: [
        "ghostName": "Emily", "reason": "permission_denied"
    ]) == [
        "Reference0": "Emily", "Reference1": "permission_denied"
    ])
    #expect(EventReferenceTable.params(forEvent: "OnWallpaperChange", refs: [
        "filePath": "/tmp/wallpaper.png"
    ]) == ["Reference0": "/tmp/wallpaper.png"])
    #expect(EventReferenceTable.params(forEvent: "OnWallpaperFailure", refs: [
        "filename": "wallpaper.png", "reason": "file_not_found"
    ]) == [
        "Reference0": "wallpaper.png", "Reference1": "file_not_found"
    ])
}

@Test
func eventReferenceTablePluginAndOtherFailureReferencesMatchUkadoc() {
    #expect(EventReferenceTable.specs["OnRaisePluginFailure"]?.references == [
        "reason", "plugin", "event"
    ])
    #expect(EventReferenceTable.specs["OnNotifyPluginFailure"]?.references == [
        "reason", "plugin", "event"
    ])
    #expect(EventReferenceTable.specs["OnRaiseOtherFailure"]?.references == [
        "reason", "ghostName", "event"
    ])
    #expect(EventReferenceTable.specs["OnNotifyOtherFailure"]?.references == [
        "reason", "ghostName", "event"
    ])

    #expect(EventReferenceTable.params(forEvent: "OnRaisePluginFailure", refs: [
        "reason": "notfound",
        "plugin": "missing-plugin",
        "event": "OnPluginTest",
        "Reference3": "alpha",
        "Reference4": "beta"
    ]) == [
        "Reference0": "notfound",
        "Reference1": "missing-plugin",
        "Reference2": "OnPluginTest",
        "Reference3": "alpha",
        "Reference4": "beta"
    ])
}

@Test
func eventReferenceTableTimeEventReferences() {
    // OnSecondChange/OnMinuteChange/OnHourTimeSignal は共通 R0..R4
    let refs = ["uptimeHours", "mikire", "kasanari", "canTalk", "idleSecondsSSP"]
    for id in ["OnSecondChange", "OnMinuteChange", "OnHourTimeSignal"] {
        #expect(EventReferenceTable.specs[id]?.references == refs, "mismatch for \(id)")
    }
}

@Test
func eventReferenceTableGhostChangedReferences() {
    // UKADOC: OnGhostChanged R0=直前ゴースト名 R1=切替時スクリプト,
    // R2/R3=SSP拡張, R7=切替先シェル名。
    let changed = EventReferenceTable.specs["OnGhostChanged"]
    #expect(changed?.references == [
        "prevGhostName", "changeScript", "prevGhostNameSSP", "prevGhostPath",
        "unused4", "unused5", "unused6", "shellName"
    ])
}

@Test
func eventReferenceTableGhostLifecycleReferencesMatchUkadoc() {
    #expect(EventReferenceTable.specs["OnGhostChanging"]?.references == [
        "nextGhostName", "changeMode", "nextGhostNameSSP", "nextGhostPath"
    ])
    #expect(EventReferenceTable.specs["OnGhostCalling"]?.references == [
        "nextGhostName", "changeMode", "nextGhostNameSSP", "nextGhostPath"
    ])
    #expect(EventReferenceTable.specs["OnGhostCalled"]?.references == [
        "callingGhostName", "callScript", "callingGhostNameSSP", "callingGhostPath",
        "unused4", "unused5", "unused6", "calledShellName"
    ])
    #expect(EventReferenceTable.specs["OnGhostCallComplete"]?.references == [
        "calledGhostMainName", "calledBootScript", "calledGhostNameSSP",
        "unused3", "unused4", "unused5", "unused6", "calledShellName"
    ])
    #expect(EventReferenceTable.specs["OnOtherGhostBooted"]?.references == [
        "ghostName", "bootScript", "ghostNameSSP", "unused3", "unused4", "unused5", "unused6", "shellName"
    ])
    #expect(EventReferenceTable.specs["OnOtherGhostChanged"]?.references == [
        "prevGhostName", "nextGhostName", "prevChangeScript", "nextChangeScript",
        "prevGhostNameSSP", "nextGhostNameSSP",
        "unused6", "unused7", "unused8", "unused9", "unused10", "unused11", "unused12", "unused13",
        "prevShellName", "nextShellName"
    ])
}

@Test
func eventReferenceTablePreservesOtherGhostChangedShellReferences() {
    #expect(EventReferenceTable.params(forEvent: "OnOtherGhostChanged", refs: [
        "prevGhostName": "old",
        "nextGhostName": "new",
        "prevShellName": "old-shell",
        "nextShellName": "new-shell"
    ]) == [
        "Reference0": "old",
        "Reference1": "new",
        "Reference14": "old-shell",
        "Reference15": "new-shell"
    ])
}

@Test
func eventReferenceTableSSTPBreakIncludesPosition() {
    #expect(EventReferenceTable.specs["OnSSTPBreak"]?.references == [
        "script", "scope", "breakPosition"
    ])
    #expect(EventReferenceTable.params(forEvent: "OnSSTPBreak", refs: [
        "script": "\\0hello\\e",
        "scope": "1",
        "breakPosition": "0"
    ]) == [
        "Reference0": "\\0hello\\e",
        "Reference1": "1",
        "Reference2": "0"
    ])
}

@Test
func eventReferenceTablePreservesSparseGhostReferenceSeven() {
    #expect(EventReferenceTable.params(forEvent: "OnOtherGhostBooted", refs: [
        "ghostName": "target",
        "shellName": "master"
    ]) == [
        "Reference0": "target",
        "Reference7": "master"
    ])
    #expect(EventReferenceTable.params(forEvent: "OnGhostCalled", refs: [
        "callingGhostName": "caller",
        "calledShellName": "master"
    ]) == [
        "Reference0": "caller",
        "Reference7": "master"
    ])
}

@Test
func eventReferenceTableHttpCompleteReferences() {
    let complete = EventReferenceTable.specs["OnExecuteHTTPComplete"]
    #expect(complete?.references == ["method", "asyncID", "url", "data", "result", "cookie", "responseHeaders"])
}

@Test
func eventReferenceTableNotifySelfInfoReferences() {
    // OnNotifySelfInfo は戻り値無視 + R0..R6
    let selfInfo = EventReferenceTable.specs["OnNotifySelfInfo"]
    #expect(selfInfo?.notifyReturnIgnored == true)
    #expect(selfInfo?.references.count == 7)
    #expect(selfInfo?.references.first == "ghostName")
    #expect(selfInfo?.references.last == "balloonPath")
}

@Test
func eventReferenceTableSystemNotifyReferencesMatchUkadoc() {
    #expect(EventReferenceTable.specs["OnNotifyUserInfo"]?.references == [
        "addressName", "fullName", "birthday", "gender"
    ])
    #expect(EventReferenceTable.specs["OnNotifyOSInfo"]?.references == [
        "osInfo", "cpuInfo", "memoryInfo", "uptimeMinutes"
    ])
    #expect(EventReferenceTable.specs["OnNotifyFontInfo"]?.references == ["fontName"])
    #expect(EventReferenceTable.specs["OnNotifyInternationalInfo"]?.references == [
        "utcOffsetMinutes", "daylightSavingTime", "countryCode", "languageCode"
    ])

    #expect(EventReferenceTable.specs["OnLanguageChange"]?.references == [
        "languageName", "languageID", "resourcePath", "helpURL"
    ])
    #expect(EventReferenceTable.notifyReturnIgnoredIDs.contains("OnLanguageChange"))
}

// MARK: - 表駆動発火 API（意味ラベル方式）の不変条件

/// すべての spec の references ラベルがイベント内で一意であること。
/// これが破れると `params(forEvent:refs:)` の ラベル→ReferenceN 逆写像が一意に定まらず、
/// 発火コードのバイト等価性が保証できなくなる。
@Test
func eventReferenceTableHasNoDuplicateLabelsPerEvent() {
    #expect(EventReferenceTable.duplicateLabelEvents.isEmpty,
            "events with duplicate reference labels: \(EventReferenceTable.duplicateLabelEvents)")
}

/// `params(forEvent:refs:)` が index→label の完全な逆写像であること。
/// 全 spec の全ラベルについて、ラベル単体を渡すと `Reference<その添字>` が得られることを検証する。
/// これにより「`["ReferenceN": v]` を `[label: v]` に置換する移行」がバイト等価であることが保証される。
@Test
func eventReferenceTableParamsIsExactInverseOfIndex() {
    for spec in EventReferenceTable.allSpecs {
        for (idx, label) in spec.references.enumerated() {
            let out = EventReferenceTable.params(forEvent: spec.id, refs: [label: "VALUE"])
            #expect(out == ["Reference\(idx)": "VALUE"],
                    "\(spec.id) label '\(label)' (index \(idx)) -> \(out)")
        }
    }
}

/// 複数ラベルをまとめて渡しても正しい ReferenceN 辞書になること（マウスイベントで代表検証）。
@Test
func eventReferenceTableParamsMapsMultipleLabels() {
    let out = EventReferenceTable.params(forEvent: "OnMouseClick",
                                         refs: ["x": "10", "y": "20", "button": "0"])
    #expect(out == ["Reference0": "10", "Reference1": "20", "Reference5": "0"])
}

/// `"ReferenceN"` 形式のキーは透過する（可変長参照などの後方互換）。
@Test
func eventReferenceTableParamsPassesThroughReferenceKeys() {
    let out = EventReferenceTable.params(forEvent: "OnFileDrop", refs: ["Reference0": "a", "Reference1": "b"])
    #expect(out == ["Reference0": "a", "Reference1": "b"])
}

/// 移行で表に追加した代表イベントのラベル定義（UKADOC + 実コード値で検証済み）。
@Test
func eventReferenceTableMigrationAddedEvents() {
    #expect(EventReferenceTable.specs["OnExecuteHTTPStreaming"]?.references == ["method", "asyncID", "url", "data", "body", "cookie", "responseHeaders"])
    #expect(EventReferenceTable.specs["OnPingProgress"]?.references == ["host", "progress", "result"])
    #expect(EventReferenceTable.specs["OnSurfaceChange"]?.references == ["sakuraSurface", "keroSurface", "changedScope"])
    #expect(EventReferenceTable.specs["OnOtherSurfaceChange"]?.references == ["ghostName", "sakuraName", "scopeID", "newSurfaceID", "oldSurfaceID", "newSurfaceSize"])
    #expect(EventReferenceTable.specs["OnGamepadAxisMove"]?.references == ["axis", "x", "y", "deviceName"])
    #expect(EventReferenceTable.specs["OnUpdateComplete"]?.references == [
        "reason", "fileList", "unused2", "targetType", "executionReason"
    ])
    #expect(EventReferenceTable.specs["OnUpdateProcessExec"]?.references == ["executionReason"])
    #expect(EventReferenceTable.specs["OnUpdate.OnDownloadBegin"]?.references == [
        "filename", "fileIndex", "fileCountMinusOne", "targetType", "executionReason"
    ])
    #expect(EventReferenceTable.specs["OnUpdate.OnMD5CompareComplete"]?.references == [
        "filename", "correctMD5", "downloadedMD5", "targetType", "executionReason"
    ])
    #expect(EventReferenceTable.specs["OnUpdateOther.OnMD5CompareFailure"]?.references == [
        "unused0", "correctMD5", "downloadedMD5", "targetType", "executionReason"
    ])
    #expect(EventReferenceTable.params(forEvent: "OnUpdate.OnDownloadBegin", refs: [
        "filename": "ghost/master/dic.dic",
        "fileIndex": "0",
        "fileCountMinusOne": "2",
        "targetType": "ghost",
        "executionReason": "manual"
    ]) == [
        "Reference0": "ghost/master/dic.dic",
        "Reference1": "0",
        "Reference2": "2",
        "Reference3": "ghost",
        "Reference4": "manual"
    ])
    #expect(EventReferenceTable.specs["OnInstallComplete"]?.references == [
        "identifier", "name", "name2"
    ])
    #expect(EventReferenceTable.specs["OnInstallCompleteEx"]?.references == [
        "identifiers", "names", "paths"
    ])
}

/// DisplayObserver の固定フィールドと可変長モニタ情報を同じ表定義で検証する。
@Test
func displayChangeReferencesUseSemanticStateAndPreserveDynamicDisplays() {
    #expect(EventReferenceTable.params(forEvent: "OnDisplayChange", refs: [
        "bpp": "32",
        "width": "2560",
        "height": "1440"
    ]) == [
        "Reference0": "32",
        "Reference1": "2560",
        "Reference2": "1440"
    ])

    #expect(EventReferenceTable.params(forEvent: "OnDisplayChangeEx", refs: [
        "state": "update",
        "Reference1": "0,0,2560,1440,32,1",
        "Reference2": "2560,0,5120,1440,32,0"
    ]) == [
        "Reference0": "update",
        "Reference1": "0,0,2560,1440,32,1",
        "Reference2": "2560,0,5120,1440,32,0"
    ])
}

/// 複合更新は対象順に複数 Reference を持つ1つの結果イベントへ変換する。
@Test
func compositeUpdateResultPayloadPreservesTargetOrder() {
    let records = [
        UpdateResultRecord(target: "ghost", targetName: "Emily", reason: "changed", fileList: "master/dic.dic", failedFile: nil),
        UpdateResultRecord(target: "shell", targetName: "Classic", reason: "none", fileList: "", failedFile: nil),
        UpdateResultRecord(target: "balloon", targetName: "Soft", reason: "network", fileList: "", failedFile: "descriptor.txt")
    ]

    let payload = GhostManager.updateResultEventPayload(records: records)
    #expect(payload.basic.keys.sorted() == ["Reference0", "Reference1", "Reference2"])
    #expect(payload.basic["Reference0"] == "ghost\u{1}OK\u{1}1")
    #expect(payload.basic["Reference1"] == "shell\u{1}OK\u{1}0")
    #expect(payload.basic["Reference2"] == "balloon\u{1}NG\u{1}network\u{1}descriptor.txt")
    #expect(payload.extended["Reference0"] == "Emily\u{1}ghost\u{1}OK\u{1}1")
    #expect(payload.extended["Reference1"] == "Classic\u{1}shell\u{1}OK\u{1}0")
    #expect(payload.extended["Reference2"] == "Soft\u{1}balloon\u{1}NG\u{1}network\u{1}descriptor.txt")
}
