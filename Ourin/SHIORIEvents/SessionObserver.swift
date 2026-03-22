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
        self.handler = handler
        let center = DistributedNotificationCenter.default()
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
    }

    /// Stop observing
    func stop() {
        let distributed = DistributedNotificationCenter.default()
        let standard = NotificationCenter.default
        for t in tokens {
            distributed.removeObserver(t)
            standard.removeObserver(t)
        }
        tokens.removeAll()
    }
}
