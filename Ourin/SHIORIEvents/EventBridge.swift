// EventBridge.swift
// SHIORI イベントをまとめて受け取り、SHIORI モジュールへ配送する
import AppKit
import UniformTypeIdentifiers

/// SHIORI へ送るイベントのセキュリティ文脈。
/// システム由来の内部イベントは `.local`、外部SSTP等に由来する場合は `.external(origin:)`。
/// SHIORI 側が `SecurityLevel` / `SecurityOrigin` で発生源を判別できるようにする（UKADOC）。
struct ShioriSecurityContext: Equatable {
    /// "local" または "external"
    let level: String
    /// SecurityOrigin（URL等）。無い場合は nil。
    let origin: String?

    /// 内部システムイベント既定（ローカル）
    static let local = ShioriSecurityContext(level: "local", origin: nil)

    /// 外部由来（必要なら origin を付与）
    static func external(origin: String? = nil) -> ShioriSecurityContext {
        ShioriSecurityContext(level: "external", origin: origin)
    }

    /// SHIORI リクエストヘッダへ差し込む辞書を返す（Charset/Sender 込み）
    func shioriHeaders() -> [String: String] {
        var h: [String: String] = ["Charset": "UTF-8", "Sender": "Ourin", "SecurityLevel": level]
        if let origin, !origin.isEmpty { h["SecurityOrigin"] = origin }
        return h
    }
}

final class EventBridge {
    static let shared = EventBridge()
    private init() {}

    private var started = false
    private var autoEventsEnabled = false

    // Queue for NOTIFY events that occur when autoEvents are disabled
    private enum QueuedNotify {
        case standard(id: EventID, params: [String: String], security: ShioriSecurityContext)
        case custom(eventName: String, params: [String: String], ignoreResponseScript: Bool, security: ShioriSecurityContext)
    }
    private var pendingNotifies: [QueuedNotify] = []

    private struct Session {
        let dispatcher: ShioriDispatcher
        weak var ghostManager: GhostManager?
    }
    private var sessions: [UUID: Session] = [:]
    private let defaults = UserDefaults.standard

    // MARK: - 開始・終了

    /// すべてのオブザーバを開始する
    /// - Parameter enableAutoEvents: 自動システムイベントを有効にするかどうか（デフォルト: false）
    ///
    /// デフォルトでは、\![raise,イベント名]のような明示的なスクリプトコマンドによるイベントのみが発火します。
    /// enableAutoEvents = true にすると、以下の自動イベントも有効になります：
    /// - タイマー（OnSecondChange等）
    /// - 入力監視（マウス/キーボード）
    /// - スリープ/復帰
    /// - ディスプレイ変更
    /// - 電源状態変更
    /// - その他のシステムイベント
    func start(enableAutoEvents: Bool = false) {
        guard !started else {
            // Already started - check if we need to enable auto events
            if enableAutoEvents && !autoEventsEnabled {
                setAutoEventsEnabled(true)
            }
            return
        }
        started = true
        autoEventsEnabled = enableAutoEvents
        let forward: (ShioriEvent) -> Void = { [weak self] ev in self?.broadcastNotify(id: ev.id, params: ev.params) }

        // All system events are now optional - only enable if explicitly requested
        // This allows ghosts to work purely with script-triggered events (\![raise,...])
        if enableAutoEvents {
            TimerEmitter.shared.start(forward)
            InputMonitor.shared.start(handler: forward)
            SystemLoadObserver.shared.start(forward)
            SleepObserver.shared.start(forward)
            DisplayObserver.shared.start(forward)
            SpaceObserver.shared.start(forward)
            PowerObserver.shared.start(forward)
            LocaleObserver.shared.start(forward)
            AppearanceObserver.shared.start(forward)
            SessionObserver.shared.start(forward)
            NetworkObserver.shared.start(forward)
            GamepadObserver.shared.start(forward)
            DeviceObserver.shared.start(forward)
            SpeechObserver.shared.start(forward)

            // Flush any queued NOTIFY events that occurred while auto events were disabled
            flushPendingNotifies()
        }
        // Boot GET events are initiated in each GhostManager instance.
    }

