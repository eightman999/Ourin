// AppearanceObserver.swift (M-Add)
// ライト/ダークモードの切り替えを監視
import AppKit

final class AppearanceObserver {
    static let shared = AppearanceObserver()
    private init() {}
    private var kvo: NSKeyValueObservation?
    private var handler: ((ShioriEvent)->Void)?

    /// 監視を開始する
    func start(_ handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        kvo = NSApp.observe(\.__effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            guard let self = self else { return }
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let name = isDark ? "dark" : "light"
            self.handler?(ShioriEvent(id: "OnAppearanceChanged", params: ["Appearance": name]))
        }
    }

    /// 監視を停止する
    func stop() {
        kvo = nil
    }
}
