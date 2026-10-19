import Foundation
import AVFoundation

/// AVAudioPlayer をラップした音声再生インスタンス。
/// NSSound では対応できなかった --rate / --balance / --seektime を実現する。
/// 同一ファイル名で複数同時再生できるよう、GhostManager 側はファイル名ごとに配列で保持する。
/// リモート URL（http/https）は AVPlayer でストリーミング再生する。
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    let filename: String
    private let localPlayer: AVAudioPlayer?
    private let remotePlayer: AVPlayer?
    private var remoteItem: AVPlayerItem?
    private var remoteEndObserver: NSObjectProtocol?
    private var remoteStatusObserver: NSKeyValueObservation?
    private(set) var loops = false
    private(set) var isPaused = false
    private(set) var didFinish = false
    private var isStopped = false

    /// GhostManager が自然終了・ループ境界・デコードエラーをイベントへ接続する。
    var onFinish: ((SoundPlayer, Bool) -> Void)?
    var onLoop: ((SoundPlayer) -> Void)?
    var onError: ((SoundPlayer, Int, String) -> Void)?

    /// リモート URL かどうかで再生基盤を選択する。
    /// - Parameters:
    ///   - isRemote: リモートなら AVPlayer、ローカルなら AVAudioPlayer。
    init?(filename: String, url: URL, options: SoundPlaybackOptions, isRemote: Bool = false) {
        self.filename = filename
        if isRemote {
            self.remotePlayer = AVPlayer(url: url)
            self.localPlayer = nil
        } else {
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                Log.info("[SoundPlayer] Failed to load audio: \(filename)")
                return nil
            }
            self.localPlayer = player
            self.remotePlayer = nil
        }
        super.init()

        if let localPlayer {
            localPlayer.delegate = self
            localPlayer.prepareToPlay()
            apply(options: options)
        } else {
            observeRemotePlayback()
        }
    }

    var isPlaying: Bool {
        if let localPlayer { return localPlayer.isPlaying }
        return remotePlayer?.timeControlStatus == .playing
    }
    var duration: TimeInterval {
        if let localPlayer { return localPlayer.duration }
        let seconds = remoteItem?.duration.seconds
        return (seconds?.isFinite ?? false) ? seconds! : 0
    }
    var currentTime: TimeInterval {
        if let localPlayer { return localPlayer.currentTime }
        let seconds = remotePlayer?.currentTime().seconds
        return (seconds?.isFinite ?? false) ? seconds! : 0
    }
    /// 外部には無限ループとして見せる。内部は delegate で周回境界を検出するため
    /// AVAudioPlayer 自動ループではなく 1 周ずつ再開する。
    var numberOfLoops: Int { loops ? -1 : 0 }
    var effectiveVolume: Float {
        if let localPlayer { return localPlayer.volume }
        return remotePlayer?.volume ?? 0
    }
    var effectiveBalance: Float {
        if let localPlayer { return localPlayer.pan }
        return 0
    }
    var effectiveRate: Float {
        if let localPlayer { return localPlayer.rate }
        return remotePlayer?.rate ?? 1
    }
    var isRateEnabled: Bool {
        if let localPlayer { return localPlayer.enableRate }
        return remotePlayer?.currentItem?.canPlayFastForward ?? false
    }

    func play() {
        isStopped = false
        didFinish = false
        isPaused = false
        if let localPlayer {
            // play() は再生開始前も currentTime を進めるため失敗時のみログに残す。
            if !localPlayer.play() {
                Log.info("[SoundPlayer] play() failed: \(filename)")
                didFinish = true
                onError?(self, -1, "play_failed")
            }
        } else {
            remotePlayer?.play()
        }
    }

    func pause() {
        if let localPlayer {
            guard localPlayer.isPlaying else { return }
            localPlayer.pause()
            isPaused = true
        } else {
            remotePlayer?.pause()
            isPaused = true
        }
    }

    func resume() {
        if let localPlayer {
            guard isPaused, !localPlayer.isPlaying else { return }
            isPaused = false
            if !localPlayer.play() {
                Log.info("[SoundPlayer] resume() failed: \(filename)")
                didFinish = true
                onError?(self, -1, "resume_failed")
            }
        } else {
            guard isPaused else { return }
            isPaused = false
            remotePlayer?.play()
        }
    }

    func stop() {
        isStopped = true
        if let localPlayer {
            localPlayer.stop()
            localPlayer.currentTime = 0
        } else {
            remotePlayer?.pause()
            remotePlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        isPaused = false
        didFinish = false
    }

    func setLoop(_ loop: Bool) {
        loops = loop
        // AVAudioPlayer の numberOfLoops=-1 では周回境界の delegate が通知されないため、
        // 1周ごとに再生を再開して OnSoundLoop を正確に発火できるようにする。
        if let localPlayer {
            localPlayer.numberOfLoops = 0
        }
    }

    /// 再生中のオプション変更（\![sound,option,*]）。
    /// - volume: 0..1
    /// - balance: -1..1（pan）
    /// - rate: 0.01..100.0。enableRate を先に立ててから rate を設定する。
    /// - seektime: 絶対/相対シーク（再生中も反映）
    func apply(options: SoundPlaybackOptions) {
        if let localPlayer {
            applyLocal(options: options, to: localPlayer)
        } else if let remotePlayer {
            if let volume = options.volume {
                remotePlayer.volume = volume
            }
            if let rate = options.rate {
                remotePlayer.rate = max(0.01, rate)
            }
            if let seektime = options.seektime {
                applyRemoteSeek(seektime, to: remotePlayer)
            }
            // balance は AVPlayer に pan が無いため無視（ローカル専用オプション）。
        }
    }

    private func applyLocal(options: SoundPlaybackOptions, to player: AVAudioPlayer) {
        if let volume = options.volume {
            player.volume = volume
        }
        if let balance = options.balance {
            player.pan = balance
        }
        if let rate = options.rate {
            player.enableRate = true
            player.rate = max(0.01, rate)
        }
        if let seektime = options.seektime {
            applySeek(seektime)
        }
    }

    private func applySeek(_ target: SeekTime) {
        guard let localPlayer else { return }
        let duration = localPlayer.duration
        guard duration.isFinite, duration > 0 else {
            // メタデータ未確定でも破棄せず 0 起点へ。
            localPlayer.currentTime = 0
            return
        }
        let clamped = { (value: TimeInterval) -> TimeInterval in
            max(0, min(value, duration))
        }
        switch target {
        case .absolute(let seconds):
            localPlayer.currentTime = clamped(seconds)
        case .relative(let delta):
            localPlayer.currentTime = clamped(localPlayer.currentTime + delta)
        }
    }

    private func applyRemoteSeek(_ target: SeekTime, to player: AVPlayer) {
        let current = player.currentTime().seconds
        let targetTime: Double
        switch target {
        case .absolute(let seconds):
            targetTime = seconds
        case .relative(let delta):
            targetTime = current + delta
        }
        let clamped = max(0, targetTime)
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    // MARK: - Remote playback (AVPlayer)

    private func observeRemotePlayback() {
        guard let remotePlayer else { return }
        remoteItem = remotePlayer.currentItem
        remoteStatusObserver = remoteItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self, !self.isStopped else { return }
            if item.status == .failed {
                self.didFinish = true
                self.isPaused = false
                let nsError = item.error as NSError?
                self.onError?(self, nsError?.code ?? -1, nsError?.localizedDescription ?? "stream_error")
            }
        }
        if let remoteItem {
            remoteEndObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: remoteItem,
                queue: .main
            ) { [weak self] _ in
                self?.handleRemoteEnd()
            }
        }
    }

    private func handleRemoteEnd() {
        guard !isPaused, !isStopped else { return }
        if loops {
            remotePlayer?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            remotePlayer?.play()
            onLoop?(self)
            return
        }
        didFinish = true
        isPaused = false
        onFinish?(self, true)
    }

    deinit {
        if let remoteEndObserver {
            NotificationCenter.default.removeObserver(remoteEndObserver)
        }
        remoteStatusObserver?.invalidate()
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard !isPaused, !isStopped else { return }
        if loops && flag {
            player.currentTime = 0
            guard player.play() else {
                didFinish = true
                onError?(self, -1, "loop_restart_failed")
                onFinish?(self, false)
                return
            }
            onLoop?(self)
            return
        }

        didFinish = true
        isPaused = false
        onFinish?(self, flag)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard !isStopped else { return }
        didFinish = true
        isPaused = false
        let nsError = error as NSError?
        onError?(self, nsError?.code ?? -1, nsError?.localizedDescription ?? "decode_error")
    }
}
