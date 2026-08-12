import AppKit

// SleepObserver.swift
// Observe system sleep/wake and screen sleep as SHIORI events

final class SleepObserver {
    static let shared = SleepObserver()
    private init() {}

    private var tokens: [Any] = []
    private var handler: ((ShioriEvent) -> Void)?

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSysSuspend, params: [:]))
            self?.handler?(ShioriEvent(id: .OnSleep, params: [:]))
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSysResume, params: [:]))
            self?.handler?(ShioriEvent(id: .OnWake, params: [:]))
        })
        tokens.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnDisplayPowerStatus, refs: ["status": "0"]))
        })
        tokens.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnDisplayPowerStatus, refs: ["status": "1"]))
        })

        // 画面スリープとスクリーンセーバーは macOS では別通知である。
        // 前者を後者として誤発火させず、利用可能なセーバー通知だけを転送する。
        let distributed = DistributedNotificationCenter.default()
        tokens.append(distributed.addObserver(
            forName: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler?(ShioriEvent(
                id: .OnScreenSaverStart,
                params: [:],
                delivery: .notify,
                ignoreResponseScript: true
            ))
        })
        tokens.append(distributed.addObserver(
            forName: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnScreenSaverEnd, params: [:]))
        })
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for t in tokens {
            center.removeObserver(t)
            distributed.removeObserver(t)
        }
        tokens.removeAll()
        handler = nil
    }
}
