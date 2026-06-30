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
func eventReferenceTableTimeEventReferences() {
    // OnSecondChange/OnMinuteChange/OnHourTimeSignal は共通 R0..R4
    let refs = ["uptimeHours", "mikire", "kasanari", "canTalk", "idleSecondsSSP"]
    for id in ["OnSecondChange", "OnMinuteChange", "OnHourTimeSignal"] {
        #expect(EventReferenceTable.specs[id]?.references == refs, "mismatch for \(id)")
    }
}

@Test
func eventReferenceTableGhostChangedReferences() {
    // UKADOC: OnGhostChanged R0=直前ゴースト名 R1=切替時スクリプト R2/R3=SSP拡張
    let changed = EventReferenceTable.specs["OnGhostChanged"]
    #expect(changed?.references == ["prevGhostName", "changeScript", "prevGhostNameSSP", "prevGhostPath"])
}

@Test
func eventReferenceTableHttpCompleteReferences() {
    let complete = EventReferenceTable.specs["OnExecuteHTTPComplete"]
    #expect(complete?.references == ["statusCode", "body", "url", "method"])
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
