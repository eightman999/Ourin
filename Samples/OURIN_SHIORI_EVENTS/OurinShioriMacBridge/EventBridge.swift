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
    func sendNotify(id: String, params: [String:String]) {
        // TODO: Build SHIORI/3.0 request and send to SHIORI module.
        print("[NOTIFY] \(id) params=\(params)")
    }
}
