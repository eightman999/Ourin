import Foundation
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
        #expect(EventID.OnArchiveComplete.rawValue == "OnArchiveComplete")
        #expect(EventID.OnArchiveFailure.rawValue == "OnArchiveFailure")
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

    @Test
    func everyOnEventInReferenceTableHasATypedEventID() {
        let missing = EventReferenceTable.specs.keys
            .filter { $0.hasPrefix("On") && EventID(rawValue: $0) == nil }
            .sorted()

        #expect(missing.isEmpty, "Missing typed EventID cases: \(missing.joined(separator: ", "))")
    }

    @Test
    func staticallyEmittedEventsHaveTypedReferenceSpecs() throws {
        let sourceRoot = Self.projectRoot.appendingPathComponent("Ourin", isDirectory: true)
        let sourceURLs = try Self.swiftSourceURLs(in: sourceRoot)
        let patterns = [
            #"ShioriEvent\s*\(\s*id:\s*\.(On[A-Za-z0-9_]+)"#,
            #"\b(?:notify|request)\s*\(\s*\.(On[A-Za-z0-9_]+)"#,
            #"\b(?:sendGet|sendNotify)\s*\(\s*id:\s*\.(On[A-Za-z0-9_]+)"#
        ]

        var emitted = Set<String>()
        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for pattern in patterns {
                emitted.formUnion(Self.captureEventNames(pattern: pattern, in: source))
            }
        }

        #expect(emitted.count >= 100, "Event emission scan unexpectedly found too few IDs: \(emitted.count)")
        let missingTypedIDs = emitted.filter { EventID(rawValue: $0) == nil }.sorted()
        let missingSpecs = emitted.filter { EventReferenceTable.specs[$0] == nil }.sorted()
        #expect(missingTypedIDs.isEmpty, "Statically emitted events without EventID: \(missingTypedIDs.joined(separator: ", "))")
        #expect(missingSpecs.isEmpty, "Statically emitted events without EventReferenceSpec: \(missingSpecs.joined(separator: ", "))")
    }

    @Test
    func literalCustomEventEmissionsHaveTypedReferenceSpecs() throws {
        let sourceRoot = Self.projectRoot.appendingPathComponent("Ourin", isDirectory: true)
        let sourceURLs = try Self.swiftSourceURLs(in: sourceRoot)
        let patterns = [
            #"\b(?:notifyCustom|requestCustom)\s*\(\s*\"(On[A-Za-z0-9_.]+)\""#,
            #"\b(?:eventName|forEvent)\s*:\s*\"(On[A-Za-z0-9_.]+)\""#
        ]

        var emitted = Set<String>()
        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for pattern in patterns {
                emitted.formUnion(Self.captureEventNames(pattern: pattern, in: source))
            }
        }

        #expect(emitted.count >= 40, "Custom event scan unexpectedly found too few IDs: \(emitted.count)")
        let missingTypedIDs = emitted.filter { EventID(rawValue: $0) == nil }.sorted()
        let missingSpecs = emitted.filter { EventReferenceTable.specs[$0] == nil }.sorted()
        #expect(missingTypedIDs.isEmpty, "Literal custom events without EventID: \(missingTypedIDs.joined(separator: ", "))")
        #expect(missingSpecs.isEmpty, "Literal custom events without EventReferenceSpec: \(missingSpecs.joined(separator: ", "))")
    }

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func swiftSourceURLs(in root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                return nil
            }
            return url
        }
    }

    private static func captureEventNames(pattern: String, in source: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return Set(regex.matches(in: source, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[captureRange])
        })
    }
}
