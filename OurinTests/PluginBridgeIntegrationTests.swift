import Foundation
import Testing
@testable import Ourin

@Suite(.serialized)
struct PluginBridgeIntegrationTests {
    @Test
    func utf8EchoFixtureRoundTripsThroughNativePlugin() throws {
        let fixture = try PluginFixtureBuilder.build(.utf8Echo)
        defer { fixture.cleanup() }

        let plugin = try Plugin(url: fixture.bundleURL)
        let value = "桜鈴 UTF-8 echo"
        let response = try plugin.get(id: "OnUTF8Echo", references: ["Reference0": value])

        #expect(response.statusCode == 200)
        #expect(response.charset == "UTF-8")
        #expect(response.value == value)
        #expect(response.otherHeaders["X-Fixture"] == "utf8_echo")
    }

    @Test
    func shiftJISEchoFixtureUsesDeclaredRequestAndResponseBytes() throws {
        let fixture = try PluginFixtureBuilder.build(.shiftJISEcho)
        defer { fixture.cleanup() }

        let plugin = try Plugin(url: fixture.bundleURL)
        let value = "桜鈴 Shift_JIS echo"
        let request = PluginRequest(
            method: .get,
            id: "OnShiftJISEcho",
            charset: "Shift_JIS",
            references: ["Reference0": value]
        )
        let wire = PluginProtocolBuilder.buildRequest(request)
        let requestData = PluginWireCodec.encodeRequest(wire, charset: request.charset)
        let expectedValueBytes = EncodingAdapter.encode(value, charset: "Shift_JIS")

        #expect(requestData.range(of: expectedValueBytes) != nil)
        #expect(String(data: requestData, encoding: .utf8) == nil)

        let responseData = try #require(plugin.send(requestData))
        #expect(responseData.range(of: expectedValueBytes) != nil)
        #expect(PluginWireCodec.responseCharset(in: responseData, default: "UTF-8") == "Shift_JIS")

        let responseText = try #require(PluginWireCodec.decodeResponse(responseData, requestCharset: "UTF-8"))
        let response = try PluginProtocolParser.parseResponse(responseText)
        #expect(response.statusCode == 200)
        #expect(response.charset == "Shift_JIS")
        #expect(response.value == value)
        #expect(response.otherHeaders["X-Fixture"] == "shift_jis_echo")
    }

    @Test
    func eventAndScriptFallbackFixtureProducesTransportAction() throws {
        let fixture = try PluginFixtureBuilder.build(.eventScriptFallback)
        defer { fixture.cleanup() }

        let plugin = try Plugin(url: fixture.bundleURL)
        let response = try plugin.get(id: "OnFallback")
        let action = try #require(OurinPluginEventBridge.transportAction(from: response, notifyOnly: false))

        #expect(action.eventName == "OnFixtureFallback")
        #expect(action.references["Reference0"] == "fixture-reference")
        #expect(action.script == "\\0fixture fallback\\e")
        #expect(action.scriptOptions == Set(["nobreak"]))

        var fallbackScript: String?
        let fallbackHandled = OurinPluginEventBridge.deliver(
            action,
            runScript: { fallbackScript = $0.script },
            emitEvent: { _ in false }
        )
        #expect(fallbackHandled == true)
        #expect(fallbackScript == "\\0fixture fallback\\e")

        var scriptRanAfterEvent = false
        let eventHandled = OurinPluginEventBridge.deliver(
            action,
            runScript: { _ in scriptRanAfterEvent = true },
            emitEvent: { _ in true }
        )
        #expect(eventHandled == true)
        #expect(scriptRanAfterEvent == false)
    }

    @Test
    func targetFixtureKeepsRawTargetForGhostResolution() throws {
        let fixture = try PluginFixtureBuilder.build(.target)
        defer { fixture.cleanup() }

        let plugin = try Plugin(url: fixture.bundleURL)
        let response = try plugin.get(id: "OnTarget")
        let action = try #require(OurinPluginEventBridge.transportAction(from: response, notifyOnly: false))
        let target = try #require(action.target)

        var targetConfig = GhostConfiguration(name: "Target Ghost", sakuraName: "Sakura", keroName: "Kero")
        targetConfig.id = "target-id"
        let targetGhost = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-target-ghost"))
        targetGhost.ghostConfig = targetConfig

        var otherConfig = GhostConfiguration(name: "Other Ghost", sakuraName: "Sakura", keroName: "Kero")
        otherConfig.id = "other-id"
        let otherGhost = GhostManager(ghostURL: URL(fileURLWithPath: "/tmp/ourin-other-ghost"))
        otherGhost.ghostConfig = otherConfig

        #expect(response.target == "Target Ghost")
        #expect(targetGhost.matchesPluginTarget(target))
        #expect(otherGhost.matchesPluginTarget(target) == false)
    }

