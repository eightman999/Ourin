import Foundation
import Testing
@testable import Ourin

/// `ShioriBridgeContext` インスタンスのルーティング・直列化・リセットを検証するスイート。
///
/// global な `BridgeToSHIORI`（`.shared`）を一切触らず、独自の `ShioriBridgeContext` インスタンスと
/// fake `NativeShioriSource` / `ShioriGhostResolver` を使うため、他スイート（`SSTPDispatcherTests` 等の
/// `.serialized` スイート）と並列競合しない。各テストは固有の UUID ベースの Resource キーを使い、
/// `ResourceTestStore` もインスタンス毎のスレッドローカルスロットを持つため状態が漏れない。
@Suite
struct ShioriBridgeContextTests {

    // MARK: - Fakes

    /// `NativeShioriSource` のテスト用フェイク。ワイヤ応答文字列をスタブで返す。
    final class FakeNativeShioriSource: NativeShioriSource {
        var stubbedWire: String?
        private(set) var callCount = 0
        private(set) var lastMethod: String?
        private(set) var lastEvent: String?
        private(set) var lastReferences: [String]?
        private(set) var lastHeaders: [String: String]?

        func wireResponse(method: String, event: String, references: [String], headers: [String: String]) -> String? {
            callCount += 1
            lastMethod = method
            lastEvent = event
            lastReferences = references
            lastHeaders = headers
            return stubbedWire
        }
    }

    /// `ShioriGhostResolver` のテスト用フェイク。構造化応答をスタブで返す。
    final class FakeShioriGhostResolver: ShioriGhostResolver {
        var stubbedResponse: BridgeToSHIORI.BridgeShioriResponse?
        private(set) var callCount = 0
        private(set) var lastMethod: String?
        private(set) var lastEvent: String?
        private(set) var lastReferences: [String]?
        private(set) var lastHeaders: [String: String]?

        func resolve(method: String, event: String, references: [String], headers: [String: String]) -> BridgeToSHIORI.BridgeShioriResponse? {
            callCount += 1
            lastMethod = method
            lastEvent = event
            lastReferences = references
            lastHeaders = headers
            return stubbedResponse
        }
    }

    // MARK: - 優先順位: resource > native > ghost

    @Test
    func resourceOverridesNativeAndGhost() {
        let native = FakeNativeShioriSource()
        native.stubbedWire = "SHIORI/3.0 200 OK\r\nValue: native-value\r\n"
        let ghost = FakeShioriGhostResolver()
        ghost.stubbedResponse = .init(status: 200, headers: [:], value: "ghost-value")
        let ctx = ShioriBridgeContext(nativeSource: native, ghostResolver: ghost)

        let key = "prio-res-\(UUID().uuidString)"
        ctx.setResource(key, value: "resource-value")

        let value = ctx.handle(event: "Resource", references: [key], headers: [:], method: "GET")
        #expect(value == "resource-value")
        // resource hit 時は native / ghost とも呼ばれない
        #expect(native.callCount == 0)
        #expect(ghost.callCount == 0)
    }

    @Test
    func nativeTakesPrecedenceOverGhostWhenNoResource() {
        let native = FakeNativeShioriSource()
        native.stubbedWire = "SHIORI/3.0 200 OK\r\nValue: native-value\r\n"
        let ghost = FakeShioriGhostResolver()
        ghost.stubbedResponse = .init(status: 200, headers: [:], value: "ghost-value")
        let ctx = ShioriBridgeContext(nativeSource: native, ghostResolver: ghost)

        let value = ctx.handle(event: "OnSecond", references: [], headers: [:], method: "GET")
        #expect(value == "native-value")
        #expect(native.callCount == 1)
        // native が応答したので ghost は呼ばれない
        #expect(ghost.callCount == 0)
    }

    @Test
    func ghostAnswersWhenNativeAbsent() {
        let ghost = FakeShioriGhostResolver()
        ghost.stubbedResponse = .init(status: 200, headers: [:], value: "ghost-only")
        let ctx = ShioriBridgeContext(nativeSource: nil, ghostResolver: ghost)

        let value = ctx.handle(event: "OnThird", references: [], headers: [:], method: "GET")
        #expect(value == "ghost-only")
        #expect(ghost.callCount == 1)
    }

    // MARK: - native handle の Value 抽出

    @Test
    func nativeHandleExtractsValueFromWire() {
        let native = FakeNativeShioriSource()
        native.stubbedWire = "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: \\h\\s0Extracted\r\n"
        let ctx = ShioriBridgeContext(nativeSource: native, ghostResolver: nil)

        let value = ctx.handle(
            event: "OnTest",
            references: ["a", "b"],
            headers: ["SecurityLevel": "local"],
            method: "GET"
        )
        #expect(value == "\\h\\s0Extracted")
        // native へ渡される引数の検証
        #expect(native.lastMethod == "GET")
        #expect(native.lastEvent == "OnTest")
        #expect(native.lastReferences == ["a", "b"])
        #expect(native.lastHeaders?["SecurityLevel"] == "local")
    }

