import Testing
import Foundation
@testable import Ourin

/// Tests for GhostConfiguration parsing and application
struct GhostConfigurationTests {

    // MARK: - Basic Parsing Tests

    @Test("Parse basic ghost configuration")
    func testBasicParsing() throws {
        let dict: [String: String] = [
            "charset": "Shift_JIS",
            "type": "ghost",
            "name": "TestGhost",
            "sakura.name": "Sakura",
            "kero.name": "Kero",
            "craftman": "testauthor",
            "craftmanw": "テスト作者",
            "craftmanurl": "https://example.com",
            "homeurl": "https://example.com/ghost/",
            "shiori": "yaya.dll"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.charset == "Shift_JIS")
        #expect(config.type == "ghost")
        #expect(config.name == "TestGhost")
        #expect(config.sakuraName == "Sakura")
        #expect(config.keroName == "Kero")
        #expect(config.craftman == "testauthor")
        #expect(config.craftmanw == "テスト作者")
        #expect(config.craftmanurl == "https://example.com")
        #expect(config.homeurl == "https://example.com/ghost/")
        #expect(config.shiori == "yaya.dll")
    }

    @Test("Parse ghost with minimal configuration")
    func testMinimalConfiguration() throws {
        let dict: [String: String] = [
            "name": "MinimalGhost"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.name == "MinimalGhost")
        #expect(config.sakuraName == "MinimalGhost")  // Defaults to name
        #expect(config.shiori == "shiori.dll")  // Default SHIORI
        #expect(config.sakuraDefaultSurface == 0)
        #expect(config.keroDefaultSurface == 10)
    }

    @Test("Parse configuration with no name returns nil")
    func testNoNameReturnsNil() {
        let dict: [String: String] = [
            "type": "ghost"
        ]

        let config = GhostConfiguration.parse(from: dict)
        #expect(config == nil)
    }

    // MARK: - Surface Configuration Tests

    @Test("Parse surface configuration")
    func testSurfaceConfiguration() throws {
        let dict: [String: String] = [
            "name": "SurfaceTest",
            "sakura.seriko.defaultsurface": "5",
            "kero.seriko.defaultsurface": "15",
            "char2.seriko.defaultsurface": "200",
            "balloon.defaultsurface": "1"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.sakuraDefaultSurface == 5)
        #expect(config.keroDefaultSurface == 15)
        #expect(config.charDefaultSurfaces[2] == 200)
        #expect(config.balloonDefaultSurface == 1)
    }

    // MARK: - Position Configuration Tests

    @Test("Parse position configuration")
    func testPositionConfiguration() throws {
        let dict: [String: String] = [
            "name": "PositionTest",
            "seriko.alignmenttodesktop": "bottom",
            "sakura.seriko.alignmenttodesktop": "top",
            "kero.seriko.alignmenttodesktop": "free",
            "sakura.defaultx": "100",
            "sakura.defaulty": "200",
            "kero.defaultleft": "300",
            "kero.defaulttop": "400"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.alignmentToDesktop == .bottom)
        #expect(config.sakuraAlignment == .top)
        #expect(config.keroAlignment == .free)
        #expect(config.sakuraDefaultX == 100)
        #expect(config.sakuraDefaultY == 200)
        #expect(config.keroDefaultLeft == 300)
        #expect(config.keroDefaultTop == 400)
    }

    @Test("Parse character-specific positions")
    func testCharacterPositions() throws {
        let dict: [String: String] = [
            "name": "CharTest",
            "char2.name": "ThirdCharacter",
            "char2.defaultx": "50",
            "char2.defaulty": "60",
            "char3.defaultleft": "150",
            "char3.defaulttop": "160"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.charNames[2] == "ThirdCharacter")
        #expect(config.charDefaultX[2] == 50)
        #expect(config.charDefaultY[2] == 60)
        #expect(config.charDefaultLeft[3] == 150)
        #expect(config.charDefaultTop[3] == 160)
    }

    // MARK: - SSTP Configuration Tests

    @Test("Parse SSTP configuration")
    func testSSTPConfiguration() throws {
        let dict: [String: String] = [
            "name": "SSTPTest",
            "sstp.allowunspecifiedsend": "0",
            "sstp.allowcommunicate": "0",
            "sstp.alwaystranslate": "1"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.sstpAllowUnspecifiedSend == false)
        #expect(config.sstpAllowCommunicate == false)
        #expect(config.sstpAlwaysTranslate == true)
    }

    @Test("SSTP defaults are correct")
    func testSSTPDefaults() throws {
        let dict: [String: String] = [
            "name": "DefaultTest"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.sstpAllowUnspecifiedSend == true)
        #expect(config.sstpAllowCommunicate == true)
        #expect(config.sstpAlwaysTranslate == nil)
    }

    // MARK: - Balloon Configuration Tests

    @Test("Parse balloon configuration")
    func testBalloonConfiguration() throws {
        let dict: [String: String] = [
            "name": "BalloonTest",
            "balloon": "myballoon",
            "default.balloon.path": "balloon/myballoon",
            "recommended.balloon": "specialballoon",
            "balloon.dontmove": "true",
            "balloon.syncscale": "true"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.balloon == "myballoon")
        #expect(config.defaultBalloonPath == "balloon/myballoon")
        #expect(config.recommendedBalloon == "specialballoon")
        #expect(config.balloonDontMove == true)
        #expect(config.balloonSyncScale == true)
    }

