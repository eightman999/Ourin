import Foundation

/// SHIORI イベントの Reference0..N カラム仕様（UKADOC list_shiori_event 準拠）。
///
/// 従来は各発火箇所で `["Reference0": ..., "Reference1": ...]` が個別ハードコード
/// されていた。このテーブルは、主要イベントの Reference 意味ラベル・メソッド種別・
/// 戻り値無視フラグを一元管理し、以下を可能にする:
/// - `ShioriDispatcher.notifyReturnIgnored` の単一ソース化
/// - DevTools でのイベント仕様表示
/// - 将来的な発火コードの表駆動化（漸次移行）
public struct EventReferenceSpec: Equatable {
    public let id: String
    /// Reference0, Reference1, ... に対応する意味ラベル（"shellName", "x", "y" 等）。
    /// 空配列は「Reference を持たない、または未定義」を意味する。
    public let references: [String]
    /// UKADOC「Notifyイベント（戻り値無視）」かどうか。
    public let notifyReturnIgnored: Bool
    /// イベント分類（"lifecycle", "mouse", "time", "network", "ui", "system" 等）。
    public let category: String

    public init(id: String, references: [String], notifyReturnIgnored: Bool = false, category: String = "general") {
        self.id = id
        self.references = references
        self.notifyReturnIgnored = notifyReturnIgnored
        self.category = category
    }
}

/// SHIORI イベント Reference 仕様テーブル。
///
/// 仕様原典: https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html
/// 各 spec の references 配列は、発火時に設定される Reference の意味を順に示す。
/// ただし一部値は実行時コンテキスト（マウス座標・起動時間等）に依存するため、
/// このテーブルは「ラベル」のみを提供し、値の生成は発火箇所が担う。
public enum EventReferenceTable {

    /// イベントID（"OnBoot", "basewareversion" 等）→ 仕様。
    public static let specs: [String: EventReferenceSpec] = {
        var dict: [String: EventReferenceSpec] = [:]
        for spec in allSpecs {
            dict[spec.id] = spec
        }
        return dict
    }()

    /// UKADOC「Notifyイベント（戻り値無視）」のイベントID集合。
    /// `ShioriDispatcher.notifyReturnIgnored` の単一ソース。
    public static let notifyReturnIgnoredIDs: Set<String> = Set(
        allSpecs.filter { $0.notifyReturnIgnored }.map { $0.id }
    )