    /// すべてのオブザーバを停止する
    func stop() {
        TimerEmitter.shared.stop()
        SleepObserver.shared.stop()
        InputMonitor.shared.stop()
        DisplayObserver.shared.stop()
        SpaceObserver.shared.stop()
        PowerObserver.shared.stop()
        LocaleObserver.shared.stop()
        AppearanceObserver.shared.stop()
        SessionObserver.shared.stop()
        NetworkObserver.shared.stop()
        SystemLoadObserver.shared.stop()
        GamepadObserver.shared.stop()
        DeviceObserver.shared.stop()
        SpeechObserver.shared.stop()
        started = false
        autoEventsEnabled = false
        // OnClose は GhostManager.beginCloseSequence が GET で送出し応答スクリプトを再生する
        // （ここで送ると二重送信になるため送らない）
    }

    /// Enable or disable auto events dynamically
    /// - Parameter enabled: Whether to enable auto events
    private func setAutoEventsEnabled(_ enabled: Bool) {
        guard started else { return }
        guard enabled != autoEventsEnabled else { return }

        autoEventsEnabled = enabled
        let forward: (ShioriEvent) -> Void = { [weak self] ev in self?.broadcastNotify(id: ev.id, params: ev.params) }

        if enabled {
            // Start all system observers
            TimerEmitter.shared.start(forward)
            InputMonitor.shared.start(handler: forward)
            SystemLoadObserver.shared.start(forward)
            SleepObserver.shared.start(forward)
            DisplayObserver.shared.start(forward)
            SpaceObserver.shared.start(forward)
            PowerObserver.shared.start(forward)
            LocaleObserver.shared.start(forward)
            AppearanceObserver.shared.start(forward)
            SessionObserver.shared.start(forward)
            NetworkObserver.shared.start(forward)
            GamepadObserver.shared.start(forward)
            DeviceObserver.shared.start(forward)
            SpeechObserver.shared.start(forward)

            // Flush any queued NOTIFY events
            flushPendingNotifies()
        } else {
            // Stop all system observers
            TimerEmitter.shared.stop()
            SleepObserver.shared.stop()
            InputMonitor.shared.stop()
            DisplayObserver.shared.stop()
            SpaceObserver.shared.stop()
            PowerObserver.shared.stop()
            LocaleObserver.shared.stop()
            AppearanceObserver.shared.stop()
            SessionObserver.shared.stop()
            NetworkObserver.shared.stop()
            SystemLoadObserver.shared.stop()
            GamepadObserver.shared.stop()
            DeviceObserver.shared.stop()
            SpeechObserver.shared.stop()
        }
    }

    /// Flush all pending NOTIFY events that were queued while auto events were disabled
    private func flushPendingNotifies() {
        guard !pendingNotifies.isEmpty else { return }

        Log.debug("[EventBridge] Flushing \(pendingNotifies.count) queued NOTIFY events")
        for queued in pendingNotifies {
            switch queued {
            case .standard(let id, let params, let security):
                broadcastNotifyImmediate(id: id, params: params, security: security)
            case .custom(let eventName, let params, let ignoreResponseScript, let security):
                broadcastNotifyCustomImmediate(eventName: eventName, params: params, ignoreResponseScript: ignoreResponseScript, security: security)
            }
        }
        pendingNotifies.removeAll()
    }

    /// Register a ghost session to receive NOTIFY broadcasts.
    func register(runtime: GhostShioriRuntime?, ghostManager: GhostManager) -> UUID {
        let d = ShioriDispatcher(); d.useRuntime(runtime); d.ghostManager = ghostManager
        let key = UUID()
        sessions[key] = Session(dispatcher: d, ghostManager: ghostManager)
        return key
    }

    /// 既存呼び出し元との互換用。新規コードは register(runtime:ghostManager:) を使う。
    func register(adapter: YayaAdapter?, ghostManager: GhostManager) -> UUID {
        register(runtime: adapter, ghostManager: ghostManager)
    }

    /// Unregister a previously registered session.
    func unregister(_ token: UUID) {
        sessions.removeValue(forKey: token)
    }

