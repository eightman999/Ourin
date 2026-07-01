// SerikoCursorController.swift
// currentghost.seriko.cursor.scope(ID).mouse????list(<当たり判定>).path プロパティに基づき、
// マウスが SERIKO の当たり判定領域に乗った際のカーソル動的切り替えを行う。
import AppKit

final class SerikoCursorController {
    static let shared = SerikoCursorController()
    private init() {}

    private var currentImagePath: String?

    enum Kind: String {
        case up = "mouseuplist"       // ボタンを押していない通常状態
        case down = "mousedownlist"   // ボタンを押している/ドラッグ中
        case hover = "mousehoverlist" // 一定時間静止した（OnMouseHover相当）
        case wheel = "mousewheellist" // ホイール操作中
    }

    /// 当たり判定領域用のカーソルへ切り替える。プロパティ未定義または画像ロード失敗時は標準カーソルへ戻す。
    func update(scope: Int, region: String, kind: Kind) {
        guard !region.isEmpty else { reset(); return }
        let key = "currentghost.seriko.cursor.scope(\(scope)).\(kind.rawValue)(\(region)).path"
        guard let path = PropertyManager.shared.get(key), !path.isEmpty else {
            reset()
            return
        }
        apply(imagePath: path)
    }

    /// マウスがゴーストエリア外に出た、または当該領域にカーソル定義が無いときに標準カーソルへ戻す。
    func reset() {
        guard currentImagePath != nil else { return }
        currentImagePath = nil
        NSCursor.arrow.set()
    }

    private func apply(imagePath: String) {
        guard currentImagePath != imagePath else { return }
        guard let resolved = resolveImagePath(imagePath), let image = NSImage(contentsOfFile: resolved) else {
            // 画像未検出、またはロード不能（Windows専用 .cur 形式など）な場合は標準カーソルへフォールバックする。
            reset()
            return
        }
        currentImagePath = imagePath
        let hotSpot = NSPoint(x: image.size.width / 2, y: image.size.height / 2)
        NSCursor(image: image, hotSpot: hotSpot).set()
    }

    /// シェル→ゴーストの順で相対パスを解決する（UKADOC: `mousecursor(.*)` と同じ探索順）。
    private func resolveImagePath(_ relativePath: String) -> String? {
        guard let ghostRoot = PropertyManager.shared.get("currentghost.path"), !ghostRoot.isEmpty else { return nil }
        let shellName = PropertyManager.shared.get("currentghost.shelllist.current.name") ?? "master"
        let root = URL(fileURLWithPath: ghostRoot)
        let shellCandidate = root.appendingPathComponent("shell/\(shellName)/\(relativePath)")
        if FileManager.default.fileExists(atPath: shellCandidate.path) { return shellCandidate.path }
        let ghostCandidate = root.appendingPathComponent("ghost/master/\(relativePath)")
        if FileManager.default.fileExists(atPath: ghostCandidate.path) { return ghostCandidate.path }
        return nil
    }
}
