import Foundation
import AppKit
import AVFoundation
import Speech

final class SpeechObserver {
    static let shared = SpeechObserver()
    static let authorizationStatusDidChangeNotification = Notification.Name(
        "OurinSpeechAuthorizationStatusDidChange"
    )
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
    // AVAudioEngine の入力ノード取得は CoreAudio の応答待ちでブロックすることがある。
    // EventBridge の開始やメインスレッド上のイベント配送を止めないため、認識開始だけを
    // 専用の直列キューで実行する。
    private let recognitionQueue = DispatchQueue(
        label: "jp.ourin.speech-recognition",
        qos: .utility
    )

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

    /// 権限要求は、起動時の自動イベントではなくユーザー操作からだけ許可する。
    /// TCC は usage description が欠落したプロセスを SIGABRT で終了させるため、
    /// 自動イベントのポーリングから requestAuthorization を呼び出してはならない。
    static func shouldRequestAuthorization(
        authorization: SFSpeechRecognizerAuthorizationStatus,
        explicitUserAction: Bool
    ) -> Bool {
        explicitUserAction && authorization == .notDetermined
    }

    /// 設定画面などの明示的なユーザー操作から音声認識権限を要求する。
    /// 自動イベント開始時には呼び出さないこと。
    func requestSpeechAuthorization() {
        let request = { [weak self] in
            guard let self else { return }
            let authorization = SFSpeechRecognizer.authorizationStatus()
            guard Self.shouldRequestAuthorization(
                authorization: authorization,
                explicitUserAction: true
            ) else {
                self.notifyAuthorizationStatusChange(authorization)
                return
            }
            guard !self.recognitionAuthorizationRequestInFlight else { return }
            self.recognitionAuthorizationRequestInFlight = true
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.recognitionAuthorizationRequestInFlight = false
                    self.notifyAuthorizationStatusChange(status)
                    if self.handler != nil {
                        self.poll()
                    }
                }
            }
        }

        if Thread.isMainThread {
            request()
        } else {
            DispatchQueue.main.async(execute: request)
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
        // 未許可状態では認識器を生成しない。自動イベント開始時のTCCアクセスを避け、
        // 認識器はユーザーが権限を許可した後のポーリングで初めて生成する。
        let recognizerAvailable = authorization == .authorized
            ? (SFSpeechRecognizer(locale: Locale.current)?.isAvailable ?? false)
            : false
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
        case .authorized where recognizerAvailable:
            startRecognitionIfNeeded()
        default:
            stopRecognition()
        }
    }

    private func notifyAuthorizationStatusChange(_ status: SFSpeechRecognizerAuthorizationStatus) {
        NotificationCenter.default.post(
            name: Self.authorizationStatusDidChangeNotification,
            object: status.rawValue
        )
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

        let sessionID = UUID()
        recognitionSessionID = sessionID

        recognitionQueue.async { [weak self] in
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                DispatchQueue.main.async {
                    guard let self, self.recognitionSessionID == sessionID else { return }
                    self.recognitionStarting = false
                    self.nextRecognitionAttempt = Date().addingTimeInterval(2)
                }
                return
            }

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
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
            } catch {
                task.cancel()
                engine.stop()
                inputNode.removeTap(onBus: 0)
                DispatchQueue.main.async {
                    guard let self, self.recognitionSessionID == sessionID else { return }
                    Log.info("[SpeechObserver] Failed to start microphone recognition: \(error)")
                    self.recognitionStarting = false
                    self.nextRecognitionAttempt = Date().addingTimeInterval(2)
                }
                return
            }

            DispatchQueue.main.async {
                guard let self,
                      self.handler != nil,
                      self.recognitionSessionID == sessionID else {
                    task.cancel()
                    engine.stop()
                    inputNode.removeTap(onBus: 0)
                    return
                }
                self.recognitionRequest = request
                self.audioEngine = engine
                self.recognitionTask = task
                self.recognitionStarting = false
            }
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
