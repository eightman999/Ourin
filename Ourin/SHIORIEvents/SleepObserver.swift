import AppKit

// SleepObserver.swift
// Observe system sleep/wake and screen sleep as SHIORI events

/// スクリーンセーバー通知から取得できる実行情報。
///
/// macOS の DistributedNotificationCenter 通知自体は仕様化された userInfo を
/// 持たないため、設定ドメインと通知 userInfo の両方から取得する。取得できない
/// フィールドは空欄のままにし、ScreenSaverEngine の情報をセーバー本体の情報として
/// 偽装しない。
struct ScreenSaverInfo: Equatable {
    let name: String
    let path: String
    let timeoutSeconds: String

    var references: [String: String] {
        [
            "name": name,
            "path": path,
            "timeoutSeconds": timeoutSeconds
        ]
    }

    var isEmpty: Bool {
        name.isEmpty && path.isEmpty && timeoutSeconds.isEmpty
    }

    static func current(
        notificationUserInfo: [AnyHashable: Any]? = nil,
        preferences: [String: Any] = UserDefaults.standard.persistentDomain(forName: "com.apple.screensaver") ?? [:]
    ) -> ScreenSaverInfo {
        let notification = normalizedDictionary(notificationUserInfo)
        let configuredModule = dictionaryValue(in: preferences, keys: ["moduleDict", "module"])
        let notificationModule = dictionaryValue(in: notification, keys: ["moduleDict", "module"])

        let name = firstString(
            in: [notification, notificationModule, configuredModule, preferences],
            keys: ["name", "moduleName", "screenSaverName", "ScreenSaverName"]
        ) ?? ""
        let path = firstString(
            in: [notification, notificationModule, configuredModule, preferences],
            keys: ["path", "modulePath", "screenSaverPath", "ScreenSaverPath"]
        ) ?? ""
        let timeoutSeconds = firstNumberString(
            in: [notification, notificationModule, configuredModule, preferences],
            keys: ["timeoutSeconds", "timeout", "idleTime", "idleTimeout"]
        ) ?? ""

        let derivedName: String
        if !name.isEmpty {
            derivedName = name
        } else if !path.isEmpty {
            derivedName = URL(fileURLWithPath: path)
                .deletingPathExtension()
                .lastPathComponent
        } else {
            derivedName = ""
        }

        return ScreenSaverInfo(
            name: derivedName,
            path: path,
            timeoutSeconds: timeoutSeconds
        )
    }

    private static func normalizedDictionary(_ values: [AnyHashable: Any]?) -> [String: Any] {
        guard let values else { return [:] }
        return values.reduce(into: [String: Any]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = item.value
        }
    }

    private static func dictionaryValue(in dictionary: [String: Any], keys: [String]) -> [String: Any] {
        for key in keys {
            if let value = dictionary[key] as? [String: Any] {
                return value
            }
            if let value = dictionary[key] as? NSDictionary {
                return value.reduce(into: [String: Any]()) { result, item in
                    guard let key = item.key as? String else { return }
                    result[key] = item.value
                }
            }
        }
        return [:]
    }

    private static func firstString(in dictionaries: [[String: Any]], keys: [String]) -> String? {
        for dictionary in dictionaries {
            for key in keys {
                guard let value = dictionary[key] else { continue }
                if let string = value as? String, !string.isEmpty {
                    return string
                }
                if let url = value as? URL {
                    return url.path
                }
            }
        }
        return nil
    }

    private static func firstNumberString(in dictionaries: [[String: Any]], keys: [String]) -> String? {
        for dictionary in dictionaries {
            for key in keys {
                guard let value = dictionary[key] else { continue }
                if let number = value as? NSNumber {
                    return String(number.intValue)
                }
                if let string = value as? String, let number = Double(string), number >= 0 {
                    return String(Int(number.rounded()))
                }
            }
        }
        return nil
    }
}

final class SleepObserver {
    static let shared = SleepObserver()
    private init() {}

    private var tokens: [Any] = []
    private var handler: ((ShioriEvent) -> Void)?
    private var lastScreenSaverInfo: ScreenSaverInfo?

    static func willSleepEvents() -> [ShioriEvent] {
        [
            ShioriEvent(
                id: .OnSysSuspend,
                params: [:],
                delivery: .notify,
                ignoreResponseScript: true
            ),
            ShioriEvent(id: .OnSleep, params: [:])
        ]
    }

    static func didWakeEvents() -> [ShioriEvent] {
        [
            // NSWorkspace does not expose auto/critical wake reasons; a normal wake
            // is the only non-synthetic value available from this notification.
            ShioriEvent(id: .OnSysResume, refs: ["reason": "normal"]),
            ShioriEvent(id: .OnWake, params: [:])
        ]
    }

    static func screenSaverStartEvent(info: ScreenSaverInfo) -> ShioriEvent {
        ShioriEvent(
            id: .OnScreenSaverStart,
            refs: info.references,
            delivery: .notify,
            ignoreResponseScript: true
        )
    }

    static func screenSaverEndEvent(info: ScreenSaverInfo) -> ShioriEvent {
        ShioriEvent(id: .OnScreenSaverEnd, refs: info.references)
    }

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            for event in Self.willSleepEvents() {
                self?.handler?(event)
            }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            for event in Self.didWakeEvents() {
                self?.handler?(event)
            }
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
        ) { [weak self] notification in
            guard let self else { return }
            let info = ScreenSaverInfo.current(notificationUserInfo: notification.userInfo)
            self.lastScreenSaverInfo = info
            self.handler?(Self.screenSaverStartEvent(info: info))
        })
        tokens.append(distributed.addObserver(
            forName: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let currentInfo = ScreenSaverInfo.current(notificationUserInfo: notification.userInfo)
            let info = currentInfo.isEmpty ? (self.lastScreenSaverInfo ?? currentInfo) : currentInfo
            self.handler?(Self.screenSaverEndEvent(info: info))
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
        lastScreenSaverInfo = nil
    }
}
