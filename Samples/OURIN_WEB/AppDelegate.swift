import AppKit
import Foundation
import ApplicationServices

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register handler for custom URL scheme via Apple Events (kAEGetURL)
        let aem = NSAppleEventManager.shared()
        aem.setEventHandler(self,
                            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                            forEventClass: AEEventClass(kInternetEventClass),
                            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                 withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        handleUkagakaLink(url: url)
    }

    // Minimal parser for "x-ukagaka-link:type=...&key=value..." style URLs.
    private func handleUkagakaLink(url: URL) {
        guard url.scheme?.lowercased() == "x-ukagaka-link" else { return }
        // The part after "x-ukagaka-link:" is the resource specifier (no "?")
        let schemePrefix = "x-ukagaka-link:"
        let full = url.absoluteString
        guard full.lowercased().hasPrefix(schemePrefix) else { return }
        let spec = String(full.dropFirst(schemePrefix.count))
        let params = parseForm(spec)

        switch params["type"]?.lowercased() {
        case "event":
            let ghost = params["ghost"] ?? ""
            let info = params["info"] ?? ""
            print("[Ourin] event for ghost=\(ghost), info=\(info)")
            // TODO: dispatch to SHIORI: OnXUkagakaLinkOpen (SecurityLevel=external, Reference0=info)
        case "install":
            if let enc = params["url"], let decoded = enc.removingPercentEncoding {
                print("[Ourin] install from URL: \(decoded)")
                // TODO: download .nar (https only), then install
            }
        case "homeurl":
            if let enc = params["url"], let decoded = enc.removingPercentEncoding {
                print("[Ourin] network update from homeurl: \(decoded)")
                // TODO: treat as update source, fetch then install
            }
        default:
            print("[Ourin] unsupported or missing type: \(params["type"] ?? "nil")")
        }
    }

    // Parses "a=b&c=d" form, percent-decoding keys/values.
    private func parseForm(_ s: String) -> [String:String] {
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
