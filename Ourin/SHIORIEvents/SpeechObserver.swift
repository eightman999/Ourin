import Foundation
import AppKit
import Speech

final class SpeechObserver {
    static let shared = SpeechObserver()
    private init() {}

    private var handler: ((ShioriEvent) -> Void)?
    private var timer: Timer?
    private var lastSpeaking: Bool?
    private var lastVoiceRecognitionStatus: String?

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastSpeaking = nil
        lastVoiceRecognitionStatus = nil
    }

    /// 音声認識の権限と認識サービスの可用性を、SHIORIへ渡す状態名へ変換する。
    /// 権限要求はここでは行わない（自動イベント開始時にOSダイアログを出さない）。
    static func voiceRecognitionStatus(
        authorization: SFSpeechRecognizerAuthorizationStatus,
        recognizerAvailable: Bool
    ) -> String {
        switch authorization {
        case .authorized:
            return recognizerAvailable ? "available" : "unavailable"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .notDetermined:
            return "not_determined"
        @unknown default:
            return "unavailable"
        }
    }

    private func poll() {
        let speaking = NSSpeechSynthesizer.isAnyApplicationSpeaking
        if lastSpeaking != speaking {
            lastSpeaking = speaking
            handler?(ShioriEvent(
                id: .OnSpeechSynthesisStatus,
                refs: ["status": speaking ? "speaking" : "idle"]
            ))
        }

        let authorization = SFSpeechRecognizer.authorizationStatus()
        let recognizerAvailable = SFSpeechRecognizer(locale: Locale.current)?.isAvailable ?? false
        let voiceStatus = Self.voiceRecognitionStatus(
            authorization: authorization,
            recognizerAvailable: recognizerAvailable
        )
        if lastVoiceRecognitionStatus != voiceStatus {
            lastVoiceRecognitionStatus = voiceStatus
            handler?(ShioriEvent(
                id: .OnVoiceRecognitionStatus,
                refs: ["status": voiceStatus]
            ))
        }
    }
}
