// EventBridge.swift
// SHIORI イベントをまとめて受け取り、SHIORI モジュールへ配送する
import AppKit
import UniformTypeIdentifiers

final class EventBridge {
    static let shared = EventBridge()
    private init() {}

    private let dispatcher = ShioriDispatcher()

    // MARK: - 開始・終了

    /// すべてのオブザーバを開始する
    func start() {
        // periodic timers and system state observers
        TimerEmitter.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        SleepObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        InputMonitor.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        DragDropReceiver.shared.activate { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        DisplayObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        SpaceObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) } // M-Add
        PowerObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        LocaleObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        AppearanceObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) } // M-Add

        // boot event (GET)
        _ = dispatcher.sendGet(id: "OnBoot", params: [:])
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

        // close event (GET)
        _ = dispatcher.sendGet(id: "OnClose", params: [:])
    }
}

/// 個別の SHIORI イベントを表す構造体
struct ShioriEvent {
    /// イベント名
    let id: String
    /// パラメータ辞書（ReferenceN に相当）
    let params: [String:String]
}

final class ShioriDispatcher {
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
    func sendNotify(id: String, params: [String:String]) {
        let req = buildRequest(method: "NOTIFY", id: id, params: params)
        let _ = BridgeToSHIORI.handle(event: id, references: Array(params.values))
        NSLog("[Ourin] NOTIFY built:\n%@", req)
    }

    /// BridgeToSHIORI 経由で SHIORI モジュールへ GET を送出し応答を返す
    func sendGet(id: String, params: [String:String]) -> String {
        let req = buildRequest(method: "GET", id: id, params: params)
        let res = BridgeToSHIORI.handle(event: id, references: Array(params.values))
        NSLog("[Ourin] GET built:\n%@", req)
        return res
    }
}
