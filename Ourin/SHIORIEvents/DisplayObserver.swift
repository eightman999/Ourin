// DisplayObserver.swift
// 画面構成の変化を監視する
import AppKit
import CoreGraphics

/// A display identity plus the wire-format record used by OnDisplayHandover and
/// OnDisplayChangeEx.  The display ID is kept separately because two monitors
/// can have identical geometry and color depth.
struct DisplaySnapshot: Equatable {
    let displayID: CGDirectDisplayID
    let wireValue: String
}

final class DisplayObserver {
    static let shared = DisplayObserver()
    private init() {}
    private var token: Any?
    private var handler: ((ShioriEvent)->Void)?

    /// Return the current monitor record for a window.  `window.screen` is the
    /// AppKit-selected screen (the screen containing most of the window); the
    /// frame-intersection fallback handles a just-moved window while AppKit is
    /// still updating its screen property.
    static func snapshot(for window: NSWindow) -> DisplaySnapshot? {
        let screen = window.screen
            ?? NSScreen.screens.first { $0.frame.intersects(window.frame) }
        guard let screen else { return nil }
        return snapshot(for: screen)
    }

    static func snapshot(for screen: NSScreen) -> DisplaySnapshot {
        let mainID = CGMainDisplayID()
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
            ?? mainID
        let frame = screen.frame
        let wireValue = [
            String(Int(frame.minX)),
            String(Int(frame.minY)),
            String(Int(frame.maxX)),
            String(Int(frame.maxY)),
            String(screen.depth.bitsPerPixel),
            displayID == mainID ? "1" : "0"
        ].joined(separator: ",")
        return DisplaySnapshot(displayID: displayID, wireValue: wireValue)
    }

    /// 監視を開始する
    func start(_ handler: @escaping (ShioriEvent)->Void) {
        self.handler = handler
        token = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.emit(initial: false)
        }
        // UKADOC: 起動時は NOTIFY、起動後の変更は GET。空のダミー参照ではなく、
        // 現在のプライマリディスプレイ情報をそのまま渡す。
        emit(initial: true)
    }

    /// 監視を停止する
    func stop() {
        if let t = token { NotificationCenter.default.removeObserver(t); token = nil }
        handler = nil
    }

    private func emit(initial: Bool) {
        let mainID = CGMainDisplayID()
        let mainScreen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == mainID
        } ?? NSScreen.main ?? NSScreen.screens.first

        if let mainScreen {
            let displayID = (mainScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map {
                CGDirectDisplayID($0.uint32Value)
            } ?? mainID
            let params: [String: String] = [
                "bpp": String(mainScreen.depth.bitsPerPixel),
                "width": String(CGDisplayPixelsWide(displayID)),
                "height": String(CGDisplayPixelsHigh(displayID))
            ]
            handler?(ShioriEvent(
                id: .OnDisplayChange,
                refs: [
                    "bpp": params["bpp"] ?? "",
                    "width": params["width"] ?? "",
                    "height": params["height"] ?? ""
                ],
                delivery: initial ? .notify : .get,
                ignoreResponseScript: initial
            ))
        }

        var extended = EventReferenceTable.params(
            forEvent: EventID.OnDisplayChangeEx.rawValue,
            refs: ["state": initial ? "init" : "update"]
        )
        for (index, screen) in NSScreen.screens.enumerated() {
            extended["Reference\(index + 1)"] = displayInfo(for: screen)
        }
        handler?(ShioriEvent(
            id: .OnDisplayChangeEx,
            params: extended,
            delivery: initial ? .notify : .get,
            ignoreResponseScript: initial
        ))
    }

    private func displayInfo(for screen: NSScreen) -> String {
        // Keep the existing call-site signature for the multi-display event;
        // the shared formatter is also used by OnDisplayHandover.
        return Self.snapshot(for: screen).wireValue
    }
}
