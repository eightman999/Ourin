import Foundation
import CoreGraphics
import Testing
@testable import Ourin

struct PowerObserverTests {
    @Test
    func convertsBatteryDictionaryToUkadocReferences() {
        let snapshot = PowerSnapshot.make(
            descriptions: [[
                "Transport Type": "Internal",
                "Power Source State": "Battery Power",
                "Current Capacity": NSNumber(value: 25),
                "Max Capacity": NSNumber(value: 100),
                "Time to Empty": NSNumber(value: 90),
                "Is Charging": NSNumber(value: false),
                "Is Present": NSNumber(value: true)
            ]],
            providingPowerSource: "Battery Power",
            lowPowerMode: false
        )

        #expect(snapshot.source == "Battery")
        #expect(snapshot.powerState == "offline")
        #expect(snapshot.batteryReferences == [
            "percent": "25",
            "remainingMinutes": "90",
            "powerState": "offline",
            "status": "low"
        ])
    }

    @Test
    func preservesChargingAndLowPowerFlags() {
        let snapshot = PowerSnapshot.make(
            descriptions: [[
                "Transport Type": "Internal",
                "Power Source State": "AC Power",
                "Current Capacity": NSNumber(value: 100),
                "Max Capacity": NSNumber(value: 100),
                "Time to Full Charge": NSNumber(value: 30),
                "Is Charging": NSNumber(value: true),
                "Is Present": NSNumber(value: true)
            ]],
            providingPowerSource: "AC Power",
            lowPowerMode: true
        )

        #expect(snapshot.batteryReferences["powerState"] == "online")
        #expect(snapshot.batteryReferences["remainingMinutes"] == "30")
        #expect(snapshot.batteryReferences["status"] == "high,charging,power_saving")
    }

    @Test
    func noBatteryIsExplicitAndDoesNotInventCapacity() {
        let snapshot = PowerSnapshot.make(
            descriptions: [],
            providingPowerSource: "AC Power",
            lowPowerMode: false
        )

        #expect(snapshot.percent == nil)
        #expect(snapshot.hasBattery == false)
        #expect(snapshot.batteryReferences["percent"] == "")
        #expect(snapshot.batteryReferences["remainingMinutes"] == "-1")
        #expect(snapshot.batteryReferences["status"] == "no_battery")
    }

    @Test
    func observerEventsDefaultToGetAndCanDeclareStartupNotify() {
        let regular = ShioriEvent(id: .OnDisplayChange, params: [:])
        let startup = ShioriEvent(
            id: .OnDisplayChange,
            params: [:],
            delivery: .notify,
            ignoreResponseScript: true
        )

        #expect(regular.delivery == .get)
        #expect(startup.delivery == .notify)
        #expect(startup.ignoreResponseScript == true)
    }

    @Test
    func systemSleepUsesNotifyForSuspendAndGetForSleep() {
        let events = SleepObserver.willSleepEvents()

        #expect(events.map(\.id) == [.OnSysSuspend, .OnSleep])
        #expect(events[0].delivery == .notify)
        #expect(events[0].ignoreResponseScript)
        #expect(events[1].delivery == .get)
        #expect(!events[1].ignoreResponseScript)
    }

    @Test
    func systemWakeAndFullScreenEventsCarryUkadocReasons() {
        let wakeEvents = SleepObserver.didWakeEvents()

        #expect(wakeEvents[0].id == .OnSysResume)
        #expect(wakeEvents[0].params == ["Reference0": "normal"])
        #expect(wakeEvents[1].id == .OnWake)

        let minimized = SessionObserver.fullScreenEvent(minimized: true)
        let restored = SessionObserver.fullScreenEvent(minimized: false)
        #expect(minimized.id == .OnFullScreenAppMinimize)
        #expect(minimized.params == ["Reference0": "fullscreen"])
        #expect(restored.id == .OnFullScreenAppRestore)
        #expect(restored.params == ["Reference0": "fullscreen"])
    }

    @Test
    func fullScreenEventsOnlyDescribeDetectedStateTransitions() {
        let application = FullScreenApplication(
            processIdentifier: 42,
            bundleIdentifier: "com.example.player",
            name: "Player"
        )

        #expect(SessionObserver.fullScreenTransitionEvents(previous: nil, current: nil).isEmpty)
        #expect(SessionObserver.fullScreenTransitionEvents(previous: nil, current: application).map(\.id) == [.OnFullScreenAppMinimize])
        #expect(SessionObserver.fullScreenTransitionEvents(previous: application, current: application).isEmpty)
        #expect(SessionObserver.fullScreenTransitionEvents(previous: application, current: nil).map(\.id) == [.OnFullScreenAppRestore])
    }

    @Test
    func fullScreenDetectionIgnoresNormalWindowsAndOurin() {
        let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let application = FullScreenApplication(
            processIdentifier: 42,
            bundleIdentifier: "com.example.player",
            name: "Player"
        )
        let normalWindow = FullScreenWindowSnapshot(
            ownerProcessIdentifier: application.processIdentifier,
            layer: 0,
            bounds: CGRect(x: 20, y: 20, width: 1400, height: 820),
            isOnscreen: true
        )
        #expect(SessionObserver.detectFullScreenApplication(
            windows: [normalWindow],
            displayBounds: [display],
            frontmostApplication: application,
            ownProcessIdentifier: 99
        ) == .none)

        let fullScreenWindow = FullScreenWindowSnapshot(
            ownerProcessIdentifier: application.processIdentifier,
            layer: 0,
            bounds: display,
            isOnscreen: true
        )
        #expect(SessionObserver.detectFullScreenApplication(
            windows: [fullScreenWindow],
            displayBounds: [display],
            frontmostApplication: application,
            ownProcessIdentifier: 99
        ) == .active(application))
        #expect(SessionObserver.detectFullScreenApplication(
            windows: [fullScreenWindow],
            displayBounds: [display],
            frontmostApplication: application,
            ownProcessIdentifier: application.processIdentifier
        ) == .none)
    }

    @Test
    func screenSaverEventsCarryConfiguredModuleReferences() {
        let info = ScreenSaverInfo.current(preferences: [
            "moduleDict": [
                "moduleName": "Flurry",
                "path": "/System/Library/Screen Savers/Flurry.saver"
            ],
            "idleTime": 600
        ])

        let start = SleepObserver.screenSaverStartEvent(info: info)
        let end = SleepObserver.screenSaverEndEvent(info: info)

        let expected = [
            "Reference0": "Flurry",
            "Reference1": "/System/Library/Screen Savers/Flurry.saver",
            "Reference2": "600"
        ]
        #expect(start.params == expected)
        #expect(start.delivery == .notify)
        #expect(start.ignoreResponseScript)
        #expect(end.params == expected)
        #expect(end.delivery == .get)
    }

    @Test
    func screenSaverNotificationValuesOverrideStoredSettings() {
        let info = ScreenSaverInfo.current(
            notificationUserInfo: [
                "moduleName": "Aerial",
                "modulePath": "/Library/Screen Savers/Aerial.saver",
                "timeoutSeconds": "90"
            ],
            preferences: [
                "moduleDict": [
                    "moduleName": "Flurry",
                    "path": "/System/Library/Screen Savers/Flurry.saver"
                ],
                "idleTime": 600
            ]
        )

        #expect(info == ScreenSaverInfo(
            name: "Aerial",
            path: "/Library/Screen Savers/Aerial.saver",
            timeoutSeconds: "90"
        ))
    }

    @Test
    func screenSaverInfoDoesNotInventUnavailableValues() {
        let info = ScreenSaverInfo.current(preferences: [:])

        #expect(info.name.isEmpty)
        #expect(info.path.isEmpty)
        #expect(info.timeoutSeconds.isEmpty)
        #expect(info.isEmpty)
    }
}
