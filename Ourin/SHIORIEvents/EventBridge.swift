// EventBridge.swift
import AppKit
import UniformTypeIdentifiers

final class EventBridge {
    static let shared = EventBridge()
    private init() {}

    private let dispatcher = ShioriDispatcher()

    // MARK: - Start/Stop

    func start() {
        InputMonitor.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        DragDropReceiver.shared.activate { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        DisplayObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        SpaceObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) } // M-Add
        PowerObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        LocaleObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) }
        AppearanceObserver.shared.start { [weak self] ev in self?.dispatcher.sendNotify(id: ev.id, params: ev.params) } // M-Add
    }
    func stop() {
        InputMonitor.shared.stop()
        DisplayObserver.shared.stop()
        SpaceObserver.shared.stop()
        PowerObserver.shared.stop()
        LocaleObserver.shared.stop()
        AppearanceObserver.shared.stop()
    }
}

struct ShioriEvent {
    let id: String
    let params: [String:String]
}

final class ShioriDispatcher {
    /// Build NOTIFY SHIORI/3.0 request text from event id and parameters.
    private func buildRequest(id: String, params: [String:String]) -> String {
        var lines = [
            "NOTIFY SHIORI/3.0",
            "Charset: UTF-8",
            "Sender: Ourin",
            "ID: \(id)"
        ]
        // Parameters are appended as ReferenceN headers in given order
        for (idx, value) in params.values.enumerated() {
            lines.append("Reference\(idx): \(value)")
        }
        lines.append("\r")
        return lines.joined(separator: "\r\n")
    }

    /// Send NOTIFY event to SHIORI module via BridgeToSHIORI
    func sendNotify(id: String, params: [String:String]) {
        let req = buildRequest(id: id, params: params)
        let _ = BridgeToSHIORI.handle(event: id, references: Array(params.values))
        NSLog("[Ourin] NOTIFY built:\n%@", req)
    }
}
