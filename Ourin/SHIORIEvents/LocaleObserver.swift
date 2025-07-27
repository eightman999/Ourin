// LocaleObserver.swift
// ロケール（地域と言語設定）の変更を監視
import Foundation

final class LocaleObserver {
    static let shared = LocaleObserver()
    private init() {}
    private var token: Any?
    private var handler: ((ShioriEvent)->Void)?

    /// 監視を開始する
    func start(_ handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        token = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: "OnLocaleChange", params: [:]))
        }
    }

    /// 監視を停止する
    func stop() {
        if let t = token { NotificationCenter.default.removeObserver(t); token = nil }
    }
}
