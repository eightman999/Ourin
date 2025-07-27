// AppearanceObserver.swift (M-Add)
import AppKit

final class AppearanceObserver {
    static let shared = AppearanceObserver()
    private init() {}
    private var kvo: NSKeyValueObservation?
    private var handler: ((ShioriEvent)->Void)?

    func start(_ handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        kvo = NSApp.observe(\.__effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            guard let self = self else { return }
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let name = isDark ? "dark" : "light"
            self.handler?(ShioriEvent(id: "OnAppearanceChanged", params: ["Appearance": name]))
        }
    }
    func stop() {
        kvo = nil
    }
}
