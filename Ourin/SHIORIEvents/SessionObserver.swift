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
        })
        tokens.append(center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSessionUnlock, params: [:]))
        })
    }

    /// Stop observing
    func stop() {
        let center = DistributedNotificationCenter.default()
        for t in tokens { center.removeObserver(t) }
        tokens.removeAll()
    }
}