    @Test
    func propertyFixtureIsReachableThroughDispatcherGetAndSet() throws {
        let base = PluginFixtureBuilder.temporaryBaseURL(prefix: "OurinPluginBridgeProperty")
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }

        let pluginRoot = try OurinPaths.subdirectory("plugin")
        _ = try PluginFixtureBuilder.build(.property, inPluginRoot: pluginRoot)

        let registry = PluginRegistry()
        registry.discoverAndLoad()
        defer { registry.unloadAll() }

        let meta = try #require(registry.allMetas.first)
        #expect(registry.plugins.count == 1)
        #expect(meta.id == PluginFixtureKind.property.pluginID)
        #expect(meta.isNative == true)
        #expect(registry.compatibilityEntries.first?.canDispatchRequests == true)

        let dispatcher = PluginEventDispatcher(registry: registry)
        defer { dispatcher.stop() }

        #expect(dispatcher.propertyGet(pluginID: meta.id, name: "", path: "", key: "fixture.value") == "initial-value")
        #expect(dispatcher.propertySet(pluginID: meta.id, name: "", path: "", key: "fixture.value", value: "updated-value"))
        #expect(dispatcher.propertyGet(pluginID: meta.id, name: "", path: "", key: "fixture.value") == "updated-value")
        #expect(dispatcher.propertyGet(pluginID: meta.id, name: "", path: "", key: "missing.value") == nil)
    }

    @Test
    func legacyMetadataOnlyFixtureIsEnumeratedButNotDispatchable() throws {
        let base = PluginFixtureBuilder.temporaryBaseURL(prefix: "OurinPluginBridgeLegacy")
        OurinPaths.testBaseOverride = base
        defer {
            OurinPaths.testBaseOverride = nil
            try? FileManager.default.removeItem(at: base)
        }

        let pluginRoot = try OurinPaths.subdirectory("plugin")
        try PluginFixtureBuilder.copyLegacyMetadataFixture(to: pluginRoot)

        let registry = PluginRegistry()
        registry.discoverAndLoad()
        defer { registry.unloadAll() }

        #expect(registry.plugins.isEmpty)
        #expect(registry.legacyMetas.count == 1)
        #expect(registry.dispatchGet(id: "version").isEmpty)

        let entry = try #require(registry.compatibilityEntries.first)
        #expect(entry.id == "fixture-legacy-metadata-only")
        #expect(entry.name == "Fixture Legacy Metadata")
        #expect(entry.filename == "legacy_fixture.dll")
        #expect(entry.native == false)
        #expect(entry.executionState == .metadataOnly)
        #expect(entry.canDispatchRequests == false)
        #expect(entry.localizedMessages["english"]?["menu.title"] == "Legacy Metadata Fixture")
        #expect(entry.localizedMessages["japanese"]?["menu.title"] == "レガシーメタデータfixture")

        let dispatcher = PluginEventDispatcher(registry: registry)
        defer { dispatcher.stop() }
        #expect(dispatcher.propertyGet(pluginID: entry.id, name: "", path: "", key: "fixture.value") == nil)
        #expect(dispatcher.propertySet(pluginID: entry.id, name: "", path: "", key: "fixture.value", value: "x") == false)
    }
}

private struct BuiltPluginFixture {
    let rootURL: URL
    let packageURL: URL
    let bundleURL: URL

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private enum PluginFixtureKind: String {
    case utf8Echo = "utf8_echo"
    case shiftJISEcho = "shift_jis_echo"
    case eventScriptFallback = "event_script_fallback"
    case target
    case property

    var sourceURL: URL {
        PluginFixtureBuilder.fixtureRootURL
            .appendingPathComponent(rawValue, isDirectory: true)
            .appendingPathComponent("plugin.c")
    }

    var bundleName: String {
        switch self {
        case .utf8Echo: return "UTF8EchoFixture"
        case .shiftJISEcho: return "ShiftJISEchoFixture"
        case .eventScriptFallback: return "EventScriptFallbackFixture"
        case .target: return "TargetFixture"
        case .property: return "PropertyFixture"
        }
    }

    var displayName: String {
        switch self {
        case .utf8Echo: return "UTF-8 Echo Fixture"
        case .shiftJISEcho: return "Shift_JIS Echo Fixture"
        case .eventScriptFallback: return "Event Script Fallback Fixture"
        case .target: return "Target Fixture"
        case .property: return "Property Fixture"
        }
    }

    var pluginID: String {
        "fixture-\(rawValue.replacingOccurrences(of: "_", with: "-"))"
    }

    var charset: String {
        switch self {
        case .shiftJISEcho: return "Shift_JIS"
        default: return "UTF-8"
        }
    }

    var bundleIdentifier: String {
        "furin-lab.OurinTests.PluginFixture.\(rawValue.replacingOccurrences(of: "_", with: "-"))"
    }
}

private enum PluginFixtureBuilder {
    static var fixtureRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/plugin", isDirectory: true)
    }

