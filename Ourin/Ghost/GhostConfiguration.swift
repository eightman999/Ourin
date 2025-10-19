import Foundation

/// Represents configuration values loaded from ghost's descript.txt.
/// Based on https://ssp.shillest.net/ukadoc/manual/descript_ghost.html
public struct GhostConfiguration {

    // MARK: - Basic Information

    /// Character encoding (charset)
    public var charset: String?

    /// File type (type) - should be "ghost"
    public var type: String?

    /// Ghost name (name)
    public var name: String

    /// Main character name (sakura.name)
    public var sakuraName: String

    /// Partner character name (kero.name)
    public var keroName: String?

    /// Additional character names (char*.name)
    public var charNames: [Int: String] = [:]

    /// ID name (id)
    public var id: String?

    /// Display title (title)
    public var title: String?

    // MARK: - Author Information

    /// Author name (ASCII only) (craftman)
    public var craftman: String?

    /// Author name (full Unicode) (craftmanw)
    public var craftmanw: String?

    /// Author URL (craftmanurl)
    public var craftmanurl: String?

    /// Home/update URL (homeurl)
    public var homeurl: String?

    // MARK: - SHIORI Configuration

    /// SHIORI DLL filename (shiori)
    public var shiori: String

    /// SHIORI protocol version (shiori.version)
    public var shioriVersion: String?

    /// Whether to cache SHIORI (shiori.cache)
    public var shioriCache: Bool?

    /// SHIORI encoding (shiori.encoding)
    public var shioriEncoding: String?

    /// Force SHIORI encoding (shiori.forceencoding)
    public var shioriForceEncoding: String?

    /// Escape unknown characters (shiori.escape_unknown)
    public var shioriEscapeUnknown: Bool?

    // MARK: - Surface Configuration

    /// Default surface for sakura (sakura.seriko.defaultsurface)
    public var sakuraDefaultSurface: Int

    /// Default surface for kero (kero.seriko.defaultsurface)
    public var keroDefaultSurface: Int

    /// Default surfaces for additional characters (char*.seriko.defaultsurface)
    public var charDefaultSurfaces: [Int: Int] = [:]

    /// Default balloon surface (balloon.defaultsurface)
    public var balloonDefaultSurface: Int?

    // MARK: - Position Configuration

    /// Overall alignment to desktop (seriko.alignmenttodesktop)
    public var alignmentToDesktop: AlignmentToDesktop?

    /// Sakura alignment (sakura.seriko.alignmenttodesktop)
    public var sakuraAlignment: AlignmentToDesktop?

    /// Kero alignment (kero.seriko.alignmenttodesktop)
    public var keroAlignment: AlignmentToDesktop?

    /// Character alignments (char*.seriko.alignmenttodesktop)
    public var charAlignments: [Int: AlignmentToDesktop] = [:]

    /// Image base X for sakura (sakura.defaultx)
    public var sakuraDefaultX: Int?

    /// Image base Y for sakura (sakura.defaulty)
    public var sakuraDefaultY: Int?

    /// Image base X for kero (kero.defaultx)
    public var keroDefaultX: Int?

    /// Image base Y for kero (kero.defaulty)
    public var keroDefaultY: Int?

    /// Character base positions (char*.defaultx/y)
    public var charDefaultX: [Int: Int] = [:]
    public var charDefaultY: [Int: Int] = [:]

    /// Display position X for sakura (sakura.defaultleft)
    public var sakuraDefaultLeft: Int?

    /// Display position Y for sakura (sakura.defaulttop)
    public var sakuraDefaultTop: Int?

    /// Display position X for kero (kero.defaultleft)
    public var keroDefaultLeft: Int?

    /// Display position Y for kero (kero.defaulttop)
    public var keroDefaultTop: Int?

    /// Character display positions (char*.defaultleft/top)
    public var charDefaultLeft: [Int: Int] = [:]
    public var charDefaultTop: [Int: Int] = [:]

    // MARK: - Shell Configuration

    /// Default shell directory name (seriko.defaultsurfacedirectoryname)
    public var defaultShellDirectory: String

    // MARK: - SSTP Configuration

    /// Allow unspecified SSTP send (sstp.allowunspecifiedsend)
    public var sstpAllowUnspecifiedSend: Bool

