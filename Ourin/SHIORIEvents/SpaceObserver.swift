// SpaceObserver.swift (M-Add)
// macOS の Spaces 変更を監視する
import AppKit

final class SpaceObserver {
    static let shared = SpaceObserver()
    private init() {}
    private var token: Any?
    private var handler: ((ShioriEvent)->Void)?

    /// 監視を開始する
    func start(_ handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        token = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: "OnSpaceChanged", params: [:]))
        }
    }

    /// 監視を停止する
    func stop() {
        if let t = token { NSWorkspace.shared.notificationCenter.removeObserver(t); token = nil }
    }
}
