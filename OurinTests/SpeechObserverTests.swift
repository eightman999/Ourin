import Speech
import Testing
@testable import Ourin

struct SpeechObserverTests {
    @Test
    func authorizedAvailableRecognitionIsReportedAsAvailable() {
        #expect(
            SpeechObserver.voiceRecognitionStatus(
                authorization: .authorized,
                recognizerAvailable: true
            ) == "available"
        )
    }

    @Test
    func authorizedUnavailableRecognitionIsReportedAsUnavailable() {
        #expect(
            SpeechObserver.voiceRecognitionStatus(
                authorization: .authorized,
                recognizerAvailable: false
            ) == "unavailable"
        )
    }

    @Test
    func deniedAndRestrictedStatesArePreserved() {
        #expect(
            SpeechObserver.voiceRecognitionStatus(
                authorization: .denied,
                recognizerAvailable: true
            ) == "denied"
        )
        #expect(
            SpeechObserver.voiceRecognitionStatus(
                authorization: .restricted,
                recognizerAvailable: true
            ) == "restricted"
        )
    }

    @Test
    func undeterminedAuthorizationIsNotReportedAsUnavailable() {
        #expect(
            SpeechObserver.voiceRecognitionStatus(
                authorization: .notDetermined,
                recognizerAvailable: false
            ) == "not_determined"
        )
    }

    @Test
    func automaticEventPollingNeverRequestsSpeechAuthorization() {
        #expect(
            !SpeechObserver.shouldRequestAuthorization(
                authorization: .notDetermined,
                explicitUserAction: false
            )
        )
    }

    @Test
    func explicitUserActionCanRequestUndeterminedSpeechAuthorization() {
        #expect(
            SpeechObserver.shouldRequestAuthorization(
                authorization: .notDetermined,
                explicitUserAction: true
            )
        )
        #expect(
            !SpeechObserver.shouldRequestAuthorization(
                authorization: .authorized,
                explicitUserAction: true
            )
        )
    }

    @Test
    func incrementalRecognitionReportsOnlyNewSuffix() {
        #expect(
            SpeechObserver.incrementalRecognitionText(
                previous: "こんにちは",
                current: "こんにちは世界",
                isFinal: false
            ) == "世界"
        )
        #expect(
            SpeechObserver.incrementalRecognitionText(
                previous: "こんにちは世界",
                current: "こんにちは世界",
                isFinal: true
            ) == nil
        )
    }

    @Test
    func correctedPartialRecognitionWaitsForFinalResult() {
        #expect(
            SpeechObserver.incrementalRecognitionText(
                previous: "おはよう",
                current: "おはようございます",
                isFinal: false
            ) == "ございます"
        )
        #expect(
            SpeechObserver.incrementalRecognitionText(
                previous: "こんにちは",
                current: "こんばんは",
                isFinal: false
            ) == nil
        )
        #expect(
            SpeechObserver.incrementalRecognitionText(
                previous: "こんにちは",
                current: "こんばんは",
                isFinal: true
            ) == "こんばんは"
        )
    }

    @Test
    func speechEventsUseUkadocReferenceOrder() {
        #expect(
            EventReferenceTable.params(forEvent: "OnSpeechSynthesisStatus", refs: [
                "enabled": "1",
                "status": "speaking"
            ]) == [
                "Reference0": "1",
                "Reference1": "speaking"
            ]
        )
        #expect(
            EventReferenceTable.params(forEvent: "OnVoiceRecognitionStatus", refs: [
                "enabled": "0",
                "status": "denied"
            ]) == [
                "Reference0": "0",
                "Reference1": "denied"
            ]
        )
        #expect(
            EventReferenceTable.params(forEvent: "OnVoiceRecognitionWord", refs: [
                "scopeID": "0",
                "word": "こんにちは"
            ]) == [
                "Reference0": "0",
                "Reference1": "こんにちは"
            ]
        )
    }
}