    /// Allow COMMUNICATE (sstp.allowcommunicate)
    public var sstpAllowCommunicate: Bool

    /// Always translate SSTP (sstp.alwaystranslate)
    public var sstpAlwaysTranslate: Bool?

    // MARK: - Balloon Configuration

    /// Recommended balloon name (balloon)
    public var balloon: String?

    /// Default balloon path (default.balloon.path)
    public var defaultBalloonPath: String?

    /// Recommended balloon (recommended.balloon)
    public var recommendedBalloon: String?

    /// Recommended balloon path (recommended.balloon.path)
    public var recommendedBalloonPath: String?

    /// Don't move balloon (balloon.dontmove)
    public var balloonDontMove: Bool?

    /// Sync balloon scale (balloon.syncscale)
    public var balloonSyncScale: Bool?

    // MARK: - UI Configuration

    /// Icon file (icon)
    public var icon: String?

    /// Minimize icon (icon.minimize)
    public var iconMinimize: String?

    /// Cursor file (cursor/mousecursor)
    public var mouseCursor: String?

    /// Text cursor (mousecursor.text)
    public var mouseCursorText: String?

    /// Wait cursor (mousecursor.wait)
    public var mouseCursorWait: String?

    /// Hand cursor (mousecursor.hand)
    public var mouseCursorHand: String?

    /// Grip cursor (mousecursor.grip)
    public var mouseCursorGrip: String?

    /// Arrow cursor (mousecursor.arrow)
    public var mouseCursorArrow: String?

    /// Menu font name (menu.font.name)
    public var menuFontName: String?

    /// Menu font height (menu.font.height)
    public var menuFontHeight: Int?

    // MARK: - Behavior Settings

    /// Allow shell name override (name.allowoverride)
    public var nameAllowOverride: Bool

    /// Don't need OnMouseMove (don't need onmousemove)
    public var dontNeedOnMouseMove: Bool?

    /// Don't need bind (don't need bind)
    public var dontNeedBind: Bool?

    /// Don't need seriko talk (don't need seriko talk)
    public var dontNeedSerikoTalk: Bool?

    // MARK: - AI Graph Configuration

    /// AI graph logo file (shiori.logo.file)
    public var shioriLogoFile: String?

    /// AI graph logo X position (shiori.logo.x)
    public var shioriLogoX: Int?

    /// AI graph logo Y position (shiori.logo.y)
    public var shioriLogoY: Int?

    /// AI graph logo alignment (shiori.logo.align)
    public var shioriLogoAlign: LogoAlignment?

    // MARK: - Installation

    /// Accepted install names (install.accept)
    public var installAccept: [String] = []

    /// Readme file (readme)
    public var readme: String

    /// Readme charset (readme.charset)
    public var readmeCharset: String?

    // MARK: - Enums

    public enum AlignmentToDesktop: String {
        case top
        case bottom
        case free
    }

    public enum LogoAlignment: String {
        case lefttop
        case leftbottom
        case righttop
        case rightbottom
    }

    // MARK: - Initialization

    /// Initialize with required fields and sensible defaults.
    public init(
        name: String,
        sakuraName: String? = nil,
        keroName: String? = nil,
        shiori: String = "shiori.dll",
        sakuraDefaultSurface: Int = 0,
        keroDefaultSurface: Int = 10,
        defaultShellDirectory: String = "master",
        sstpAllowUnspecifiedSend: Bool = true,
        sstpAllowCommunicate: Bool = true,
        nameAllowOverride: Bool = true,
        readme: String = "readme.txt"
    ) {
        self.name = name
        self.sakuraName = sakuraName ?? name
        self.keroName = keroName
        self.shiori = shiori
        self.sakuraDefaultSurface = sakuraDefaultSurface
        self.keroDefaultSurface = keroDefaultSurface
        self.defaultShellDirectory = defaultShellDirectory
        self.sstpAllowUnspecifiedSend = sstpAllowUnspecifiedSend
        self.sstpAllowCommunicate = sstpAllowCommunicate
        self.nameAllowOverride = nameAllowOverride
        self.readme = readme
    }

    // MARK: - Parsing from descript.txt

