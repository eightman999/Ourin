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
}
