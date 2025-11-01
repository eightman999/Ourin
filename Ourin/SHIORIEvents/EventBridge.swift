// EventBridge.swift
// SHIORI イベントをまとめて受け取り、SHIORI モジュールへ配送する
import AppKit
import UniformTypeIdentifiers

final class EventBridge {
    static let shared = EventBridge()
    private init() {}

    private var started = false
    private var autoEventsEnabled = false

    // Queue for NOTIFY events that occur when autoEvents are disabled
    private enum QueuedNotify {
        case standard(id: EventID, params: [String: String])
        case custom(eventName: String, params: [String: String])
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
        started = false
        autoEventsEnabled = false
        // Send OnClose to each session
        for (_, s) in sessions { _ = s.dispatcher.sendGet(id: .OnClose, params: [:]) }
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
        }
    }

    /// Flush all pending NOTIFY events that were queued while auto events were disabled
    private func flushPendingNotifies() {
        guard !pendingNotifies.isEmpty else { return }

        Log.debug("[EventBridge] Flushing \(pendingNotifies.count) queued NOTIFY events")
        for queued in pendingNotifies {
            switch queued {
            case .standard(let id, let params):
                broadcastNotifyImmediate(id: id, params: params)
            case .custom(let eventName, let params):
                broadcastNotifyCustomImmediate(eventName: eventName, params: params)
            }
        }
        pendingNotifies.removeAll()
    }

    /// Register a ghost session to receive NOTIFY broadcasts.
    func register(adapter: YayaAdapter?, ghostManager: GhostManager) -> UUID {
        let d = ShioriDispatcher(); d.useYaya(adapter); d.ghostManager = ghostManager
        let key = UUID()
        sessions[key] = Session(dispatcher: d, ghostManager: ghostManager)
        return key
    }

    /// Unregister a previously registered session.
    func unregister(_ token: UUID) {
        sessions.removeValue(forKey: token)
    }

    /// Public helper to send a NOTIFY event by ID
    func notify(_ id: EventID, params: [String:String] = [:]) {
        broadcastNotify(id: id, params: params)
    }

    /// Public helper to send a NOTIFY event by custom name (for \![raise,...])
    func notifyCustom(_ eventName: String, params: [String:String] = [:]) {
        broadcastNotifyCustom(eventName: eventName, params: params)
    }

    // Broadcast a NOTIFY to all registered sessions
    // If auto events are disabled, queue the event for later delivery
    private func broadcastNotify(id: EventID, params: [String:String]) {
        if !autoEventsEnabled {
            // Queue this event for later when auto events are enabled
            pendingNotifies.append(.standard(id: id, params: params))
            Log.debug("[EventBridge] Queued NOTIFY event: \(id.rawValue) (auto events disabled)")
            return
        }
        broadcastNotifyImmediate(id: id, params: params)
    }

    // Broadcast a custom NOTIFY to all registered sessions
    // If auto events are disabled, queue the event for later delivery
    private func broadcastNotifyCustom(eventName: String, params: [String:String]) {
        if !autoEventsEnabled {
            // Queue this event for later when auto events are enabled
            pendingNotifies.append(.custom(eventName: eventName, params: params))
            Log.debug("[EventBridge] Queued custom NOTIFY event: \(eventName) (auto events disabled)")
            return
        }
        broadcastNotifyCustomImmediate(eventName: eventName, params: params)
    }

    // Immediately broadcast a NOTIFY to all registered sessions (bypassing queue)
    private func broadcastNotifyImmediate(id: EventID, params: [String:String]) {
        for (_, s) in sessions {
            s.dispatcher.sendNotify(id: id, params: params)
        }
    }

    // Immediately broadcast a custom NOTIFY to all registered sessions (bypassing queue)
    private func broadcastNotifyCustomImmediate(eventName: String, params: [String:String]) {
        for (_, s) in sessions {
            s.dispatcher.sendNotifyCustom(eventName: eventName, params: params)
        }
    }
}

/// 個別の SHIORI イベントを表す構造体
struct ShioriEvent {
    /// イベント識別子
    let id: EventID
    /// パラメータ辞書（ReferenceN に相当）
    let params: [String:String]
}

