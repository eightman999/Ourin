import AppKit
import Testing
@testable import Ourin

struct CharacterHitTestTests {
    /// 窓（300x400）より小さいサーフェス（相方の 255x161 など）は左上に描かれる。
    /// hitTest の point は superview（非 flipped のフレームビュー）座標なので、上端付近の
    /// 見えている部分は superview の y が大きい側になる。以前は変換せずに上下反転して判定し、
    /// 見えている部分を掴んでも透明扱いになって相方をドラッグできなかった。
    @MainActor
    @Test
    func smallSurfaceIsHitWhereItIsDrawnNearTheTop() throws {
        let viewModel = CharacterViewModel()
        let image = NSImage(size: NSSize(width: 255, height: 161))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        viewModel.image = image

        let host = CharacterHitTestingHostingView(rootView: CharacterView(viewModel: viewModel), viewModel: viewModel)
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }
        let frameView = try #require(host.superview)

        // 窓の上端から 50pt（描かれている部分）→ フレームビュー座標では y = 400 - 50
        let onSurface = host.convert(NSPoint(x: 100, y: 50), to: frameView)
        #expect(host.hitTest(onSurface) != nil)

        // 窓の下端付近（何も描かれていない部分）は透過する
        let belowSurface = host.convert(NSPoint(x: 100, y: 350), to: frameView)
        #expect(host.hitTest(belowSurface) == nil)
    }
}
