import Testing
import AppKit
@testable import Ourin

struct SurfaceOverlayOrderingTests {
    @Test
    func surfaceTransparencyModeParsesUkadocValues() {
        #expect(SurfaceTransparencyMode.parse(nil) == .legacy)
        #expect(SurfaceTransparencyMode.parse("0") == .legacy)
        #expect(SurfaceTransparencyMode.parse("1") == .useSelfAlpha)
        #expect(SurfaceTransparencyMode.parse(" true ") == .useSelfAlpha)
        #expect(SurfaceTransparencyMode.parse("FULL") == .full)
    }

    @MainActor
    @Test
    func shellDescriptorControlsSurfaceTransparencyMode() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-surface-transparency-\(UUID().uuidString)", isDirectory: true)
        let shell = root.appendingPathComponent("shell/master", isDirectory: true)
        try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
        try "seriko.use_self_alpha,full\n".write(
            to: shell.appendingPathComponent("descript.txt"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let manager = GhostManager(ghostURL: root)
        defer { manager.shutdown() }

        #expect(manager.surfaceTransparencyMode == .full)
    }

    @MainActor
    @Test
    func selfAlphaUsesPngAlphaAndFullKeepsRgbImageOpaque() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-surface-alpha-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let alphaURL = root.appendingPathComponent("alpha.png")
        let rgbURL = root.appendingPathComponent("rgb.png")
        try Self.writePNG(at: alphaURL, hasAlpha: true)
        try Self.writePNG(at: rgbURL, hasAlpha: false)

        let manager = GhostManager(ghostURL: root)
        defer { manager.shutdown() }

        let alphaImage = try #require(manager.loadSurfaceFile(
            url: alphaURL,
            transparencyMode: .useSelfAlpha
        ))
        let alphaBitmap = try Self.bitmap(for: alphaImage)
        let alphaColor = try #require(alphaBitmap.colorAt(x: 0, y: 0))
        #expect(alphaColor.alphaComponent < 0.01)

        let keyedImage = try #require(manager.loadSurfaceFile(
            url: rgbURL,
            transparencyMode: .useSelfAlpha
        ))
        let keyedBitmap = try Self.bitmap(for: keyedImage)
        let keyedColor = try #require(keyedBitmap.colorAt(x: 0, y: 0))
        #expect(keyedColor.alphaComponent < 0.01)

        let fullImage = try #require(manager.loadSurfaceFile(
            url: rgbURL,
            transparencyMode: .full
        ))
        let fullBitmap = try Self.bitmap(for: fullImage)
        let fullColor = try #require(fullBitmap.colorAt(x: 0, y: 0))
        #expect(fullColor.alphaComponent > 0.99)
    }

    @Test
    func overlaysSortByZOrderThenInsertion() async throws {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        let overlays = [
            SurfaceOverlay(id: "c", image: img, zOrder: 100, insertionOrder: 2),
            SurfaceOverlay(id: "a", image: img, zOrder: 0, insertionOrder: 5),
            SurfaceOverlay(id: "b", image: img, zOrder: 100, insertionOrder: 1)
        ]

        let sorted = SurfaceOverlay.sortedForDisplay(overlays)
        #expect(sorted.map(\.id) == ["a", "b", "c"])
    }

    @MainActor
    @Test
    func unloadedCharacterDoesNotHitTestAnOverlay() {
        let viewModel = CharacterViewModel()
        let overlayImage = NSImage(size: NSSize(width: 32, height: 32))
        overlayImage.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(origin: .zero, size: overlayImage.size).fill()
        overlayImage.unlockFocus()
        viewModel.overlays = [SurfaceOverlay(id: "detached-face", image: overlayImage)]

        let host = CharacterHitTestingHostingView(
            rootView: CharacterView(viewModel: viewModel),
            viewModel: viewModel
        )
        host.frame = NSRect(x: 0, y: 0, width: 64, height: 64)
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

        #expect(host.hitTest(NSPoint(x: 16, y: 16)) == nil)
    }

    @MainActor
    @Test
    func animationSurfaceAssetRemovesPureGreenBackground() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetURL = repositoryRoot
            .appendingPathComponent("emily4/shell/master/surface5006.png")
        let manager = GhostManager(ghostURL: repositoryRoot)

        let image = try #require(manager.loadSurfaceFile(url: assetURL))
        var proposedRect = NSRect.zero
        let cgImage = try #require(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        // NSBitmapImageRep の y=0 が、この PNG の緑背景側の角に対応する。
        let greenCorner = try #require(bitmap.colorAt(x: 0, y: 0))

        #expect(greenCorner.alphaComponent < 0.01)
    }

    @MainActor
    @Test
    func greenChromakeyKeepsAnimationAssetOrientation() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetURL = repositoryRoot
            .appendingPathComponent("emily4/shell/master/surface4100.png")
        let manager = GhostManager(ghostURL: repositoryRoot)
        defer { manager.shutdown() }

        let source = try #require(RetinaImageLoader.image(contentsOf: assetURL))
        let keyed = try #require(manager.loadSurfaceFile(url: assetURL))

        func redBounds(for image: NSImage) throws -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
            var proposedRect = NSRect(origin: .zero, size: image.size)
            let cgImage = try #require(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            var bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)?
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let color = bitmap.colorAt(x: x, y: y),
                          let rgb = color.usingColorSpace(.deviceRGB),
                          rgb.alphaComponent > 0.5,
                          rgb.redComponent > rgb.greenComponent * 1.5,
                          rgb.redComponent > rgb.blueComponent * 1.5 else {
                        continue
                    }
                    if let current = bounds {
                        bounds = (
                            min(current.minX, x),
                            min(current.minY, y),
                            max(current.maxX, x),
                            max(current.maxY, y)
                        )
                    } else {
                        bounds = (x, y, x, y)
                    }
                }
            }
            return try #require(bounds)
        }

        #expect(try redBounds(for: keyed) == redBounds(for: source))
    }

    @MainActor
    @Test
    func animationOverlayUsesSurfaceAliasAndNormalSurfaceResolver() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = GhostManager(ghostURL: repositoryRoot.appendingPathComponent("emily4"))
        defer { manager.shutdown() }

        // Emily4 defines sakura surface alias 35 -> 55. There is no surface35.png,
        // so a direct filename lookup would silently drop this overlay.
        manager.characterViewModels[0] = CharacterViewModel()
        manager.loadAnimationsForCurrentSurface(surfaceID: 0, scope: 0)
        manager.handleAnimAddOverlay(id: 35)
        try await Task.sleep(nanoseconds: 50_000_000)

        let overlays = manager.characterViewModels[0]?.overlays ?? []
        let overlay = try #require(overlays.last)
        #expect(overlay.surfaceID == 55)
        #expect(overlay.image.size.width > 0 && overlay.image.size.height > 0)
    }

    @MainActor
    @Test
    func backgroundSerikoAnimationMarksOverlayBehindBaseSurface() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-seriko-background-(UUID().uuidString)", isDirectory: true)
        let shell = root.appendingPathComponent("shell/master", isDirectory: true)
        try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        surface0
        {
          animation7.interval,never
          animation7.option,background
          animation7.pattern0,overlay,1,100,0,0
        }
        """.write(
            to: shell.appendingPathComponent("surfaces.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Self.writePNG(at: shell.appendingPathComponent("surface1.png"), hasAlpha: false)

        let manager = GhostManager(ghostURL: root)
        defer { manager.shutdown() }
        manager.characterViewModels[0] = CharacterViewModel()
        manager.loadAnimationsForCurrentSurface(surfaceID: 0, scope: 0)
        manager.playAnimation(id: 7, wait: false)
        try await Task.sleep(nanoseconds: 50_000_000)

        let overlay = try #require(manager.characterViewModels[0]?.overlays.first)
        #expect(overlay.animationID == 7)
        #expect(overlay.zOrder < 0)
    }

    @MainActor
    @Test
    func serikoMoveShiftsCharacterSurfaceAndResetsOnStop() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-seriko-move-(UUID().uuidString)", isDirectory: true)
        let shell = root.appendingPathComponent("shell/master", isDirectory: true)
        try FileManager.default.createDirectory(at: shell, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try """
        surface0
        {
          animation7.interval,never
          animation7.pattern0,move,0,100,12,-8
        }
        """.write(
            to: shell.appendingPathComponent("surfaces.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Self.writePNG(at: shell.appendingPathComponent("surface0.png"), hasAlpha: false)

        let manager = GhostManager(ghostURL: root)
        defer { manager.shutdown() }
        manager.characterViewModels[0] = CharacterViewModel()
        manager.loadAnimationsForCurrentSurface(surfaceID: 0, scope: 0)
        manager.playAnimation(id: 7, wait: false)

        #expect(manager.characterViewModels[0]?.serikoMoveOffset == CGPoint(x: 12, y: -8))
        manager.serikoExecutor.stopAnimation(id: 7)
        #expect(manager.characterViewModels[0]?.serikoMoveOffset == .zero)
    }

    @MainActor
    @Test
    func animAddOverlaySupportsCoordinatesAndTimedFrames() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = GhostManager(ghostURL: repositoryRoot.appendingPathComponent("emily4"))
        defer { manager.shutdown() }

        manager.characterViewModels[0] = CharacterViewModel()
        manager.loadAnimationsForCurrentSurface(surfaceID: 0, scope: 0)

        manager.handleAnimAddOverlay(id: 35, x: 12, y: 34)
        try await Task.sleep(nanoseconds: 50_000_000)
        let positioned = try #require(manager.characterViewModels[0]?.overlays.last)
        #expect(positioned.offset == CGPoint(x: 12, y: 34))

        let sequence = try #require(manager.parseAnimAddOverlaySequence(args: [
            "35", "10", "20", "50",
            "40", "14", "24", "50",
            "runonce"
        ]))
        #expect(sequence.frames.map(\.surfaceID) == [35, 40])
        #expect(sequence.frames.map(\.durationMilliseconds) == [50, 50])
        #expect(sequence.timing == .runonce)

        manager.handleAnimAddOverlaySequence(
            frames: sequence.frames,
            timing: sequence.timing,
            blendMode: .normal
        )
        try await Task.sleep(nanoseconds: 20_000_000)
        let firstFrame = try #require(manager.characterViewModels[0]?.overlays.last)
        #expect(firstFrame.offset == CGPoint(x: 10, y: 20))

        try await Task.sleep(nanoseconds: 70_000_000)
        let secondFrame = try #require(manager.characterViewModels[0]?.overlays.last)
        #expect(secondFrame.offset == CGPoint(x: 14, y: 24))

        try await Task.sleep(nanoseconds: 70_000_000)
        #expect(manager.characterViewModels[0]?.overlays.last?.id != secondFrame.id)
        #expect(manager.animAddSurfaceTimers.isEmpty)
    }

    private static func writePNG(at url: URL, hasAlpha: Bool) throws {
        let samplesPerPixel = hasAlpha ? 4 : 3
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: samplesPerPixel,
            hasAlpha: hasAlpha,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))

        if hasAlpha {
            Self.setPixel([255, 0, 0, 0], atX: 0, y: 0, in: bitmap)
            Self.setPixel([0, 0, 255, 255], atX: 1, y: 0, in: bitmap)
        } else {
            Self.setPixel([255, 0, 255], atX: 0, y: 0, in: bitmap)
            Self.setPixel([0, 0, 255], atX: 1, y: 0, in: bitmap)
        }

        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    private static func bitmap(for image: NSImage) throws -> NSBitmapImageRep {
        let tiff = try #require(image.tiffRepresentation)
        return try #require(NSBitmapImageRep(data: tiff))
    }

    private static func setPixel(
        _ values: [Int],
        atX x: Int,
        y: Int,
        in bitmap: NSBitmapImageRep
    ) {
        var values = values
        values.withUnsafeMutableBufferPointer { buffer in
            bitmap.setPixel(buffer.baseAddress!, atX: x, y: y)
        }
    }

}
