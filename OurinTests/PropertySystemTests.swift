import Testing
@testable import Ourin

/// Tests for the Property System
struct PropertySystemTests {

    @Test("System properties - Date/Time")
    func testSystemDateTime() {
        let provider = SystemPropertyProvider()

        // Year should be 4 digits
        if let year = provider.get(key: "year"), let yearInt = Int(year) {
            #expect(yearInt >= 2024 && yearInt <= 2030)
        } else {
            Issue.record("Year property should return valid integer")
        }

        // Month should be 1-12
        if let month = provider.get(key: "month"), let monthInt = Int(month) {
            #expect(monthInt >= 1 && monthInt <= 12)
        } else {
            Issue.record("Month property should return valid integer")
        }

        // Day should be 1-31
        if let day = provider.get(key: "day"), let dayInt = Int(day) {
            #expect(dayInt >= 1 && dayInt <= 31)
        } else {
            Issue.record("Day property should return valid integer")
        }
    }

    @Test("System properties - OS Info")
    func testSystemOSInfo() {
        let provider = SystemPropertyProvider()

        // OS type should be macOS
        let osType = provider.get(key: "os.type")
        #expect(osType == "macOS")

        // OS name should contain "macOS"
        if let osName = provider.get(key: "os.name") {
            #expect(osName.contains("macOS"))
        } else {
            Issue.record("OS name should not be nil")
        }
    }

    @Test("Baseware properties")
    func testBasewareProperties() {
        let provider = BasewarePropertyProvider()

        // Name should be Ourin
        let name = provider.get(key: "name")
        #expect(name == "Ourin")

        // Version should exist
        let version = provider.get(key: "version")
        #expect(version != nil)
    }

    @Test("Ghost properties - ghostlist")
    func testGhostList() {
        let ghosts = [
            Ghost(name: "Emily/Phase4.5", sakuraname: "Emily", keroname: "Teddy",
                  craftmanw: "Yuyuko", craftmanurl: "https://emily.shillest.net/",
                  path: "emily4", icon: "emily4/icon.ico", homeurl: "https://emily.shillest.net/")
        ]
        let provider = GhostPropertyProvider(mode: .ghostlist, ghosts: ghosts, activeIndices: [0])

        // Count
        #expect(provider.get(key: "count") == "1")

        // Access by index
        #expect(provider.get(key: "index(0).name") == "Emily/Phase4.5")
        #expect(provider.get(key: "index(0).sakuraname") == "Emily")
        #expect(provider.get(key: "index(0).keroname") == "Teddy")

        // Access by name
        #expect(provider.get(key: "(Emily/Phase4.5).sakuraname") == "Emily")
        #expect(provider.get(key: "(Emily).keroname") == "Teddy")
    }

    @Test("Ghost properties - currentghost")
    func testCurrentGhost() {
        let ghosts = [
            Ghost(name: "TestGhost", sakuraname: "Sakura", keroname: "Kero",
                  path: "/test/path", icon: "icon.ico")
        ]
        let shells = [
            Shell(name: "Default", path: "/shell/default"),
            Shell(name: "Winter", path: "/shell/winter", menu: "hidden")
        ]
        let provider = GhostPropertyProvider(mode: .currentghost, ghosts: ghosts, activeIndices: [0], shells: shells)

        // Basic properties
        #expect(provider.get(key: "name") == "TestGhost")
        #expect(provider.get(key: "sakuraname") == "Sakura")
        #expect(provider.get(key: "keroname") == "Kero")

        // Shell list
        #expect(provider.get(key: "shelllist.count") == "2")
        #expect(provider.get(key: "shelllist(Default).path") == "/shell/default")
        #expect(provider.get(key: "shelllist(Winter).menu") == "hidden")
    }

    @Test("PropertyManager - Integration")
    func testPropertyManagerIntegration() {
        let manager = PropertyManager()

        // System properties
        #expect(manager.get("system.year") != nil)
        #expect(manager.get("system.os.type") == "macOS")

        // Baseware properties
        #expect(manager.get("baseware.name") == "Ourin")

        // Ghost properties
        #expect(manager.get("ghostlist.count") != nil)
        #expect(manager.get("currentghost.name") != nil)
    }

    @Test("PropertyManager - %property[] expansion")
    func testPropertyExpansion() {
        let manager = PropertyManager()

        let text = "Welcome to %property[baseware.name] version %property[baseware.version]!"
        let expanded = manager.expand(text: text)

        #expect(expanded.contains("Ourin"))
        #expect(!expanded.contains("%property"))
    }

    @Test("BalloonPropertyProvider")
    func testBalloonProperties() {
        let balloons = [
            Balloon(name: "Default", path: "/balloon/default", craftmanw: "Author", craftmanurl: "https://example.com")
        ]
        let provider = BalloonPropertyProvider(mode: .balloonlist, balloons: balloons)

        #expect(provider.get(key: "count") == "1")
        #expect(provider.get(key: "index(0).name") == "Default")
        #expect(provider.get(key: "(Default).craftmanw") == "Author")
    }

    @Test("HeadlinePropertyProvider")
    func testHeadlineProperties() {
        let headlines = [
            Headline(name: "News", path: "/headline/news")
        ]
        let provider = HeadlinePropertyProvider(headlines: headlines)

        #expect(provider.get(key: "count") == "1")
        #expect(provider.get(key: "index(0).name") == "News")
    }

    @Test("PluginPropertyProvider")
    func testPluginProperties() {
        let plugins = [
            PropertyPlugin(name: "TestPlugin", path: "/plugin/test", id: "plugin001")
        ]
        let provider = PluginPropertyProvider(plugins: plugins)

        #expect(provider.get(key: "count") == "1")
        #expect(provider.get(key: "index(0).name") == "TestPlugin")
        #expect(provider.get(key: "(plugin001).name") == "TestPlugin")
    }

    @Test("Property SET functionality")
    func testPropertySet() {
        let ghosts = [
            Ghost(name: "TestGhost", path: "/test")
        ]
        let shells = [
            Shell(name: "Default", path: "/shell/default")
        ]
        let provider = GhostPropertyProvider(mode: .currentghost, ghosts: ghosts, activeIndices: [0], shells: shells)

        // Test setting shell menu property
        let success = provider.set(key: "shelllist(Default).menu", value: "hidden")
        #expect(success == true)
        #expect(provider.get(key: "shelllist(Default).menu") == "hidden")
    }
}
