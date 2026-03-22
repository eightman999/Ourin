import Foundation
import AppKit

final class SpeechObserver {
    static let shared = SpeechObserver()
    private init() {}

    private var handler: ((ShioriEvent) -> Void)?
    private var timer: Timer?
    private var lastSpeaking: Bool?
    private var emittedVoiceStatus = false

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
        emittedVoiceStatus = false
    }

    private func poll() {
        let speaking = NSSpeechSynthesizer.isAnyApplicationSpeaking
        if lastSpeaking != speaking {
            lastSpeaking = speaking
            handler?(ShioriEvent(
                id: .OnSpeechSynthesisStatus,
                params: ["Reference0": speaking ? "speaking" : "idle"]
            ))
        }
        if !emittedVoiceStatus {
            emittedVoiceStatus = true
            handler?(ShioriEvent(
                id: .OnVoiceRecognitionStatus,
                params: ["Reference0": "unavailable"]
            ))
        }
    }
}
