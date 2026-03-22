import Foundation
import GameController

final class GamepadObserver {
    static let shared = GamepadObserver()
    private init() {}

    private var handler: ((ShioriEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        self.handler = handler
        stop()
        self.handler = handler

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let controller = notification.object as? GCController else { return }
            self.attachHandlers(to: controller)
            self.handler?(ShioriEvent(
                id: .OnGamepadConnected,
                params: ["Reference0": controller.vendorName ?? "Unknown"]
            ))
        })

        observers.append(center.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let controller = notification.object as? GCController else { return }
            self.handler?(ShioriEvent(
                id: .OnGamepadDisconnected,
                params: ["Reference0": controller.vendorName ?? "Unknown"]
            ))
        })

        GCController.startWirelessControllerDiscovery(completionHandler: nil)
        for controller in GCController.controllers() {
            attachHandlers(to: controller)
        }
    }

    func stop() {
        let center = NotificationCenter.default
        for token in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
        GCController.stopWirelessControllerDiscovery()
    }

    private func attachHandlers(to controller: GCController) {
        if let gamepad = controller.extendedGamepad {
            attachButtonHandlers(controller: controller, gamepad: gamepad)
            attachAxisHandlers(controller: controller, gamepad: gamepad)
            return
        }
        if let gamepad = controller.microGamepad {
            gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
                self?.emitAxis(controller: controller, axis: "dpad", x: x, y: y)
            }
            gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.emitButton(controller: controller, button: "A", pressed: pressed)
            }
            gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                self?.emitButton(controller: controller, button: "X", pressed: pressed)
            }
        }
    }

    private func attachButtonHandlers(controller: GCController, gamepad: GCExtendedGamepad) {
        gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in self?.emitButton(controller: controller, button: "A", pressed: pressed) }
        gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in self?.emitButton(controller: controller, button: "B", pressed: pressed) }
        gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in self?.emitButton(controller: controller, button: "X", pressed: pressed) }
        gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in self?.emitButton(controller: controller, button: "Y", pressed: pressed) }
        gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in self?.emitButton(controller: controller, button: "L1", pressed: pressed) }
        gamepad.rightShoulder.pressedChangedHandler = { [weak self] _, _, pressed in self?.emitButton(controller: controller, button: "R1", pressed: pressed) }
        gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in self?.emitButton(controller: controller, button: "L2", pressed: pressed) }
        gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in self?.emitButton(controller: controller, button: "R2", pressed: pressed) }
    }

    private func attachAxisHandlers(controller: GCController, gamepad: GCExtendedGamepad) {
        gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.emitAxis(controller: controller, axis: "leftThumbstick", x: x, y: y)
        }
        gamepad.rightThumbstick.valueChangedHandler = { [weak self] _, x, y in
            self?.emitAxis(controller: controller, axis: "rightThumbstick", x: x, y: y)
        }
        gamepad.dpad.valueChangedHandler = { [weak self] _, x, y in
            self?.emitAxis(controller: controller, axis: "dpad", x: x, y: y)
        }
    }

    private func emitButton(controller: GCController, button: String, pressed: Bool) {
        handler?(ShioriEvent(
            id: pressed ? .OnGamepadButtonDown : .OnGamepadButtonUp,
            params: [
                "Reference0": button,
                "Reference1": controller.vendorName ?? "Unknown"
            ]
        ))
    }

    private func emitAxis(controller: GCController, axis: String, x: Float, y: Float) {
        handler?(ShioriEvent(
            id: .OnGamepadAxisMove,
            params: [
                "Reference0": axis,
                "Reference1": String(x),
                "Reference2": String(y),
                "Reference3": controller.vendorName ?? "Unknown"
            ]
        ))
    }
}
