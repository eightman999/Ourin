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
}
