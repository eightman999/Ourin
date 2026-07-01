import AppKit
import Testing
@testable import Ourin

/// `SerikoCursorController` の当たり判定連動カーソル切り替えロジックを検証する。
/// 実ゴースト画像を伴う統合テストは `currentghost.path` の差し替えが難しいため、
/// ここではキー構築・フォールバック（未定義/画像ロード失敗時に標準カーソルへ戻る）挙動を検証する。
@MainActor
struct SerikoCursorControllerTests {
    @Test
    func resetsToArrowWhenNoRegionResolved() {
        SerikoCursorController.shared.update(scope: 0, region: "SomeRegion", kind: .up)
        SerikoCursorController.shared.reset()
        #expect(NSCursor.current == NSCursor.arrow)
    }

    @Test
    func fallsBackToArrowWhenCursorPropertyUndefined() {
        // 未定義の当たり判定領域名 → プロパティが見つからないので標準カーソルへフォールバックする。
        SerikoCursorController.shared.update(scope: 0, region: "UndefinedRegion_\(UUID().uuidString)", kind: .up)
        #expect(NSCursor.current == NSCursor.arrow)
    }

    @Test
    func fallsBackToArrowWhenImageFileDoesNotExist() {
        let region = "CursorTestRegion_\(UUID().uuidString)"
        let key = "currentghost.seriko.cursor.scope(0).mouseuplist(\(region)).path"
        _ = PropertyManager.shared.set(key, value: "nonexistent_cursor_image.png")

        SerikoCursorController.shared.update(scope: 0, region: region, kind: .up)

        // ghost root 配下に実在しない画像なので、フォールバックして標準カーソルのままになる。
        #expect(NSCursor.current == NSCursor.arrow)
    }

    @Test
    func emptyRegionResetsCursor() {
        SerikoCursorController.shared.update(scope: 0, region: "", kind: .up)
        #expect(NSCursor.current == NSCursor.arrow)
    }
}