    @Test
    func nativeHandleReturnsEmptyWhenWireHasNoValue() {
        let native = FakeNativeShioriSource()
        native.stubbedWire = "SHIORI/3.0 204 No Content\r\n"
        let ctx = ShioriBridgeContext(nativeSource: native, ghostResolver: nil)

        #expect(ctx.handle(event: "OnTest", references: [], headers: [:], method: "GET") == "")
    }

    // MARK: - native handleResponse の wire passthrough

    @Test
    func nativeHandleResponseReturnsWireAsIs() {
        let native = FakeNativeShioriSource()
        let wire = "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nValue: v\r\nSurface: 8\r\nReference0: r0\r\n\r\n"
        native.stubbedWire = wire
        let ctx = ShioriBridgeContext(nativeSource: native, ghostResolver: nil)

        let resp = ctx.handleResponse(event: "OnTest", references: [], headers: [:], method: "GET")
        // 再直列化せずワイヤ文字列をそのまま返す（Status / ReferenceN / Surface 等の応答ヘッダを保持）
        #expect(resp == wire)
    }

    // MARK: - ghost response serialization

    @Test
    func ghostHandleResponseSerializesStructuredResponse() {
        let ghost = FakeShioriGhostResolver()
        ghost.stubbedResponse = .init(
            status: 200,
            headers: ["Reference1": "second", "Reference0": "first", "Surface": "5"],
            value: "\\h\\s0GhostScript"
        )
        let ctx = ShioriBridgeContext(nativeSource: nil, ghostResolver: ghost)

        let resp = ctx.handleResponse(event: "OnTest", references: [], headers: [:], method: "GET")
        #expect(resp.hasPrefix("SHIORI/3.0 200 OK\r\n"))
        // ReferenceN は数値順で安定出力
        #expect(resp.contains("Reference0: first\r\n"))
        #expect(resp.contains("Reference1: second\r\n"))
        // Value ヘッダが未設定なら応答値から補われる
        #expect(resp.contains("Value: \\h\\s0GhostScript\r\n"))
        #expect(resp.contains("Surface: 5\r\n"))
    }

    // MARK: - reset の状態初期化

    @Test
    func resetClearsResourceAndResolverState() {
        let ghost = FakeShioriGhostResolver()
        ghost.stubbedResponse = .init(status: 200, headers: [:], value: "ghost-value")
        let ctx = ShioriBridgeContext(nativeSource: nil, ghostResolver: ghost)

        let key = "reset-res-\(UUID().uuidString)"
        ctx.setResource(key, value: "stored")

        // reset 前: resource 登録値が優先し、ghost は呼ばれない
        #expect(ctx.handle(event: "Resource", references: [key], headers: [:], method: "GET") == "stored")
        #expect(ghost.callCount == 0)

        ctx.reset()

        // reset 後: resource map クリア + resolver クリア → すべて miss → 空文字。
        // native も env（SHIORI_BUNDLE_PATH 未設定）から再構築されて nil。
        #expect(ctx.handle(event: "Resource", references: [key], headers: [:], method: "GET") == "")
        #expect(ctx.handle(event: "OnTest", references: [], headers: [:], method: "GET") == "")
        // resolver が ctx から切り離されているため、ghost は依然呼ばれない
        #expect(ghost.callCount == 0)
    }

    // MARK: - setter による差し替え

    @Test
    func setNativeSourceSwapsActiveSource() {
        let ctx = ShioriBridgeContext(nativeSource: nil, ghostResolver: nil)
        // 初期状態: 何も無い → 空文字
        #expect(ctx.handle(event: "OnTest", references: [], headers: [:], method: "GET") == "")

        let native = FakeNativeShioriSource()
        native.stubbedWire = "SHIORI/3.0 200 OK\r\nValue: swapped\r\n"
        ctx.setNativeSource(native)

        #expect(ctx.handle(event: "OnTest", references: [], headers: [:], method: "GET") == "swapped")
        #expect(native.callCount == 1)
    }

    @Test
    func setGhostResolverSwapsActiveResolver() {
        let ctx = ShioriBridgeContext(nativeSource: nil, ghostResolver: nil)
        let ghost = FakeShioriGhostResolver()
        ghost.stubbedResponse = .init(status: 200, headers: [:], value: "swapped-ghost")
        ctx.setGhostResolver(ghost)

        #expect(ctx.handle(event: "OnTest", references: [], headers: [:], method: "GET") == "swapped-ghost")
        #expect(ghost.callCount == 1)

        // nil でクリア
        ctx.setGhostResolver(nil)
        #expect(ctx.handle(event: "OnTest", references: [], headers: [:], method: "GET") == "")
        #expect(ghost.callCount == 1)
    }
}
