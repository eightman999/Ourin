// DisplayObserver.swift
// 画面構成の変化を監視する
import AppKit

final class DisplayObserver {
    static let shared = DisplayObserver()
    private init() {}
    private var token: Any?
    private var handler: ((ShioriEvent)->Void)?

    /// 監視を開始する
    func start(_ handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        token = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: "OnDisplayChange", params: [:]))
        }
    }

    /// 監視を停止する
    func stop() {
        if let t = token { NotificationCenter.default.removeObserver(t); token = nil }
    }
}
