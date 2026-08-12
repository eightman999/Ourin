import Foundation
import AppKit

/// SessionObserver.swift
/// Observe session lock/unlock events and dispatch SHIORI events
final class SessionObserver {
    static let shared = SessionObserver()
    private init() {}

    private var tokens: [NSObjectProtocol] = []
    private var handler: ((ShioriEvent) -> Void)?

    /// Start observing session lock/unlock
    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler
        let center = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSessionLock, params: [:]))
            self?.handler?(ShioriEvent(id: .OnScreenLock, params: [:]))
        })
        tokens.append(center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSessionUnlock, params: [:]))
            self?.handler?(ShioriEvent(id: .OnScreenUnlock, params: [:]))
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnFullScreenAppMinimize, params: [:]))
        })
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnFullScreenAppRestore, params: [:]))
        })
        // macOS の fast-user-switching / login session 切断・再接続。
        // UKADOC でも他 OS では同等通知が存在しない場合があるため、macOS が
        // 実際に提供する NSWorkspace セッション通知だけを転送する。
        tokens.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSessionDisconnect, params: [:]))
        })
        tokens.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSessionReconnect, params: [:]))
        })
    }

    /// Stop observing
    func stop() {
        let distributed = DistributedNotificationCenter.default()
        let standard = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        for t in tokens {
            distributed.removeObserver(t)
            standard.removeObserver(t)
            workspace.removeObserver(t)
        }
        tokens.removeAll()
        handler = nil
    }
}
