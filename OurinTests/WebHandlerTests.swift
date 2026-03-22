import Foundation
import Testing
@testable import Ourin

struct WebHandlerTests {
    @Test
    func parseFormDecodesPlusAndPercentEncoding() throws {
        let parsed = WebHandler.parseForm("type=event&ghost=Emily+4&info=hello%20world")
        #expect(parsed["type"] == "event")
        #expect(parsed["ghost"] == "Emily 4")
        #expect(parsed["info"] == "hello world")
    }

    @Test
    func homeurlPostsNotificationWithoutAutoInstall() throws {
        let url = URL(string: "x-ukagaka-link:type=homeurl&url=https%3A%2F%2Fexample.com%2Fupdates2.dau&ghost=Emily")!
        let handler = WebHandler.shared

        var receivedURL: String?
        var receivedGhost: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .ourinWebHomeURLReceived,
            object: nil,
            queue: nil
        ) { note in
            receivedURL = note.userInfo?["url"] as? String
            receivedGhost = note.userInfo?["ghost"] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        handler.handleURL(url)
        #expect(receivedURL == "https://example.com/updates2.dau")
        #expect(receivedGhost == "Emily")
    }

    @Test
    func eventPostsNotificationWithGhostAndInfo() throws {
        let url = URL(string: "x-ukagaka-link:type=event&ghost=Emily&info=hello%20from%20web")!
        let handler = WebHandler.shared

        var receivedInfo: String?
        var receivedGhost: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .ourinWebEventReceived,
            object: nil,
            queue: nil
        ) { note in
            receivedInfo = note.userInfo?["info"] as? String
            receivedGhost = note.userInfo?["ghost"] as? String
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        handler.handleURL(url)
        #expect(receivedInfo == "hello from web")
        #expect(receivedGhost == "Emily")
    }
}
