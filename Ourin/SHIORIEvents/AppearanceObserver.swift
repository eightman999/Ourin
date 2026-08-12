// AppearanceObserver.swift (M-Add)
// ライト/ダークモードの切り替えを監視
import AppKit

final class AppearanceObserver {
    static let shared = AppearanceObserver()
    private init() {}
    private var handler: ((ShioriEvent)->Void)?
    private var hasEmittedInitialState = false

    /// 監視を開始する
    func start(_ handler: @escaping (ShioriEvent)->Void) {
        stop()
        self.handler = handler
        hasEmittedInitialState = false

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
        handler = nil
        hasEmittedInitialState = false
    }

    @objc private func appearanceChanged() {
        emit()
    }

    private func emit() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let name = isDark ? "dark" : "light"
        handler?(ShioriEvent(id: .OnAppearanceChanged, refs: ["appearance": name]))

        let systemDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
        let initial = !hasEmittedInitialState
        hasEmittedInitialState = true
        handler?(ShioriEvent(
            id: .OnDarkTheme,
            refs: ["application": isDark ? "1" : "0", "system": systemDark ? "1" : "0"],
            delivery: initial ? .notify : .get,
            ignoreResponseScript: initial
        ))
    }
}
