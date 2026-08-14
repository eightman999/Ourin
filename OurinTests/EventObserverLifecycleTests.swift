import Foundation
import Testing
@testable import Ourin

struct EventObserverLifecycleTests {
    @Test @MainActor
    func timerRestartReestablishesMinuteAndHourEvents() {
        let emitter = TimerEmitter()
        emitter.stop()

        var eventsAfterStop: [ShioriEvent] = []
        emitter.start { eventsAfterStop.append($0) }
        emitter.stop()
        emitter.tick(now: Date(timeIntervalSince1970: 0))
        #expect(eventsAfterStop.isEmpty)

        var restartedEvents: [ShioriEvent] = []
        emitter.start { restartedEvents.append($0) }
        emitter.tick(now: Date())
        emitter.stop()

        #expect(restartedEvents.contains { $0.id == .OnMinuteChange })
        #expect(restartedEvents.contains { $0.id == .OnHourTimeSignal })
    }
}