    /// Public helper to send a NOTIFY event by ID
    /// - Parameter security: 発生源のセキュリティ文脈（既定: 内部システム = local）
    func notify(_ id: EventID, params: [String:String] = [:], security: ShioriSecurityContext = .local) {
        broadcastNotify(id: id, params: params, security: security)
    }

    /// 表駆動発火（推奨）: 意味ラベル辞書でイベントを送出する。
    /// 例: `notify(.OnMouseClick, refs: ["x": px, "y": py, "button": btn])`。
    /// ラベル → `ReferenceN` 変換は `EventReferenceTable`（SHIORIEvents/EventReferenceSpec.swift）が担う。
    func notify(_ id: EventID, refs: [String:String], security: ShioriSecurityContext = .local) {
        broadcastNotify(id: id, params: EventReferenceTable.params(forEvent: id.rawValue, refs: refs), security: security)
    }

    /// 外部SSTP（SEND の Script ヘッダ等）から、登録済みゴーストのバルーンでスクリプトを再生する。
    /// - Parameters:
    ///   - script: 再生する SakuraScript
    ///   - ghostName: ReceiverGhostName 指定。nil なら全セッションへ送る
    /// - Returns: 再生先セッションが1つでもあれば true
    @discardableResult
    func playScriptOnGhosts(_ script: String, ghostName: String? = nil) -> Bool {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return playScriptOnGhostsResolving(ghostName: ghostName) { _ in trimmed }
    }

    /// ゴースト毎に異なるスクリプトを再生する（SSTP の IfGhost 振り分け用）。
    /// resolve はセッションのゴースト名（descript.txt の name、不明時 nil）を受け取り
    /// 再生するスクリプトを返す。nil または空を返したセッションでは再生しない。
    /// - Parameter notify: true の場合は `runScript` ではなく `runNotifyScript` を使う。
    ///   NOTIFY 由来のスクリプト（ValueNotify）は可視テキストを含まないとき現バルーンを保持する。
    @discardableResult
    func playScriptOnGhostsResolving(ghostName: String? = nil, notify: Bool = false, resolve: (String?) -> String?) -> Bool {
        var targets = sessions.values.compactMap { $0.ghostManager }
        if let name = ghostName?.lowercased(), !name.isEmpty {
            targets = targets.filter {
                ($0.ghostConfig?.name.lowercased() == name) || ($0.ghostURL.lastPathComponent.lowercased() == name)
            }
        }
        var jobs: [(GhostManager, String)] = []
        for gm in targets {
            let resolved = resolve(gm.ghostConfig?.name)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let script = resolved, !script.isEmpty {
                jobs.append((gm, script))
            }
        }
        guard !jobs.isEmpty else { return false }
        DispatchQueue.main.async {
            for (gm, script) in jobs {
                if notify { gm.runNotifyScript(script) } else { gm.runScript(script) }
            }
        }
        return true
    }

    /// Public helper to send a NOTIFY event by custom name (for \![raise,...])
    /// - Parameter security: 発生源のセキュリティ文脈（既定: 内部 = local）
    func notifyCustom(_ eventName: String, params: [String:String] = [:], ignoreResponseScript: Bool = false, security: ShioriSecurityContext = .local) {
        broadcastNotifyCustom(eventName: eventName, params: params, ignoreResponseScript: ignoreResponseScript, security: security)
    }

    /// 表駆動発火（推奨）: 意味ラベル辞書でカスタム名イベント（EventID 列挙に無いもの）を送出する。
    /// 例: `notifyCustom("OnExecuteRSSFailure", refs: ["reason": msg, "url": u, "method": m])`。
    func notifyCustom(_ eventName: String, refs: [String:String], ignoreResponseScript: Bool = false, security: ShioriSecurityContext = .local) {
        broadcastNotifyCustom(eventName: eventName, params: EventReferenceTable.params(forEvent: eventName, refs: refs), ignoreResponseScript: ignoreResponseScript, security: security)
    }

