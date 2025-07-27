import AppKit
import Foundation
import ApplicationServices

public final class WebHandler: NSObject {
    public static let shared = WebHandler()

    /// Register kAEGetURL handler for the custom scheme
    public func register() {
        let manager = NSAppleEventManager.shared()
        manager.setEventHandler(self,
                                andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                                forEventClass: AEEventClass(kInternetEventClass),
                                andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                         withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        handle(url: url)
    }

    private func handle(url: URL) {
        guard url.scheme?.lowercased() == "x-ukagaka-link" else { return }
        let schemePrefix = "x-ukagaka-link:"
        let full = url.absoluteString
        guard full.lowercased().hasPrefix(schemePrefix) else { return }
        let spec = String(full.dropFirst(schemePrefix.count))
        let params = WebHandler.parseForm(spec)

        switch params["type"]?.lowercased() {
        case "event":
            let ghost = params["ghost"] ?? ""
            let info = params["info"] ?? ""
            NSLog("[Ourin] event ghost=\(ghost) info=\(info)")
            _ = BridgeToSHIORI.handle(event: "OnXUkagakaLinkOpen", references: [info])
        case "install":
            if let enc = params["url"], let decoded = enc.removingPercentEncoding {
                NSLog("[Ourin] install from URL \(decoded)")
                NarInstaller.install(from: decoded)
            }
        case "homeurl":
            if let enc = params["url"], let decoded = enc.removingPercentEncoding {
                NSLog("[Ourin] homeurl \(decoded)")
                NarInstaller.install(from: decoded)
            }
        default:
            NSLog("[Ourin] unsupported type \(params["type"] ?? "nil")")
        }
    }

    static func parseForm(_ s: String) -> [String:String] {
        var dict: [String:String] = [:]
        for pair in s.split(separator: "&") {
            if let eq = pair.firstIndex(of: "=") {
                let k = String(pair[..<eq])
                let v = String(pair[pair.index(after: eq)...])
                let kd = k.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? k
                let vd = v.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? v
                dict[kd] = vd
            } else {
                let key = String(pair)
                dict[key] = ""
            }
        }
        return dict
    }
}
