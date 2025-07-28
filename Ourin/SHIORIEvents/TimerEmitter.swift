import Foundation

// TimerEmitter.swift
// Periodic timers for OnIdle and OnMinuteChange events

final class TimerEmitter {
    static let shared = TimerEmitter()
    private init() {}

    private var idleTimer: DispatchSourceTimer?
    private var minuteTimer: DispatchSourceTimer?
    private var handler: ((ShioriEvent) -> Void)?

    /// Start emitting timer based events
    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        self.handler = handler

        let idle = DispatchSource.makeTimerSource()
        idle.schedule(deadline: .now() + .seconds(1), repeating: .seconds(1))
        idle.setEventHandler { [weak self] in
            self?.handler?(ShioriEvent(id: .OnIdle, params: [:]))
        }
        idle.resume()
        idleTimer = idle

        let minute = DispatchSource.makeTimerSource()
        minute.schedule(deadline: .now() + .seconds(60), repeating: .seconds(60))
        minute.setEventHandler { [weak self] in
            self?.handler?(ShioriEvent(id: .OnMinuteChange, params: [:]))
        }
        minute.resume()
        minuteTimer = minute
    }

    /// Stop timers
    func stop() {
        idleTimer?.cancel(); idleTimer = nil
        minuteTimer?.cancel(); minuteTimer = nil
    }
}