    // MARK: - UI Configuration Tests

    @Test("Parse UI configuration")
    func testUIConfiguration() throws {
        let dict: [String: String] = [
            "name": "UITest",
            "icon": "icon.ico",
            "icon.minimize": "icon_mini.ico",
            "mousecursor": "cursor.cur",
            "mousecursor.text": "text.cur",
            "menu.font.name": "Arial",
            "menu.font.height": "14"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.icon == "icon.ico")
        #expect(config.iconMinimize == "icon_mini.ico")
        #expect(config.mouseCursor == "cursor.cur")
        #expect(config.mouseCursorText == "text.cur")
        #expect(config.menuFontName == "Arial")
        #expect(config.menuFontHeight == 14)
    }

    // MARK: - Behavior Settings Tests

    @Test("Parse behavior settings")
    func testBehaviorSettings() throws {
        let dict: [String: String] = [
            "name": "BehaviorTest",
            "name.allowoverride": "0",
            "don't need onmousemove": "1",
            "don't need bind": "1",
            "don't need seriko talk": "1"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.nameAllowOverride == false)
        #expect(config.dontNeedOnMouseMove == true)
        #expect(config.dontNeedBind == true)
        #expect(config.dontNeedSerikoTalk == true)
    }

    // MARK: - SHIORI Configuration Tests

    @Test("Parse SHIORI configuration")
    func testSHIORIConfiguration() throws {
        let dict: [String: String] = [
            "name": "SHIORITest",
            "shiori": "custom.dll",
            "shiori.version": "SHIORI/3.0",
            "shiori.cache": "0",
            "shiori.encoding": "UTF-8",
            "shiori.forceencoding": "Shift_JIS",
            "shiori.escape_unknown": "1"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.shiori == "custom.dll")
        #expect(config.shioriVersion == "SHIORI/3.0")
        #expect(config.shioriCache == false)
        #expect(config.shioriEncoding == "UTF-8")
        #expect(config.shioriForceEncoding == "Shift_JIS")
        #expect(config.shioriEscapeUnknown == true)
    }

    // MARK: - Installation Configuration Tests

    @Test("Parse installation configuration")
    func testInstallationConfiguration() throws {
        let dict: [String: String] = [
            "name": "InstallTest",
            "install.accept": "Ghost1,Ghost2,Ghost3",
            "readme": "readme.txt",
            "readme.charset": "UTF-8"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.installAccept == ["Ghost1", "Ghost2", "Ghost3"])
        #expect(config.readme == "readme.txt")
        #expect(config.readmeCharset == "UTF-8")
    }

    // MARK: - AI Graph Configuration Tests

    @Test("Parse AI graph configuration")
    func testAIGraphConfiguration() throws {
        let dict: [String: String] = [
            "name": "AIGraphTest",
            "shiori.logo.file": "ai.png",
            "shiori.logo.x": "10",
            "shiori.logo.y": "20",
            "shiori.logo.align": "righttop"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.shioriLogoFile == "ai.png")
        #expect(config.shioriLogoX == 10)
        #expect(config.shioriLogoY == 20)
        #expect(config.shioriLogoAlign == .righttop)
    }

    // MARK: - Emily4 Real-World Test

    @Test("Parse Emily4 configuration")
    func testEmily4Configuration() throws {
        // This mirrors the actual Emily4 descript.txt
        let dict: [String: String] = [
            "charset": "Shift_JIS",
            "type": "ghost",
            "name": "Emily/Phase4.5",
            "sakura.name": "Emily",
            "kero.name": "Teddy",
            "balloon": "emily4",
            "id": "Emily/Phase4.5",
            "title": "Slapstick Beauty",
            "char2.seriko.defaultsurface": "200",
            "name.allowoverride": "0",
            "craftmanurl": "http://ssp.shillest.net/",
            "craftman": "[SSPBT/GL03B]Emily Development Team",
            "updateurl": "http://ssp.shillest.net/ghost/emily4/",
            "sstp.allowunspecifiedsend": "1",
            "icon": "icon.ico",
            "icon.minimize": "icon_minimize.ico",
            "shiori": "yaya.dll",
            "shiori.version": "SHIORI/3.0"
        ]

        let config = try #require(GhostConfiguration.parse(from: dict))

        #expect(config.name == "Emily/Phase4.5")
        #expect(config.sakuraName == "Emily")
        #expect(config.keroName == "Teddy")
        #expect(config.charDefaultSurfaces[2] == 200)
        #expect(config.nameAllowOverride == false)
        #expect(config.shiori == "yaya.dll")
        #expect(config.shioriVersion == "SHIORI/3.0")
        #expect(config.sstpAllowUnspecifiedSend == true)
    }

    // MARK: - Ghost Integration Tests

    @Test("Create Ghost from GhostConfiguration")
    func testGhostFromConfiguration() throws {
        let config = GhostConfiguration(
            name: "TestGhost",
            sakuraName: "Sakura",
            keroName: "Kero"
        )

        let ghost = Ghost(from: config, path: "/path/to/ghost", username: "TestUser")

        #expect(ghost.name == "TestGhost")
        #expect(ghost.sakuraname == "Sakura")
        #expect(ghost.keroname == "Kero")
        #expect(ghost.path == "/path/to/ghost")
        #expect(ghost.username == "TestUser")
        #expect(ghost.configuration != nil)
    }
}
