import AppKit
import Testing
@testable import Ourin

/// ukadoc（plugin-event / descript/plugin / spec/plugin）と SSP の挙動に合わせた PLUGIN 互換の細部。
@Suite(.serialized)
@MainActor
struct PluginSSPCompatTests {
    // MARK: - descript.txt

    @Test
    func descriptValuesStartingWithScriptOrEnvTagAreDiscarded() {
        #expect(LegacyDescriptor.literalValue("\\0hello") == nil)
        #expect(LegacyDescriptor.literalValue("%username") == nil)
        #expect(LegacyDescriptor.literalValue("\\\\server") == "\\server")
        #expect(LegacyDescriptor.literalValue("\\%percent") == "%percent")
        #expect(LegacyDescriptor.literalValue("plain") == "plain")
    }

    // MARK: - 文字コード交渉

    @Test
    func initialCharsetFollowsDescriptOrFallsBackToShiftJIS() {
        #expect(PluginEventDispatcher.declaredCharset(nil) == "Shift_JIS")
        #expect(PluginEventDispatcher.declaredCharset(meta(charset: "UTF-8")) == "UTF-8")
        #expect(PluginEventDispatcher.declaredCharset(meta(charset: " ")) == "Shift_JIS")
    }

    @Test
    func versionResponseWithoutCharsetHeaderMeansShiftJIS() {
        let withHeader = "PLUGIN/2.0M 200 OK\r\nCharset: UTF-8\r\nValue: 1.0\r\n\r\n"
        let withoutHeader = "PLUGIN/2.0M 200 OK\r\nValue: 1.0\r\n\r\n"
        #expect(PluginEventDispatcher.negotiatedCharset(fromVersionResponse: withHeader) == "UTF-8")
        #expect(PluginEventDispatcher.negotiatedCharset(fromVersionResponse: withoutHeader) == "Shift_JIS")
        #expect(PluginEventDispatcher.negotiatedCharset(fromVersionResponse: "") == nil)
    }

    // MARK: - リクエストヘッダ

    @Test
    func senderIsGhostNameForGhostOriginatedRequests() {
        let host = PluginFrame(id: "OnSecondChange").build()
        #expect(host.contains("Sender: \(PluginFrame.hostSender)\r\n"))

        let ghost = PluginFrame(id: "OnCustom", sender: "さくら").build()
        #expect(ghost.contains("Sender: さくら\r\n"))
        #expect(PluginEventDispatcher.senderName(for: nil) == nil)
    }

    // MARK: - Reference の形

    @Test
    func characterWindowListIsByteOneDelimitedLikeHWNDList() {
        let windows = [NSWindow(), NSWindow()]
        let ids = WindowIDMapper.ids(for: windows)
        #expect(ids.split(separator: "\u{1}", omittingEmptySubsequences: false).count == 2)
        #expect(!ids.contains(","))
    }

    @Test
    func folderPathsCarryTrailingSeparatorLikeSSP() {
        #expect(PathNormalizer.directory("/Users/t/ghost/emily4") == "/Users/t/ghost/emily4/")
        #expect(PathNormalizer.directory("/Users/t/ghost/emily4/") == "/Users/t/ghost/emily4/")
        #expect(PathNormalizer.directory("") == "")
    }

    @Test
    func installedPluginSendsNameAndIDPerReference() {
        let refs = PluginEventDispatcher.installedPluginReferences([
            meta(name: "A", id: "a-id"),
            meta(name: "B", id: "b-id")
        ])
        #expect(refs == ["A\u{1}a-id", "B\u{1}b-id"])
    }

    // MARK: - helpers

    private func meta(name: String = "P", id: String = "p-id", charset: String? = nil) -> PluginMeta {
        PluginMeta(
            name: name, id: id, filename: "p.dll", charset: charset,
            secondChangeInterval: nil, otherGhostTalk: nil, otherGhostTalkTiming: nil,
            craftman: nil, craftmanURL: nil, isNative: true, installType: nil, installDirectory: nil,
            localizedMessages: [:], menuDefinitions: [],
            compatibilityPath: "/tmp/p.dll", executablePath: "/tmp/p.dylib", packagePath: nil
        )
    }
}

/// Windows 向けプラグインが返す file URL（`\` 区切り）を macOS で開ける形にする。
struct BrowserURLNormalizationTests {
    @Test
    func fileURLWithBackslashesBecomesPOSIXFileURL() {
        let url = GhostManager.browserURL(for: "file:////Users/t/plugin/CharameL/html\\public.html")
        #expect(url?.isFileURL == true)
        #expect(url?.path == "/Users/t/plugin/CharameL/html/public.html")
    }

    @Test
    func schemesAndBareHostsAreKept() {
        #expect(GhostManager.browserURL(for: "mailto:a@example.com")?.scheme == "mailto")
        #expect(GhostManager.browserURL(for: "example.com/x")?.absoluteString == "https://example.com/x")
        #expect(GhostManager.browserURL(for: "file:///Users/t/空白 あり.html")?.path == "/Users/t/空白 あり.html")
    }
}
