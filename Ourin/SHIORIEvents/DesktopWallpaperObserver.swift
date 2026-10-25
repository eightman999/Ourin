// DesktopWallpaperObserver.swift
// OS 側のデスクトップ壁紙の変化を監視し、OnDesktopWallpaperChange（UKADOC 2.8.86）を送る。
import AppKit

/// 1 画面ぶんの壁紙の状態。
struct WallpaperScreenState: Equatable {
    var path: String
    var style: String
    var color: String
}

/// OnDesktopWallpaperChange の Reference:
///   R0=init/update R1=きっかけ R2=現在の壁紙 R3=直前の壁紙（init は空） R4=表示スタイル
///   R5=背景色 "R,G,B" R6～=モニタ番号[\1]壁紙[\1]スタイル
/// macOS では利用者の変更・スライドショー・テーマを区別できないため、R1 は
/// Ourin 自身の変更なら self、それ以外は unknown とする。[起動時 NOTIFY / 他 GET]
final class DesktopWallpaperObserver {
    static let shared = DesktopWallpaperObserver()

    /// Ourin 自身の変更とみなす猶予。`\![set,wallpaper]` の直後に検知した変化を self とする。
    static let selfChangeWindow: TimeInterval = 10
    static var pollInterval: TimeInterval = 3

    private var handler: ((ShioriEvent) -> Void)?
    private var timer: Timer?
    private var tokens: [(NotificationCenter, Any)] = []
    private var lastState: [WallpaperScreenState]?
    private var lastSelfChangeAt: Date?

    /// 現在の壁紙を読む関数（テストで差し替える）。
    var readState: () -> [WallpaperScreenState] = DesktopWallpaperObserver.currentState

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        tokens.append((workspaceCenter, workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.check() }))
        tokens.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.check() }))
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
        let state = readState()
        lastState = state
        emit(initial: true, cause: "unknown", current: state, previous: nil)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, token) in tokens { center.removeObserver(token) }
        tokens.removeAll()
        handler = nil
        lastState = nil
    }

    /// Ourin 自身が壁紙を変えたことを記録する（\![set,wallpaper] / \![restore,wallpaper]）。
    func noteSelfChange(at date: Date = Date()) {
        lastSelfChangeAt = date
    }

    /// 現在の壁紙を読み、変化があれば update を送る。
    func check(now: Date = Date()) {
        guard handler != nil else { return }
        let state = readState()
        guard state != lastState else { return }
        let previous = lastState
        lastState = state
        let isSelf = lastSelfChangeAt.map { now.timeIntervalSince($0) <= Self.selfChangeWindow } ?? false
        if isSelf { lastSelfChangeAt = nil }
        emit(initial: false, cause: isSelf ? "self" : "unknown", current: state, previous: previous)
    }

    private func emit(initial: Bool, cause: String, current: [WallpaperScreenState], previous: [WallpaperScreenState]?) {
        handler?(ShioriEvent(
            id: .OnDesktopWallpaperChange,
            params: Self.references(initial: initial, cause: cause, current: current, previous: previous),
            delivery: initial ? .notify : .get,
            ignoreResponseScript: initial
        ))
    }

    static func references(initial: Bool,
                           cause: String,
                           current: [WallpaperScreenState],
                           previous: [WallpaperScreenState]?) -> [String: String] {
        let main = current.first
        var params: [String: String] = [
            "Reference0": initial ? "init" : "update",
            "Reference1": cause,
            "Reference2": main?.path ?? "",
            "Reference3": initial ? "" : (previous?.first?.path ?? ""),
            "Reference4": main?.style ?? "center",
            "Reference5": main?.color ?? "0,0,0"
        ]
        for (index, screen) in current.enumerated() {
            params["Reference\(6 + index)"] = "\(index)\u{1}\(screen.path)\u{1}\(screen.style)"
        }
        return params
    }

    /// NSWorkspace の表示オプションを UKADOC の表示スタイルへ対応づける。
    static func style(scaling: NSImageScaling?, allowClipping: Bool?) -> String {
        switch scaling {
        case .scaleAxesIndependently?:
            return "stretch"
        case .scaleNone?:
            return "center"
        case .scaleProportionallyDown?:
            return "fit"
        case .scaleProportionallyUpOrDown?, nil:
            // macOS の既定は「画面いっぱい」（切り抜きあり）。
            return allowClipping == false ? "fit" : "fill"
        @unknown default:
            return "fill"
        }
    }

    static func colorString(_ color: NSColor?) -> String {
        guard let rgb = color?.usingColorSpace(.deviceRGB) else { return "0,0,0" }
        func component(_ value: CGFloat) -> Int { Int((max(0, min(1, value)) * 255).rounded()) }
        return "\(component(rgb.redComponent)),\(component(rgb.greenComponent)),\(component(rgb.blueComponent))"
    }

    /// 画面ごとの現在の壁紙。並びは NSScreen.screens（OnDisplayChangeEx と同じ）。
    static func currentState() -> [WallpaperScreenState] {
        let workspace = NSWorkspace.shared
        return NSScreen.screens.map { screen in
            let options = workspace.desktopImageOptions(for: screen) ?? [:]
            let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) }
            let clipping = (options[.allowClipping] as? NSNumber)?.boolValue
            let url = workspace.desktopImageURL(for: screen)
            // フォルダ（ダイナミック壁紙等）や単色の場合は画像ファイルのパスにならないため空にする。
            var isDirectory: ObjCBool = false
            let path: String
            if let url, url.isFileURL,
               FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               !isDirectory.boolValue {
                path = url.path
            } else {
                path = ""
            }
            return WallpaperScreenState(
                path: path,
                style: style(scaling: scaling, allowClipping: clipping),
                color: colorString(options[.fillColor] as? NSColor)
            )
        }
    }
}