    /// PLUGIN/2.0 `Event` 応答をゴーストへ橋渡しする。
    /// `EventOption: notify` の場合は NOTIFY、未指定なら GET として送り、ゴーストが返したスクリプトを再生する。
    @discardableResult
    func dispatchPluginResponseEvent(
        _ eventName: String,
        params: [String:String] = [:],
        notifyOnly: Bool = false,
        target: String? = nil,
        caller: GhostManager? = nil,
        scriptOptions: Set<String> = [],
        security: ShioriSecurityContext = .local
    ) -> Bool {
        let resolved = resolvePluginTarget(target, caller: caller)
        switch resolved {
        case .unresolved:
            return false
        case .baseware:
            return true
        case .ghosts(let targetSessions):
            var eventParams = params
            if scriptOptions.contains("notranslate") {
                eventParams["NoTranslate"] = "1"
            }
            if notifyOnly {
                for session in targetSessions {
                    session.dispatcher.sendNotifyCustom(
                        eventName: eventName,
                        params: eventParams,
                        ignoreResponseScript: true,
                        security: security
                    )
                }
                return !targetSessions.isEmpty
            }
            var producedScript = false
            for session in targetSessions {
                let script = session.dispatcher.sendGetCustom(eventName: eventName, params: eventParams, security: security)
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    producedScript = true
                    let gm = session.ghostManager
                    DispatchQueue.main.async {
                        gm?.runPluginScript(trimmed, options: scriptOptions.union(["plugin-event"]))
                    }
                }
            }
            return producedScript
        }
    }

    @discardableResult
    func runPluginResponseScript(_ action: PluginTransportAction, caller: GhostManager? = nil) -> Bool {
        guard let script = action.script?.trimmingCharacters(in: .whitespacesAndNewlines), !script.isEmpty else {
            return false
        }
        switch resolvePluginTarget(action.target, caller: caller) {
        case .unresolved:
            return false
        case .baseware:
            return true
        case .ghosts(let targetSessions):
            guard !targetSessions.isEmpty else { return false }
            DispatchQueue.main.async {
                for session in targetSessions {
                    session.ghostManager?.runPluginScript(script, options: action.scriptOptions.union(["plugin-script"]))
                }
            }
            return true
        }
    }

    func canResolvePluginTarget(_ target: String?, caller: GhostManager? = nil) -> Bool {
        switch resolvePluginTarget(target, caller: caller) {
        case .unresolved:
            return false
        case .baseware:
            return true
        case .ghosts(let targetSessions):
            return !targetSessions.isEmpty
        }
    }

    private enum PluginResolvedTarget {
        case ghosts([Session])
        case baseware
        case unresolved
    }

    private func resolvePluginTarget(_ target: String?, caller: GhostManager?) -> PluginResolvedTarget {
        let token = target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = token.lowercased()
        if normalized == "baseware" || normalized == "ourin" {
            return .baseware
        }
        if normalized == "__system_all_ghost__" || normalized == "system_all_ghost" || normalized == "all" {
            return .ghosts(Array(sessions.values))
        }
        if normalized.isEmpty || normalized == "self" || normalized == "ghost" || normalized == "any" || normalized == "systemany" {
            if let caller, let session = session(for: caller) {
                return .ghosts([session])
            }
            if let active = activeGhostManager(), let session = session(for: active) {
                return .ghosts([session])
            }
            if let first = sessions.values.first {
                return .ghosts([first])
            }
            return .unresolved
        }

        let matches = sessions.values.filter { session in
            guard let gm = session.ghostManager else { return false }
            return gm.matchesPluginTarget(token)
        }
        return matches.isEmpty ? .unresolved : .ghosts(matches)
    }

    private func activeGhostManager() -> GhostManager? {
        if let app = NSApp.delegate as? AppDelegate, let gm = app.ghostManager {
            return gm
        }
        return sessions.values.first?.ghostManager
    }

    private func session(for ghostManager: GhostManager) -> Session? {
        sessions.values.first { $0.ghostManager === ghostManager }
    }

    // Broadcast a NOTIFY to all registered sessions
    // If auto events are disabled, queue the event for later delivery
    private func broadcastNotify(id: EventID, params: [String:String], security: ShioriSecurityContext = .local) {
        if !autoEventsEnabled {
            // Queue this event for later when auto events are enabled
            pendingNotifies.append(.standard(id: id, params: params, security: security))
            Log.debug("[EventBridge] Queued NOTIFY event: \(id.rawValue) (auto events disabled)")
            return
        }
        broadcastNotifyImmediate(id: id, params: params, security: security)
    }

    // Broadcast a custom NOTIFY to all registered sessions
    // If auto events are disabled, queue the event for later delivery
    private func broadcastNotifyCustom(eventName: String, params: [String:String], ignoreResponseScript: Bool, security: ShioriSecurityContext = .local) {
        if !autoEventsEnabled {
            // Queue this event for later when auto events are enabled
            pendingNotifies.append(.custom(eventName: eventName, params: params, ignoreResponseScript: ignoreResponseScript, security: security))
            Log.debug("[EventBridge] Queued custom NOTIFY event: \(eventName) (auto events disabled)")
            return
        }
        broadcastNotifyCustomImmediate(eventName: eventName, params: params, ignoreResponseScript: ignoreResponseScript, security: security)
    }

    // 時刻系イベント: Reference3（トーク再生可否）に応じて GET / NOTIFY を切り替える（UKADOC）
    private static let timeSignalEvents: Set<EventID> = [.OnSecondChange, .OnMinuteChange, .OnHourTimeSignal]

    // ユーザー操作で会話を返しうるイベントは GET で問い合わせる。
    private static let mouseTalkEvents: Set<EventID> = [
        .OnMouseClick, .OnMouseClickEx, .OnMouseDoubleClick, .OnMouseDoubleClickEx,
        .OnMouseMultipleClick, .OnMouseMultipleClickEx
    ]

    // \t タイムクリティカルセクション中に通知を抑止するマウス系イベント（UKADOC: \t）
    private static let mouseEvents: Set<EventID> = [
        .OnMouseClick, .OnMouseClickEx, .OnMouseDoubleClick, .OnMouseDoubleClickEx,
        .OnMouseMultipleClick, .OnMouseMultipleClickEx,
        .OnMouseDown, .OnMouseDownEx, .OnMouseUp, .OnMouseUpEx,
        .OnMouseMove, .OnMouseWheel, .OnMouseEnter, .OnMouseEnterAll,
        .OnMouseLeave, .OnMouseLeaveAll, .OnMouseHover,
        .OnMouseDragStart, .OnMouseDragEnd, .OnMouseGesture
    ]

    // OnOtherOffscreen / OnOtherOverlap の遷移検出用の直前状態（全ゴースト横断、UKADOC Reference1）。
    // nil = 未サンプル（初回 tick はベースライン確立のみでイベント発火しない）
    private var lastOtherOffscreenRef0: String?
    private var lastOtherOverlapRef0: String?

    // Immediately broadcast a NOTIFY to all registered sessions (bypassing queue)
    private func broadcastNotifyImmediate(id: EventID, params: [String:String], security: ShioriSecurityContext = .local) {
        // Save character names on OnNotifySelfInfo
        if id == .OnNotifySelfInfo {
            let sakuraName = params["Reference0"] ?? params["Reference1"] ?? ""
            let keroName = params["Reference2"]
            for (_, s) in sessions {
                s.ghostManager?.saveCharacterNames(sakuraName: sakuraName, keroName: keroName)
            }
        }

        if Self.timeSignalEvents.contains(id) {
            for (_, s) in sessions {
                var p = params
                let cantalk = s.ghostManager?.canPlayTalkNow() ?? false
                p["Reference3"] = cantalk ? "1" : "0"
                // 見切れ/重なりはセッション毎のキャラウィンドウから判定する（UKADOC Reference1/Reference2）
                if let gm = s.ghostManager {
                    p["Reference1"] = gm.mikireScopes()
                    p["Reference2"] = gm.kasanariScopes()
                }
                if cantalk {
                    // 再生可能: GET で送り、返値スクリプトを再生する（ランダムトークの基本動線）
                    let script = s.dispatcher.sendGet(id: id, params: p, security: security)
                    let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        let gm = s.ghostManager
                        DispatchQueue.main.async { gm?.runScript(trimmed) }
                    }
                } else {
                    // 再生不能: NOTIFY で送り、返値は無視する
                    s.dispatcher.sendNotify(id: id, params: p, ignoreResponseScript: true, security: security)
                }
            }
            // 見切れ / 重なりの状態遷移検出（毎秒 1 回 = OnSecondChange のみ。
            // OnMinuteChange 等と同時発火する分秒境界での二重チェックを避ける）
            if id == .OnSecondChange {
                dispatchOverlapTransitions(security: security)
            }
            return
        }

        for (_, s) in sessions {
            // \t タイムクリティカルセクション中はマウス系イベントを通知しない（UKADOC）
            if Self.mouseEvents.contains(id), s.ghostManager?.timeCriticalActive == true {
                continue
            }
            if Self.mouseTalkEvents.contains(id) {
                let script = s.dispatcher.sendGet(id: id, params: params, security: security)
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let gm = s.ghostManager
                    DispatchQueue.main.async { gm?.runScript(trimmed) }
                }
                continue
            }
            s.dispatcher.sendNotify(id: id, params: params, security: security)
        }
    }

    /// OnOffscreen / OnOverlap（自ゴースト）と OnOtherOffscreen / OnOtherOverlap（全ゴースト横断）の
    /// 状態遷移を検出して GET で通知し、応答スクリプトを再生する（UKADOC: 4イベントとも GET、
    /// Reference0=現在状態 / Reference1=直前状態、区切りはバイト値1）。
    private func dispatchOverlapTransitions(security: ShioriSecurityContext) {
        // 自ゴースト分: セッション毎に遷移検出（計算は既存の見切れ/重なり判定基盤を流用）
        for (_, s) in sessions {
            guard let gm = s.ghostManager else { continue }
            for ev in gm.overlapTransitionEvents() {
                let script = s.dispatcher.sendGet(id: ev.id, params: ev.params, security: security)
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    DispatchQueue.main.async { gm.runScript(trimmed) }
                }
            }
        }

        // 全ゴースト横断分（"Sakura名/ID" 表記、自分自身の情報も含む）
        var labeled: [(label: String, frame: CGRect, screenVisible: CGRect)] = []
        for (_, s) in sessions {
            guard let gm = s.ghostManager else { continue }
            let name = gm.ghostConfig?.name ?? gm.ghostURL.lastPathComponent
            for f in gm.characterFrameList() {
                labeled.append(("\(name)/\(f.scope)", f.frame, f.screenVisible))
            }
        }
        let otherOffscreen = labeled.filter { !$0.screenVisible.contains($0.frame) }
            .map { $0.label }
            .sorted()
            .joined(separator: "\u{01}")
        var otherPairs: [String] = []
        for i in 0..<labeled.count {
            for j in (i + 1)..<labeled.count where labeled[i].frame.intersects(labeled[j].frame) {
                let a = min(labeled[i].label, labeled[j].label)
                let b = max(labeled[i].label, labeled[j].label)
                otherPairs.append("\(a)-\(b)")
            }
        }
        let otherOverlap = otherPairs.sorted().joined(separator: "\u{01}")

        var otherEvents: [(id: EventID, params: [String: String])] = []
        if let prev = lastOtherOffscreenRef0, prev != otherOffscreen {
            otherEvents.append((.OnOtherOffscreen, ["Reference0": otherOffscreen, "Reference1": prev]))
        }
        lastOtherOffscreenRef0 = otherOffscreen
        if let prev = lastOtherOverlapRef0, prev != otherOverlap {
            otherEvents.append((.OnOtherOverlap, ["Reference0": otherOverlap, "Reference1": prev]))
        }
        lastOtherOverlapRef0 = otherOverlap

        guard !otherEvents.isEmpty else { return }
        for (_, s) in sessions {
            guard let gm = s.ghostManager else { continue }
            for ev in otherEvents {
                let script = s.dispatcher.sendGet(id: ev.id, params: ev.params, security: security)
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    DispatchQueue.main.async { gm.runScript(trimmed) }
                }
            }
        }
    }

    // Immediately broadcast a custom NOTIFY to all registered sessions (bypassing queue)
    private func broadcastNotifyCustomImmediate(eventName: String, params: [String:String], ignoreResponseScript: Bool, security: ShioriSecurityContext = .local) {
        for (_, s) in sessions {
            s.dispatcher.sendNotifyCustom(eventName: eventName, params: params, ignoreResponseScript: ignoreResponseScript, security: security)
        }
    }

    // Immediately broadcast a custom GET and play any returned script.
    @discardableResult
    private func broadcastGetCustomImmediate(eventName: String, params: [String:String], security: ShioriSecurityContext = .local) -> Bool {
        var producedScript = false
        for (_, s) in sessions {
            let script = s.dispatcher.sendGetCustom(eventName: eventName, params: params, security: security)
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                producedScript = true
                let gm = s.ghostManager
                DispatchQueue.main.async { gm?.runScript(trimmed) }
            }
        }
        return producedScript
    }
}