    /// Parse a GhostConfiguration from a descript.txt dictionary.
    public static func parse(from dict: [String: String]) -> GhostConfiguration? {
        // Name is required
        guard let name = dict["name"] else { return nil }

        var config = GhostConfiguration(name: name)

        // Basic information
        config.charset = dict["charset"]
        config.type = dict["type"]
        config.sakuraName = dict["sakura.name"] ?? name
        config.keroName = dict["kero.name"]
        config.id = dict["id"]
        config.title = dict["title"]

        // Author information
        config.craftman = dict["craftman"]
        config.craftmanw = dict["craftmanw"]
        config.craftmanurl = dict["craftmanurl"]
        config.homeurl = dict["homeurl"]

        // SHIORI configuration
        if let shiori = dict["shiori"] {
            config.shiori = shiori
        }
        config.shioriVersion = dict["shiori.version"]
        config.shioriCache = dict["shiori.cache"].flatMap { $0 == "1" }
        config.shioriEncoding = dict["shiori.encoding"]
        config.shioriForceEncoding = dict["shiori.forceencoding"]
        config.shioriEscapeUnknown = dict["shiori.escape_unknown"].flatMap { $0 == "1" }

        // Surface configuration
        if let surface = dict["sakura.seriko.defaultsurface"].flatMap(Int.init) {
            config.sakuraDefaultSurface = surface
        }
        if let surface = dict["kero.seriko.defaultsurface"].flatMap(Int.init) {
            config.keroDefaultSurface = surface
        }
        if let surface = dict["balloon.defaultsurface"].flatMap(Int.init) {
            config.balloonDefaultSurface = surface
        }

        // Position configuration
        config.alignmentToDesktop = dict["seriko.alignmenttodesktop"].flatMap(AlignmentToDesktop.init)
        config.sakuraAlignment = dict["sakura.seriko.alignmenttodesktop"].flatMap(AlignmentToDesktop.init)
        config.keroAlignment = dict["kero.seriko.alignmenttodesktop"].flatMap(AlignmentToDesktop.init)

        config.sakuraDefaultX = dict["sakura.defaultx"].flatMap(Int.init)
        config.sakuraDefaultY = dict["sakura.defaulty"].flatMap(Int.init)
        config.keroDefaultX = dict["kero.defaultx"].flatMap(Int.init)
        config.keroDefaultY = dict["kero.defaulty"].flatMap(Int.init)

        config.sakuraDefaultLeft = dict["sakura.defaultleft"].flatMap(Int.init)
        config.sakuraDefaultTop = dict["sakura.defaulttop"].flatMap(Int.init)
        config.keroDefaultLeft = dict["kero.defaultleft"].flatMap(Int.init)
        config.keroDefaultTop = dict["kero.defaulttop"].flatMap(Int.init)

        // Shell configuration
        if let shellDir = dict["seriko.defaultsurfacedirectoryname"] {
            config.defaultShellDirectory = shellDir
        }

        // SSTP configuration
        if let allow = dict["sstp.allowunspecifiedsend"] {
            config.sstpAllowUnspecifiedSend = (allow == "1")
        }
        if let allow = dict["sstp.allowcommunicate"] {
            config.sstpAllowCommunicate = (allow == "1")
        }
        config.sstpAlwaysTranslate = dict["sstp.alwaystranslate"].flatMap { $0 == "1" }

        // Balloon configuration
        config.balloon = dict["balloon"]
        config.defaultBalloonPath = dict["default.balloon.path"]
        config.recommendedBalloon = dict["recommended.balloon"]
        config.recommendedBalloonPath = dict["recommended.balloon.path"]
        config.balloonDontMove = dict["balloon.dontmove"].flatMap { $0 == "true" }
        config.balloonSyncScale = dict["balloon.syncscale"].flatMap { $0 == "true" }

        // UI configuration
        config.icon = dict["icon"]
        config.iconMinimize = dict["icon.minimize"]
        config.mouseCursor = dict["cursor"] ?? dict["mousecursor"]
        config.mouseCursorText = dict["mousecursor.text"]
        config.mouseCursorWait = dict["mousecursor.wait"]
        config.mouseCursorHand = dict["mousecursor.hand"]
        config.mouseCursorGrip = dict["mousecursor.grip"]
        config.mouseCursorArrow = dict["mousecursor.arrow"]
        config.menuFontName = dict["menu.font.name"]
        config.menuFontHeight = dict["menu.font.height"].flatMap(Int.init)

        // Behavior settings
        if let override = dict["name.allowoverride"] {
            config.nameAllowOverride = (override == "1")
        }
        config.dontNeedOnMouseMove = dict["don't need onmousemove"].flatMap { $0 == "1" }
        config.dontNeedBind = dict["don't need bind"].flatMap { $0 == "1" }
        config.dontNeedSerikoTalk = dict["don't need seriko talk"].flatMap { $0 == "1" }

        // AI graph configuration
        config.shioriLogoFile = dict["shiori.logo.file"]
        config.shioriLogoX = dict["shiori.logo.x"].flatMap(Int.init)
        config.shioriLogoY = dict["shiori.logo.y"].flatMap(Int.init)
        config.shioriLogoAlign = dict["shiori.logo.align"].flatMap(LogoAlignment.init)

        // Installation
        if let accept = dict["install.accept"] {
            config.installAccept = accept.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        if let readme = dict["readme"] {
            config.readme = readme
        }
        config.readmeCharset = dict["readme.charset"]

        // Parse char* entries for additional characters
        parseCharEntries(from: dict, into: &config)

        return config
    }

    /// Parse char*.* entries for additional characters (char2, char3, etc.)
    private static func parseCharEntries(from dict: [String: String], into config: inout GhostConfiguration) {
        let charPattern = "^char(\\d+)\\.(.+)$"
        guard let regex = try? NSRegularExpression(pattern: charPattern, options: []) else { return }

        for (key, value) in dict {
            let nsKey = key as NSString
            let matches = regex.matches(in: key, range: NSRange(location: 0, length: nsKey.length))

            guard let match = matches.first,
                  match.numberOfRanges == 3,
                  let charNumRange = Range(match.range(at: 1), in: key),
                  let propRange = Range(match.range(at: 2), in: key),
                  let charNum = Int(key[charNumRange]) else {
                continue
            }

            let property = String(key[propRange])

            switch property {
            case "name":
                config.charNames[charNum] = value
            case "seriko.defaultsurface":
                if let surface = Int(value) {
                    config.charDefaultSurfaces[charNum] = surface
                }
            case "seriko.alignmenttodesktop":
                if let alignment = AlignmentToDesktop(rawValue: value) {
                    config.charAlignments[charNum] = alignment
                }
            case "defaultx":
                if let x = Int(value) {
                    config.charDefaultX[charNum] = x
                }
            case "defaulty":
                if let y = Int(value) {
                    config.charDefaultY[charNum] = y
                }
            case "defaultleft":
                if let left = Int(value) {
                    config.charDefaultLeft[charNum] = left
                }
            case "defaulttop":
                if let top = Int(value) {
                    config.charDefaultTop[charNum] = top
                }
            default:
                break
            }
        }
    }

    /// Load GhostConfiguration from a ghost directory.
    public static func load(from ghostRoot: URL) -> GhostConfiguration? {
        let descriptPath = ghostRoot.appendingPathComponent("descript.txt")
        guard let dict = try? parseDescriptFile(descriptPath) else {
            return nil
        }
        return parse(from: dict)
    }
}

// MARK: - Private Helper for parsing descript.txt

private extension GhostConfiguration {
    /// Parse a single descript.txt file
    static func parseDescriptFile(_ file: URL) throws -> [String: String] {
        let raw = try Data(contentsOf: file)
        var text = String(data: raw, encoding: .utf8)
        if text == nil {
            text = String(data: raw, encoding: .shiftJIS)
        }
        guard let str = text else {
            throw NSError(domain: "GhostConfiguration", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Encoding error"])
        }
        var dict: [String: String] = [:]
        for line in str.components(separatedBy: .newlines) {
            guard let comma = line.firstIndex(of: ",") else { continue }
            let key = String(line[..<comma]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { dict[key] = value }
        }
        return dict
    }
}

private extension String.Encoding {
    /// Windows compatible Shift_JIS code page (CP932)
    static let shiftJIS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
}
