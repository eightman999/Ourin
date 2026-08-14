import Foundation
import AppKit
import CoreGraphics

/// SessionObserver.swift
/// Observe session lock/unlock events and dispatch SHIORI events
struct FullScreenApplication: Equatable {
    let processIdentifier: Int32
    let bundleIdentifier: String
    let name: String
}

enum FullScreenDetection: Equatable {
    case unavailable
    case none
    case active(FullScreenApplication)
}

struct FullScreenWindowSnapshot: Equatable {
    let ownerProcessIdentifier: Int32
    let layer: Int
    let bounds: CGRect
    let isOnscreen: Bool
}

final class SessionObserver {
    static let shared = SessionObserver()
    private init() {}

    private var tokens: [NSObjectProtocol] = []
    private var handler: ((ShioriEvent) -> Void)?
    private var lastFullScreenApplication: FullScreenApplication?

    static func fullScreenEvent(minimized: Bool) -> ShioriEvent {
        ShioriEvent(
            id: minimized ? .OnFullScreenAppMinimize : .OnFullScreenAppRestore,
            refs: ["reason": "fullscreen"]
        )
    }

    /// フルスクリーンアプリの状態差分をSHIORIイベントへ変換する。
    /// 同じアプリの再通知や、通常の前面アプリ切替では何も発火しない。
    static func fullScreenTransitionEvents(
        previous: FullScreenApplication?,
        current: FullScreenApplication?
    ) -> [ShioriEvent] {
        switch (previous, current) {
        case (nil, nil):
            return []
        case (nil, .some):
            return [fullScreenEvent(minimized: true)]
        case (.some, nil):
            return [fullScreenEvent(minimized: false)]
        case let (.some(previous), .some(current)) where previous == current:
            return []
        case (.some, .some):
            return [
                fullScreenEvent(minimized: false),
                fullScreenEvent(minimized: true)
            ]
        }
    }

    /// フルスクリーン判定の純粋部分。通常の最大化ウィンドウを誤検出しないよう、
    /// 表示領域のほぼ全体を覆うレイヤー0のウィンドウだけを対象にする。
    static func isFullScreenWindow(
        _ window: FullScreenWindowSnapshot,
        displayBounds: CGRect,
        tolerance: CGFloat = 4
    ) -> Bool {
        guard window.isOnscreen, window.layer == 0,
              displayBounds.width > 0, displayBounds.height > 0 else {
            return false
        }
        let target = displayBounds.insetBy(dx: tolerance, dy: tolerance)
        return window.bounds.contains(target)
    }

    /// ウィンドウ一覧から前面アプリのフルスクリーン状態を判定する。
    /// `frontmostApplication` が取れない、または画面一覧が取れない場合は
    /// `.unavailable` とし、権限不足時に復帰イベントを偽発火しない。
    static func detectFullScreenApplication(
        windows: [FullScreenWindowSnapshot],
        displayBounds: [CGRect],
        frontmostApplication: FullScreenApplication?,
        ownProcessIdentifier: Int32
    ) -> FullScreenDetection {
        guard !displayBounds.isEmpty, let frontmostApplication else {
            return .unavailable
        }
        guard frontmostApplication.processIdentifier != ownProcessIdentifier else {
            return .none
        }
        let isFullScreen = windows.contains { window in
            window.ownerProcessIdentifier == frontmostApplication.processIdentifier
                && displayBounds.contains { display in
                    isFullScreenWindow(window, displayBounds: display)
                }
        }
        return isFullScreen ? .active(frontmostApplication) : .none
    }

    /// Start observing session lock/unlock
    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler
        let center = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        establishFullScreenState()
        tokens.append(center.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSessionLock, params: [:]))
            self?.handler?(ShioriEvent(id: .OnScreenLock, params: [:]))
        })
        tokens.append(center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.handler?(ShioriEvent(id: .OnSessionUnlock, params: [:]))
            self?.handler?(ShioriEvent(id: .OnScreenUnlock, params: [:]))
        })
        // didResignActive/didBecomeActive は単なる Cmd-Tab やモーダル表示でも発火する。
        // フルスクリーン状態は NSWorkspace の前面アプリ／Space 変更時だけ再評価する。
        tokens.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshFullScreenState()
        })
        tokens.append(workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshFullScreenState()
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
        let workspace = NSWorkspace.shared.notificationCenter
        for t in tokens {
            distributed.removeObserver(t)
            workspace.removeObserver(t)
        }
        tokens.removeAll()
        handler = nil
        lastFullScreenApplication = nil
    }

    private func establishFullScreenState() {
        switch Self.currentFullScreenDetection() {
        case .active(let application):
            lastFullScreenApplication = application
        case .none, .unavailable:
            lastFullScreenApplication = nil
        }
    }

    private func refreshFullScreenState() {
        switch Self.currentFullScreenDetection() {
        case .unavailable:
            // CGWindow の権限不足時などは状態を変更しない。これにより、
            // 観測不能を「フルスクリーン解除」と誤認しない。
            return
        case .none:
            emitFullScreenTransitions(to: nil)
        case .active(let application):
            emitFullScreenTransitions(to: application)
        }
    }

    private func emitFullScreenTransitions(to current: FullScreenApplication?) {
        let events = Self.fullScreenTransitionEvents(
            previous: lastFullScreenApplication,
            current: current
        )
        lastFullScreenApplication = current
        events.forEach { handler?($0) }
    }

    private static func currentFullScreenDetection() -> FullScreenDetection {
        guard let rawWindowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) else {
            return .unavailable
        }

        let rawWindows = (rawWindowInfo as NSArray).compactMap { item -> [String: Any]? in
            item as? [String: Any]
        }
        let windows = rawWindows.compactMap(windowSnapshot(from:))

        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return .unavailable
        }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
            return .unavailable
        }
        let displayBounds = displayIDs.map(CGDisplayBounds)

        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            return .unavailable
        }
        let frontmostApplication = FullScreenApplication(
            processIdentifier: frontmost.processIdentifier,
            bundleIdentifier: frontmost.bundleIdentifier ?? "",
            name: frontmost.localizedName ?? ""
        )
        return detectFullScreenApplication(
            windows: windows,
            displayBounds: displayBounds,
            frontmostApplication: frontmostApplication,
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier
        )
    }

    private static func windowSnapshot(from info: [String: Any]) -> FullScreenWindowSnapshot? {
        guard let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
              let layer = info[kCGWindowLayer as String] as? NSNumber,
              let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
            return nil
        }
        let onscreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? true
        return FullScreenWindowSnapshot(
            ownerProcessIdentifier: owner.int32Value,
            layer: layer.intValue,
            bounds: bounds,
            isOnscreen: onscreen
        )
    }
}