/// 個別の SHIORI イベントを表す構造体
struct ShioriEvent {
    /// イベント識別子
    let id: EventID
    /// パラメータ辞書（ReferenceN に相当）
    let params: [String:String]
}

extension ShioriEvent {
    /// 表駆動コンストラクタ（推奨）: 意味ラベル辞書から `params` を生成する。
    /// 例: `ShioriEvent(id: .OnMouseClick, refs: ["x": px, "y": py])`。
    /// ラベル → `ReferenceN` 変換は `EventReferenceTable` が担う。
    init(id: EventID, refs: [String:String]) {
        self.init(id: id, params: EventReferenceTable.params(forEvent: id.rawValue, refs: refs))
    }
}

final class ShioriDispatcher {
    // NOTIFY-only events whose return value (script) must be ignored per UKADOC
    // https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html (Notifyイベント)
    // 仕様定義は EventReferenceTable（SHIORIEvents/EventReferenceSpec.swift）に一元化。
    private static let notifyReturnIgnored: Set<String> = EventReferenceTable.notifyReturnIgnoredIDs
    private var shioriRuntime: GhostShioriRuntime?
    weak var ghostManager: GhostManager?
    func useRuntime(_ runtime: GhostShioriRuntime?) { self.shioriRuntime = runtime }

