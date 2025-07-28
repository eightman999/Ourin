import Foundation

/// SystemLoadObserver.swift
/// Periodically check CPU and memory usage to dispatch SHIORI events
final class SystemLoadObserver {
    static let shared = SystemLoadObserver()
    private init() {}

    private var timer: DispatchSourceTimer?
    private var handler: ((ShioriEvent) -> Void)?
    private var cpuHigh = false
    private var memHigh = false
    private let provider = SystemPropertyProvider()

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        self.handler = handler
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.check()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel(); timer = nil
    }

    private func check() {
        if let loadStr = provider.get(key: "cpu.load"), let load = Double(loadStr) {
            let high = load > 80
            if high != cpuHigh {
                cpuHigh = high
                let id: EventID = high ? .OnCPULoadHigh : .OnCPULoadLow
                handler?(ShioriEvent(id: id, params: ["Load": String(Int(load))]))
            }
        }
        if let memStr = provider.get(key: "memory.load"), let load = Double(memStr) {
            let high = load > 80
            if high != memHigh {
                memHigh = high
                let id: EventID = high ? .OnMemoryLoadHigh : .OnMemoryLoadLow
                handler?(ShioriEvent(id: id, params: ["Load": String(Int(load))]))
            }
        }
    }
}
