// OurinPluginEventBridge.swift (minimal skeleton)
import AppKit
import CoreGraphics

struct PluginFrame {
    var id: String
    var references: [String] = []
    func build() -> String {
        var lines: [String] = []
        lines.append("GET PLUGIN/2.0")
        lines.append("ID: \(id)")
        lines.append("Sender: Ourin")
        for (i, ref) in references.enumerated() {
            lines.append("Reference\(i): \(ref)")
        }
        lines.append("\n###\n")
        return lines.joined(separator: "\n")
    }
}

enum WindowIDMapper {
    static func ids(for windows: [NSWindow]) -> String {
        let ids = windows.map { String(CGWindowID($0.windowNumber)) }
        return ids.joined(separator: ",")
    }
}

final class PluginEventDispatcher {
    func onGhostBoot(windows: [NSWindow], ghostName: String, shellName: String, ghostID: String, pathPOSIX: String) {
        let ref0 = WindowIDMapper.ids(for: windows) // CGWindowID 列
        let frame = PluginFrame(id: "OnGhostBoot", references: [ref0, ghostName, shellName, ghostID, pathPOSIX])
        send(frame)
    }

    func onMenuExec(windows: [NSWindow], ghostName: String, shellName: String, ghostID: String, pathPOSIX: String) {
        let ref0 = WindowIDMapper.ids(for: windows)
        let frame = PluginFrame(id: "OnMenuExec", references: [ref0, ghostName, shellName, ghostID, pathPOSIX])
        send(frame)
    }

    private func send(_ frame: PluginFrame) {
        // TODO: deliver to PLUGIN/2.0 transport (dylib/XPC/IPC)
        print(frame.build())
    }
}