    /// 既存コードとの互換用。新規コードは useRuntime(_:) を使う。
    func useYaya(_ adapter: YayaAdapter?) { self.shioriRuntime = adapter }
    /// イベント ID とパラメータからリクエスト文字列を組み立てる
    private func buildRequest(method: String, id: String, params: [String:String]) -> String {
        var lines = [
            "\(method) SHIORI/3.0",
            "Charset: UTF-8",
            "Sender: Ourin",
            "ID: \(id)"
        ]
        // ReferenceN は数値順（辞書順だと Reference10 が Reference2 より前に並ぶ）
        for (key, value) in Self.referencePairs(from: params) {
            lines.append("\(key): \(value)")
        }
        // Reference 以外のヘッダは後ろにまとめる
        for (key, value) in params.sorted(by: { $0.key < $1.key }) where Self.referenceIndex(of: key) == nil {
            lines.append("\(key): \(value)")
        }
        lines.append("\r")
        return lines.joined(separator: "\r\n")
    }

    /// "ReferenceN" 形式のキーなら N を返す
    private static func referenceIndex(of key: String) -> Int? {
        guard key.hasPrefix("Reference"), let n = Int(key.dropFirst("Reference".count)), n >= 0 else { return nil }
        return n
    }

    /// ReferenceN キーのみを数値順に並べた (key, value) 配列
    private static func referencePairs(from params: [String:String]) -> [(key: String, value: String)] {
        params.compactMap { key, value -> (Int, String, String)? in
            guard let n = referenceIndex(of: key) else { return nil }
            return (n, key, value)
        }
        .sorted { $0.0 < $1.0 }
        .map { (key: $0.1, value: $0.2) }
    }

