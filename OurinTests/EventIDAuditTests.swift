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
        #expect(EventID.OnSoundError.rawValue == "OnSoundError")
        #expect(EventID.OnSoundStop.rawValue == "OnSoundStop")
        #expect(EventID.OnVideoPlayEx.rawValue == "OnVideoPlayEx")
    }

    @Test
    func soundErrorReferencesFollowUkadocOrder() {
        let params = EventReferenceTable.params(forEvent: "OnSoundError", refs: [
            "command": "play",
            "errorCode": "-1",
            "filename": "missing.wav",
            "message": "file_not_found"
        ])
        #expect(params == [
            "Reference0": "play",
            "Reference1": "-1",
            "Reference2": "missing.wav",
            "Reference3": "file_not_found"
        ])
    }

    @Test
    func musicEventsUseExternalPlayerMetadataReferences() {
        #expect(EventReferenceTable.specs["OnMusicPlay"]?.references == ["title", "artist"])
        #expect(EventReferenceTable.specs["OnMusicPlayEx"]?.references == ["title", "artist"])
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

    @Test
    func nestedUpdateEventsUseUkadocIDs() {
        let names = [
            "OnUpdate.OnDownloadBegin",
            "OnUpdate.OnMD5CompareBegin",
            "OnUpdate.OnMD5CompareComplete",
            "OnUpdate.OnMD5CompareFailure",
            "OnUpdateOther.OnDownloadBegin",
            "OnUpdateOther.OnMD5CompareBegin",
            "OnUpdateOther.OnMD5CompareComplete",
            "OnUpdateOther.OnMD5CompareFailure",
        ]
        for name in names {
            #expect(EventID(rawValue: name) != nil, "Missing nested update EventID for \(name)")
        }
    }

    @Test
    func updatePipelineResolvesOnlyOfficialNestedStages() {
        #expect(GhostManager.updatePipelineEventName(base: "OnUpdate", stage: "OnDownloadBegin") == "OnUpdate.OnDownloadBegin")
        #expect(GhostManager.updatePipelineEventName(base: "OnUpdateOther", stage: "OnMD5CompareFailure") == "OnUpdateOther.OnMD5CompareFailure")
        #expect(GhostManager.updatePipelineEventName(base: "OnUpdate", stage: "OnDownloadFailure") == "OnUpdate.OnDownloadFailure")
    }
}
