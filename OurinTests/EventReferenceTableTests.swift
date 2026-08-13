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
        "prevGhostNameSSP", "nextGhostNameSSP"
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
