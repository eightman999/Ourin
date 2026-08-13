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
    private let calendarScheduleEmitter: CalendarScheduleEmitter

    private init() {
        let emitter = CalendarScheduleEmitter()
        calendarScheduleEmitter = emitter
        emitter.setHandler { [weak self] event in
            guard let self else { return }
            if Thread.isMainThread {
                self.broadcast(event: event)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.broadcast(event: event)
                }
            }
        }
    }

    private var started = false
    private var autoEventsEnabled = false
    /// Observer callback の世代。stop→start の間に main queue へ残った古いイベントを破棄する。
    private var observerGeneration: UInt64 = 0

    // Queue for NOTIFY events that occur when autoEvents are disabled
    private enum QueuedNotify {
        case standard(id: EventID, params: [String: String], ignoreResponseScript: Bool, security: ShioriSecurityContext)
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
        observerGeneration &+= 1
        let generation = observerGeneration
        let forward: (ShioriEvent) -> Void = { [weak self] ev in
            self?.dispatchObserverEvent(ev, generation: generation)
        }

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
            OSUpdateObserver.shared.start(forward)
            RecycleBinObserver.shared.start(forward)
            calendarScheduleEmitter.start()

            // Flush any queued NOTIFY events that occurred while auto events were disabled
            flushPendingNotifies()
        }
        // Boot GET events are initiated in each GhostManager instance.
    }

    /// すべてのオブザーバを停止する
    func stop() {
        observerGeneration &+= 1
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
        OSUpdateObserver.shared.stop()
        RecycleBinObserver.shared.stop()
        calendarScheduleEmitter.stop()
        started = false
        autoEventsEnabled = false
        // 停止はイベントライフサイクルの境界。停止前に observer が積んだ通知を
        // 次の起動へ持ち越すと、旧セッションの状態を新しい起動へ誤配送する。
        pendingNotifies.removeAll()
        // 他ゴーストの状態も次の起動で現在値から再確立する。
        lastOtherOffscreenRef0 = nil
        lastOtherOverlapRef0 = nil
        // OnClose は GhostManager.beginCloseSequence が GET で送出し応答スクリプトを再生する
        // （ここで送ると二重送信になるため送らない）
    }

    /// Enable or disable auto events dynamically
    /// - Parameter enabled: Whether to enable auto events
    private func setAutoEventsEnabled(_ enabled: Bool) {
        guard started else { return }
        guard enabled != autoEventsEnabled else { return }

        autoEventsEnabled = enabled
        observerGeneration &+= 1
        let generation = observerGeneration
        let forward: (ShioriEvent) -> Void = { [weak self] ev in
            self?.dispatchObserverEvent(ev, generation: generation)
        }

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
            OSUpdateObserver.shared.start(forward)
            RecycleBinObserver.shared.start(forward)
            calendarScheduleEmitter.start()

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
            OSUpdateObserver.shared.stop()
            RecycleBinObserver.shared.stop()
            calendarScheduleEmitter.stop()
        }
    }

    /// カレンダーの保存済み予定を再読込し、センスイベントを発火する。
    @discardableResult
    func refreshCalendarSchedules(sensorName: String = CalendarScheduleEmitter.builtinSensorName) -> CalendarScheduleRefreshResult {
        calendarScheduleEmitter.refresh(sensorName: sensorName)
    }

    /// SCHEDULE/1.0 のセンサー応答を保存してカレンダーへ反映する。
    @discardableResult
    func importCalendarScheduleData(_ data: Data, sensorName: String) -> CalendarScheduleRefreshResult {
        calendarScheduleEmitter.importSensorData(data, sensorName: sensorName)
    }

    /// 指定予定を読み上げ、OnScheduleRead を全ゴーストへ送る。
    @discardableResult
    func readCalendarSchedule(id: UUID) -> Bool {
        calendarScheduleEmitter.read(id: id)
    }

    func beginCalendarSchedulePost(sensorName: String) {
        calendarScheduleEmitter.beginPost(sensorName: sensorName)
    }

    func completeCalendarSchedulePost(sensorName: String) {
        calendarScheduleEmitter.completePost(sensorName: sensorName)
    }

    /// Flush all pending NOTIFY events that were queued while auto events were disabled
    private func flushPendingNotifies() {
        guard !pendingNotifies.isEmpty else { return }

        Log.debug("[EventBridge] Flushing \(pendingNotifies.count) queued NOTIFY events")
        for queued in pendingNotifies {
            switch queued {
            case .standard(let id, let params, let ignoreResponseScript, let security):
                broadcastNotifyImmediate(id: id, params: params, ignoreResponseScript: ignoreResponseScript, security: security)
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

    /// 登録済みゴーストのいずれかがスクリプト再生中かを照会する。
    ///
    /// `sessions` と `GhostManager.isPlaying` はメインスレッドで扱われるため、
    /// 非メインスレッド（SSTP受信経路等）からの照会はメインスレッドへ委譲して安全に読む。
    /// メインスレッド上から呼ばれた場合は直接参照し、`DispatchQueue.main.sync` による
    /// デッドロックを避ける。
    func isAnyGhostPlaying() -> Bool {
        let query: () -> Bool = {
            self.sessions.values.contains { $0.ghostManager?.isPlaying == true }
        }
        if Thread.isMainThread {
            return query()
        }
        return DispatchQueue.main.sync(execute: query)
    }

    /// Public helper to send a NOTIFY event by ID
    /// - Parameter security: 発生源のセキュリティ文脈（既定: 内部システム = local）
    func notify(_ id: EventID, params: [String:String] = [:], security: ShioriSecurityContext = .local) {
        // 明示的なAPI呼び出し（スクリプト、メディア、初期化等）は
        // 自動システムイベントの開始状態に依存させない。キューに入れるのは
        // observer の forward が呼ぶ private broadcastNotify() だけにする。
        performOnMain {
            self.broadcastNotifyImmediate(id: id, params: params, security: security)
        }
    }

    /// 表駆動発火（推奨）: 意味ラベル辞書でイベントを送出する。
    /// 例: `notify(.OnMouseClick, refs: ["x": px, "y": py, "button": btn])`。
    /// ラベル → `ReferenceN` 変換は `EventReferenceTable`（SHIORIEvents/EventReferenceSpec.swift）が担う。
    func notify(_ id: EventID, refs: [String:String], security: ShioriSecurityContext = .local) {
        let params = EventReferenceTable.params(forEvent: id.rawValue, refs: refs)
        performOnMain {
            self.broadcastNotifyImmediate(id: id, params: params, security: security)
        }
    }

    /// 他ゴーストのサーフェス変更を、監視を有効にしたセッションだけへ GET で送る。
    ///
    /// `OnOtherSurfaceChange` は全体ブロードキャストではなく、変更元を除外して
    /// 受信側の `\![set,othersurfacechange,true]` の状態を判定する必要があるため、
    /// 通常の `notify` とは別に送信元付きの経路を持つ。
    func notifyOtherSurfaceChange(
        from source: GhostManager,
        scope: Int,
        newSurfaceID: Int,
        oldSurfaceID: Int,
        newSurfaceSize: CGSize,
        security: ShioriSecurityContext = .local
    ) {
        let send = {
            let sourceGhostName = source.ghostConfig?.name ?? source.ghostURL.lastPathComponent
            let sourceSakuraName = source.ghostConfig?.sakuraName ?? sourceGhostName
            let width = max(0, Int(newSurfaceSize.width.rounded()))
            let height = max(0, Int(newSurfaceSize.height.rounded()))
            let params = EventReferenceTable.params(
                forEvent: EventID.OnOtherSurfaceChange.rawValue,
                refs: [
                    "ghostName": sourceGhostName,
                    "sakuraName": sourceSakuraName,
                    "scopeID": String(scope),
                    "newSurfaceID": String(newSurfaceID),
                    "oldSurfaceID": String(oldSurfaceID),
                    "newSurfaceSize": "0,0,\(width),\(height)"
                ]
            )

            for session in self.sessions.values {
                guard let target = session.ghostManager,
                      target !== source,
                      target.observesOtherSurfaceChange else { continue }

                let script = session.dispatcher.sendGet(
                    id: .OnOtherSurfaceChange,
                    params: params,
                    security: security
                )
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let context = Self.translationContext(
                    eventID: EventID.OnOtherSurfaceChange.rawValue,
                    params: params
                )
                DispatchQueue.main.async {
                    target.runScript(trimmed, translationContext: context)
                }
            }
        }

        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.sync(execute: send)
        }
    }

    /// Observer/UI由来のイベントを、イベント自身が指定した配送方式で送る。
    /// D&Dのように EventBridge 外で生成されるイベントも、GET/NOTIFY の仕様を失わないよう
    /// この入口を使う。
    func dispatch(_ event: ShioriEvent) {
        performOnMain {
            self.broadcast(event: event)
        }
    }

    /// スクリプトの `\\![raise,...]` 用に、標準イベント名を GET で実行する。
    /// `notify` はシステム由来の NOTIFY を表すため、raise をそこへ流すと
    /// SHIORI の返答スクリプトが再生されない。raise はイベントの結果を会話へ
    /// 反映する仕様なので、明示的に GET 経路を公開する。
    @discardableResult
    func request(_ id: EventID, params: [String:String] = [:], security: ShioriSecurityContext = .local) -> Bool {
        let send = {
            var producedScript = false
            for (_, session) in self.sessions {
                let script = session.dispatcher.sendGet(id: id, params: params, security: security)
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                producedScript = true
                let context = Self.translationContext(eventID: id.rawValue, params: params)
                let manager = session.ghostManager
                DispatchQueue.main.async {
                    manager?.runScript(trimmed, translationContext: context)
                }
            }
            return producedScript
        }
        if Thread.isMainThread {
            return send()
        }
        return DispatchQueue.main.sync(execute: send)
    }

    @discardableResult
    func request(_ id: EventID,
                 params: [String:String] = [:],
                 to target: GhostManager,
                 security: ShioriSecurityContext = .local) -> Bool {
        requestScript(id, params: params, to: target, security: security) != nil
    }

    /// 指定ゴーストへの GET の応答スクリプトを返しつつ再生する。
    /// 切替イベントの Reference1 のように、後続イベントへ応答本文を引き渡す必要がある
    /// ライフサイクル処理で使用する。
    @discardableResult
    func requestScript(_ id: EventID,
                       params: [String:String] = [:],
                       to target: GhostManager,
                       security: ShioriSecurityContext = .local) -> String? {
        let send: () -> String? = {
            guard let session = self.session(for: target) else { return nil }
            let script = session.dispatcher.sendGet(id: id, params: params, security: security)
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            target.runScript(trimmed, translationContext: Self.translationContext(eventID: id.rawValue, params: params))
            return trimmed
        }
        if Thread.isMainThread {
            return send()
        }
        return DispatchQueue.main.sync { send() }
    }

    /// 表駆動発火の指定ゴースト向けGET。
    @discardableResult
    func request(_ id: EventID,
                 refs: [String:String],
                 to target: GhostManager,
                 security: ShioriSecurityContext = .local) -> Bool {
        request(id,
                params: EventReferenceTable.params(forEvent: id.rawValue, refs: refs),
                to: target,
                security: security)
    }

    /// 指定したゴーストを除外して GET をブロードキャストする。
    ///
    /// `OnOtherGhostBooted` / `OnOtherGhostChanged` のように、発生源と対象自身には
    /// 送らず、無関係な起動中ゴーストだけへ通知するイベントで使用する。
    @discardableResult
    func request(_ id: EventID,
                 params: [String:String] = [:],
                 excluding excludedGhosts: [GhostManager],
                 security: ShioriSecurityContext = .local) -> Bool {
        let excludedIDs = Set(excludedGhosts.map(ObjectIdentifier.init))
        let send = {
            var producedScript = false
            for (_, session) in self.sessions {
                guard let manager = session.ghostManager,
                      !excludedIDs.contains(ObjectIdentifier(manager)) else { continue }
                let script = session.dispatcher.sendGet(id: id, params: params, security: security)
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                producedScript = true
                let context = Self.translationContext(eventID: id.rawValue, params: params)
                if Thread.isMainThread {
                    manager.runScript(trimmed, translationContext: context)
                } else {
                    DispatchQueue.main.sync {
                        manager.runScript(trimmed, translationContext: context)
                    }
                }
            }
            return producedScript
        }
        if Thread.isMainThread {
            return send()
        }
        return DispatchQueue.main.sync(execute: send)
    }

    func notify(_ id: EventID,
                params: [String:String] = [:],
                to target: GhostManager,
                ignoreResponseScript: Bool = false,
                security: ShioriSecurityContext = .local) {
        let send = {
            guard let session = self.session(for: target) else { return }
            session.dispatcher.sendNotify(id: id,
                                          params: params,
                                          ignoreResponseScript: ignoreResponseScript,
                                          security: security)
        }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.sync(execute: send)
        }
    }

    /// 表駆動発火の指定ゴースト向けNOTIFY。
    @discardableResult
    func notify(_ id: EventID,
                refs: [String:String],
                to target: GhostManager,
                ignoreResponseScript: Bool = false,
                security: ShioriSecurityContext = .local) -> Bool {
        let params = EventReferenceTable.params(forEvent: id.rawValue, refs: refs)
        let send = {
            guard let session = self.session(for: target) else { return false }
            session.dispatcher.sendNotify(id: id,
                                          params: params,
                                          ignoreResponseScript: ignoreResponseScript,
                                          security: security)
            return true
        }
        if Thread.isMainThread {
            return send()
        }
        return DispatchQueue.main.sync(execute: send)
    }

    /// 外部SSTP（SEND の Script ヘッダ等）から、登録済みゴーストのバルーンでスクリプトを再生する。
    /// - Parameters:
    ///   - script: 再生する SakuraScript
    ///   - ghostName: ReceiverGhostName 指定。nil なら全セッションへ送る
    /// - Returns: 再生先セッションが1つでもあれば true
    @discardableResult
    func playScriptOnGhosts(
        _ script: String,
        ghostName: String? = nil,
        translationContext: ScriptTranslationContext = .baseware
    ) -> Bool {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return playScriptOnGhostsResolving(ghostName: ghostName, translationContext: translationContext) { _ in trimmed }
    }

    /// ゴースト毎に異なるスクリプトを再生する（SSTP の IfGhost 振り分け用）。
    /// resolve は対象セッションの GhostManager を受け取り、再生するスクリプトを返す。
    /// nil または空を返したセッションでは再生しない。GhostManager を渡すことで、
    /// descript.txt の name だけでなく sakura.name / kero.name も判定に利用できる。
    /// - Parameter notify: true の場合は `runScript` ではなく `runNotifyScript` を使う。
    ///   NOTIFY 由来のスクリプト（ValueNotify）は可視テキストを含まないとき現バルーンを保持する。
    @discardableResult
    func playScriptOnGhostsResolving(
        ghostName: String? = nil,
        notify: Bool = false,
        translationContext: ScriptTranslationContext = .baseware,
        resolve: @escaping (GhostManager) -> String?
    ) -> Bool {
        var targets = sessions.values.compactMap { $0.ghostManager }
        if let name = ghostName?.lowercased(), !name.isEmpty {
            targets = targets.filter {
                ($0.ghostConfig?.name.lowercased() == name)
                    || ($0.ghostConfig?.sakuraName.lowercased() == name)
                    || ($0.ghostURL.lastPathComponent.lowercased() == name)
            }
        }
        var jobs: [(GhostManager, String)] = []
        for gm in targets {
            let resolved = resolve(gm)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let script = resolved, !script.isEmpty {
                jobs.append((gm, script))
            }
        }
        guard !jobs.isEmpty else { return false }
        DispatchQueue.main.async {
            for (gm, script) in jobs {
                if notify {
                    gm.runNotifyScript(script, translationContext: translationContext)
                } else {
                    gm.runScript(script, translationContext: translationContext)
                }
            }
        }
        return true
    }

    /// SSTP用: ゴーストごとに一度だけ翻訳し、その結果を再生と応答で共有する。
    /// Receiver未指定時はAppDelegateの起動順に並べ、先頭（プライマリ）の翻訳結果を応答値とする。
    func playTranslatedScriptOnGhostsResolving(
        ghostName: String? = nil,
        notify: Bool = false,
        translationContext: ScriptTranslationContext = .baseware,
        resolve: @escaping (GhostManager) -> String?
    ) -> String? {
        let prepareAndPlay: () -> String? = {
            var targets = self.sessions.values.compactMap { $0.ghostManager }
            if let appDelegate = NSApp.delegate as? AppDelegate {
                let order = Dictionary(uniqueKeysWithValues: appDelegate.allGhostManagers.enumerated().map {
                    (ObjectIdentifier($0.element), $0.offset)
                })
                targets.sort {
                    (order[ObjectIdentifier($0)] ?? Int.max) < (order[ObjectIdentifier($1)] ?? Int.max)
                }
            }
            if let name = ghostName?.lowercased(), !name.isEmpty {
                targets = targets.filter {
                    ($0.ghostConfig?.name.lowercased() == name)
                        || ($0.ghostConfig?.sakuraName.lowercased() == name)
                        || ($0.ghostURL.lastPathComponent.lowercased() == name)
                }
            }

            var jobs: [(GhostManager, String)] = []
            for gm in targets {
                guard let source = resolve(gm)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !source.isEmpty else { continue }
                let translated = gm.translateForDisplay(source, context: translationContext)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translated.isEmpty else { continue }
                jobs.append((gm, translated))
            }
            for (gm, translated) in jobs {
                if notify {
                    gm.runTranslatedNotifyScript(translated)
                } else {
                    gm.runTranslatedScript(translated)
                }
            }
            return jobs.first?.1
        }

        if Thread.isMainThread {
            return prepareAndPlay()
        }
        return DispatchQueue.main.sync(execute: prepareAndPlay)
    }

    /// スクリプトの `\![notify,...]` など、カスタム名の NOTIFY を送る。
    /// - Parameter security: 発生源のセキュリティ文脈（既定: 内部 = local）
    func notifyCustom(_ eventName: String, params: [String:String] = [:], ignoreResponseScript: Bool = false, security: ShioriSecurityContext = .local) {
        performOnMain {
            self.broadcastNotifyCustomImmediate(eventName: eventName, params: params, ignoreResponseScript: ignoreResponseScript, security: security)
        }
    }

    func notifyCustom(_ eventName: String,
                      params: [String:String],
                      to target: GhostManager,
                      ignoreResponseScript: Bool = false,
                      security: ShioriSecurityContext = .local) {
        let send = {
            guard let session = self.session(for: target) else { return }
            session.dispatcher.sendNotifyCustom(
                eventName: eventName,
                params: params,
                ignoreResponseScript: ignoreResponseScript,
                security: security
            )
        }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.sync(execute: send)
        }
    }

    /// 指定ゴースト以外へだけカスタム NOTIFY を配送する。
    /// OnRecycleBinEmptyFromOther のような「実行元以外」イベントで使用する。
    func notifyCustom(_ eventName: String,
                      params: [String:String],
                      excluding target: GhostManager,
                      ignoreResponseScript: Bool = false,
                      security: ShioriSecurityContext = .local) {
        let send = {
            for session in self.sessions.values where session.ghostManager !== target {
                session.dispatcher.sendNotifyCustom(
                    eventName: eventName,
                    params: params,
                    ignoreResponseScript: ignoreResponseScript,
                    security: security
                )
            }
        }
        if Thread.isMainThread {
            send()
        } else {
            DispatchQueue.main.sync(execute: send)
        }
    }

    /// 表駆動発火（推奨）: 意味ラベル辞書でカスタム名イベント（EventID 列挙に無いもの）を送出する。
    /// 例: `notifyCustom("OnExecuteRSSFailure", refs: ["reason": msg, "url": u, "method": m])`。
    func notifyCustom(_ eventName: String, refs: [String:String], ignoreResponseScript: Bool = false, security: ShioriSecurityContext = .local) {
        let params = EventReferenceTable.params(forEvent: eventName, refs: refs)
        performOnMain {
            self.broadcastNotifyCustomImmediate(eventName: eventName, params: params, ignoreResponseScript: ignoreResponseScript, security: security)
        }
    }

    /// 指定した起動中ゴーストへだけカスタム NOTIFY を送る。
    /// インストールの accept/reroute のように、対象ゴースト以外へ配送してはいけないイベントで使う。
    @discardableResult
    func notifyCustom(_ eventName: String,
                      refs: [String:String],
                      to target: GhostManager,
                      ignoreResponseScript: Bool = false,
                      security: ShioriSecurityContext = .local) -> Bool {
        let params = EventReferenceTable.params(forEvent: eventName, refs: refs)
        let send = {
            guard let session = self.session(for: target) else { return false }
            session.dispatcher.sendNotifyCustom(eventName: eventName,
                                                 params: params,
                                                 ignoreResponseScript: ignoreResponseScript,
                                                 security: security)
            return true
        }
        if Thread.isMainThread {
            return send()
        }
        return DispatchQueue.main.sync(execute: send)
    }

    /// `install.txt` の accept に対応する起動中ゴーストを返す。
    /// descript.txt の name、ディレクトリ名、install.accept のいずれも対象名として扱う。
    func runningGhost(named acceptedName: String, excluding: GhostManager? = nil) -> GhostManager? {
        let normalized = acceptedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let find = {
            self.sessions.values.compactMap(\.ghostManager).first { gm in
                guard gm !== excluding else { return false }
                var names = [
                    gm.ghostConfig?.name ?? "",
                    gm.ghostConfig?.sakuraName ?? "",
                    gm.ghostURL.lastPathComponent
                ]
                names.append(contentsOf: gm.ghostConfig?.installAccept ?? [])
                return names.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized }
            }
        }
        if Thread.isMainThread {
            return find()
        }
        return DispatchQueue.main.sync(execute: find)
    }

    /// 現在 SSTP 経由で配送可能なゴースト名を返す。
    ///
    /// `__SYSTEM_ALL_GHOST__` は SSTP の ReceiverGhostName にそのまま渡せないため、
    /// 送信前に個別の受信先へ展開する必要がある。実際に登録済みのセッションだけを
    /// 対象にし、descript.txt の name（未設定時はゴーストディレクトリ名）を返す。
    func runningGhostNames() -> [String] {
        let collect = {
            var names: [String] = []
            var seen = Set<String>()
            for ghostManager in self.sessions.values.compactMap(\.ghostManager) {
                let configuredName = ghostManager.ghostConfig?.name
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fallbackName = ghostManager.ghostURL.lastPathComponent
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let name = configuredName.isEmpty ? fallbackName : configuredName
                guard !name.isEmpty else { continue }
                let key = name.lowercased()
                guard seen.insert(key).inserted else { continue }
                names.append(name)
            }
            return names.sorted { lhs, rhs in
                let left = lhs.lowercased()
                let right = rhs.lowercased()
                return left == right ? lhs < rhs : left < right
            }
        }
        if Thread.isMainThread {
            return collect()
        }
        return DispatchQueue.main.sync(execute: collect)
    }

    /// カスタム名イベントを GET として全セッションへ送出し、応答スクリプトを再生する。
    ///
    /// GET はシステム自動イベントの有効/無効にかかわらず即時配送する。
    /// `OnDressupChanged` の最終差分や、ユーザー操作時の
    /// `OnNotifyDressupInfo` のように、応答スクリプトが意味を持つイベントで使用する。
    @discardableResult
    func requestCustom(_ eventName: String, params: [String:String] = [:], security: ShioriSecurityContext = .local) -> Bool {
        let send = { self.broadcastGetCustomImmediate(eventName: eventName, params: params, security: security) }
        if Thread.isMainThread {
            return send()
        }
        return DispatchQueue.main.sync(execute: send)
    }

    @discardableResult
    func requestCustom(_ eventName: String,
                       params: [String:String],
                       to target: GhostManager,
                       security: ShioriSecurityContext = .local) -> Bool {
        let send = {
            guard let session = self.session(for: target) else { return false }
            let script = session.dispatcher.sendGetCustom(eventName: eventName, params: params, security: security)
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            target.runScript(trimmed, translationContext: Self.translationContext(eventID: eventName, params: params))
            return true
        }
        if Thread.isMainThread {
            return send()
        }
        return DispatchQueue.main.sync(execute: send)
    }

    /// 表駆動発火（推奨）: 意味ラベル辞書でカスタム名 GET を送出する。
    @discardableResult
    func requestCustom(_ eventName: String, refs: [String:String], security: ShioriSecurityContext = .local) -> Bool {
        requestCustom(eventName, params: EventReferenceTable.params(forEvent: eventName, refs: refs), security: security)
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
            let eventParams = params
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

    /// Observer は Network/Speech/GameController 等から任意のキューで呼ばれる。
    /// セッション辞書、GhostManager状態、SHIORIランタイムを同時に触るため、
    /// observer由来のイベントは main queue に直列化する。
    ///
    /// 世代を捕捉してから非同期配送することで、stop→start の境界をまたいだ
    /// 古いイベントが新しいゴーストセッションへ流れ込むことも防ぐ。
    private func dispatchObserverEvent(_ event: ShioriEvent, generation: UInt64) {
        let deliver = { [weak self] in
            guard let self,
                  self.started,
                  self.autoEventsEnabled,
                  self.observerGeneration == generation else { return }
            self.broadcast(event: event)
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }

    /// EventBridge の共有状態とSHIORI実行を main queue に統一する。
    /// 既に main queue 上なら同期呼び出しを避け、通常のイベント順序を保つ。
    private func performOnMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.sync(execute: action)
        }
    }

    // Broadcast a NOTIFY to all registered sessions
    // If auto events are disabled, queue the event for later delivery
    private func broadcast(event: ShioriEvent) {
        switch event.delivery {
        case .get:
            broadcastGetImmediate(id: event.id, params: event.params, security: event.security)
        case .notify:
            broadcastNotify(id: event.id,
                            params: event.params,
                            ignoreResponseScript: event.ignoreResponseScript,
                            security: event.security)
        }

        // ロケール変更時は、既存の OnLocaleChange / OnLanguageChange に加えて
        // 起動時 Notify と同じ国際化情報を再通知する。
        if event.id == .OnLocaleChange {
            broadcastNotifyImmediate(
                id: .OnNotifyInternationalInfo,
                params: SystemNotificationData.currentInternationalInfo().parameters,
                ignoreResponseScript: true,
                security: event.security
            )
        }
    }

    private func broadcastNotify(id: EventID,
                                 params: [String:String],
                                 ignoreResponseScript: Bool = false,
                                 security: ShioriSecurityContext = .local) {
        if !autoEventsEnabled {
            // Queue this event for later when auto events are enabled
            pendingNotifies.append(.standard(id: id,
                                              params: params,
                                              ignoreResponseScript: ignoreResponseScript,
                                              security: security))
            Log.debug("[EventBridge] Queued NOTIFY event: \(id.rawValue) (auto events disabled)")
            return
        }
        broadcastNotifyImmediate(id: id,
                                 params: params,
                                 ignoreResponseScript: ignoreResponseScript,
                                 security: security)
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

    private static func translationContext(eventID: String, params: [String: String]) -> ScriptTranslationContext {
        var indexed: [Int: String] = [:]
        var maxIndex = -1
        for (key, value) in params where key.hasPrefix("Reference") {
            if let index = Int(key.dropFirst("Reference".count)), index >= 0 {
                indexed[index] = value
                maxIndex = max(maxIndex, index)
            }
        }
        let refs = maxIndex < 0 ? [] : (0...maxIndex).map { indexed[$0] ?? "" }
        return ScriptTranslationContext(eventID: eventID, references: refs)
    }

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
    private func broadcastNotifyImmediate(id: EventID,
                                          params: [String:String],
                                          ignoreResponseScript: Bool = false,
                                          security: ShioriSecurityContext = .local) {
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
                        let context = Self.translationContext(eventID: id.rawValue, params: p)
                        DispatchQueue.main.async { gm?.runScript(trimmed, translationContext: context) }
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
                    let context = Self.translationContext(eventID: id.rawValue, params: params)
                    DispatchQueue.main.async { gm?.runScript(trimmed, translationContext: context) }
                }
                continue
            }
            s.dispatcher.sendNotify(id: id,
                                    params: params,
                                    ignoreResponseScript: ignoreResponseScript,
                                    security: security)
        }
    }

    /// GET イベントを全ゴーストへ送り、返された Sakura Script を各ゴーストで再生する。
    /// 起動時 NOTIFY と更新時 GET の両方を持つイベントは、起動側からは
    /// `ShioriEvent.delivery == .notify` を指定する。
    private func broadcastGetImmediate(id: EventID,
                                       params: [String:String],
                                       security: ShioriSecurityContext = .local) {
        if Self.timeSignalEvents.contains(id) {
            broadcastTimeSignalImmediate(id: id, params: params, security: security)
            return
        }

        for (_, s) in sessions {
            // \t タイムクリティカルセクション中はマウス系イベントを抑止する（UKADOC）。
            if Self.mouseEvents.contains(id), s.ghostManager?.timeCriticalActive == true {
                continue
            }
            let script = s.dispatcher.sendGet(id: id, params: params, security: security)
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let gm = s.ghostManager
            let context = Self.translationContext(eventID: id.rawValue, params: params)
            DispatchQueue.main.async { gm?.runScript(trimmed, translationContext: context) }
        }

        if id == .OnSecondChange {
            dispatchOverlapTransitions(security: security)
        }
    }

    /// 時刻系イベントは、会話可能時だけ GET、会話不能時は NOTIFY とする。
    private func broadcastTimeSignalImmediate(id: EventID,
                                               params: [String:String],
                                               security: ShioriSecurityContext) {
        for (_, s) in sessions {
            var p = params
            let cantalk = s.ghostManager?.canPlayTalkNow() ?? false
            p["Reference3"] = cantalk ? "1" : "0"
            if let gm = s.ghostManager {
                p["Reference1"] = gm.mikireScopes()
                p["Reference2"] = gm.kasanariScopes()
            }
            if cantalk {
                let script = s.dispatcher.sendGet(id: id, params: p, security: security)
                let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let gm = s.ghostManager
                    let context = Self.translationContext(eventID: id.rawValue, params: p)
                    DispatchQueue.main.async { gm?.runScript(trimmed, translationContext: context) }
                }
            } else {
                s.dispatcher.sendNotify(id: id, params: p, ignoreResponseScript: true, security: security)
            }
        }
        if id == .OnSecondChange {
            dispatchOverlapTransitions(security: security)
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
                    let context = Self.translationContext(eventID: ev.id.rawValue, params: ev.params)
                    DispatchQueue.main.async { gm.runScript(trimmed, translationContext: context) }
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
                    let context = Self.translationContext(eventID: ev.id.rawValue, params: ev.params)
                    DispatchQueue.main.async { gm.runScript(trimmed, translationContext: context) }
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
                let context = Self.translationContext(eventID: eventName, params: params)
                DispatchQueue.main.async { gm?.runScript(trimmed, translationContext: context) }
            }
        }
        return producedScript
    }
}

