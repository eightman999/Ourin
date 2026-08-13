import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Ourin

struct BalloonTests {
    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func descriptorOverlay() async throws {
        let dir = URL(fileURLWithPath: #file).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let desc = try DescriptorLoader.load(from: dir)
        #expect(desc["foo"] == "baz")
    }

    @Test func descriptorCharsetTwoPassShiftJIS() async throws {
        // charset,Shift_JIS 宣言付きの descript.txt を Shift_JIS で書き出し、
        // 宣言エンコーディングで正しく再デコードされることを検証する（二段読み）。
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let body = "charset,Shift_JIS\nname,テストバルーン\n"
        let sjisEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
        let sjisData = body.data(using: sjisEncoding) ?? Data()
        try sjisData.write(to: dir.appendingPathComponent("descript.txt"))
        let desc = try DescriptorLoader.load(from: dir)
        #expect(desc["name"] == "テストバルーン")
    }

    @Test func icoDecode() async throws {
        // 1x1px の最小 ICO ファイルをバイト列として埋め込む
        let bytes: [UInt8] = [
            0x00,0x00,0x01,0x00,0x01,0x00,0x01,0x01,0x00,0x00,0x01,0x00,0x20,0x00,0x30,0x00,
            0x00,0x00,0x16,0x00,0x00,0x00,0x28,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x02,0x00,
            0x00,0x00,0x01,0x00,0x20,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
            0xff,0xff,0x00,0x00,0x00,0x00
        ]
        let data = Data(bytes)
        // 一時ファイルに書き出して ImageLoader をテスト
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.ico")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let img = try ImageLoader.load(url: tmp)
        #expect(img.width == 1)
        #expect(img.height == 1)
    }

    // MARK: - \_b --option=fixed

    @MainActor
    @Test func balloonImageOptionFixedSetsIsFixedFlag() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-balloon-fixed"))
        // handleBalloonImage requires balloonViewModels[currentScope] to already exist.
        let vm = gm.getBalloonVM(for: gm.currentScope)
        gm.handleBalloonImage(args: ["nonexistent.png", "0", "0", "--option=fixed"])

        // handleBalloonImage appends to balloonImages inside DispatchQueue.main.async; wait for it.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { c.resume() }
        }

        #expect(vm.balloonImages.count == 1)
        #expect(vm.balloonImages.first?.isFixed == true)
    }

    @MainActor
    @Test func balloonImageWithoutFixedOptionDefaultsToScrolling() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-balloon-scroll"))
        let vm = gm.getBalloonVM(for: gm.currentScope)
        gm.handleBalloonImage(args: ["nonexistent.png", "0", "0"])

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { c.resume() }
        }

        #expect(vm.balloonImages.count == 1)
        #expect(vm.balloonImages.first?.isFixed == false)
    }

    @MainActor
    @Test func balloonImageOptionsPreserveOpaqueClippingAndForeground() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-balloon-options"))
        let vm = gm.getBalloonVM(for: gm.currentScope)
        gm.handleBalloonImage(args: [
            "missing.png", "10", "20", "--option=opaque",
            "--clipping=1 2 8 9", "--option=foreground", "--option=fixed"
        ])
        await drainMainQueue()

        #expect(vm.balloonImages.count == 1)
        #expect(vm.balloonImages.first?.isOpaque == true)
        #expect(vm.balloonImages.first?.clipping == CGRect(x: 1, y: 2, width: 7, height: 7))
        #expect(vm.balloonImages.first?.isForeground == true)
        #expect(vm.balloonImages.first?.isFixed == true)
    }

    @MainActor
    @Test func balloonImageCommandUsesPlaybackScope() async throws {
        let gm = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ghost-test-balloon-scope"))
        let scopeZero = gm.getBalloonVM(for: 0)

        gm.sakuraEngine(gm.sakuraEngine, didEmit: .scope(1))
        gm.sakuraEngine(gm.sakuraEngine, didEmit: .command(name: "_b", args: ["missing.png", "0", "0"]))
        gm.processNextUnit()
        await drainMainQueue()

        #expect(gm.currentScope == 1)
        #expect(scopeZero.balloonImages.isEmpty)
        #expect(gm.balloonViewModels[1]?.balloonImages.count == 1)
    }

    @MainActor
    @Test func resetBalloonContentClearsAttachedImages() {
        let vm = BalloonViewModel()
        vm.text = "本文"
        vm.balloonImages = [BalloonViewModel.BalloonImage(
            filepath: "sample.png",
            x: 0,
            y: 0,
            isInline: false,
            isOpaque: false,
            useSelfAlpha: false,
            clipping: nil,
            isForeground: false,
            isFixed: false,
            image: NSImage(size: CGSize(width: 4, height: 4))
        )]

        vm.resetBalloonContent()

        #expect(vm.text.isEmpty)
        #expect(vm.balloonImages.isEmpty)
    }

    @Test func balloonImageClippingMapsToViewportSizeAndOffset() {
        let layout = BalloonView.balloonImageLayout(
            for: CGSize(width: 100, height: 80),
            clipping: CGRect(x: 10, y: 20, width: 40, height: 30)
        )

        #expect(layout.displaySize == CGSize(width: 40, height: 30))
        #expect(layout.imageOffset == CGSize(width: -10, height: -20))
    }

    @MainActor
    @Test func balloonImagesRenderWithoutTextAndForegroundWinsRegardlessOfInputOrder() {
        func solidImage(_ color: NSColor) -> NSImage {
            let image = NSImage(size: CGSize(width: 24, height: 24))
            image.lockFocus()
            color.setFill()
            NSRect(x: 0, y: 0, width: 24, height: 24).fill()
            image.unlockFocus()
            return image
        }

        let vm = BalloonViewModel()
        // 前景を先に入れても、描画時は foreground が background より上に来ることを確認する。
        vm.balloonImages = [
            BalloonViewModel.BalloonImage(
                filepath: "foreground.png", x: 10, y: 10, isInline: false,
                isOpaque: true, useSelfAlpha: false, clipping: nil,
                isForeground: true, isFixed: true, image: solidImage(.blue)
            ),
            BalloonViewModel.BalloonImage(
                filepath: "background.png", x: 10, y: 10, isInline: false,
                isOpaque: true, useSelfAlpha: false, clipping: nil,
                isForeground: false, isFixed: true, image: solidImage(.red)
            )
        ]

        let host = NSHostingView(rootView: BalloonView(viewModel: vm))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 150)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        window.displayIfNeeded()
        host.layoutSubtreeIfNeeded()
        defer { window.orderOut(nil) }

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            Issue.record("BalloonView did not produce a display bitmap")
            return
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var pixel = [Int](repeating: 0, count: 4)
        let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
        let sampleX = min(max(0, Int((10 + 12) * scale)), bitmap.pixelsWide - 1)
        let sampleY = min(max(0, Int((10 + 12) * scale)), bitmap.pixelsHigh - 1)
        bitmap.getPixel(&pixel, atX: sampleX, y: sampleY)

        #expect(pixel[2] > pixel[0])
    }
}
