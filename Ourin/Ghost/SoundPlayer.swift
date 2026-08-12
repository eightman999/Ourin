import Foundation
import AVFoundation

/// AVAudioPlayer をラップした音声再生インスタンス。
/// NSSound では対応できなかった --rate / --balance / --seektime を実現する。
/// 同一ファイル名で複数同時再生できるよう、GhostManager 側はファイル名ごとに配列で保持する。
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    let filename: String
    private let player: AVAudioPlayer
    private(set) var loops = false
    private(set) var isPaused = false
    private(set) var didFinish = false
    private var isStopped = false

    /// GhostManager が自然終了・ループ境界・デコードエラーをイベントへ接続する。
    var onFinish: ((SoundPlayer, Bool) -> Void)?
    var onLoop: ((SoundPlayer) -> Void)?
    var onError: ((SoundPlayer, Int, String) -> Void)?

    init?(filename: String, url: URL, options: SoundPlaybackOptions) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else {
            Log.info("[SoundPlayer] Failed to load audio: \(filename)")
            return nil
        }
        self.filename = filename
        self.player = player
        super.init()
        player.delegate = self
        player.prepareToPlay()
        apply(options: options)
    }

    var isPlaying: Bool { player.isPlaying }
    var duration: TimeInterval { player.duration }
    var currentTime: TimeInterval { player.currentTime }
    /// 外部には無限ループとして見せる。内部は delegate で周回境界を検出するため
    /// AVAudioPlayer 自動ループではなく 1 周ずつ再開する。
    var numberOfLoops: Int { loops ? -1 : 0 }
    var effectiveVolume: Float { player.volume }
    var effectiveBalance: Float { player.pan }
    var effectiveRate: Float { player.rate }
    var isRateEnabled: Bool { player.enableRate }

    func play() {
        isStopped = false
        didFinish = false
        isPaused = false
        // play() は再生開始前も currentTime を進めるため失敗時のみログに残す。
        if !player.play() {
            Log.info("[SoundPlayer] play() failed: \(filename)")
            didFinish = true
            onError?(self, -1, "play_failed")
        }
    }

    func pause() {
        guard player.isPlaying else { return }
        player.pause()
        isPaused = true
    }

    func resume() {
        guard isPaused, !player.isPlaying else { return }
        isPaused = false
        if !player.play() {
            Log.info("[SoundPlayer] resume() failed: \(filename)")
            didFinish = true
            onError?(self, -1, "resume_failed")
        }
    }

    func stop() {
        isStopped = true
        player.stop()
        player.currentTime = 0
        isPaused = false
        didFinish = false
    }

    func setLoop(_ loop: Bool) {
        loops = loop
        // AVAudioPlayer の numberOfLoops=-1 では周回境界の delegate が通知されないため、
        // 1周ごとに再生を再開して OnSoundLoop を正確に発火できるようにする。
        player.numberOfLoops = 0
    }

    /// 再生中のオプション変更（\![sound,option,*]）。
    /// - volume: 0..1
    /// - balance: -1..1（pan）
    /// - rate: 0.01..100.0。enableRate を先に立ててから rate を設定する。
    /// - seektime: 絶対/相対シーク（再生中も反映）
    func apply(options: SoundPlaybackOptions) {
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
        let duration = player.duration
        guard duration.isFinite, duration > 0 else {
            // メタデータ未確定でも破棄せず 0 起点へ。
            player.currentTime = 0
            return
        }
        let clamped = { (value: TimeInterval) -> TimeInterval in
            max(0, min(value, duration))
        }
        switch target {
        case .absolute(let seconds):
            player.currentTime = clamped(seconds)
        case .relative(let delta):
            player.currentTime = clamped(player.currentTime + delta)
        }
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