/// Observer が SHIORI に要求する wire method。
/// UKADOC は `[NOTIFY]` の明記がないイベントを GET と定義しているため、
/// Observer の既定値は GET とする。起動時だけ NOTIFY になるイベントは発火側で
/// `.notify` を明示する。
enum ShioriEventDelivery: Equatable {
    case get
    case notify
}

/// 個別の SHIORI イベントを表す構造体
struct ShioriEvent {
    /// イベント識別子
    let id: EventID
    /// パラメータ辞書（ReferenceN に相当）
    let params: [String:String]
    /// GET/NOTIFY の配送方式
    let delivery: ShioriEventDelivery
    /// NOTIFY 応答のスクリプトを再生しない場合に true
    let ignoreResponseScript: Bool
    /// 発生源のセキュリティ文脈
    let security: ShioriSecurityContext

    init(id: EventID,
         params: [String:String],
         delivery: ShioriEventDelivery = .get,
         ignoreResponseScript: Bool = false,
         security: ShioriSecurityContext = .local) {
        self.id = id
        self.params = params
        self.delivery = delivery
        self.ignoreResponseScript = ignoreResponseScript
        self.security = security
    }
}

extension ShioriEvent {
    /// 表駆動コンストラクタ（推奨）: 意味ラベル辞書から `params` を生成する。
    /// 例: `ShioriEvent(id: .OnMouseClick, refs: ["x": px, "y": py])`。
    /// ラベル → `ReferenceN` 変換は `EventReferenceTable` が担う。
    init(id: EventID,
         refs: [String:String],
         delivery: ShioriEventDelivery = .get,
         ignoreResponseScript: Bool = false,
         security: ShioriSecurityContext = .local) {
        self.init(id: id,
                  params: EventReferenceTable.params(forEvent: id.rawValue, refs: refs),
                  delivery: delivery,
                  ignoreResponseScript: ignoreResponseScript,
                  security: security)
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
            let context = ScriptTranslationContext(eventID: id.rawValue, references: refs)
            DispatchQueue.main.async {
                self.ghostManager?.runNotifyScript(trimmed, translationContext: context)
            }
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
            let context = ScriptTranslationContext(eventID: eventName, references: refs)
            DispatchQueue.main.async {
                self.ghostManager?.runNotifyScript(trimmed, translationContext: context)
            }
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