    /// 全イベントの仕様リスト（定義順）。
    /// 新規イベントを追加する場合はこの配列に追記する。
    public static let allSpecs: [EventReferenceSpec] = [
        // MARK: - ライフサイクル
        .init(id: "OnFirstBoot", references: ["vanishCount"], category: "lifecycle"),
        .init(id: "OnBoot", references: ["shellName"], category: "lifecycle"),
        .init(id: "OnInitialize", references: [], category: "lifecycle"),
        .init(id: "OnClose", references: ["closeReason"], category: "lifecycle"),
        .init(id: "OnVanishing", references: [], category: "lifecycle"),
        .init(id: "OnVanished", references: [], category: "lifecycle"),
        .init(id: "OnVanishSelecting", references: [], category: "lifecycle"),
        .init(id: "OnVanishSelected", references: ["ghostName"], category: "lifecycle"),

        // MARK: - ゴースト切替
        .init(id: "OnGhostChanging", references: ["nextGhostName", "changeMode", "nextGhostNameSSP", "nextGhostPath"], category: "ghost"),
        .init(id: "OnGhostChanged", references: ["prevGhostName", "changeScript", "prevGhostNameSSP", "prevGhostPath"], category: "ghost"),
        .init(id: "OnOtherGhostBooted", references: ["ghostName", "sakuraName", "keroName", "shellName", "ghostPath"], category: "ghost"),
        .init(id: "OnOtherGhostChanged", references: ["prevGhostName", "nextGhostName"], category: "ghost"),
        .init(id: "OnOtherGhostClosed", references: ["ghostName"], category: "ghost"),

        // MARK: - 時刻系
        .init(id: "OnSecondChange", references: ["uptimeHours", "mikire", "kasanari", "canTalk", "idleSecondsSSP"], category: "time"),
        .init(id: "OnMinuteChange", references: ["uptimeHours", "mikire", "kasanari", "canTalk", "idleSecondsSSP"], category: "time"),
        .init(id: "OnHourTimeSignal", references: ["uptimeHours", "mikire", "kasanari", "canTalk", "idleSecondsSSP"], category: "time"),

        // MARK: - マウス
        .init(id: "OnMouseClick", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseClickEx", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseDoubleClick", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseDoubleClickEx", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseMultipleClick", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType", "clickCount"], category: "mouse"),
        .init(id: "OnMouseMultipleClickEx", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType", "clickCount"], category: "mouse"),
        .init(id: "OnMouseDown", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseUp", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseMove", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseWheel", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseEnter", references: ["x", "y", "wheelDelta", "scopeID", "collisionID"], category: "mouse"),
        .init(id: "OnMouseLeave", references: ["x", "y", "wheelDelta", "scopeID", "collisionID"], category: "mouse"),
        .init(id: "OnMouseDragStart", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseDragEnd", references: ["x", "y", "wheelDelta", "scopeID", "collisionID", "button", "deviceType"], category: "mouse"),
        .init(id: "OnMouseGesture", references: ["direction", "startPosition", "endPosition"], category: "mouse"),

        // MARK: - キー
        .init(id: "OnKeyDown", references: ["characters", "keyCode"], category: "key"),
        .init(id: "OnKeyUp", references: ["characters", "keyCode"], category: "key"),

        // MARK: - バルーン / 選択肢
        .init(id: "OnBalloonBreak", references: ["displayedScript", "scope", "breakPosition"], category: "ui"),
        .init(id: "OnBalloonClose", references: ["displayedScript"], category: "ui"),
        .init(id: "OnBalloonTimeout", references: ["scope"], category: "ui"),
        .init(id: "OnBalloonChange", references: ["prevBalloonName", "newBalloonName", "phase"], category: "ui"),
        .init(id: "OnChoiceEnter", references: ["label", "choiceID", "extInfo"], category: "ui"),
        .init(id: "OnChoiceSelect", references: ["choiceID"], category: "ui"),
        .init(id: "OnChoiceSelectEx", references: ["choiceID", "extInfo"], category: "ui"),
        .init(id: "OnAnchorSelect", references: ["anchorID"], category: "ui"),
        .init(id: "OnAnchorEnter", references: ["anchorID"], category: "ui"),

        // MARK: - シェル / サーフェス
        .init(id: "OnShellChanging", references: ["prevShellName", "newShellName"], category: "shell"),
        .init(id: "OnShellChanged", references: ["prevShellName", "newShellName"], category: "shell"),
        .init(id: "OnSurfaceChange", references: ["sakuraSurface", "keroSurface", "changedScope"], category: "shell"),
        .init(id: "OnSurfaceRestore", references: ["sakuraSurface", "keroSurface"], category: "shell"),
        .init(id: "OnSurfacesReloaded", references: ["shellName"], category: "shell"),
        .init(id: "OnDressupChanged", references: ["category", "part", "value"], category: "shell"),
        .init(id: "OnAnimationFinished", references: ["animationID"], category: "shell"),

        // MARK: - D&D
        .init(id: "OnFileDrop", references: ["filePath"], category: "dragdrop"),
        .init(id: "OnFileDrop2", references: ["filePath", "x", "y"], category: "dragdrop"),
        .init(id: "OnDirectoryDrop", references: ["dirPath"], category: "dragdrop"),
        .init(id: "OnURLDrop", references: ["url"], category: "dragdrop"),
        .init(id: "OnURLDropping", references: ["url"], category: "dragdrop"),
        .init(id: "OnURLDropped", references: ["url"], category: "dragdrop"),
        .init(id: "OnTextDrop", references: ["text"], category: "dragdrop"),

        // MARK: - HTTP / WebSocket
        .init(id: "OnExecuteHTTPComplete", references: ["statusCode", "body", "url", "method"], category: "network"),
        .init(id: "OnExecuteHTTPProgress", references: ["phase", "progress", "method", "url"], category: "network"),
        .init(id: "OnExecuteHTTPFailure", references: ["reason", "url", "method"], category: "network"),
        .init(id: "OnExecuteHTTPSSLInfo", references: ["host", "url"], category: "network"),
        .init(id: "OnExecuteHTTPStreaming", references: ["body", "url", "statusCode", "method"], category: "network"),
        .init(id: "OnExecuteWebSocketOpen", references: ["url"], category: "network"),
        .init(id: "OnExecuteWebSocketReceive", references: ["payload", "url", "dataType"], category: "network"),
        .init(id: "OnExecuteWebSocketSend", references: ["payload", "url", "dataType"], category: "network"),
        .init(id: "OnExecuteWebSocketState", references: ["state", "url"], category: "network"),
        .init(id: "OnExecuteWebSocketError", references: ["reason", "url"], category: "network"),
        .init(id: "OnExecuteWebSocketClose", references: ["url"], category: "network"),

        // MARK: - メディア
        .init(id: "OnMusicPlay", references: ["filename"], category: "media"),
        .init(id: "OnMusicPlayEx", references: ["filename"], category: "media"),
        .init(id: "OnMusicStop", references: ["filename"], category: "media"),
        .init(id: "OnSoundLoop", references: ["filename"], category: "media"),
        .init(id: "OnSoundStop", references: ["filename"], category: "media"),
        .init(id: "OnVideoPlayEx", references: ["filename", "loopMode"], category: "media"),

        // MARK: - アップデート / NAR
        .init(id: "OnUpdateResult", references: ["reason", "fileList", "target"], category: "update"),
        .init(id: "OnUpdateResultEx", references: ["reason", "fileList", "target", "explorerPath"], category: "update"),
        .init(id: "OnUpdateResultExplorer", references: ["explorerPath", "target"], category: "update"),
        .init(id: "OnNarCreating", references: ["name"], category: "update"),
        .init(id: "OnNarCreated", references: ["filePath"], category: "update"),
        .init(id: "OnInstall", references: [], category: "update"),
        .init(id: "OnInstallComplete", references: ["type", "name", "path"], category: "update"),

        // MARK: - 通信 / SNTP / BIFF / Headline
        .init(id: "OnSNTPComplete", references: [], category: "network"),
        .init(id: "OnSNTPFailure", references: ["reason"], category: "network"),
        .init(id: "OnHeadlineCheck", references: ["headline", "url"], category: "network"),
        .init(id: "OnBIFF", references: ["state"], category: "network"),

        // MARK: - ウィンドウ / トレイ
        .init(id: "OnWindowStateMinimize", references: ["windowID"], category: "ui"),
        .init(id: "OnWindowStateRestore", references: ["windowID"], category: "ui"),
        .init(id: "OnTrayBalloonClick", references: ["identifier", "title", "message"], category: "ui"),
        .init(id: "OnSecurityWarning", references: ["source", "detail", "url"], category: "system"),

        // MARK: - SSTP
        .init(id: "OnSSTPBlacklisting", references: ["ipAddress", "securityOrigin"], category: "sstp"),
        .init(id: "OnSSTPBreak", references: ["script", "scope"], category: "sstp"),
        .init(id: "OnCommunicate", references: ["sender", "sentence"], category: "sstp"),

        // MARK: - AI トーク
        .init(id: "OnAITalk", references: [], category: "talk"),

        // MARK: - UKADOC「Notifyイベント（戻り値無視）」
        // 小文字の SHIORI/3.0 Request ID 群
        .init(id: "basewareversion", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "hwnd", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "uniqueid", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "capability", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "ownerghostname", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "otherghostname", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "installedsakuraname", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "installedkeroname", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "installedghostname", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "installedshellname", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "installedballoonname", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "installedheadlinename", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "installedplugin", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "configuredbiffname", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "ghostpathlist", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "balloonpathlist", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "headlinepathlist", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "pluginpathlist", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "calendarskinpathlist", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "calendarpluginpathlist", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "rateofusegraph", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "enable_log", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "enable_debug", references: [], notifyReturnIgnored: true, category: "system"),
        // OnNotify* 群
        .init(id: "OnNotifySelfInfo", references: ["ghostName", "sakuraName", "keroName", "shellName", "shellPath", "balloonName", "balloonPath"], notifyReturnIgnored: true, category: "system"),
        .init(id: "OnNotifyBalloonInfo", references: ["balloonName", "balloonPath"], notifyReturnIgnored: true, category: "system"),
        .init(id: "OnNotifyShellInfo", references: ["shellName", "shellPath"], notifyReturnIgnored: true, category: "system"),
        .init(id: "OnNotifyDressupInfo", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "OnNotifyUserInfo", references: ["userName"], notifyReturnIgnored: true, category: "system"),
        .init(id: "OnNotifyOSInfo", references: ["osInfo"], notifyReturnIgnored: true, category: "system"),
        .init(id: "OnNotifyFontInfo", references: [], notifyReturnIgnored: true, category: "system"),
        .init(id: "OnNotifyInternationalInfo", references: [], notifyReturnIgnored: true, category: "system"),

        // MARK: - 発火箇所の表駆動移行で追加（2026-06）
        // 全 ~216 発火箇所の table 駆動化に伴い、発火されている全イベントを網羅。
        // ラベルは UKADOC list_shiori_event(_ex)/list_plugin_event の Reference 意味 +
        // 実コードが各 ReferenceN に格納する値で検証済み（移行は ReferenceN とバイト等価）。
        .init(id: "OnAnchorHover", references: ["text"], category: "ui"),
        .init(id: "OnAnchorSelectEx", references: [], category: "ui"),
        .init(id: "OnArchiveFailure", references: ["operation", "reason"], category: "update"),
        .init(id: "OnBasewareUpdated", references: ["version"], category: "update"),
        .init(id: "OnBasewareUpdating", references: ["version"], category: "update"),
        .init(id: "OnClipboardClear", references: [], category: "system"),
        .init(id: "OnClipboardRead", references: ["text"], category: "system"),
        .init(id: "OnClipboardWrite", references: ["text"], category: "system"),
        .init(id: "OnCompressArchiveBegin", references: ["source", "outputPath"], category: "update"),
        .init(id: "OnCompressArchiveFailure", references: ["eventID"], category: "update"),
        .init(id: "OnCreateShortcutComplete", references: ["linkPath"], category: "system"),
        .init(id: "OnCreateShortcutFailure", references: ["reason"], category: "system"),
        .init(id: "OnCreateUpdateDataComplete", references: ["filePath"], category: "update"),
        .init(id: "OnCreateUpdateDataFailure", references: ["reason"], category: "update"),
        .init(id: "OnDescriptReloaded", references: ["target", "params"], category: "system"),
        .init(id: "OnDumpSurfaceComplete", references: ["outputPath"], category: "shell"),
        .init(id: "OnDumpSurfaceFailure", references: ["reason"], category: "shell"),
        .init(id: "OnEmptyRecycleBinComplete", references: ["count"], category: "system"),
        .init(id: "OnEmptyRecycleBinFailure", references: ["reason"], category: "system"),
        .init(id: "OnExecuteRSSComplete", references: ["title", "url", "method"], category: "network"),
        .init(id: "OnExecuteRSSFailure", references: ["reason", "url", "method"], category: "network"),
        .init(id: "OnExecuteRSS_SSLInfo", references: ["host", "url"], category: "network"),
        .init(id: "OnExtractArchiveBegin", references: ["archivePath", "destPath"], category: "update"),
        .init(id: "OnExtractArchiveFailure", references: ["eventID"], category: "update"),
        .init(id: "OnGhostCallComplete", references: ["ghostName"], category: "ghost"),
        .init(id: "OnGhostCalled", references: ["ghostName"], category: "ghost"),
        .init(id: "OnGhostCalling", references: ["ghostName"], category: "ghost"),
        .init(id: "OnGhostTermsAccept", references: ["ghostName"], category: "ghost"),
        .init(id: "OnGhostTermsDecline", references: ["ghostName"], category: "ghost"),
        .init(id: "OnHeadlineCheckFailure", references: ["reason"], category: "network"),
        .init(id: "OnInductionModeBegin", references: [], category: "ui"),
        .init(id: "OnInductionModeEnd", references: [], category: "ui"),
        .init(id: "OnInstallBegin", references: [], category: "update"),
        .init(id: "OnInstallFailure", references: ["reason"], category: "update"),
        .init(id: "OnNameChanged", references: ["userName"], category: "ghost"),
        .init(id: "OnNoUserBreakModeBegin", references: [], category: "ui"),
        .init(id: "OnNoUserBreakModeEnd", references: [], category: "ui"),
        .init(id: "OnOtherGhostVanished", references: ["ghostName"], category: "ghost"),
        .init(id: "OnPassiveModeBegin", references: [], category: "ui"),
        .init(id: "OnPassiveModeEnd", references: [], category: "ui"),
        .init(id: "OnPingComplete", references: ["host", "output"], category: "network"),
        .init(id: "OnPingFailure", references: ["host", "output"], category: "network"),
        .init(id: "OnPingProgress", references: ["host", "progress", "result"], category: "network"),
        .init(id: "OnSNTP", references: ["dateTime", "timezone"], category: "network"),
        .init(id: "OnSNTPAdjust", references: ["deltaMs", "dateTime", "timezone"], category: "network"),
        .init(id: "OnSNTPBegin", references: [], category: "network"),
        .init(id: "OnSNTPCompare", references: ["dateTime", "timezone"], category: "network"),
        .init(id: "OnSSPCompatExecutable", references: ["kind", "rawPath", "path", "dataPath"], category: "system"),
        .init(id: "OnSelectModeBegin", references: [], category: "ui"),
        .init(id: "OnSelectModeCancel", references: [], category: "ui"),
        .init(id: "OnSelectModeComplete", references: [], category: "ui"),
        .init(id: "OnSerikoTalkChanged", references: ["enabled"], category: "shell"),
        .init(id: "OnShioriDebugModeChanged", references: ["enabled"], category: "system"),
        .init(id: "OnShioriLoadFailure", references: ["reason"], category: "system"),
        .init(id: "OnShioriLoaded", references: ["name", "entryCount"], category: "system"),
        .init(id: "OnShioriUnloaded", references: ["name"], category: "system"),
        .init(id: "OnSurfaceReloaded", references: ["surfaceID"], category: "shell"),
        .init(id: "OnSystemMessage", references: ["title", "body", "level"], category: "system"),
        .init(id: "OnTrayBalloonTimeout", references: ["identifier", "title"], category: "ui"),
        .init(id: "OnURLDropFailure", references: ["filePath"], category: "dragdrop"),
        .init(id: "OnURLQuery", references: ["url"], category: "dragdrop"),
        .init(id: "OnUpdateBegin", references: ["ghostName", "path", "extra2", "type"], category: "update"),
        .init(id: "OnUpdateCheckComplete", references: ["reason", "fileList", "count", "type"], category: "update"),
        .init(id: "OnUpdateCheckFailure", references: ["reason"], category: "update"),
        .init(id: "OnUpdateComplete", references: ["reason", "fileList", "count", "type"], category: "update"),
        .init(id: "OnUpdateFailure", references: ["reason", "fileList", "extra2", "type"], category: "update"),
        .init(id: "OnUpdateOtherBegin", references: ["ghostName", "path", "extra2", "type"], category: "update"),
        .init(id: "OnUpdateOtherComplete", references: ["reason", "fileList", "extra2", "type"], category: "update"),
        .init(id: "OnUpdateOtherReady", references: ["fileIndex", "fileList", "extra2", "type"], category: "update"),
        .init(id: "OnUpdateReady", references: ["fileIndex", "fileList", "extra2", "type"], category: "update"),
        .init(id: "OnUpdatedataCreated", references: ["path"], category: "update"),
        .init(id: "OnUpdatedataCreating", references: ["filePath"], category: "update"),
        .init(id: "OnVanishButtonHold", references: [], category: "lifecycle"),
        .init(id: "OnVanishCancel", references: [], category: "lifecycle"),
        .init(id: "OnXUkagakaLinkOpen", references: ["info"], category: "general"),

        // MARK: - オブザーバ発火イベント（ShioriEvent 経由）
        .init(id: "OnNSLookupComplete", references: ["host", "output"], category: "network"),
        .init(id: "OnNSLookupFailure", references: ["host", "output"], category: "network"),
        .init(id: "OnDeviceArrival", references: ["path"], category: "system"),
        .init(id: "OnDeviceRemove", references: ["path"], category: "system"),
        .init(id: "OnURLDragDropping", references: ["url"], category: "dragdrop"),
        .init(id: "OnGamepadConnected", references: ["deviceName"], category: "input"),
        .init(id: "OnGamepadDisconnected", references: ["deviceName"], category: "input"),
        .init(id: "OnGamepadButtonDown", references: ["button", "deviceName"], category: "input"),
        .init(id: "OnGamepadButtonUp", references: ["button", "deviceName"], category: "input"),
        .init(id: "OnGamepadAxisMove", references: ["axis", "x", "y", "deviceName"], category: "input"),
        .init(id: "OnSpeechSynthesisStatus", references: ["status"], category: "system"),
        .init(id: "OnVoiceRecognitionStatus", references: ["status"], category: "system"),
    ]

    // MARK: - 表駆動発火 API の中核（ラベル ⇄ ReferenceN 変換）

    /// 意味ラベル辞書（例: `["x": "10", "y": "20", "button": "0"]`）を、
    /// SHIORI リクエスト用の `ReferenceN` 辞書（例: `["Reference0": "10", "Reference1": "20", "Reference5": "0"]`）へ変換する。
    ///
    /// ラベル → 添字の写像は `specs[id].references` 内の位置（`firstIndex`）で行う。
    /// 各発火箇所が従来書いていた `["ReferenceN": v]` と**バイト等価**になるよう、
    /// ラベルは `references[N]` の完全な逆写像である（`references` 配列内のラベルは
    /// イベント毎に一意であることが前提。`duplicateLabelEvents` で検証可能）。
    ///
    /// - Note: `"ReferenceN"` 形式のキーはそのまま透過する（可変長参照などの特殊ケース用）。
    ///   テーブル未定義のラベルは DEBUG ビルドで `assertionFailure`、リリースでは生ヘッダとして保持し挙動を壊さない。
    public static func params(forEvent id: String, refs: [String: String]) -> [String: String] {
        guard !refs.isEmpty else { return [:] }
        let spec = specs[id]
        #if DEBUG
        if spec == nil {
            assertionFailure("EventReferenceTable: イベント \(id) の spec が無いのに refs が指定されました: \(Array(refs.keys))")
        }
        #endif
        var out: [String: String] = [:]
        out.reserveCapacity(refs.count)
        for (label, value) in refs {
            if let spec, let idx = spec.references.firstIndex(of: label) {
                out["Reference\(idx)"] = value
            } else if label.hasPrefix("Reference") {
                out[label] = value
            } else {
                #if DEBUG
                assertionFailure("EventReferenceTable: イベント \(id) に未知の参照ラベル '\(label)'。references=\(spec?.references ?? [])")
                #endif
                out[label] = value
            }
        }
        return out
    }

    /// イベントの添字 `index` に対応する意味ラベルを返す（DevTools / 移行ツール用）。範囲外は nil。
    public static func label(forEvent id: String, index: Int) -> String? {
        guard let spec = specs[id], index >= 0, index < spec.references.count else { return nil }
        return spec.references[index]
    }

    /// `references` 配列内に重複ラベルを持つイベント ID の一覧（DEBUG 自己検査用）。
    /// 表駆動発火の逆写像が一意に定まることを保証するため、テストで空であることを検証する。
    public static var duplicateLabelEvents: [String] {
        allSpecs.compactMap { spec in
            Set(spec.references).count == spec.references.count ? nil : spec.id
        }
    }
}