    static func temporaryBaseURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    }

    static func build(_ kind: PluginFixtureKind) throws -> BuiltPluginFixture {
        let root = temporaryBaseURL(prefix: "OurinPluginBridgeFixture")
        let pluginRoot = root.appendingPathComponent("plugin", isDirectory: true)
        return try build(kind, inPluginRoot: pluginRoot, cleanupRoot: root)
    }

    @discardableResult
    static func build(_ kind: PluginFixtureKind, inPluginRoot pluginRoot: URL) throws -> BuiltPluginFixture {
        try build(kind, inPluginRoot: pluginRoot, cleanupRoot: pluginRoot.deletingLastPathComponent())
    }

    private static func build(
        _ kind: PluginFixtureKind,
        inPluginRoot pluginRoot: URL,
        cleanupRoot: URL
    ) throws -> BuiltPluginFixture {
        let fm = FileManager.default
        let packageURL = pluginRoot.appendingPathComponent(kind.rawValue, isDirectory: true)
        let bundleURL = packageURL.appendingPathComponent("\(kind.bundleName).plugin", isDirectory: true)
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let executableURL = macOSURL.appendingPathComponent(kind.bundleName)

        try fm.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        try writeInfoPlist(for: kind, to: contentsURL.appendingPathComponent("Info.plist"))

        let descriptor = descriptorText(for: kind)
        try descriptor.write(to: packageURL.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try descriptor.write(to: resourcesURL.appendingPathComponent("descript.txt"), atomically: true, encoding: .utf8)
        try installText(for: kind).write(to: packageURL.appendingPathComponent("install.txt"), atomically: true, encoding: .utf8)

        try runClang(sourceURL: kind.sourceURL, outputURL: executableURL)
        return BuiltPluginFixture(rootURL: cleanupRoot, packageURL: packageURL, bundleURL: bundleURL)
    }

    static func copyLegacyMetadataFixture(to pluginRoot: URL) throws {
        let fm = FileManager.default
        let sourceURL = fixtureRootURL.appendingPathComponent("legacy_metadata_only", isDirectory: true)
        let destinationURL = pluginRoot.appendingPathComponent("legacy_metadata_only", isDirectory: true)
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let files = [
            ("legacy_descript.txt", "descript.txt"),
            ("legacy_message.english.txt", "message.english.txt"),
            ("legacy_message.japanese.txt", "message.japanese.txt")
        ]
        for (sourceName, destinationName) in files {
            try fm.copyItem(
                at: sourceURL.appendingPathComponent(sourceName),
                to: destinationURL.appendingPathComponent(destinationName)
            )
        }
    }

    private static func descriptorText(for kind: PluginFixtureKind) -> String {
        """
        Charset,\(kind.charset)
        name,\(kind.displayName)
        craftman,Ourin Test
        filename,\(kind.bundleName).plugin
        id,\(kind.pluginID)
        homeurl,https://example.invalid/ourin-fixture
        """
    }

    private static func installText(for kind: PluginFixtureKind) -> String {
        """
        charset,UTF-8
        type,plugin
        directory,\(kind.rawValue)
        """
    }

    private static func writeInfoPlist(for kind: PluginFixtureKind, to url: URL) throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleName</key>
          <string>\(kind.bundleName)</string>
          <key>CFBundleIdentifier</key>
          <string>\(kind.bundleIdentifier)</string>
          <key>CFBundleVersion</key>
          <string>1.0</string>
          <key>CFBundleShortVersionString</key>
          <string>1.0</string>
          <key>CFBundlePackageType</key>
          <string>BNDL</string>
          <key>CFBundleExecutable</key>
          <string>\(kind.bundleName)</string>
          <key>LSMinimumSystemVersion</key>
          <string>10.15</string>
        </dict>
        </plist>
        """
        try plist.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func runClang(sourceURL: URL, outputURL: URL) throws {
        let clangTemporaryURL = outputURL
            .deletingLastPathComponent()
            .appendingPathComponent("clang-tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: clangTemporaryURL, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        process.arguments = [
            "-DOURIN_PLUGIN_FIXTURE_BUILD=1",
            "-std=c11",
            "-fvisibility=default",
            "-bundle",
            sourceURL.path,
            "-o",
            outputURL.path
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["TMPDIR"] = clangTemporaryURL.path
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "PluginBridgeIntegrationTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "clang failed for \(sourceURL.path)\nstdout:\n\(stdout)\nstderr:\n\(stderr)"
                ]
            )
        }
    }
}
