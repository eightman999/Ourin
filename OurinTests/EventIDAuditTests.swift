import Testing
@testable import Ourin

/// 監査 TODO「WebSocket/アーカイブ系14イベント」で追加された EventID の回帰テスト。
/// これらのイベントが列挙子として存在し、rawValue が仕様通りであることを保証する。
struct EventIDAuditTests {
    @Test
    func webSocketEventsExist() {
        #expect(EventID.OnExecuteWebSocketOpen.rawValue == "OnExecuteWebSocketOpen")
        #expect(EventID.OnExecuteWebSocketReceive.rawValue == "OnExecuteWebSocketReceive")
        #expect(EventID.OnExecuteWebSocketClose.rawValue == "OnExecuteWebSocketClose")
        #expect(EventID.OnExecuteWebSocketError.rawValue == "OnExecuteWebSocketError")
        #expect(EventID.OnExecuteWebSocketSend.rawValue == "OnExecuteWebSocketSend")
        #expect(EventID.OnExecuteWebSocketState.rawValue == "OnExecuteWebSocketState")
    }

    @Test
    func archiveEventsExist() {
        #expect(EventID.OnCompressArchiveComplete.rawValue == "OnCompressArchiveComplete")
        #expect(EventID.OnCompressArchiveFailure.rawValue == "OnCompressArchiveFailure")
        #expect(EventID.OnExtractArchiveComplete.rawValue == "OnExtractArchiveComplete")
        #expect(EventID.OnExtractArchiveFailure.rawValue == "OnExtractArchiveFailure")
    }

    @Test
    func streamingAndMediaEventsExist() {
        #expect(EventID.OnExecuteHTTPStreaming.rawValue == "OnExecuteHTTPStreaming")
        #expect(EventID.OnMusicPlayEx.rawValue == "OnMusicPlayEx")
        #expect(EventID.OnSoundLoop.rawValue == "OnSoundLoop")
        #expect(EventID.OnVideoPlayEx.rawValue == "OnVideoPlayEx")
    }

    @Test
    func videoPlayFailureEventExistsAndMapsReferences() {
        #expect(EventID.OnVideoPlayFailure.rawValue == "OnVideoPlayFailure")
        let params = EventReferenceTable.params(forEvent: "OnVideoPlayFailure", refs: [
            "filename": "legacy.wmv",
            "reason": "unsupported_codec"
        ])
        #expect(params["Reference0"] == "legacy.wmv")
        #expect(params["Reference1"] == "unsupported_codec")
    }

    @Test
    func allFourteenEventsResolvableByRawValue() {
        let names = [
            "OnExecuteWebSocketOpen", "OnExecuteWebSocketReceive", "OnExecuteWebSocketClose",
            "OnExecuteWebSocketError", "OnExecuteWebSocketSend", "OnExecuteWebSocketState",
            "OnCompressArchiveComplete", "OnCompressArchiveFailure",
            "OnExtractArchiveComplete", "OnExtractArchiveFailure",
            "OnExecuteHTTPStreaming", "OnMusicPlayEx", "OnSoundLoop", "OnVideoPlayEx"
        ]
        for name in names {
            #expect(EventID(rawValue: name) != nil, "Missing EventID for \(name)")
        }
    }
}
