import Foundation
import AppKit

final class DeviceObserver {
    static let shared = DeviceObserver()
    private init() {}

    private var handler: ((ShioriEvent) -> Void)?
    private var mountedObserver: NSObjectProtocol?
    private var unmountedObserver: NSObjectProtocol?

    func start(_ handler: @escaping (ShioriEvent) -> Void) {
        stop()
        self.handler = handler
        let center = NSWorkspace.shared.notificationCenter

        mountedObserver = center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let path = (notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path ?? ""
            self.handler?(ShioriEvent(id: .OnDeviceArrival, params: ["Reference0": path]))
        }

        unmountedObserver = center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let path = (notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.path ?? ""
            self.handler?(ShioriEvent(id: .OnDeviceRemove, params: ["Reference0": path]))
        }
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        if let mountedObserver {
            center.removeObserver(mountedObserver)
            self.mountedObserver = nil
        }
        if let unmountedObserver {
            center.removeObserver(unmountedObserver)
            self.unmountedObserver = nil
        }
    }
}
