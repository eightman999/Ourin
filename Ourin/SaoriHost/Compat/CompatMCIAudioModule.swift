import AVFoundation
import Foundation

/// mciaudio（MIY 氏作。SSP の互換モジュールは loop も持つ）。音声ファイルの再生。
///
/// - load ファイル名: 読み込む（ghost/master からの相対パス。`\` 区切り・絶対パスも可）
/// - play: 再生する。再生中なら一時停止、一時停止中なら再開（トグル）
/// - loop: play と同じだが、終わりまで来たら先頭から繰り返す
/// - stop: 止める（次の play は先頭から）
/// 戻り値は無い（204）。ゴーストなしの呼び出しでは 400（ghost required）。
final class CompatMCIAudioModule: CompatSaoriModule {
    private let environment: CompatSaoriEnvironment
    private var file: URL?
    private var player: CompatAudioPlayer?
    private let lock = NSLock()

    init(environment: CompatSaoriEnvironment) {
        self.environment = environment
    }

    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult {
        guard let command = arguments.first?.lowercased() else { return .badRequest }
        guard ["load", "play", "loop", "stop"].contains(command) else { return .badRequest }
        guard environment.hasGhost else { return .ghostRequired }
        lock.lock(); defer { lock.unlock() }
        switch command {
        case "load":
            guard arguments.count >= 2, let url = environment.resolve(arguments[1]) else { return .badRequest }
            player?.stop()
            player = nil
            file = url
        case "play", "loop":
            if let player, player.state != .stopped {
                // 再生中なら一時停止、一時停止中なら再開する。
                if player.state == .playing { player.pause() } else { player.resume() }
                return .noContent
            }
            guard let file, FileManager.default.fileExists(atPath: file.path) else { return .noContent }
            if player == nil { player = CompatSaoriHooks.makeAudioPlayer(file) }
            player?.start(looping: command == "loop")
        default: // stop
            player?.stop()
        }
        return .noContent
    }

    func unload() {
        lock.lock(); defer { lock.unlock() }
        player?.stop()
        player = nil
    }
}

enum CompatAudioState {
    case stopped, playing, paused
}

/// 再生の部品（テストでは差し替える）。
protocol CompatAudioPlayer: AnyObject {
    var state: CompatAudioState { get }
    func start(looping: Bool)
    func pause()
    func resume()
    func stop()
}

/// AVFoundation での再生。MIDI（.mid / .midi）は AVMIDIPlayer、それ以外は AVAudioPlayer。
final class CompatSystemAudioPlayer: NSObject, CompatAudioPlayer, AVAudioPlayerDelegate {
    private let url: URL
    private var audio: AVAudioPlayer?
    private var midi: AVMIDIPlayer?
    private var looping = false
    private let lock = NSLock()
    private var currentState = CompatAudioState.stopped

    init?(url: URL) {
        self.url = url
        super.init()
        if ["mid", "midi"].contains(url.pathExtension.lowercased()) {
            guard let player = try? AVMIDIPlayer(contentsOf: url, soundBankURL: nil) else { return nil }
            midi = player
        } else {
            guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
            player.delegate = self
            audio = player
        }
    }

    var state: CompatAudioState {
        lock.lock(); defer { lock.unlock() }
        return currentState
    }

    private func setState(_ state: CompatAudioState) {
        lock.lock(); currentState = state; lock.unlock()
    }

    func start(looping: Bool) {
        self.looping = looping
        if let audio {
            audio.currentTime = 0
            audio.numberOfLoops = looping ? -1 : 0
            audio.play()
        } else if let midi {
            midi.currentPosition = 0
            playMIDI(midi)
        }
        setState(.playing)
    }

    private func playMIDI(_ player: AVMIDIPlayer) {
        player.play { [weak self] in
            guard let self, self.state == .playing else { return }
            if self.looping {
                DispatchQueue.main.async {
                    player.currentPosition = 0
                    self.playMIDI(player)
                }
            } else {
                self.setState(.stopped)
            }
        }
    }

    func pause() {
        audio?.pause()
        midi?.stop() // AVMIDIPlayer の stop は位置を保つ（一時停止になる）
        setState(.paused)
    }

    func resume() {
        if let audio {
            audio.play()
        } else if let midi {
            setState(.playing)
            playMIDI(midi)
        }
        setState(.playing)
    }

    func stop() {
        setState(.stopped)
        audio?.stop()
        audio?.currentTime = 0
        midi?.stop()
        midi?.currentPosition = 0
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        setState(.stopped)
    }
}