    /// Extract ordered reference values from params dict (numeric order, gaps padded with "").
    /// 非Referenceキー（補助情報）は位置引数に混入させない。
    private func orderedRefs(from params: [String:String]) -> [String] {
        var byIndex: [Int: String] = [:]
        var maxIndex = -1
        for (key, value) in params {
            guard let n = Self.referenceIndex(of: key) else { continue }
            byIndex[n] = value
            maxIndex = max(maxIndex, n)
        }
        guard maxIndex >= 0 else { return [] }
        return (0...maxIndex).map { byIndex[$0] ?? "" }
    }

    /// BridgeToSHIORI 経由で SHIORI モジュールへ NOTIFY を送出する
    /// - Parameter ignoreResponseScript: true の場合、返値スクリプトを再生しない（cantalk=0 の時刻系イベント等）
    func sendNotify(id: EventID, params: [String:String], ignoreResponseScript: Bool = false, security: ShioriSecurityContext = .local) {
        let req = buildRequest(method: "NOTIFY", id: id.rawValue, params: params)
        let refs = orderedRefs(from: params)
        var script: String = ""

        let hdrs = security.shioriHeaders()
        if let runtime = shioriRuntime {
            if let res = runtime.request(method: "NOTIFY", id: id.rawValue, headers: hdrs, refs: refs, timeout: 2.0), res.ok, let val = res.value {
                script = val
            }
        } else {
            script = BridgeToSHIORI.handle(event: id.rawValue, references: refs, headers: hdrs)
        }
        Log.debug("[Ourin] NOTIFY built:\n\(req)")
        if ignoreResponseScript { return }
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !ShioriDispatcher.notifyReturnIgnored.contains(id.rawValue) {
            DispatchQueue.main.async { self.ghostManager?.runNotifyScript(trimmed) }
        }
    }

