import AppKit

// SleepObserver.swift
// Observe system sleep/wake and screen sleep as SHIORI events

final class SleepObserver {
    static let shared = SleepObserver()
    private init() {}

    private var tokens: [Any] = []
    private var handler: ((ShioriEvent) -> Void)?

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        self.handler = handler
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSysSuspend, params: [:]))
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSysResume, params: [:]))
        })
        tokens.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnScreenSaverStart, params: [:]))
        })
        tokens.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnScreenSaverEnd, params: [:]))
        })
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for t in tokens { center.removeObserver(t) }
        tokens.removeAll()
    }
}
