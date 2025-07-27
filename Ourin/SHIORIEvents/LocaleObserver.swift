// LocaleObserver.swift
import Foundation

final class LocaleObserver {
    static let shared = LocaleObserver()
    private init() {}
    private var token: Any?
    private var handler: ((ShioriEvent)->Void)?

    func start(_ handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        token = NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: "OnLocaleChange", params: [:]))
        }
    }
    func stop() {
        if let t = token { NotificationCenter.default.removeObserver(t); token = nil }
    }
}
