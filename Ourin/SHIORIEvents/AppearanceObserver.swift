// AppearanceObserver.swift (M-Add)
// ライト/ダークモードの切り替えを監視
import AppKit

final class AppearanceObserver {
    static let shared = AppearanceObserver()
    private init() {}
    private var handler: ((ShioriEvent)->Void)?

    /// 監視を開始する
    func start(_ handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        emit() // 初期状態通知
    }

    func stop() {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    @objc private func appearanceChanged() {
        emit()
    }

    private func emit() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = isDark ? "dark" : "light"
        handler?(ShioriEvent(id: "OnAppearanceChanged", params: ["Appearance": name]))
    }
}