final class ShioriDispatcher {
    // NOTIFY-only events whose return value (script) must be ignored per UKADOC
    // https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html (Notifyイベント)
    private static let notifyReturnIgnored: Set<String> = [
        "basewareversion","hwnd","uniqueid","capability",
        "ownerghostname","otherghostname",
        "installedsakuraname","installedkeroname","installedghostname",
        "installedshellname","installedballoonname","installedheadlinename",
        "installedplugin","configuredbiffname",
        "ghostpathlist","balloonpathlist","headlinepathlist","pluginpathlist",
        "calendarskinpathlist","calendarpluginpathlist",
        "rateofusegraph","enable_log","enable_debug",
        "OnNotifySelfInfo","OnNotifyBalloonInfo","OnNotifyShellInfo",
        "OnNotifyDressupInfo","OnNotifyUserInfo","OnNotifyOSInfo",
        "OnNotifyFontInfo","OnNotifyInternationalInfo"
    ]
    private var yayaAdapter: YayaAdapter?
    weak var ghostManager: GhostManager?
    func useYaya(_ adapter: YayaAdapter?) { self.yayaAdapter = adapter }
    /// イベント ID とパラメータからリクエスト文字列を組み立てる
    private func buildRequest(method: String, id: String, params: [String:String]) -> String {
        var lines = [
            "\(method) SHIORI/3.0",
            "Charset: UTF-8",
            "Sender: Ourin",
            "ID: \(id)"
        ]
        // パラメータは与えられた順に ReferenceN として追加する
        for (idx, value) in params.values.enumerated() {
            lines.append("Reference\(idx): \(value)")
        }
        lines.append("\r")
        return lines.joined(separator: "\r\n")
    }

    /// BridgeToSHIORI 経由で SHIORI モジュールへ NOTIFY を送出する
    func sendNotify(id: EventID, params: [String:String]) {
        let req = buildRequest(method: "NOTIFY", id: id.rawValue, params: params)
        let refs = Array(params.values)
        var script: String = ""

        if let ya = yayaAdapter {
            if let res = ya.request(method: "NOTIFY", id: id.rawValue, headers: ["Charset":"UTF-8"], refs: refs, timeout: 2.0), res.ok, let val = res.value {
                script = val
            }
        } else {
            script = BridgeToSHIORI.handle(event: id.rawValue, references: refs)
        }
        Log.debug("[Ourin] NOTIFY built:\n\(req)")
        // Per UKADOC: for specific Notify events, returned script must be ignored
        // Also ignore whitespace-only responses to avoid clearing current balloon text.
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !ShioriDispatcher.notifyReturnIgnored.contains(id.rawValue) {
            DispatchQueue.main.async { self.ghostManager?.runNotifyScript(trimmed) }
        }
    }

    /// BridgeToSHIORI 経由で SHIORI モジュールへカスタム名の NOTIFY を送出する（\![raise,...]用）
    func sendNotifyCustom(eventName: String, params: [String:String]) {
        let req = buildRequest(method: "NOTIFY", id: eventName, params: params)
        let refs = Array(params.values)
        var script: String = ""

        if let ya = yayaAdapter {
            if let res = ya.request(method: "NOTIFY", id: eventName, headers: ["Charset":"UTF-8"], refs: refs, timeout: 2.0), res.ok, let val = res.value {
                script = val
            }
        } else {
            script = BridgeToSHIORI.handle(event: eventName, references: refs)
        }
        Log.debug("[Ourin] Custom NOTIFY built:\n\(req)")
        // Custom events are not in the ignore list, so process the returned script
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            DispatchQueue.main.async { self.ghostManager?.runNotifyScript(trimmed) }
        }
    }

    /// BridgeToSHIORI 経由で SHIORI モジュールへ GET を送出し応答を返す
    func sendGet(id: EventID, params: [String:String]) -> String {
        let req = buildRequest(method: "GET", id: id.rawValue, params: params)
        let refs = Array(params.values)
        var res = ""
        if let ya = yayaAdapter {
            if let r = ya.request(method: "GET", id: id.rawValue, headers: ["Charset":"UTF-8"], refs: refs, timeout: 3.0), r.ok, let val = r.value {
                res = val
            }
        } else {
            res = BridgeToSHIORI.handle(event: id.rawValue, references: refs)
        }
        Log.debug("[Ourin] GET built:\n\(req)")
        return res
    }
}
