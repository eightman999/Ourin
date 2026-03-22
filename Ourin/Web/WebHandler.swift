import AppKit
import Foundation
import ApplicationServices

// `x-ukagaka-link` スキームを処理するハンドラ。
// 詳細は docs/WEB_1.0M_SPEC.md を参照。

public extension Notification.Name {
    static let ourinWebInstallRequested = Notification.Name("OurinWebInstallRequested")
    static let ourinWebHomeURLReceived = Notification.Name("OurinWebHomeURLReceived")
    static let ourinWebEventReceived = Notification.Name("OurinWebEventReceived")
}

public final class WebHandler: NSObject {
    /// シングルトンインスタンス。アプリ全体で1つだけ生成して使う
    public static let shared = WebHandler()

    /// `kAEGetURL` イベントにハンドラを登録し、カスタムスキームを受理できるようにする
    public func register() {
        let manager = NSAppleEventManager.shared()
        manager.setEventHandler(self,
                                andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
                                forEventClass: AEEventClass(kInternetEventClass),
                                andEventID: AEEventID(kAEGetURL))
    }

    /// URL 受理イベントを処理する
    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor,
                                         withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        handleURL(url)
    }

    /// 受け取った URL を解析して個別処理に振り分ける
    func handleURL(_ url: URL) {
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
            var headers: [String: String] = ["SecurityLevel": "external"]
            if !ghost.isEmpty {
                headers["ReceiverGhostName"] = ghost
            }
            EventBridge.shared.notify(.OnXUkagakaLinkOpen, params: ["Reference0": info])
            _ = BridgeToSHIORI.handle(event: "OnXUkagakaLinkOpen", references: [info], headers: headers)
            NotificationCenter.default.post(
                name: .ourinWebEventReceived,
                object: self,
                userInfo: ["ghost": ghost, "info": info]
            )
        case "install":
            if let enc = params["url"], let decoded = enc.removingPercentEncoding {
                NSLog("[Ourin] install from URL \(decoded)")
                NotificationCenter.default.post(
                    name: .ourinWebInstallRequested,
                    object: self,
                    userInfo: ["url": decoded]
                )
                WebNarInstaller.install(from: decoded)
            }
        case "homeurl":
            if let enc = params["url"], let decoded = enc.removingPercentEncoding {
                NSLog("[Ourin] homeurl \(decoded)")
                NotificationCenter.default.post(
                    name: .ourinWebHomeURLReceived,
                    object: self,
                    userInfo: ["url": decoded, "ghost": params["ghost"] ?? ""]
                )
            }
        case "query":
            let ghost = params["ghost"] ?? ""
            let query = params["query"] ?? ""
            var headers: [String: String] = ["SecurityLevel": "external"]
            if !ghost.isEmpty {
                headers["ReceiverGhostName"] = ghost
            }
            EventBridge.shared.notify(.OnURLQuery, params: ["Reference0": query])
            _ = BridgeToSHIORI.handle(event: "OnURLQuery", references: [query], headers: headers)
            NotificationCenter.default.post(
                name: .ourinWebEventReceived,
                object: self,
                userInfo: ["ghost": ghost, "info": query, "type": "query"]
            )
        default:
            NSLog("[Ourin] unsupported type \(params["type"] ?? "nil")")
        }
    }

    /// HTMLフォーム形式の文字列を辞書に変換するヘルパー
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
