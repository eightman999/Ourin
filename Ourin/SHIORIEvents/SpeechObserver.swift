import Foundation
import AppKit
import AVFoundation
import Speech

final class SpeechObserver {
    static let shared = SpeechObserver()
    private init() {}

    private var handler: ((ShioriEvent) -> Void)?
    private var timer: Timer?
    private var lastSpeaking: Bool?
    private var lastVoiceRecognitionStatus: String?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var recognitionSessionID = UUID()
    private var recognitionAuthorizationRequestInFlight = false
    private var recognitionStarting = false
    private var nextRecognitionAttempt = Date.distantPast
    private var lastRecognizedTranscript = ""

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
        stopRecognition()
        lastSpeaking = nil
        lastVoiceRecognitionStatus = nil
        speechRecognizer = nil
        recognitionAuthorizationRequestInFlight = false
        handler = nil
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

    /// 前回の部分認識結果との差分だけをイベントとして発火する。
    /// 部分結果が修正された場合は、確定結果になるまで送らない。
    static func incrementalRecognitionText(
        previous: String,
        current: String,
        isFinal: Bool
    ) -> String? {
        let normalizedPrevious = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCurrent.isEmpty, normalizedCurrent != normalizedPrevious else {
            return nil
        }

        if normalizedPrevious.isEmpty {
            return normalizedCurrent
        }
        if normalizedCurrent.hasPrefix(normalizedPrevious) {
            let suffix = String(normalizedCurrent.dropFirst(normalizedPrevious.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? nil : suffix
        }
        return isFinal ? normalizedCurrent : nil
    }

    private func poll() {
        let speaking = NSSpeechSynthesizer.isAnyApplicationSpeaking
        if lastSpeaking != speaking {
            lastSpeaking = speaking
            handler?(ShioriEvent(
                id: .OnSpeechSynthesisStatus,
                refs: [
                    "enabled": speaking ? "1" : "0",
                    "status": speaking ? "speaking" : "idle"
                ]
            ))
        }

        let authorization = SFSpeechRecognizer.authorizationStatus()
        let recognizerAvailable = SFSpeechRecognizer(locale: Locale.current)?.isAvailable ?? false
        let voiceStatus = Self.voiceRecognitionStatus(
            authorization: authorization,
            recognizerAvailable: recognizerAvailable
        )
        let recognitionEnabled = authorization == .authorized && recognizerAvailable
        let voiceStateKey = "\(recognitionEnabled ? "1" : "0"):\(voiceStatus)"
        if lastVoiceRecognitionStatus != voiceStateKey {
            lastVoiceRecognitionStatus = voiceStateKey
            handler?(ShioriEvent(
                id: .OnVoiceRecognitionStatus,
                refs: [
                    "enabled": recognitionEnabled ? "1" : "0",
                    "status": voiceStatus
                ]
            ))
        }

        switch authorization {
        case .notDetermined:
            requestSpeechAuthorizationIfNeeded()
        case .authorized where recognizerAvailable:
            startRecognitionIfNeeded()
        default:
            stopRecognition()
        }
    }

    private func requestSpeechAuthorizationIfNeeded() {
        guard !recognitionAuthorizationRequestInFlight else { return }
        recognitionAuthorizationRequestInFlight = true
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.handler != nil else { return }
                self.recognitionAuthorizationRequestInFlight = false
                self.poll()
            }
        }
    }

    private func startRecognitionIfNeeded() {
        guard handler != nil,
              !recognitionStarting,
              recognitionTask == nil,
              Date() >= nextRecognitionAttempt else { return }

        let recognizer = speechRecognizer ?? SFSpeechRecognizer(locale: Locale.current)
        guard let recognizer, recognizer.isAvailable else { return }
        speechRecognizer = recognizer
        recognitionStarting = true
        lastRecognizedTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            recognitionStarting = false
            nextRecognitionAttempt = Date().addingTimeInterval(2)
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        let sessionID = UUID()
        recognitionSessionID = sessionID
        recognitionRequest = request
        audioEngine = engine
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.recognitionSessionID == sessionID else { return }
                if let result {
                    self.consume(result)
                }
                if error != nil || result?.isFinal == true {
                    self.stopRecognition()
                    self.nextRecognitionAttempt = Date().addingTimeInterval(1)
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            recognitionStarting = false
        } catch {
            Log.info("[SpeechObserver] Failed to start microphone recognition: \(error)")
            recognitionStarting = false
            stopRecognition()
            nextRecognitionAttempt = Date().addingTimeInterval(2)
        }
    }

    private func consume(_ result: SFSpeechRecognitionResult) {
        let transcript = result.bestTranscription.formattedString
        let text = Self.incrementalRecognitionText(
            previous: lastRecognizedTranscript,
            current: transcript,
            isFinal: result.isFinal
        )
        lastRecognizedTranscript = transcript
        guard let text else { return }
        handler?(ShioriEvent(
            id: .OnVoiceRecognitionWord,
            refs: ["scopeID": "0", "word": text]
        ))
    }

    private func stopRecognition() {
        recognitionSessionID = UUID()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if let audioEngine {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        self.audioEngine = nil
        recognitionStarting = false
        lastRecognizedTranscript = ""
    }
}