    /// BridgeToSHIORI 経由で SHIORI モジュールへカスタム名の NOTIFY を送出する（\![raise,...]用）
    func sendNotifyCustom(eventName: String, params: [String:String], ignoreResponseScript: Bool = false, security: ShioriSecurityContext = .local) {
        let req = buildRequest(method: "NOTIFY", id: eventName, params: params)
        let refs = orderedRefs(from: params)
        var script: String = ""

        let hdrs = security.shioriHeaders()
        if let runtime = shioriRuntime {
            if let res = runtime.request(method: "NOTIFY", id: eventName, headers: hdrs, refs: refs, timeout: 2.0), res.ok, let val = res.value {
                script = val
            }
        } else {
            script = BridgeToSHIORI.handle(event: eventName, references: refs, headers: hdrs)
        }
        Log.debug("[Ourin] Custom NOTIFY built:\n\(req)")
        if ignoreResponseScript {
            return
        }
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            DispatchQueue.main.async { self.ghostManager?.runNotifyScript(trimmed) }
        }
    }

    /// BridgeToSHIORI 経由でカスタム名の GET を送出し応答を返す（PLUGIN/2.0 Event 応答用）
    func sendGetCustom(eventName: String, params: [String:String], security: ShioriSecurityContext = .local) -> String {
        let req = buildRequest(method: "GET", id: eventName, params: params)
        let refs = orderedRefs(from: params)
        let hdrs = security.shioriHeaders()
        var res = ""
        if let runtime = shioriRuntime {
            if let r = runtime.request(method: "GET", id: eventName, headers: hdrs, refs: refs, timeout: 3.0), r.ok, let val = r.value {
                res = val
            }
        } else {
            res = BridgeToSHIORI.handle(event: eventName, references: refs, headers: hdrs)
        }
        Log.debug("[Ourin] Custom GET built:\n\(req)")
        return res
    }

    /// BridgeToSHIORI 経由で SHIORI モジュールへ GET を送出し応答を返す
    func sendGet(id: EventID, params: [String:String], security: ShioriSecurityContext = .local) -> String {
        let req = buildRequest(method: "GET", id: id.rawValue, params: params)
        let refs = orderedRefs(from: params)
        let hdrs = security.shioriHeaders()
        var res = ""
        if let runtime = shioriRuntime {
            if let r = runtime.request(method: "GET", id: id.rawValue, headers: hdrs, refs: refs, timeout: 3.0), r.ok, let val = r.value {
                res = val
            }
        } else {
            res = BridgeToSHIORI.handle(event: id.rawValue, references: refs, headers: hdrs)
        }
        Log.debug("[Ourin] GET built:\n\(req)")
        return res
    }
}
