import Foundation
import CryptoKit
import AppKit
import Testing
@testable import Ourin

/// Integration coverage against the user's original NAR, extracted only into a temporary directory.
struct HiroSatoriEngineTests {
    private static let expectedSHA256 = "eeff4e64cfc96dad292e090b4144c3c2251508f18907f9419e3c4c8e25f48bef"
    private static var nar: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["OURIN_HIRO_NAR"]
            ?? NSHomeDirectory() + "/Downloads/HiroShinosawa.nar")
    }
    private static var available: Bool { FileManager.default.fileExists(atPath: nar.path) }
    private func digest(_ file: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
    }
    private func snapshot(_ root: URL) throws -> [String: String] {
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: String] = [:]
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(root.path.count + 1))] = try digest(file)
            }
        }
        return result
    }

    @Test(.enabled(if: available, "Provide the original HiroShinosawa.nar with OURIN_HIRO_NAR"))
    func originalHiroNARUsesProductionSatoriFactoryAndPersistsAcrossHelpers() throws {
        let nar = Self.nar
        try #require(digest(nar) == Self.expectedSHA256, "This test is pinned to the supplied original NAR")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Hiro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let extraction = Process()
        extraction.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        extraction.arguments = ["-q", nar.path, "-d", root.path]
        extraction.standardOutput = FileHandle.nullDevice
        extraction.standardError = FileHandle.nullDevice
        try extraction.run(); extraction.waitUntilExit()
        try #require(extraction.terminationStatus == 0)
        let master = root.appendingPathComponent("ghost/master")
        let originalFiles = try snapshot(master)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "satori.dll")
        for count in [1, 2] {
            let runtime = try #require(ShioriRuntimeFactory.makeRuntime(context: context))
            defer { runtime.unload() }
            #expect(runtime.kind == .satori)
            try #require(runtime.load(context: context))
            for (event, refs) in [("OnInitialize", []), ("OnNotifySelfInfo", ["篠澤広", ""]),
                                  ("OnNotifyUserInfo", ["プロデューサー"]), ("OnLanguageChange", ["Japanese"])] {
                #expect(runtime.request(method: "NOTIFY", id: event, refs: refs, timeout: 5)?.status == 204)
            }
            if count == 1 {
                let first = try #require(runtime.request(method: "GET", id: "OnFirstBoot", timeout: 5))
                #expect(first.status == 200)
                #expect(first.value?.contains("篠澤広") == true)
                #expect(first.value?.contains("プロデューサー") == true)
            }
            // The original dictionary legitimately selects "こんにちは。" during daytime.
            // Check actual successful nonempty lifecycle responses, not one random sentence.
            for (event, refs) in [("OnBoot", []), ("OnMouseDoubleClick", ["0", "0", "0", "0", ""]), ("OnClose", [])] {
                let response = try #require(runtime.request(method: "GET", id: event, refs: refs, timeout: 5))
                #expect(response.status == 200)
                #expect(response.value?.isEmpty == false)
                #expect(response.headers?["ErrorLevel"] == nil)
                #expect(response.headers?["ErrorDescription"] == nil)
            }
            // Conditional candidate selection prints upstream diagnostics. Those
            // CP932 lines must never enter stdout's JSONL response stream.
            for delta in ["1", "-1", "-169", "1"] {
                let wheel = try #require(runtime.request(method: "GET", id: "OnMouseWheel",
                    refs: ["200", "160", delta, "0", "", "", "mouse"], timeout: 5))
                #expect(wheel.ok)
                let tick = try #require(runtime.request(method: "GET", id: "OnSecondChange",
                    refs: ["0", "", "", "0", "0"], timeout: 5))
                #expect(tick.ok)
            }
            runtime.unload()
            // This original dictionary is CP932, while descript.txt is UTF-8.
            let saved = try String(contentsOf: master.appendingPathComponent("satori_savedata.txt"), encoding: .shiftJIS)
            #expect(saved.contains("＄起動回数\t\(count)"))
        }
        let after = try snapshot(master)
        for (file, hash) in originalFiles { #expect(after[file] == hash) }
        #expect(try digest(nar) == Self.expectedSHA256)
        // Deliberately do not select あか/あお/きいろ/もどす: these call fill_desktop.
    }
    @MainActor
    @Test(.enabled(if: available, "Provide original Hiro NAR with OURIN_HIRO_NAR"))
    func originalHiroDefaultsComposeHairClothesAndPinFromBindGroups() async throws {
        try #require(digest(Self.nar) == Self.expectedSHA256)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-Hiro-Dressup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let extraction = Process()
        extraction.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        extraction.arguments = ["-q", Self.nar.path, "-d", root.path]
        extraction.standardOutput = FileHandle.nullDevice
        extraction.standardError = FileHandle.nullDevice
        try extraction.run(); extraction.waitUntilExit()
        try #require(extraction.terminationStatus == 0)
        let manager = GhostManager(ghostURL: root)
        defer { manager.shutdown() }
        let vm = CharacterViewModel()
        manager.characterViewModels[0] = vm
        vm.image = try #require(manager.loadImage(surfaceId: 0, scope: 0))
        vm.currentSurfaceID = 0
        manager.loadAnimationsForCurrentSurface(surfaceID: 0, scope: 0)
        manager.applyDefaultDressupBindings(for: 0)
        let expected: Set<Int> = [2001, 2101, 2201, 3110, 4000]
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while manager.enabledDressupAnimationIDs(for: 0) != expected && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(manager.enabledDressupAnimationIDs(for: 0) == expected)
        #expect(vm.overlays.filter { $0.id.hasPrefix("dressup_seriko_") }.count == 5)
        #expect(!vm.overlays.contains { $0.id.hasPrefix("dressup_seriko_2011_") || $0.id.hasPrefix("dressup_seriko_2111_") })
        let base = try #require(vm.image)
        let composite = try #require(SurfaceBlendRenderer.composite(base: base, overlays: vm.overlays))
        #expect(composite.size == NSSize(width: 421, height: 399))
        func pixels(_ image: NSImage) throws -> [UInt8] {
            let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try #require(CGContext(data: &bytes, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            return bytes
        }
        let before = try pixels(base), after = try pixels(composite)
        #expect(before != after)
        let baseOpaque = stride(from: 3, to: before.count, by: 4).filter { before[$0] > 0 }.count
        let dressedOpaque = stride(from: 3, to: after.count, by: 4).filter { after[$0] > 0 }.count
        #expect(dressedOpaque > baseOpaque + 10_000)
        for id in [2001, 2101, 2201, 3110, 4000] {
            let withoutPart = try #require(SurfaceBlendRenderer.composite(base: base, overlays: vm.overlays.filter {
                !$0.id.hasPrefix("dressup_seriko_\(id)_")
            }))
            #expect(try pixels(withoutPart) != after)
        }
        let evidence = URL(fileURLWithPath: "/tmp/ourin-hiro-dressup-20261028")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        let bitmap = NSBitmapImageRep(cgImage: try #require(composite.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: evidence.appendingPathComponent("production-composite.png"))
        print("Hiro MAYUNA: IDs=\(expected.sorted()), canvas=\(composite.size), opaque=\(baseOpaque)->\(dressedOpaque), PNG=\(evidence.path)/production-composite.png")
        let initialStaticPixels = try Dictionary(uniqueKeysWithValues: vm.overlays.filter { $0.id.hasPrefix("dressup_seriko_") }.map { ($0.id, try pixels($0.image)) })
        func assertDressupPresent(_ stage: String) throws {
            let layers = vm.overlays.filter { $0.id.hasPrefix("dressup_seriko_") }
            #expect(layers.count == 5, "\(stage): static dressup layers")
            #expect(manager.enabledDressupAnimationIDs(for: 0) == expected, "\(stage): enabled dressup IDs")
            for layer in layers { #expect(try pixels(layer.image) == initialStaticPixels[layer.id], "\(stage): immutable dressup image \(layer.id)") }
            let rendered = try #require(SurfaceBlendRenderer.composite(base: base, overlays: vm.overlays))
            let data = try pixels(rendered)
            let opaque = stride(from: 3, to: data.count, by: 4).filter { data[$0] > 0 }.count
            #expect(opaque >= dressedOpaque, "\(stage): clothes/hair alpha area retained")
            print("HIRO_DRESSUP_STAGE", stage, "surface", vm.currentSurfaceID, "enabled", manager.enabledDressupAnimationIDs(for: 0).sorted(), "layers", vm.overlays.map { ($0.id, $0.animationID, $0.image.size) }, "opaque", opaque)
        }
        var completed = false
        manager.handleBindDressup(category: "身体", part: "通常", value: "0", scope: 0,
            emitEvents: false, emitInfo: false, completion: { completed = true })
        let disableDeadline = ProcessInfo.processInfo.systemUptime + 2
        while !completed && ProcessInfo.processInfo.systemUptime < disableDeadline { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(completed)
        try assertDressupPresent("after-mustselect-refusal")
        #expect(manager.enabledDressupAnimationIDs(for: 0).contains(2101)) // mustselect cannot remove the sole outfit.
        // Real runonce eyes/mouth/brows persist after completion, and callbacks
        // keep their scope even when the currently speaking character changes.
        let firstExecutor = manager.serikoExecutor(for: 0)
        let otherVM = CharacterViewModel()
        otherVM.image = base
        manager.characterViewModels[1] = otherVM
        manager.currentScope = 1
        firstExecutor.startLoop()
        let faceIDs: Set<Int> = [3010, 3011, 3012, 3014]
        let faceDeadline = ProcessInfo.processInfo.systemUptime + 2
        while !faceIDs.isSubset(of: Set(vm.overlays.compactMap(\.animationID))) && ProcessInfo.processInfo.systemUptime < faceDeadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(faceIDs.isSubset(of: Set(vm.overlays.compactMap(\.animationID))))
        #expect(otherVM.overlays.isEmpty)
        #expect(firstExecutor.activeAnimations[3011] == nil)
        try assertDressupPresent("after-face-layers")
        let face = try #require(SurfaceBlendRenderer.composite(base: base, overlays: vm.overlays))
        #expect(try pixels(face) != after)
        let faceBitmap = NSBitmapImageRep(cgImage: try #require(face.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        try #require(faceBitmap.representation(using: .png, properties: [:])).write(to: evidence.appendingPathComponent("production-face-composite.png"))
        // Let the real blink cycle finish. Its resting eyes and mouth must
        // remain present while the periodic timer waits for the next cycle.
        let blinkDeadline = ProcessInfo.processInfo.systemUptime + 2
        while firstExecutor.activeAnimations[3010] != nil && ProcessInfo.processInfo.systemUptime < blinkDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(firstExecutor.activeAnimations[3010] == nil)
        #expect(firstExecutor.needsScheduling)
        try assertDressupPresent("after-blink-cycle")
        #expect(faceIDs.isSubset(of: Set(vm.overlays.compactMap(\.animationID))))
        let secondExecutor = manager.serikoExecutor(for: 1)
        #expect(firstExecutor !== secondExecutor)
        secondExecutor.register(animations: [3011: try #require(manager.parsedSurfaceDefs[0]?.animations[3011])])
        secondExecutor.startLoop()
        let otherDeadline = ProcessInfo.processInfo.systemUptime + 2
        while otherVM.overlays.isEmpty && ProcessInfo.processInfo.systemUptime < otherDeadline { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(otherVM.overlays.contains { $0.animationID == 3011 })
        firstExecutor.stopAnimation(id: 3011)
        let stopDeadline = ProcessInfo.processInfo.systemUptime + 2
        while vm.overlays.contains(where: { $0.animationID == 3011 }) && ProcessInfo.processInfo.systemUptime < stopDeadline { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(!vm.overlays.contains { $0.animationID == 3011 })
        #expect(otherVM.overlays.contains { $0.animationID == 3011 })
        manager.currentScope = 0
        // A surface change rebuilds the selected static bind layers against the new expression.
        vm.currentSurfaceID = 1
        vm.overlays.removeAll()
        manager.loadAnimationsForCurrentSurface(surfaceID: 1, scope: 0)
        #expect(vm.overlays.filter { $0.id.hasPrefix("dressup_seriko_") }.count == 5)
    }

    @Test func mayunaSelectorRangesAndAddIDsRemainInParsedDefinitions() throws {
        #expect(SerikoParser.parseSurfaceIDs(from: "surface.append0-9,11-20,!7") == Array(0...6) + [8, 9] + Array(11...20))
        let parsed = GhostManager.parseDressupMetadata(content: "sakura.bindgroup2001.name,髪型,通常\nsakura.bindgroup2001.addid,2201,4000\nsakura.bindoption.group,髪型,mustselect\n")
        #expect(parsed.bindGroupAddIDsByScope[0]?[2001] == [2201, 4000])
        #expect(parsed.bindOptionsByScope[0]?["髪型"]?.mustSelect == true)
        let surfaces = SerikoParser.parseSurfaces("""
        surface0
        {
        element0,base,face.png,0,0
        }
        surface.append0-9,11-20
        {
        animation2001.interval,bind
        animation2001.pattern0,overlay,1900,0,0,0
        }
        """)
        #expect(surfaces[0]?.animations[2001]?.interval == .bind)
        #expect(surfaces[20]?.animations[2001]?.patterns.first?.surfaceID == 1900)
        #expect(surfaces[10] == nil)
    }

    @MainActor
    @Test func rasterDPIIsIgnoredAndExplicitRetinaScaleDeterminesLogicalSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-PNG-DPI-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ name: String, width: Int, height: Int) throws -> URL {
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: width * 4, bitsPerPixel: 32))
            bitmap.size = NSSize(width: CGFloat(width) / 5, height: CGFloat(height) / 5) // 360 DPI metadata.
            let file = root.appendingPathComponent(name)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: file)
            return file
        }
        let base = try write("base.png", width: 20, height: 10)
        _ = try write("base@2x.png", width: 40, height: 20)
        let loaded = try #require(RetinaImageLoader.image(contentsOf: base))
        #expect(loaded.size == NSSize(width: 20, height: 10))
        #expect(loaded.representations.contains { $0.pixelsWide == 40 && $0.size == loaded.size })
        #expect(RetinaImageLoader.image(contentsOf: root.appendingPathComponent("base@2x.png"))?.size == NSSize(width: 20, height: 10))
        _ = try write("fallback@3x.png", width: 60, height: 30)
        #expect(RetinaImageLoader.image(contentsOf: root.appendingPathComponent("fallback.png"))?.size == NSSize(width: 20, height: 10))
    }

    @Test func waitingIntervalsRetainTheirClockAndPeriodicRestingFrame() throws {
        var now = Date(timeIntervalSince1970: 0)
        let executor = SerikoExecutor(nowProvider: { now }, randomProvider: { 1 })
        let pattern = SerikoPattern(index: 0, method: .overlay, surfaceID: 1050, duration: 0, x: 0, y: 0, rawArguments: [])
        let periodic = SerikoParser.AnimationDefinition(id: 3010, interval: .periodic(4), options: [], patterns: [pattern])
        executor.register(animations: [3010: periodic])
        var rendered: [Int] = []
        executor.onMethodInvoked = { _, _, surface, _, _ in rendered.append(surface) }
        #expect(executor.needsScheduling)
        executor.startInitialPeriodicAnimations()
        executor.startLoop()
        #expect(rendered == [1050])
        #expect(executor.activeAnimations.isEmpty)
        #expect(executor.needsScheduling)
        now = now.addingTimeInterval(3.9)
        executor.startLoop()
        #expect(rendered == [1050])
        now = now.addingTimeInterval(0.2)
        executor.startLoop()
        #expect(rendered == [1050, 1050])
        for interval in [SerikoInterval.sometimes, .rarely, .always] {
            let waiting = SerikoExecutor(randomProvider: { 1 })
            waiting.register(animations: [1: .init(id: 1, interval: interval, options: [], patterns: [pattern])])
            #expect(waiting.needsScheduling)
            if interval != .always {
                waiting.startLoop()
                #expect(waiting.activeAnimations.isEmpty)
                #expect(waiting.needsScheduling)
            }
        }
        let disabled = SerikoExecutor()
        disabled.register(animations: [1: .init(id: 1, interval: .combined([.bind, .always]), options: [], patterns: [pattern])])
        disabled.setEnabledBindAnimationIDs([])
        #expect(!disabled.needsScheduling)
        disabled.setEnabledBindAnimationIDs([1])
        #expect(disabled.needsScheduling)
    }

}
