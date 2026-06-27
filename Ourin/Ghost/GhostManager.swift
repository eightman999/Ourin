import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications

// MARK: - ViewModels

/// ViewModel for the character view.
class CharacterViewModel: ObservableObject {
    @Published var image: NSImage?
    @Published var currentSurfaceID: Int = 0

    // Visual effects state (persists until ghost terminates)
    @Published var scaleX: Double = 1.0
    @Published var scaleY: Double = 1.0
    @Published var alpha: Double = 1.0  // 0.0 to 1.0

    // Position and alignment state
    @Published var position: CGPoint?  // nil = free movement, set = locked position
    @Published var alignment: DesktopAlignment = .free

    // Rendering control
    @Published var repaintLocked: Bool = false
    @Published var manualRepaintLock: Bool = false
    
    // Balloon state
    @Published var currentBalloonID: Int = 0  // Current balloon style ID
    
    // Surface compositing - overlay surfaces
    @Published var overlays: [SurfaceOverlay] = []
    
    // Effects and filters
    @Published var activeEffects: [EffectConfig] = []
    @Published var activeFilters: [FilterConfig] = []
    
    // Dressup bindings
    var dressupBindings: [String: [String: String]] = [:] // category -> part -> value

    // Dressup parts
    @Published var dressupParts: [DressupPart] = []

    // Text animations
    @Published var textAnimations: [TextAnimationConfig] = []

    // Window stacking
    var zOrderGroup: [Int]? = nil  // nil = default, or array of scope IDs in front-to-back order
    var stickyGroup: [Int]? = nil  // nil = independent, or array of scope IDs that move together

    /// Desktop alignment options
    enum DesktopAlignment {
        case free
        case top
        case bottom
        case left
        case right
    }
}

/// ViewModel for the balloon view.
class BalloonViewModel: ObservableObject {
    @Published var text: String = ""
    @Published var balloonID: Int = 0  // Current balloon style ID (0, 2, 4, etc.)

    // Cursor position for \_l[x,y] command
    @Published var cursorX: CGFloat = 0
    @Published var cursorY: CGFloat = 0

    // Balloon offset for \![set,balloonoffset,...] command
    @Published var balloonOffsetX: CGFloat = 0
    @Published var balloonOffsetY: CGFloat = 0
    @Published var useCustomOffset: Bool = false

    // Balloon alignment for \![set,balloonalign,...] command
    @Published var balloonAlignment: BalloonAlignment = .none

    // Font settings for \f[...] commands
    @Published var fontName: String = ""
    @Published var fontSize: CGFloat = 12
    @Published var fontWeight: Font.Weight = .regular
    @Published var fontItalic: Bool = false
    @Published var fontUnderline: Bool = false
    @Published var fontStrike: Bool = false
    @Published var fontSubscript: Bool = false
    @Published var fontSuperscript: Bool = false
    @Published var fontColor: NSColor = .textColor
    @Published var anchorFontColor: NSColor = .linkColor
    @Published var anchorActive: Bool = false
    @Published var shadowColor: NSColor = .clear
    @Published var shadowStyle: BalloonShadowStyle = .none
    @Published var outlineWidth: CGFloat = 0
    @Published var textAlign: BalloonTextAlign = .left
    @Published var textVAlign: BalloonTextVAlign = .top

    // Balloon control settings
    @Published var autoscrollEnabled: Bool = true
    @Published var balloonTimeout: TimeInterval = 60
    @Published var balloonWaitEnabled: Bool = true
    @Published var balloonWaitMultiplier: Double = 1.0
    @Published var balloonMarkerText: String = ""
    @Published var balloonNumberVisible: Bool = false
    @Published var repaintLocked: Bool = false
    @Published var balloonMoveLocked: Bool = false

    enum BalloonAlignment {
        case none
        case left
        case center
        case right
        case top
        case bottom
    }

    enum BalloonShadowStyle {
        case none
        case offset
        case outline
    }

    enum BalloonTextAlign {
        case left
        case center
        case right
    }

    enum BalloonTextVAlign {
        case top
        case center
        case bottom
    }

    // Balloon images
    struct BalloonImage: Identifiable {
        let id = UUID()
        let filepath: String
        let x: CGFloat
        let y: CGFloat
        let isInline: Bool
        let isOpaque: Bool
        let useSelfAlpha: Bool
        let clipping: CGRect?
        let isForeground: Bool
        let image: NSImage?
    }
    @Published var balloonImages: [BalloonImage] = []
}


// MARK: - GhostManager

/// Manages the lifecycle and display of a single ghost.
class GhostManager: NSObject, SakuraScriptEngineDelegate {

    // MARK: - Properties

    let ghostURL: URL
    var yayaAdapter: YayaAdapter?
    let sakuraEngine = SakuraScriptEngine()
    private var eventToken: UUID?
    let resourceManager = ResourceManager()
    var ghostConfig: GhostConfiguration?
    var activeShellName: String = "master"
    var lastSntpServerDate: Date?
    var lastSntpServerDateTime: String?
    var lastSntpTimezone: String?

    // Window management
    var characterWindows: [Int: NSWindow] = [:] // Support multiple scopes (0=master, 1=partner)
    var balloonWindows: [Int: NSWindow] = [:]

    // ViewModels
    var characterViewModels: [Int: CharacterViewModel] = [:] // One per scope
    var balloonViewModels: [Int: BalloonViewModel] = [:]

    // Balloon configuration and image loader
    var balloonConfig: BalloonConfig?
    var balloonImageLoader: BalloonImageLoader?

    var currentScope: Int = 0
    var balloonTextCancellables: [Int: AnyCancellable] = [:]

    // Context tracking for URL/email commands
    fileprivate var pendingURL: String?
    fileprivate var pendingEmail: String?

    // Typing playback state
    enum PlaybackUnit {
        case text(Character)
        case textChunk(String)
        case newline
        case scope(Int)
        case surface(Int)
        case wait(TimeInterval)
        case waitUntil(TimeInterval) // seconds from precise base
        case waitAnimation(Int) // wait until SERIKO animation ID completes
        case resetPrecise
        case clickWait(noclear: Bool)
        case end
        case deferredCommand(() -> Void) // Deferred command to execute after script completes
    }
    var playbackQueue: [PlaybackUnit] = []
    var isPlaying: Bool = false
    private var quickMode: Bool = false
    private var preciseBase: Date = Date()
    private let defaultTypingInterval: TimeInterval = 0.1
    private var typingInterval: TimeInterval = 0.1
    private var syncEnabled: Bool = false
    private var syncScopes: Set<Int> = []
    var pendingClick: Bool? = nil
    var pendingAnchorAction: (action: ChoiceAction, pluginOrigin: Bool)? = nil
    
    // Append mode flag - when true, balloon text is not cleared on script start
    private var appendModeEnabled: Bool = false
    
    // Sound playback tracking
    var currentSounds: [NSSound] = []
    var namedSounds: [String: [NSSound]] = [:]
    var preloadedSounds: [String: NSSound] = [:]
    
    // Animation engine
    var animationEngine: AnimationEngine = AnimationEngine()
    var surfaceAliases: [Int: Int] = [:]
    var surfaceNameAliases: [String: Int] = [:]   // \s[alias] 用: 文字列別名 → サーフェスID
    var parsedSurfaceDefs: [Int: SerikoSurfaceDefinition] = [:]  // element 合成・アニメ定義のキャッシュ
    var waitingForAnimation: Int? = nil  // Animation ID we're waiting for

    // Window management (used by Window extension)
    var stickyWindowRelationships: [Int: Set<Int>] = [:] // Master scope -> follower scopes

    // Choice dialog state (used by System extension)
    var pendingChoices: [(title: String, action: ChoiceAction, pluginOrigin: Bool)] = []
    var choiceHasCancelOption: Bool = false
    var choiceTimeout: TimeInterval? = nil
    /// \* 指定（このスクリプトの選択肢をタイムアウトさせない）
    var choiceTimeoutDisabled: Bool = false
    var localEventTimers: [String: Timer] = [:]
    var remoteEventTimers: [String: Timer] = [:]
    var pluginEventTimers: [String: Timer] = [:]
    /// \![execute,websocket,URL] で開いた WebSocket 接続（URL 文字列でキー）
    var webSocketTasks: [String: URLSessionWebSocketTask] = [:]
    var selectModeActive: Bool = false
    var quickSessionEnabled: Bool = false
    var collisionModeActive: Bool = false
    var passiveModeActive: Bool = false
    var inductionModeActive: Bool = false
    var noUserBreakModeActive: Bool = false
    /// \t タイムクリティカルセクション中（スクリプトブレークまたは \e まで、マウス系イベント通知を抑止）
    var timeCriticalActive: Bool = false

    struct PluginTalkNotificationContext {
        let script: String
        let reasons: Set<String>
        let eventID: String
        let references: [String]
    }
    var pendingPluginTalkAfter: PluginTalkNotificationContext?
    var isEmittingPluginTalk = false
    var currentScriptIsPluginOrigin = false

    // 終了シーケンス管理（OnClose 応答再生 → \- → 終了確定）
    var isShuttingDown: Bool = false
    var awaitingTerminateReply: Bool = false
    var didFinalizeTermination: Bool = false
    var terminateAfterPlayback: Bool = false

    // Dressup configuration
    var dressupConfigurations: [DressupConfig] = []
    var dressupBindGroupsByScope: [Int: [Int: DressupBindGroupMeta]] = [:]
    var dressupMenuItemsByScope: [Int: [Int: Int]] = [:] // scope -> menuIndex -> bindgroupID

    enum ChoiceAction {
        case event(id: String, references: [String])
        case script(String)
    }

    // Dressup configuration types
    struct DressupConfig {
        let category: String
        let parts: [DressupPartBinding]
    }

    struct DressupPartBinding {
        let partName: String
        let surfaceID: Int
        let x: Int
        let y: Int
        let overlay: Bool
    }

    struct DressupBindGroupMeta: Equatable {
        let scope: Int
        let bindGroupID: Int
        let category: String
        let part: String
        let thumbnail: String?
        let isDefault: Bool
    }

    // MARK: - Initialization

    init(ghostURL: URL) {
        self.ghostURL = ghostURL
        super.init()
        self.sakuraEngine.delegate = self

        // Load saved username into environment expander
        if let username = resourceManager.username {
            sakuraEngine.envExpander.username = username
        }
        
        // Load persistent character names
        loadPersistentCharacterNames()
        
        // Setup animation engine callbacks
        setupAnimationCallbacks()

        // Load dressup configuration
        loadDressupConfiguration()

        // Setup screen change observer for desktop alignment
        setupScreenChangeObserver()
    }

    deinit {
        shutdown()
    }
    
    // MARK: - Character Name Persistence
    
    func loadPersistentCharacterNames() {
        let defaults = UserDefaults.standard
        
        if let savedSakuraName = defaults.string(forKey: "OurinSakuraName") {
            sakuraEngine.envExpander.selfname = savedSakuraName
            Log.debug("[GhostManager] Loaded sakura name: \(savedSakuraName)")
        }
        
        if let savedKeroName = defaults.string(forKey: "OurinKeroName") {
            sakuraEngine.envExpander.keroname = savedKeroName
            Log.debug("[GhostManager] Loaded kero name: \(savedKeroName)")
        }
    }
    
    func loadDressupConfiguration() {
        dressupConfigurations.removeAll()
        dressupBindGroupsByScope.removeAll()
        dressupMenuItemsByScope.removeAll()
        // Load dressup configuration from shell descript.txt
        guard let shellPath = loadShellPath() else { return }
        let descriptPath = shellPath.appendingPathComponent("descript.txt")

        var content: String?
        if let utf8Content = try? String(contentsOf: descriptPath, encoding: .utf8) {
            content = utf8Content
        } else if let shiftJISContent = try? String(contentsOf: descriptPath, encoding: .shiftJIS) {
            content = shiftJISContent
        }

        guard let fileContent = content else {
            Log.debug("[GhostManager] Failed to load shell descript.txt")
            return
        }

        let parsed = Self.parseDressupMetadata(content: fileContent)
        let partsByCategory = parsed.partsByCategory

        if partsByCategory.isEmpty {
            Log.debug("[GhostManager] No dressup configuration found in descript.txt")
        } else {
            let configs = partsByCategory
                .map { DressupConfig(category: $0.key, parts: $0.value) }
                .sorted { $0.category < $1.category }
            dressupConfigurations.append(contentsOf: configs)
            let totalParts = configs.reduce(0) { $0 + $1.parts.count }
            Log.debug("[GhostManager] Dressup configuration loaded: categories=\(configs.count), parts=\(totalParts)")
        }

        for (scope, groups) in parsed.bindGroupNameByScope {
            for (id, groupValue) in groups {
                let meta = DressupBindGroupMeta(
                    scope: scope,
                    bindGroupID: id,
                    category: groupValue.category,
                    part: groupValue.part,
                    thumbnail: groupValue.thumbnail,
                    isDefault: parsed.bindGroupDefaultByScope[scope]?[id] ?? false
                )
                dressupBindGroupsByScope[scope, default: [:]][id] = meta
            }
        }
        dressupMenuItemsByScope = parsed.menuItemsByScope
    }

    static func parseDressupMetadata(content: String) -> (
        partsByCategory: [String: [DressupPartBinding]],
        bindGroupNameByScope: [Int: [Int: (category: String, part: String, thumbnail: String?)]],
        bindGroupDefaultByScope: [Int: [Int: Bool]],
        menuItemsByScope: [Int: [Int: Int]]
    ) {
        var partsByCategory: [String: [DressupPartBinding]] = [:]
        var bindGroupNameByScope: [Int: [Int: (category: String, part: String, thumbnail: String?)]] = [:]
        var bindGroupDefaultByScope: [Int: [Int: Bool]] = [:]
        var menuItemsByScope: [Int: [Int: Int]] = [:]

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//") else { continue }

            if trimmedLine.lowercased().hasPrefix("dressup,") {
                let components = trimmedLine.split(separator: ",", maxSplits: 5)
                if components.count >= 4 {
                    let category = String(components[1]).trimmingCharacters(in: .whitespaces)
                    let partName = String(components[2]).trimmingCharacters(in: .whitespaces)
                    let surfaceID = Int(components[3]) ?? 0
                    let x = components.count >= 5 ? Int(components[4]) ?? 0 : 0
                    let y = components.count >= 6 ? Int(components[5]) ?? 0 : 0

                    let binding = DressupPartBinding(
                        partName: partName,
                        surfaceID: surfaceID,
                        x: x,
                        y: y,
                        overlay: true
                    )
                    partsByCategory[category, default: []].append(binding)
                }
                continue
            }

            let segments = trimmedLine.split(separator: ",", maxSplits: 1).map(String.init)
            guard !segments.isEmpty else { continue }
            let key = segments[0].trimmingCharacters(in: .whitespaces)
            let value = segments.count > 1 ? segments[1].trimmingCharacters(in: .whitespaces) : ""

            if let parsed = parseBindGroupNameKey(key) {
                let fields = value.split(separator: ",", maxSplits: 2).map { String($0).trimmingCharacters(in: .whitespaces) }
                if fields.count >= 2 {
                    let thumbnail = fields.count >= 3 && !fields[2].isEmpty ? fields[2] : nil
                    bindGroupNameByScope[parsed.scope, default: [:]][parsed.bindGroupID] = (
                        category: fields[0],
                        part: fields[1],
                        thumbnail: thumbnail
                    )
                }
                continue
            }

            if let parsed = parseBindGroupDefaultKey(key) {
                let flag = value == "1" || value.lowercased() == "true"
                bindGroupDefaultByScope[parsed.scope, default: [:]][parsed.bindGroupID] = flag
                continue
            }

            if let parsed = parseMenuItemKey(key), let bindID = Int(value) {
                menuItemsByScope[parsed.scope, default: [:]][parsed.menuIndex] = bindID
            }
        }

        return (partsByCategory, bindGroupNameByScope, bindGroupDefaultByScope, menuItemsByScope)
    }

    private static func parseBindGroupNameKey(_ key: String) -> (scope: Int, bindGroupID: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(sakura|kero|char\d+)\.bindgroup(\d+)\.name$"#, options: [.caseInsensitive]) else {
            return nil
        }
        let nsKey = key as NSString
        guard let match = regex.firstMatch(in: key, range: NSRange(location: 0, length: nsKey.length)),
              let scopeRange = Range(match.range(at: 1), in: key),
              let idRange = Range(match.range(at: 2), in: key),
              let bindGroupID = Int(key[idRange]) else {
            return nil
        }
        return (scopeTokenToID(String(key[scopeRange])), bindGroupID)
    }

    private static func parseBindGroupDefaultKey(_ key: String) -> (scope: Int, bindGroupID: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(sakura|kero|char\d+)\.bindgroup(\d+)\.default$"#, options: [.caseInsensitive]) else {
            return nil
        }
        let nsKey = key as NSString
        guard let match = regex.firstMatch(in: key, range: NSRange(location: 0, length: nsKey.length)),
              let scopeRange = Range(match.range(at: 1), in: key),
              let idRange = Range(match.range(at: 2), in: key),
              let bindGroupID = Int(key[idRange]) else {
            return nil
        }
        return (scopeTokenToID(String(key[scopeRange])), bindGroupID)
    }

    private static func parseMenuItemKey(_ key: String) -> (scope: Int, menuIndex: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"^(sakura|kero|char\d+)\.menuitem(\d+)$"#, options: [.caseInsensitive]) else {
            return nil
        }
        let nsKey = key as NSString
        guard let match = regex.firstMatch(in: key, range: NSRange(location: 0, length: nsKey.length)),
              let scopeRange = Range(match.range(at: 1), in: key),
              let indexRange = Range(match.range(at: 2), in: key),
              let menuIndex = Int(key[indexRange]) else {
            return nil
        }
        return (scopeTokenToID(String(key[scopeRange])), menuIndex)
    }

    private static func scopeTokenToID(_ token: String) -> Int {
        let lowered = token.lowercased()
        if lowered == "sakura" { return 0 }
        if lowered == "kero" { return 1 }
        if lowered.hasPrefix("char"), let value = Int(lowered.dropFirst(4)) {
            return value
        }
        return 0
    }
    
    func saveCharacterNames(sakuraName: String, keroName: String?) {
        let defaults = UserDefaults.standard
        defaults.set(sakuraName, forKey: "OurinSakuraName")
        if let kero = keroName {
            defaults.set(kero, forKey: "OurinKeroName")
        }
        sakuraEngine.envExpander.selfname = sakuraName
        if let kero = keroName {
            sakuraEngine.envExpander.keroname = kero
        }
        Log.debug("[GhostManager] Saved character names - Sakura: \(sakuraName), Kero: \(keroName ?? "none")")
    }

    // MARK: - Public API

    func start() {
        Log.info("[GhostManager] start() called for ghost at: \(ghostURL.path)")
        setupWindows()
        setupRightClickMenu()
        Log.debug("[GhostManager] Windows setup complete")

        // Show a placeholder surface immediately so the user sees the ghost
        DispatchQueue.main.async {
            self.updateSurface(id: 0)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let ghostRoot = self.ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
            Log.debug("[GhostManager] Ghost root: \(ghostRoot.path)")
            let fm = FileManager.default

            // Load ghost configuration from descript.txt
            if let config = GhostConfiguration.load(from: ghostRoot) {
                self.ghostConfig = config
                self.activeShellName = config.defaultShellDirectory.isEmpty ? "master" : config.defaultShellDirectory
                self.loadDressupConfiguration()
                Log.info("[GhostManager] Loaded ghost configuration: \(config.name)")
                Log.debug("[GhostManager]   - Sakura: \(config.sakuraName), Kero: \(config.keroName ?? "none")")
                Log.debug("[GhostManager]   - SHIORI: \(config.shiori)")
                Log.debug("[GhostManager]   - Default shell: \(config.defaultShellDirectory)")

                // Apply configuration settings to environment
                self.applyGhostConfiguration(config, ghostRoot: ghostRoot)
                DispatchQueue.main.async {
                    self.applyDefaultDressupBindings(for: self.currentScope)
                }
                
                // Initialization notifies (hwnd, capability, OnNotifySelfInfo etc.)
                // are sent later after EventBridge registration and window creation.
            } else {
                Log.info("[GhostManager] Failed to load ghost configuration from descript.txt")
            }

            // Load balloon configuration from ghost/balloon/descript.txt
            // Try to find balloon directory in ghost root first
            let balloonPath = self.ghostURL.appendingPathComponent("balloon", isDirectory: true).path
            let balloonDescriptPath = (balloonPath as NSString).appendingPathComponent("descript.txt")
            if let config = BalloonConfig.load(from: balloonDescriptPath) {
                self.balloonConfig = config
                self.balloonImageLoader = BalloonImageLoader(balloonPath: balloonPath)
                Log.info("[GhostManager] Loaded balloon configuration: \(config.name)")
            } else {
                Log.info("[GhostManager] Failed to load balloon configuration from \(balloonDescriptPath)")
            }

            guard let contents = try? fm.contentsOfDirectory(at: ghostRoot, includingPropertiesForKeys: nil) else {
                NSLog("[GhostManager] Failed to read contents of \(ghostRoot.path)")
                return
            }

            // yaya.txt から辞書リストを読み込む（順序が重要）
            // includeディレクティブも再帰的に処理する
            var dicCollector = DicCollector()
            let yayaTxtPath = ghostRoot.appendingPathComponent("yaya.txt")
            if let yayaContent = (try? String(contentsOf: yayaTxtPath, encoding: .utf8)) ??
                                 (try? String(contentsOf: yayaTxtPath, encoding: .shiftJIS)) {
                Log.debug("[GhostManager] Found yaya.txt, parsing dictionary list with includes...")
                collectDicEntries(content: yayaContent, baseURL: ghostRoot, sourceName: "yaya.txt",
                                  collector: &dicCollector, visited: [])
                Log.debug("[GhostManager] Found \(dicCollector.entries.count) dictionaries (including from includes, charset: \(dicCollector.globalCharset ?? "auto")): \(dicCollector.entries.prefix(5).map { $0.path })...")
            } else {
                // yaya.txt がない場合は全ファイルをロード
                dicCollector.entries = contents.filter { $0.pathExtension.lowercased() == "dic" }.map {
                    DicEntry(path: $0.lastPathComponent, encoding: nil, sourceConfig: "(fallback)", sourceLine: 0)
                }
                Log.debug("[GhostManager] yaya.txt not found, loading all \(dicCollector.entries.count) .dic files")
            }

            guard let adapter = YayaAdapter() else {
                Log.info("[GhostManager] Failed to initialize YayaAdapter.")
                return
            }
            Log.debug("[GhostManager] YayaAdapter initialized successfully")

            // Connect ResourceManager to YayaAdapter for SHIORI resource handling
            adapter.resourceManager = self.resourceManager

            self.yayaAdapter = adapter
            // Register this ghost to receive NOTIFY broadcasts
            DispatchQueue.main.async {
                self.eventToken = EventBridge.shared.register(adapter: adapter, ghostManager: self)
            }

            // 全辞書をロード（yaya_coreが並列化やキャッシュで最適化すべき）
            Log.debug("[GhostManager] Starting dictionary load...")
            let loadStart = Date()
            guard adapter.load(ghostRoot: ghostRoot, dicEntries: dicCollector.entries, encoding: dicCollector.globalCharset ?? "auto") else {
                Log.info("[GhostManager] Failed to load ghost with Yaya.")
                return
            }
            let loadTime = Date().timeIntervalSince(loadStart)
            Log.debug("[GhostManager] Dictionary load complete in \(String(format: "%.2f", loadTime))s")

            let defaults = UserDefaults.standard
            let bootCount = defaults.integer(forKey: "OurinBootCount")

            // Per UKADOC, OnFirstBoot/OnBoot are GET events (not NOTIFY).
            // Only emit an internal OnInitialize notify; GET is handled below via obtainBootScript().
            DispatchQueue.main.async {
                EventBridge.shared.notify(.OnInitialize)
                defaults.set(bootCount + 1, forKey: "OurinBootCount")
            }

            // Start EventBridge immediately after OnBoot load (dictionary loading completed)
            Log.info("[GhostManager] Starting EventBridge immediately after OnBoot load")
            DispatchQueue.main.async {
                self.startEventBridgeIfNeeded()
            }

            // Request boot script with a timeout; keep placeholder visible meanwhile.
            Log.info("[GhostManager] Requesting boot script (OnFirstBoot/OnBoot)...")
            let sem = DispatchSemaphore(value: 0)

            DispatchQueue.global(qos: .userInitiated).async {
                let script = self.obtainBootScript(using: adapter, bootCount: bootCount)
                if let script = script {
                    let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Log.debug("[GhostManager] Boot script resolved (len=\(trimmed.count))")
                        // Print a safe preview via NSLog so it always appears in logs
                        let preview = trimmed.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
                        NSLog("[GhostManager] Boot script preview: \(preview)")
                        DispatchQueue.main.async {
                            self.runScript(trimmed)
                        }
                    } else {
                        NSLog("[GhostManager] Boot script is whitespace-only after trim; skipping display")
                    }
                }
                sem.signal()
            }

            // If OnBoot takes too long, just wait - EventBridge is already started
            let timeout: DispatchTime = .now() + .seconds(5)
            if sem.wait(timeout: timeout) == .timedOut {
                Log.info("[GhostManager] OnBoot timed out (5s). EventBridge already running, keeping placeholder.")
            }

            // Send initialization NOTIFYs after boot (windows and EventBridge exist)
            if let config = self.ghostConfig {
                DispatchQueue.main.async {
                    self.sendInitializationNotifies(config: config)
                    NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
                }
            }
        }
    }

    func shutdown() {
        NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
        NotificationCenter.default.removeObserver(self)
        if let config = ghostConfig,
           let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher {
            dispatcher.onGhostExit(
                windows: characterWindows.sorted(by: { $0.key < $1.key }).map { $0.value },
                ghostName: config.name,
                shellName: activeShellName,
                ghostID: config.id ?? ghostURL.lastPathComponent,
                path: ghostURL.path
            )
        }
        for timer in localEventTimers.values {
            timer.invalidate()
        }
        localEventTimers.removeAll()
        for timer in remoteEventTimers.values {
            timer.invalidate()
        }
        remoteEventTimers.removeAll()
        for timer in pluginEventTimers.values {
            timer.invalidate()
        }
        pluginEventTimers.removeAll()
        for w in characterWindows.values { w.orderOut(nil) }
        for w in balloonWindows.values { w.orderOut(nil) }
        characterWindows.removeAll()
        balloonWindows.removeAll()
        yayaAdapter?.unload()
        yayaAdapter = nil
        if let token = eventToken { EventBridge.shared.unregister(token); eventToken = nil }
    }

    // MARK: - Scripting

    /// 今すぐトークを再生してよい状態かどうか（OnSecondChange 等の Reference3 / GET・NOTIFY 切替に使用）。
    /// 再生中・タイムクリティカルセクション中・受動/誘導モード中は false。
    func canPlayTalkNow() -> Bool {
        return !isPlaying && !timeCriticalActive && !passiveModeActive && !inductionModeActive
    }

    // MARK: - Termination sequence

    /// 終了シーケンスを開始する。OnClose を GET で送り、応答スクリプト（お別れトーク、通常は末尾 \-）を
    /// 再生してから終了する（UKADOC）。
    /// - Parameters:
    ///   - reason: OnClose の Reference0（user / system 等）
    ///   - replyToTermination: applicationShouldTerminate から呼ばれた場合 true（reply で完了を通知する）
    /// - Returns: シーケンスを開始した場合 true（既に終了処理中なら false）
    @discardableResult
    func beginCloseSequence(reason: String = "user", replyToTermination: Bool = false) -> Bool {
        guard !isShuttingDown else { return false }
        isShuttingDown = true
        awaitingTerminateReply = replyToTermination
        Log.info("[GhostManager] Close sequence started (reason: \(reason))")

        DispatchQueue.global(qos: .userInitiated).async {
            var script = ""
            if let yaya = self.yayaAdapter {
                let hdrs: [String: String] = ["Charset": "UTF-8", "SecurityLevel": "local", "Sender": "Ourin"]
                if let r = yaya.request(method: "GET", id: "OnClose", headers: hdrs, refs: [reason], timeout: 4.0),
                   r.ok, let v = r.value {
                    script = v.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                script = BridgeToSHIORI.handle(event: "OnClose", references: [reason])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            DispatchQueue.main.async {
                if script.isEmpty {
                    self.finalizeTermination()
                } else {
                    // \- が含まれていなくても再生完了後に終了できるようフラグを立てる
                    self.terminateAfterPlayback = true
                    self.runScript(script)
                }
            }
        }
        return true
    }

    /// ゴースト終了を確定する（\- ハンドラ／OnClose 応答再生完了から呼ばれる）。
    func finalizeTermination() {
        guard !didFinalizeTermination else { return }
        didFinalizeTermination = true
        isShuttingDown = true
        Log.info("[GhostManager] Finalizing ghost termination")
        DispatchQueue.main.async {
            if self.awaitingTerminateReply {
                self.awaitingTerminateReply = false
                NSApp.reply(toApplicationShouldTerminate: true)
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Entity reference / Jump

    /// \&[ID] の実体参照を解決する。数値文字参照（#NNN / #xHHHH）と主要な名前付き実体に対応。
    static func resolveEntityReference(_ id: String) -> String? {
        // 数値文字参照: #123 / #x30A2 / 0x30A2
        if id.hasPrefix("#") || id.lowercased().hasPrefix("0x") {
            var body = id.hasPrefix("#") ? String(id.dropFirst()) : String(id.dropFirst(2))
            var radix = 10
            if body.lowercased().hasPrefix("x") {
                body = String(body.dropFirst())
                radix = 16
            } else if id.lowercased().hasPrefix("0x") {
                radix = 16
            }
            guard let value = UInt32(body, radix: radix), let scalar = UnicodeScalar(value) else { return nil }
            return String(scalar)
        }
        // 名前付き実体（HTML互換の主要なもの）
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
            "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–"
        ]
        return named[id.lowercased()]
    }

    /// \j[ID] - ジャンプタグ。URL/ファイルはオープン、それ以外はイベント起動（raise 相当）として扱う。
    func handleJumpCommand(args: [String]) {
        guard let target = args.first?.trimmingCharacters(in: .whitespaces), !target.isEmpty else {
            Log.info("[GhostManager] \\j with no target (ignored)")
            return
        }
        let lowered = target.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            // URLジャンプ: 既定ブラウザで開く
            playbackQueue.append(.deferredCommand {
                if let url = URL(string: target) {
                    Log.info("[GhostManager] \\j opening URL: \(target)")
                    NSWorkspace.shared.open(url)
                }
            })
        } else if lowered.hasPrefix("file://") {
            playbackQueue.append(.deferredCommand {
                if let url = URL(string: target) {
                    Log.info("[GhostManager] \\j opening file: \(target)")
                    NSWorkspace.shared.open(url)
                }
            })
        } else if target.hasPrefix("On") || target.hasPrefix("\\") == false && lowered.hasPrefix("on") {
            // イベントジャンプ: SHIORI へ GET し、返値スクリプトを再生する
            let references = Array(args.dropFirst())
            playbackQueue.append(.deferredCommand { [weak self] in
                guard let self else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let yaya = self.yayaAdapter,
                          let r = yaya.request(method: "GET", id: target, headers: ["Charset": "UTF-8"], refs: references, timeout: 3.0),
                          r.ok, let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else {
                        Log.info("[GhostManager] \\j[\(target)] event jump returned no script")
                        return
                    }
                    DispatchQueue.main.async { self.runScript(v) }
                }
            })
        } else {
            // TODO: スクリプト内ラベルへのジャンプ等は未対応
            Log.info("[GhostManager] \\j[\(target)] - unsupported jump target (ignored)")
        }
    }

    func runScript(_ script: String) {
        let preview = script.prefix(200)
        Log.debug("[GhostManager] runScript called with: \(preview)")
        // Avoid clearing the balloon when script is effectively empty (whitespace only)
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        beginPluginTalkNotification(script: trimmed, reasons: ["owned"])

        // Reset playback state and balloon text for new script
        playbackQueue.removeAll()
        isPlaying = false
        quickMode = false
        preciseBase = Date()
        // 新しいスクリプト開始 = スクリプトブレーク扱い: タイムクリティカル区間と \* 指定を解除
        timeCriticalActive = false
        choiceTimeoutDisabled = false
        for vm in balloonViewModels.values {
            vm.text = ""
            vm.anchorActive = false
        }
        typingInterval = defaultTypingInterval
        let previousPluginOrigin = currentScriptIsPluginOrigin
        currentScriptIsPluginOrigin = false
        sakuraEngine.run(script: trimmed)
        currentScriptIsPluginOrigin = previousPluginOrigin
        startPlaybackIfNeeded()
    }

    /// Run a script originating from NOTIFY. If the script contains no visible text
    /// tokens, keep the current balloon text and apply only commands (surface/scope/etc.).
    func runNotifyScript(_ script: String) {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let hasText = sakuraEngine.containsText(in: trimmed)
        if hasText {
            beginPluginTalkNotification(script: trimmed, reasons: ["owned"])
            // New visible text: cancel pending playback and clear balloon
            playbackQueue.removeAll()
            isPlaying = false
            quickMode = false
            preciseBase = Date()
            timeCriticalActive = false
            choiceTimeoutDisabled = false
            for vm in balloonViewModels.values {
                vm.text = ""
                vm.anchorActive = false
            }
            typingInterval = defaultTypingInterval
        }
        let previousPluginOrigin = currentScriptIsPluginOrigin
        currentScriptIsPluginOrigin = false
        sakuraEngine.run(script: trimmed)
        currentScriptIsPluginOrigin = previousPluginOrigin
        startPlaybackIfNeeded()
    }

    func runPluginScript(_ script: String, options: Set<String>) {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var reasons = options.intersection(["plugin-script", "plugin-event", "notranslate"])
        if reasons.isEmpty {
            reasons.insert("plugin-script")
        }
        if options.contains("nobreak") {
            beginPluginTalkNotification(script: trimmed, reasons: reasons)
            let previousPluginOrigin = currentScriptIsPluginOrigin
            currentScriptIsPluginOrigin = true
            sakuraEngine.run(script: trimmed)
            currentScriptIsPluginOrigin = previousPluginOrigin
            startPlaybackIfNeeded()
        } else {
            beginPluginTalkNotification(script: trimmed, reasons: reasons)
            playbackQueue.removeAll()
            isPlaying = false
            quickMode = false
            preciseBase = Date()
            timeCriticalActive = false
            choiceTimeoutDisabled = false
            for vm in balloonViewModels.values {
                vm.text = ""
                vm.anchorActive = false
            }
            typingInterval = defaultTypingInterval
            let previousPluginOrigin = currentScriptIsPluginOrigin
            currentScriptIsPluginOrigin = true
            sakuraEngine.run(script: trimmed)
            currentScriptIsPluginOrigin = previousPluginOrigin
            startPlaybackIfNeeded()
        }
    }

    func matchesPluginTarget(_ token: String) -> Bool {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        var candidates = [
            ghostURL.path,
            ghostURL.standardizedFileURL.path,
            ghostURL.lastPathComponent,
            ghostConfig?.name,
            ghostConfig?.id,
            ghostConfig?.title,
            ghostConfig?.sakuraName,
            ghostConfig?.keroName
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        candidates.append(contentsOf: characterWindows.values.map { String($0.windowNumber).lowercased() })
        return candidates.contains(normalized)
    }

    private func beginPluginTalkNotification(script: String, reasons: Set<String>, eventID: String = "", references: [String] = []) {
        guard sakuraEngine.containsText(in: script) else { return }
        let context = PluginTalkNotificationContext(script: script, reasons: reasons, eventID: eventID, references: references)
        pendingPluginTalkAfter = context
        emitPluginTalkNotification(context, phase: .before)
    }

    private func emitPluginTalkAfterIfNeeded() {
        guard let context = pendingPluginTalkAfter else { return }
        pendingPluginTalkAfter = nil
        emitPluginTalkNotification(context, phase: .after)
    }

    private func emitPluginTalkNotification(_ context: PluginTalkNotificationContext, phase: PluginOtherGhostTalkTiming) {
        guard !isEmittingPluginTalk,
              let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher else { return }
        isEmittingPluginTalk = true
        defer { isEmittingPluginTalk = false }
        let ghostName = ghostConfig?.name ?? ghostURL.lastPathComponent
        let baseName = ghostConfig?.sakuraName ?? ghostName
        dispatcher.onOtherGhostTalk(
            ghostName: ghostName,
            baseName: baseName,
            reasons: context.reasons.sorted().joined(separator: ","),
            eventID: context.eventID,
            script: context.script,
            refs: context.references,
            phase: phase
        )
    }

    // MARK: - SakuraScriptEngineDelegate

    func sakuraEngine(_ engine: SakuraScriptEngine, didEmit token: SakuraScriptEngine.Token) {
        // Enqueue tokens for playback with per-character typing delay for text
        NSLog("[GhostManager] sakuraEngine didEmit token: \(token)")
        switch token {
        case .scope(let id):
            playbackQueue.append(.scope(id))
        case .surface(let id):
            playbackQueue.append(.surface(id))
        case .surfaceNamed(let name):
            // \s[alias]: 文字列別名を surfaceNameAliases で解決して数値サーフェスへ
            if let id = surfaceNameAliases[name.lowercased()] {
                playbackQueue.append(.surface(id))
            } else {
                NSLog("[GhostManager] Unknown surface alias \(name) in \\s[...]")
            }
        case .text(let text):
            // Display text character by character with typing effect
            for ch in text { playbackQueue.append(.text(ch)) }
        case .newline:
            playbackQueue.append(.newline)
         case .newlineVariation(let type):
              // \n[half] or \n[percent] - custom newline height
              handleNewline(type: type)
              scheduleNext(after: typingInterval)
              return
        case .balloon(let id):
            // \bN or \b[ID] - change balloon ID
            Log.debug("[GhostManager] Switching to balloon ID: \(id)")
            switchBalloon(to: id, scope: currentScope)
            
        case .appendMode:
            // \C - append to previous balloon
            Log.debug("[GhostManager] Append mode enabled - will not clear balloon text")
            appendModeEnabled = true
            // Append mode keeps the current balloon open and adds new text
            // The balloon view will continue displaying the previous content
         case .end:
            playbackQueue.append(.end)
        case .animation(let id, let wait):
            // \i[ID] or \i[ID,wait] - play surface animation
            if wait {
                // Start animation then enqueue a wait-for-animation unit
                playAnimation(id: id, wait: false)
                playbackQueue.append(.waitAnimation(id))
            } else {
                // Play animation without waiting
                playAnimation(id: id, wait: false)
            }
        // New token types - added for comprehensive Sakura Script support
        case .wait:
            // \t - タイムクリティカルセクション（UKADOC）。
            // スクリプトブレークまたは \e までマウス系イベント通知を抑止する（ポーズではない）。
            playbackQueue.append(.deferredCommand { [weak self] in
                self?.timeCriticalActive = true
            })

        case .endConversation(let clearBalloon):
            // \x or \x[noclear] - End conversation
            playbackQueue.append(.clickWait(noclear: !clearBalloon))

        case .choiceCancel:
            // \z - Choice cancellation
            Log.debug("[GhostManager] Choice cancel marker")
            choiceHasCancelOption = true

        case .choiceMarker:
            // \* - このスクリプトの選択肢をタイムアウトさせない（UKADOC）
            Log.debug("[GhostManager] \\* - disabling choice timeout for this script")
            choiceTimeout = nil
            choiceTimeoutDisabled = true

        case .anchor:
            // \a - 旧仕様: OnAITalk（ランダムトーク）を発生させる（UKADOC）。
            // GET で送り、返値スクリプトがあれば再生する。
            Log.debug("[GhostManager] \\a - raising OnAITalk (legacy)")
            playbackQueue.append(.deferredCommand { [weak self] in
                guard let self else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let yaya = self.yayaAdapter,
                          let r = yaya.request(method: "GET", id: "OnAITalk", timeout: 3.0), r.ok,
                          let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return }
                    DispatchQueue.main.async { self.runScript(v) }
                }
            })

        case .choiceLineBr:
            // \- - 当該ゴーストの終了（UKADOC）。先行テキストの表示後に終了処理を行う。
            Log.info("[GhostManager] \\- - ghost termination requested by script")
            playbackQueue.append(.deferredCommand { [weak self] in
                self?.finalizeTermination()
            })

        case .moveAway:
            // \4 - 相方キャラクターから離れる方向へ移動（UKADOC）
            moveAwayFromPartner(scope: currentScope)

        case .moveClose:
            // \5 - 相方キャラクターと接触する距離まで移動（UKADOC）
            moveTowardPartner(scope: currentScope)
        
        case .bootGhost:
            // \+ - Boot/call other ghost via SSTP
            // The ghost name should be specified in a following command or in context
            Log.debug("[GhostManager] Boot ghost command - attempting to boot ghost via SSTP")
            bootOtherGhost()
        
        case .bootAllGhosts:
            // \_+ - Boot all ghosts via SSTP broadcast
            Log.debug("[GhostManager] Boot all ghosts command")
            bootAllGhosts()
        
        case .openPreferences:
            // \v - このスクリプト以降、最前面表示（stay-on-top）にする（UKADOC）。
            // 旧実装の「設定ウィンドウを開く」は誤り。
            playbackQueue.append(.deferredCommand { [weak self] in
                self?.setWindowState(state: "stayontop")
            })
        
        case .openURL:
            // \6 - execute SNTP correction action (ukadoc semantics)
            executeSNTPApply()
        
        case .openEmail:
            // \7 - begin SNTP sequence (same family as \![executesntp])
            executeSNTP()
        
        case .playSound(let filename):
            // \8[filename] - Play sound file
            playSound(filename: filename)
        
        case .command(let name, let args):
            // SakuraScript タグは大文字小文字を区別する（\_V=再生完了待ち と \_v=再生 は別タグ）。
            // 下の switch は小文字化して照合するため、大文字を含むタグはここで先に分岐する。
            if name == "_V" {
                // \_V - wait for currently playing voice/sound to complete
                let duration = estimatedSoundWaitDuration()
                if duration > 0 {
                    playbackQueue.append(.wait(duration))
                }
                break
            }
            switch name.lowercased() {
            case "w":
                if let first = args.first, let n = Int(first) {
                    if (1...9).contains(n) {
                        playbackQueue.append(.wait(Double(n) * 0.05))
                    } else if n >= 10 {
                        // \w10 => 50ms then output "0"
                        playbackQueue.append(.wait(0.05))
                        playbackQueue.append(.text("0"))
                    }
                } else {
                    // No arg: default pause
                    playbackQueue.append(.wait(defaultTypingInterval))
                }
            case "_w":
                if let first = args.first, let ms = Double(first) {
                    playbackQueue.append(.wait(ms/1000.0))
                }
            case "__w":
                if let first = args.first?.lowercased() {
                    if first == "clear" {
                        playbackQueue.append(.resetPrecise)
                    } else if first == "animation" {
                        // \__w[animation,ID] – wait until SERIKO animation with ID completes
                        if args.count >= 2, let animID = Int(args[1]) {
                            playbackQueue.append(.waitAnimation(animID))
                        }
                    } else if let ms = Double(first) {
                        playbackQueue.append(.waitUntil(ms/1000.0))
                    }
                }
            case "x":
                let noclear = (args.first?.lowercased() == "noclear")
                playbackQueue.append(.clickWait(noclear: noclear))
            case "_q":
                quickMode.toggle()
            case "__q":
                handleQueuedChoiceCommand(args: args)
            case "__t":
                // \__t メタタグ: 教えてダイアログを開く（\![open,teachbox] と同等）
                playbackQueue.append(.deferredCommand {
                    DispatchQueue.main.async { self.showTeachBoxDialog() }
                })
            case "_n":
                // \_n: 自動改行（ワードラップ）抑制メタタグ。現行レンダラはワードラップ非依存の
                // ため認識のみ（誤った改行挿入はしない）。
                NSLog("[GhostManager] \\_n (no-wrap) recognized")
            case "__v":
                // \__v: 代替読み/音声制御メタタグ。発話表示には影響しないため認識して無視。
                NSLog("[GhostManager] \\__v recognized (no-op)")
            case "!":
                NSLog("[GhostManager] ! command with args: \(args)")
                if let first = args.first?.lowercased() {
                    NSLog("[GhostManager] ! command first arg: \(first)")
                    if first == "raise" {
                        // \![raise,イベント名,Reference0,Reference1,...]
                        // Explicitly trigger a SHIORI event from script
                        if args.count >= 2 {
                            let eventName = args[1]
                            var params: [String: String] = [:]
                            // Collect Reference parameters (Reference0, Reference1, etc.)
                            for i in 2..<args.count {
                                params["Reference\(i-2)"] = args[i]
                            }
                            // Convert event name to EventID if possible, or use custom event
                            if let eventID = EventID(rawValue: eventName) {
                                EventBridge.shared.notify(eventID, params: params)
                            } else {
                                // Custom event name - still broadcast it
                                Log.debug("[GhostManager] Raising custom event: \(eventName) with params: \(params)")
                                EventBridge.shared.notifyCustom(eventName, params: params)
                            }
                        }
                    } else if first == "notify", args.count >= 2 {
                        // \![notify,event,ref0,ref1,...]
                        let eventName = args[1]
                        let refs = Array(args.dropFirst(2))
                        dispatchLocalEvent(event: eventName, references: refs, notifyOnly: true)
                    } else if first == "raiseother", args.count >= 3 {
                        // \![raiseother,ghost,event,ref0,ref1,...]
                        let ghostSpec = args[1]
                        let eventName = args[2]
                        let refs = Array(args.dropFirst(3))
                        raiseOtherGhostEvent(ghostSpec: ghostSpec, event: eventName, references: refs, notifyOnly: false)
                    } else if first == "embed", args.count >= 2 {
                        // \![embed,event,ref0,ref1,...]
                        let eventName = args[1]
                        let refs = Array(args.dropFirst(2))
                        executeEmbeddedEvent(event: eventName, references: refs)
                    } else if first == "timerraise", args.count >= 4 {
                        // \![timerraise,ms,repeat,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let eventName = args[3]
                        let refs = Array(args.dropFirst(4))
                        scheduleLocalEventTimer(intervalMs: intervalMs, repeatSpec: repeatSpec, event: eventName, references: refs, notifyOnly: false)
                    } else if first == "timernotify", args.count >= 4 {
                        // \![timernotify,ms,repeat,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let eventName = args[3]
                        let refs = Array(args.dropFirst(4))
                        scheduleLocalEventTimer(intervalMs: intervalMs, repeatSpec: repeatSpec, event: eventName, references: refs, notifyOnly: true)
                    } else if first == "timerraiseother", args.count >= 5 {
                        // \![timerraiseother,ms,repeat,ghost,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let ghostSpec = args[3]
                        let eventName = args[4]
                        let refs = Array(args.dropFirst(5))
                        scheduleTimerRaiseOther(intervalMs: intervalMs, repeatSpec: repeatSpec, ghostSpec: ghostSpec, event: eventName, references: refs, notifyOnly: false)
                    } else if first == "raiseplugin", args.count >= 3 {
                        // \![raiseplugin,plugin,event,ref0,ref1,...]
                        let pluginSpec = args[1]
                        let eventName = args[2]
                        let refs = Array(args.dropFirst(3))
                        dispatchPluginEvent(pluginSpec: pluginSpec, event: eventName, references: refs, notifyOnly: false)
                    } else if first == "timerraiseplugin", args.count >= 5 {
                        // \![timerraiseplugin,ms,repeat,plugin,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let pluginSpec = args[3]
                        let eventName = args[4]
                        let refs = Array(args.dropFirst(5))
                        scheduleTimerPluginEvent(intervalMs: intervalMs, repeatSpec: repeatSpec, pluginSpec: pluginSpec, event: eventName, references: refs, notifyOnly: false)
                    } else if first == "notifyother", args.count >= 3 {
                        // \![notifyother,ghost,event,ref0,ref1,...]
                        let ghostSpec = args[1]
                        let eventName = args[2]
                        let refs = Array(args.dropFirst(3))
                        raiseOtherGhostEvent(ghostSpec: ghostSpec, event: eventName, references: refs, notifyOnly: true)
                    } else if first == "timernotifyother", args.count >= 5 {
                        // \![timernotifyother,ms,repeat,ghost,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let ghostSpec = args[3]
                        let eventName = args[4]
                        let refs = Array(args.dropFirst(5))
                        scheduleTimerRaiseOther(intervalMs: intervalMs, repeatSpec: repeatSpec, ghostSpec: ghostSpec, event: eventName, references: refs, notifyOnly: true)
                    } else if first == "notifyplugin", args.count >= 3 {
                        // \![notifyplugin,plugin,event,ref0,ref1,...]
                        let pluginSpec = args[1]
                        let eventName = args[2]
                        let refs = Array(args.dropFirst(3))
                        dispatchPluginEvent(pluginSpec: pluginSpec, event: eventName, references: refs, notifyOnly: true)
                    } else if first == "timernotifyplugin", args.count >= 5 {
                        // \![timernotifyplugin,ms,repeat,plugin,event,ref0,ref1,...]
                        let intervalMs = Int(args[1]) ?? 0
                        let repeatSpec = args[2]
                        let pluginSpec = args[3]
                        let eventName = args[4]
                        let refs = Array(args.dropFirst(5))
                        scheduleTimerPluginEvent(intervalMs: intervalMs, repeatSpec: repeatSpec, pluginSpec: pluginSpec, event: eventName, references: refs, notifyOnly: true)
                    } else if first == "change", args.count >= 3 {
                        // \![change,ghost|shell|balloon,target]
                        let target = args[1].lowercased()
                        let value = args[2]
                        switch target {
                        case "ghost":
                            let options = Array(args.dropFirst(3))
                            switchGhost(named: value, options: options)
                        case "shell":
                            let options = Array(args.dropFirst(3))
                            _ = switchShell(named: value, raiseEvent: options.contains("--option=raise-event"))
                        case "balloon":
                            let options = Array(args.dropFirst(3))
                            _ = switchBalloon(named: value, scope: currentScope, raiseEvent: options.contains("--option=raise-event"))
                        default:
                            Log.info("[GhostManager] Unsupported change target: \(target)")
                        }
                    } else if first == "call", args.count >= 3 {
                        // \![call,ghost,target(,--option=raise-event)]
                        let target = args[1].lowercased()
                        let value = args[2]
                        if target == "ghost" {
                            let options = Array(args.dropFirst(3))
                            callGhost(named: value, options: options)
                        }
                    } else if first == "get", args.count >= 2 {
                        let getType = args[1].lowercased()
                        if getType == "property", args.count >= 4 {
                            // \![get,property,イベント名,プロパティ名]
                            // Get property value and raise SHIORI event with value in Reference0
                            let eventName = args[2]
                            let propertyKey = args[3]
                            let propertyValue = sakuraEngine.propertyManager.get(propertyKey) ?? ""
                            var params: [String: String] = ["Reference0": propertyValue]
                            // Additional references if provided
                            for i in 4..<args.count {
                                params["Reference\(i-3)"] = args[i]
                            }
                            Log.debug("[GhostManager] Property get: \(propertyKey) = \(propertyValue), raising event: \(eventName)")
                            EventBridge.shared.notifyCustom(eventName, params: params)
                        } else {
                            let eventByGetType: [String: String] = [
                                "word": "OnGetWord",
                                "string": "OnGetString",
                                "integer": "OnGetInteger",
                                "wordcount": "OnGetWordCount",
                                "wordposition": "OnGetWordPosition"
                            ]
                            if let eventID = eventByGetType[getType] {
                                let references = Array(args.dropFirst(2))
                                Log.debug("[GhostManager] Dispatching SHIORI GET event: \(eventID), refs=\(references.count)")
                                _ = requestDialogEvent(eventID: eventID, references: references)
                            }
                        }
                    } else if first == "set", args.count >= 3, args[1].lowercased() == "property" {
                        // \![set,property,プロパティ名,値]
                        // Set property value
                        let propertyKey = args[2]
                        let propertyValue = args.count >= 4 ? args[3] : ""
                        let success = sakuraEngine.propertyManager.set(propertyKey, value: propertyValue)
                        // scope(N).surface.num / animation.num への SET は実サーフェス/アニメへ反映する（UKADOC: WRITE 可）
                        applyScopePropertySideEffect(key: propertyKey, value: propertyValue)
                        Log.debug("[GhostManager] Property set: \(propertyKey) = \(propertyValue), success: \(success)")
                    } else if first == "quicksection", args.count >= 2 {
                        let v = args[1].lowercased()
                        quickMode = (v == "1" || v == "true")
                    } else if first == "wait", args.count >= 2, args[1].lowercased() == "syncobject" {
                        let name = args.count >= 3 ? args[2] : ""
                        let timeout = args.count >= 4 ? (Double(args[3]) ?? 0) : 0
                        let delay = timeout <= 0 ? TimeInterval.infinity : timeout/1000.0
                        let result = SyncCenter.shared.wait(name: name, timeout: delay)
                        playbackQueue.append(.wait(result))
                    } else if first == "wait", args.count >= 2, args[1].lowercased() == "timer" {
                        // \![wait,timer,ms]
                        if args.count >= 3, let ms = Double(args[2]) {
                            playbackQueue.append(.wait(max(0, ms / 1000.0)))
                        }
                    } else if first == "signal", args.count >= 2, args[1].lowercased() == "syncobject" {
                        let name = args.count >= 3 ? args[2] : ""
                        SyncCenter.shared.signal(name: name)
                    } else if first == "input", args.count >= 2 {
                        // Compatibility aliases: \![input,*]
                        let inputType = args[1].lowercased()
                        let parsed = parseCommandArguments(Array(args.dropFirst(2)))
                        let id = parsed.positionals.first ?? parsed.options["id"] ?? "input"
                        let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                            ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)

                        if inputType == "textbox" || inputType == "text" {
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showInputBoxDialog(id: id, timeoutMs: timeoutMs, initialText: initialText)
                                }
                            })
                        } else if inputType == "pass" || inputType == "password" {
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showPasswordInputDialog(id: id, timeoutMs: timeoutMs, initialText: initialText)
                                }
                            })
                        } else if inputType == "date" {
                            let csv = parsed.options["text"]?.split(separator: ",").map(String.init) ?? []
                            let year = csv.count >= 1 ? Int(csv[0]) : (parsed.positionals.count >= 3 ? Int(parsed.positionals[2]) : nil)
                            let month = csv.count >= 2 ? Int(csv[1]) : (parsed.positionals.count >= 4 ? Int(parsed.positionals[3]) : nil)
                            let day = csv.count >= 3 ? Int(csv[2]) : (parsed.positionals.count >= 5 ? Int(parsed.positionals[4]) : nil)
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showDateInputDialog(id: id, timeoutMs: timeoutMs, year: year, month: month, day: day)
                                }
                            })
                        } else if inputType == "choice" {
                            let choices = parsed.positionals.count >= 3
                                ? Array(parsed.positionals.dropFirst(2))
                                : parsed.options["choices"]?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } ?? []
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showChoiceInputDialog(id: id, timeoutMs: timeoutMs, choices: choices)
                                }
                            })
                        } else if inputType == "capture" {
                            // Minimal compatibility: route to text input and raise OnUserInput.
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showInputBoxDialog(id: id, timeoutMs: timeoutMs, initialText: initialText)
                                }
                            })
                        }
                    } else if first == "file", args.count >= 2 {
                        let fileAction = args[1].lowercased()
                        if fileAction == "open" {
                            let eventID = args.count >= 3 ? args[2] : ""
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showSystemDialog(type: "open", parameters: ["--id=\(eventID)"])
                                }
                            })
                        } else if fileAction == "save" {
                            let eventID = args.count >= 3 ? args[2] : ""
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showSystemDialog(type: "save", parameters: ["--id=\(eventID)"])
                                }
                            })
                        }
                    } else if first == "hide" {
                        setCurrentWindowHidden(true)
                    } else if first == "show" {
                        setCurrentWindowHidden(false)
                    } else if first == "focus" {
                        focusCurrentWindow()
                    } else if first == "b" {
                        // \![b] compatibility: bring/focus current window.
                        focusCurrentWindow()
                    } else if first == "minimize" {
                        setWindowState(state: "minimize")
                    } else if first == "maximize" {
                        maximizeCurrentWindow()
                    } else if first == "open", args.count >= 2 {
                        let openType = args[1].lowercased()
                        switch openType {
                        case "configurationdialog", "config":
                            // \![open,configurationdialog,setup] / \![open,config,setup]
                            if args.count >= 3, args[2].lowercased() == "setup" {
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.showNameInputDialog() }
                                })
                            } else {
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.showSettings() }
                                })
                            }
                        case "inputbox":
                            let parsed = parseCommandArguments(Array(args.dropFirst(2)))
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "inputbox"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showInputBoxDialog(id: id, timeoutMs: timeoutMs, initialText: initialText)
                                }
                            })
                        case "passwordinput":
                            let parsed = parseCommandArguments(Array(args.dropFirst(2)))
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "passwordinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let initialText = parsed.options["text"]
                                ?? (parsed.positionals.count >= 3 ? parsed.positionals[2] : "")
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showPasswordInputDialog(id: id, timeoutMs: timeoutMs, initialText: initialText)
                                }
                            })
                        case "dateinput":
                            let parsed = parseCommandArguments(Array(args.dropFirst(2)))
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "dateinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let csv = parsed.options["text"]?.split(separator: ",").map(String.init) ?? []
                            let year = csv.count >= 1 ? Int(csv[0]) : (parsed.positionals.count >= 3 ? Int(parsed.positionals[2]) : nil)
                            let month = csv.count >= 2 ? Int(csv[1]) : (parsed.positionals.count >= 4 ? Int(parsed.positionals[3]) : nil)
                            let day = csv.count >= 3 ? Int(csv[2]) : (parsed.positionals.count >= 5 ? Int(parsed.positionals[4]) : nil)
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showDateInputDialog(id: id, timeoutMs: timeoutMs, year: year, month: month, day: day)
                                }
                            })
                        case "sliderinput":
                            let parsed = parseCommandArguments(Array(args.dropFirst(2)))
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "sliderinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let csv = parsed.options["text"]?.split(separator: ",").map(String.init) ?? []
                            let initial = csv.count >= 1 ? Double(csv[0]) : (parsed.positionals.count >= 3 ? Double(parsed.positionals[2]) : nil)
                            let min = csv.count >= 2 ? Double(csv[1]) : (parsed.positionals.count >= 4 ? Double(parsed.positionals[3]) : nil)
                            let max = csv.count >= 3 ? Double(csv[2]) : (parsed.positionals.count >= 5 ? Double(parsed.positionals[4]) : nil)
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showSliderInputDialog(id: id, timeoutMs: timeoutMs, initial: initial, min: min, max: max)
                                }
                            })
                        case "timeinput":
                            let parsed = parseCommandArguments(Array(args.dropFirst(2)))
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "timeinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let csv = parsed.options["text"]?.split(separator: ",").map(String.init) ?? []
                            let hour = csv.count >= 1 ? Int(csv[0]) : (parsed.positionals.count >= 3 ? Int(parsed.positionals[2]) : nil)
                            let minute = csv.count >= 2 ? Int(csv[1]) : (parsed.positionals.count >= 4 ? Int(parsed.positionals[3]) : nil)
                            let second = csv.count >= 3 ? Int(csv[2]) : (parsed.positionals.count >= 5 ? Int(parsed.positionals[4]) : nil)
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showTimeInputDialog(id: id, timeoutMs: timeoutMs, hour: hour, minute: minute, second: second)
                                }
                            })
                        case "ipinput":
                            let parsed = parseCommandArguments(Array(args.dropFirst(2)))
                            let id = parsed.positionals.first ?? parsed.options["id"] ?? "ipinput"
                            let timeoutMs = parsed.options["timeout"].flatMap(Int.init)
                                ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                            let initialText: String = {
                                if let text = parsed.options["text"] {
                                    return text
                                }
                                if parsed.positionals.count >= 6 {
                                    return parsed.positionals[2...5].joined(separator: ",")
                                }
                                return parsed.positionals.count >= 3 ? parsed.positionals[2] : ""
                            }()
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showIPInputDialog(id: id, timeoutMs: timeoutMs, initialText: initialText)
                                }
                            })
                        case "dialog":
                            if args.count >= 3 {
                                let dialogType = args[2].lowercased()
                                let params = Array(args.dropFirst(3))
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async {
                                        self.showSystemDialog(type: dialogType, parameters: params)
                                    }
                                })
                            }
                        case "teachbox":
                            // \![open,teachbox]
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showTeachBoxDialog()
                                }
                            })
                        case "communicatebox":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.showCommunicateBoxDialog(timeoutMs: nil, initialText: "")
                                }
                            })
                        case "browser":
                            if args.count >= 3 {
                                let target = args[2]
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openURL(target) }
                                })
                            }
                        case "http":
                            if args.count >= 3 {
                                let params = Array(args.dropFirst(2))
                                executeHTTP(subcommand: "http-get", params: params)
                            }
                        case "send":
                            if args.count >= 3 {
                                let target = args[2]
                                let body = args.count >= 4 ? args[3] : ""
                                executeHTTP(subcommand: "http-post", params: [target, body])
                            }
                        case "mailer":
                            if args.count >= 3 {
                                let target = args[2]
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openEmail(target) }
                                })
                            }
                        case "editor", "file":
                            let parsed = parseCommandArguments(Array(args.dropFirst(2)))
                            let path = parsed.positionals.first ?? parsed.options["path"] ?? ""
                            if !path.isEmpty {
                                let line = parsed.options["line"].flatMap(Int.init)
                                    ?? (parsed.positionals.count >= 2 ? Int(parsed.positionals[1]) : nil)
                                let app = parsed.options["app"]
                                let allowExternal = parsed.flags.contains("allow-external")
                                    || (parsed.options["allow-external"]?.lowercased() == "1")
                                    || (parsed.options["allow-external"]?.lowercased() == "true")
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async {
                                        self.openFilePath(path: path, line: line, appName: app, allowExternal: allowExternal)
                                    }
                                })
                            }
                        case "explorer":
                            if args.count >= 4 {
                                let kind = args[2].lowercased()
                                let name = args[3]
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openInstalledTypeDirectory(type: kind, name: name) }
                                })
                            } else if args.count >= 3 {
                                let path = args[2]
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.revealInExplorer(path) }
                                })
                            }
                        case "ghostexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "ghost", name: name) }
                            })
                        case "shellexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "shell", name: name) }
                            })
                        case "balloonexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "balloon", name: name) }
                            })
                        case "headlinesensorexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "headline", name: name) }
                            })
                        case "pluginexplorer":
                            let name = args.count >= 3 ? args[2] : nil
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "plugin", name: name) }
                            })
                        case "calendar":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openInstalledTypeDirectory(type: "calendar") }
                            })
                        case "rateofusegraph", "rateofusegraphballoon", "rateofusegraphtotal", "messenger":
                            if let homeurl = self.ghostConfig?.homeurl, !homeurl.isEmpty {
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openURL(homeurl) }
                                })
                            } else {
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openFilePath("readme.txt") }
                                })
                            }
                        case "readme":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openFilePath("readme.txt") }
                            })
                        case "terms":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.handleGhostTermsConsent() }
                            })
                        case "help":
                            if let homeurl = self.ghostConfig?.homeurl, !homeurl.isEmpty {
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openURL(homeurl) }
                                })
                            } else {
                                playbackQueue.append(.deferredCommand {
                                    DispatchQueue.main.async { self.openFilePath("readme.txt") }
                                })
                            }
                        case "developer", "shiorirequest", "dressupexplorer":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openDeveloperTool(openType) }
                            })
                        case "surfacetest":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openFilePath("surfaces.txt") }
                            })
                        case "aigraph":
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async { self.openFilePath("aigraph.txt") }
                            })
                        default:
                            break
                        }
                    } else if first == "close", args.count >= 2 {
                        let closeType = args[1].lowercased()
                        switch closeType {
                        case "inputbox":
                            let id = args.count >= 3 ? args[2] : "inputbox"
                            emitUserInputCancel(id: id, timedOut: false)
                        case "communicatebox":
                            emitCommunicateInputCancel(timedOut: false)
                        case "dialog":
                            let id = args.count >= 3 ? args[2] : ""
                            emitSystemDialogCancel(type: "dialog", eventID: id)
                        case "teachbox":
                            _ = requestDialogEvent(eventID: "OnTeachInputCancel", references: [])
                        case "websocket":
                            closeWebSocket(params: Array(args.dropFirst(2)))
                        default:
                            break
                        }
                    } else if first == "send", args.count >= 2 {
                        // \![send,websocket,URL,data] / \![send,websocket-binary,URL,base64]
                        let sendType = args[1].lowercased()
                        if sendType == "websocket" {
                            sendWebSocket(params: Array(args.dropFirst(2)), binary: false)
                        } else if sendType == "websocket-binary" {
                            sendWebSocket(params: Array(args.dropFirst(2)), binary: true)
                        }
                    } else if first == "cancel", args.count >= 2 {
                        // \![cancel,websocket,URL]（http のキャンセルは未対応）
                        let cancelType = args[1].lowercased()
                        if cancelType == "websocket" {
                            cancelWebSocket(params: Array(args.dropFirst(2)))
                        }
                    } else if first == "enter", args.count >= 2 {
                        let enterType = args[1].lowercased()
                        switch enterType {
                        case "selectmode":
                            let params = Array(args.dropFirst(2))
                            enterSelectMode(params: params)
                        case "collisionmode":
                            enterCollisionMode()
                        case "passivemode":
                            enterPassiveMode()
                        case "inductionmode":
                            let params = Array(args.dropFirst(2))
                            enterInductionMode(params: params)
                        case "nouserbreakmode":
                            enterNoUserBreakMode()
                        default:
                            break
                        }
                    } else if first == "leave", args.count >= 2 {
                        let leaveType = args[1].lowercased()
                        switch leaveType {
                        case "selectmode":
                            let params = Array(args.dropFirst(2))
                            leaveSelectMode(params: params)
                        case "collisionmode":
                            leaveCollisionMode()
                        case "passivemode":
                            leavePassiveMode()
                        case "inductionmode":
                            leaveInductionMode()
                        case "nouserbreakmode":
                            leaveNoUserBreakMode()
                        default:
                            break
                        }
                    } else if first == "sound", args.count >= 2 {
                        // \![sound,*]
                        let subcmd = args[1].lowercased()
                        switch subcmd {
                        case "play":
                            if args.count >= 3 {
                                playSound(filename: args[2], loop: false)
                            }
                        case "load":
                            if args.count >= 3 {
                                loadSound(filename: args[2])
                            }
                        case "loop":
                            if args.count >= 3 {
                                playSound(filename: args[2], loop: true)
                            }
                        case "wait":
                            let duration = estimatedSoundWaitDuration()
                            if duration > 0 {
                                playbackQueue.append(.wait(duration))
                            }
                        case "pause":
                            let filename = args.count >= 3 ? args[2] : nil
                            pauseSound(filename: filename)
                        case "resume":
                            let filename = args.count >= 3 ? args[2] : nil
                            resumeSound(filename: filename)
                        case "stop":
                            if args.count >= 3 {
                                stopSound(filename: args[2])
                            } else {
                                stopAllSounds()
                            }
                        case "option":
                            if args.count >= 3 {
                                let filename = args[2]
                                let options = Array(args.dropFirst(3))
                                applySoundOptions(filename: filename, options: options)
                            }
                        default:
                            break
                        }
                    } else if first == "set", args.count >= 2 {
                        // Handle \![set,*] commands
                        let subcmd = args[1].lowercased()
                        switch subcmd {
                        case "scaling":
                            executeSetScalingCommand(args: args)
                        case "alpha":
                            executeSetAlphaCommand(args: args)
                        case "alignmentondesktop", "alignmenttodesktop":
                            // \![set,alignmenttodesktop,direction]
                            if args.count >= 3 {
                                let direction = args[2].lowercased()
                                DispatchQueue.main.async {
                                    guard let vm = self.characterViewModels[self.currentScope],
                                          self.characterWindows[self.currentScope] != nil else { return }

                                    switch direction {
                                    case "top": vm.alignment = .top
                                    case "bottom": vm.alignment = .bottom
                                    case "left": vm.alignment = .left
                                    case "right": vm.alignment = .right
                                    case "free": vm.alignment = .free
                                    case "default": vm.alignment = .free
                                    default: break
                                    }
                                    
                                    // Apply desktop alignment constraint
                                    self.enforceDesktopAlignment(for: self.currentScope)
                                }
                            }
                        case "position":
                            // \![set,position,x,y,scopeID]
                            if args.count >= 5, let x = Int(args[2]), let y = Int(args[3]), let scopeID = Int(args[4]) {
                                setWindowPosition(x: x, y: y, scopeID: scopeID)
                            }
                        case "zorder":
                            executeSetZOrderCommand(args: args)
                        case "sticky-window":
                            executeSetStickyWindowCommand(args: args)
                        case "timerinterval":
                            if args.count >= 3, let ms = Double(args[2]) {
                                typingInterval = max(0, ms / 1000.0)
                            }
                        case "balloonoffset":
                            // \![set,balloonoffset,x,y]
                            if args.count >= 4, args[1].lowercased() == "x" {
                                // \![set,balloonoffset,x,y]
                                let xValue = args[2]
                                let yValue = args[3]
                                handleBalloonOffset(x: xValue, y: yValue)
                            } else if args.count >= 3 {
                                // \![set,balloonoffset,@x,@y]
                                handleBalloonOffset(x: args[1], y: args[2], isRelative: true)
                            }
                        case "balloonalign":
                            // \![set,balloonalign,direction]
                            if args.count >= 3 {
                                let direction = args[2].lowercased()
                                handleBalloonAlignment(direction: direction)
                            }
                        case "autoscroll":
                            // \![set,autoscroll,0/1/true/false]
                            if args.count >= 3 {
                                let value = args[2].lowercased()
                                DispatchQueue.main.async {
                                    guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                    vm.autoscrollEnabled = (value == "1" || value == "true")
                                    Log.debug("[GhostManager] Autoscroll set to: \(vm.autoscrollEnabled)")
                                }
                            }
                        case "balloontimeout":
                            // \![set,balloontimeout,time]
                            if args.count >= 3, let timeout = Double(args[2]) {
                                DispatchQueue.main.async {
                                    guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                    vm.balloonTimeout = timeout / 1000.0
                                    Log.debug("[GhostManager] Balloon timeout set to: \(vm.balloonTimeout)s")
                                }
                            }
                        case "choicetimeout":
                            // \![set,choicetimeout,time]
                            if args.count >= 3, let timeoutMs = Double(args[2]) {
                                // \* で「このスクリプトの選択肢をタイムアウトさせない」指定中は上書きしない
                                if !choiceTimeoutDisabled {
                                    choiceTimeout = timeoutMs > 0 ? timeoutMs / 1000.0 : nil
                                }
                                Log.debug("[GhostManager] Choice timeout set to: \(choiceTimeout ?? -1)s")
                            }
                        case "balloonwait":
                            // \![set,balloonwait,0/1/true/false or multiplier]
                            if args.count >= 3 {
                                let value = args[2].lowercased()
                                DispatchQueue.main.async {
                                    guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                    if let multiplier = Double(value) {
                                        vm.balloonWaitMultiplier = max(0, multiplier)
                                        vm.balloonWaitEnabled = multiplier != 0
                                    } else {
                                        vm.balloonWaitEnabled = (value == "1" || value == "true")
                                        vm.balloonWaitMultiplier = vm.balloonWaitEnabled ? 1.0 : 0.0
                                    }
                                    Log.debug("[GhostManager] Balloon wait set to: \(vm.balloonWaitEnabled)")
                                }
                            }
                        case "balloonmarker":
                            if args.count >= 3 {
                                setBalloonMarker(args[2])
                            }
                        case "balloonnum":
                            if args.count >= 3 {
                                setBalloonNumberDisplay(enabled: args[2].lowercased() == "1" || args[2].lowercased() == "true")
                            }
                        case "wallpaper":
                            // \![set,wallpaper,filename,options]
                            if args.count >= 3 {
                                let filename = args[2]
                                let options = args.count >= 4 ? args[3] : ""
                                setWallpaper(filename: filename, options: options)
                            }
                        case "tasktrayicon", "trayicon":
                            // \![set,tasktrayicon,filename,text] (trayicon is SSP alias)
                            if args.count >= 3 {
                                let filename = args[2]
                                let text = args.count >= 4 ? args[3] : ""
                                setTaskTrayIcon(filename: filename, text: text)
                            }
                        case "trayballoon":
                            // \![set,trayballoon,options...]
                            let options = Array(args.dropFirst(2))
                            setTrayBalloon(options: options)
                        case "otherghosttalk":
                            // \![set,otherghosttalk,true/false/before/after]
                            if args.count >= 3 {
                                setOtherGhostTalk(mode: args[2])
                            }
                        case "othersurfacechange":
                            // \![set,othersurfacechange,true/false]
                            if args.count >= 3 {
                                let value = args[2].lowercased()
                                setOtherSurfaceChange(enabled: value == "true" || value == "1" || value == "on")
                            }
                        case "windowstate":
                            // \![set,windowstate,stayontop/!stayontop/minimize]
                            if args.count >= 3 {
                                setWindowState(state: args[2])
                            }
                        case "shioridebugmode":
                            if args.count >= 3 {
                                let enabled = args[2].lowercased() == "1" || args[2].lowercased() == "true" || args[2].lowercased() == "on"
                                UserDefaults.standard.set(enabled, forKey: "OurinShioriDebugMode")
                                EventBridge.shared.notifyCustom("OnShioriDebugModeChanged", params: ["Reference0": enabled ? "1" : "0"])
                            }
                        case "serikotalk":
                            if args.count >= 3 {
                                setSerikoTalk(mode: args[2])
                            }
                        default:
                            break
                        }
                    } else if first == "reset", args.count >= 2 {
                        // Handle \![reset,*] commands
                        let subcmd = args[1].lowercased()
                        switch subcmd {
                        case "position":
                            // \![reset,position] - unlock position
                            resetWindowPosition()
                        case "zorder":
                            // \![reset,zorder] - reset to default z-order
                            resetWindowZOrder()
                        case "sticky-window":
                            // \![reset,sticky-window] - unlink windows
                            resetStickyWindow()
                        default:
                            break
                        }
                    } else if first == "bind", args.count >= 2 {
                        executeBindCommand(args: args)
                    } else if first == "reload", args.count >= 2 {
                        let target = args[1].lowercased()
                        if target == "surfaces.txt" {
                            playbackQueue.append(.deferredCommand {
                                DispatchQueue.main.async {
                                    self.reloadSurfacesDefinition()
                                }
                            })
                        }
                    } else if first == "lock", args.count >= 2 {
                        // Handle \![lock,*] commands
                        let subcmd = args[1].lowercased()
                        if subcmd == "repaint" {
                            let manual = args.count >= 3 && args[2].lowercased() == "manual"
                            DispatchQueue.main.async {
                                guard let vm = self.characterViewModels[self.currentScope] else { return }
                                vm.repaintLocked = true
                                vm.manualRepaintLock = manual
                            }
                        } else if subcmd == "balloonrepaint" {
                            let manual = args.count >= 3 && args[2].lowercased() == "manual"
                            DispatchQueue.main.async {
                                guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                vm.repaintLocked = true
                                Log.debug("[GhostManager] Balloon repaint locked: \(manual)")
                            }
                        } else if subcmd == "balloonmove" {
                            DispatchQueue.main.async {
                                guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                vm.balloonMoveLocked = true
                                Log.debug("[GhostManager] Balloon move locked")
                            }
                        }
                    } else if first == "unlock", args.count >= 2 {
                        // Handle \![unlock,*] commands
                        let subcmd = args[1].lowercased()
                        if subcmd == "repaint" {
                            DispatchQueue.main.async {
                                guard let vm = self.characterViewModels[self.currentScope] else { return }
                                vm.repaintLocked = false
                                vm.manualRepaintLock = false
                            }
                        } else if subcmd == "balloonrepaint" {
                            DispatchQueue.main.async {
                                guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                vm.repaintLocked = false
                                Log.debug("[GhostManager] Balloon repaint unlocked")
                            }
                        } else if subcmd == "balloonmove" {
                            DispatchQueue.main.async {
                                guard let vm = self.balloonViewModels[self.currentScope] else { return }
                                vm.balloonMoveLocked = false
                                Log.debug("[GhostManager] Balloon move unlocked")
                            }
                        }
                    } else if first == "execute", args.count >= 2 {
                        // Handle \![execute,*] commands
                        let subcmd = args[1].lowercased()
                        if subcmd == "resetwindowpos" {
                            // \![execute,resetwindowpos] - reset all windows to initial positions
                            executeResetWindowPos()
                        } else if subcmd == "headline" {
                            // \![execute,headline,headlineName]
                            let headlineName = args.count >= 3 ? args[2] : ""
                            executeHeadline(name: headlineName)
                        } else if subcmd.hasPrefix("http-") {
                            let params = Array(args.dropFirst(2))
                            executeHTTP(subcommand: subcmd, params: params)
                        } else if subcmd.hasPrefix("rss-") {
                            let params = Array(args.dropFirst(2))
                            executeRSS(subcommand: subcmd, params: params)
                        } else if subcmd == "extractarchive" {
                            executeExtractArchive(params: Array(args.dropFirst(2)))
                        } else if subcmd == "compressarchive" {
                            executeCompressArchive(params: Array(args.dropFirst(2)))
                        } else if subcmd == "dumpsurface" {
                            executeDumpSurface(params: Array(args.dropFirst(2)))
                        } else if subcmd == "install" {
                            executeInstall(params: Array(args.dropFirst(2)))
                        } else if subcmd == "createnar" {
                            executeCreateNar()
                        } else if subcmd == "createupdatedata" {
                            executeCreateUpdateData()
                        } else if subcmd == "emptyrecyclebin" {
                            executeEmptyRecycleBin()
                        } else if subcmd == "ping" {
                            executePing(params: Array(args.dropFirst(2)))
                        } else if subcmd == "nslookup" {
                            executeNslookup(params: Array(args.dropFirst(2)))
                        } else if subcmd == "websocket" {
                            executeWebSocket(params: Array(args.dropFirst(2)))
                        }
                    } else if first == "create", args.count >= 2 {
                        let createType = args[1].lowercased()
                        if createType == "shortcut" {
                            executeCreateShortcut(params: Array(args.dropFirst(2)))
                        }
                    } else if first == "clipboard", args.count >= 2 {
                        let subcmd = args[1].lowercased()
                        if subcmd == "set" || subcmd == "copy" {
                            let text = args.count >= 3 ? args[2] : ""
                            setClipboardText(text)
                        } else if subcmd == "get" || subcmd == "paste" {
                            let text = getClipboardText()
                            if args.count >= 3 {
                                let eventID = args[2]
                                _ = requestDialogEvent(eventID: eventID, references: [text])
                            } else {
                                EventBridge.shared.notifyCustom("OnClipboardRead", params: ["Reference0": text])
                            }
                        } else if subcmd == "clear" {
                            clearClipboard()
                        }
                    } else if first == "systemmessage" || (first == "system" && args.count >= 2 && args[1].lowercased() == "message") {
                        let offset = first == "systemmessage" ? 1 : 2
                        let title = args.count > offset ? args[offset] : ""
                        let body = args.count > offset + 1 ? args[offset + 1] : ""
                        let level = args.count > offset + 2 ? args[offset + 2] : "info"
                        postSystemMessage(title: title, body: body, level: level)
                    } else if first == "quicksession" {
                        // \![quicksession,true/false] - enable/disable quick session mode
                        let enabled = args.count >= 2 && args[1].lowercased() == "true"
                        quickSessionEnabled = enabled
                        Log.debug("[GhostManager] Quick session mode: \(enabled)")
                    } else if first == "executesntp" {
                        // \![executesntp] - execute SNTP time synchronization
                        executeSNTP()
                    } else if first == "biff" {
                        // \![biff] - check for new mail
                        executeBiff()
                    } else if first == "updatebymyself" {
                        // \![updatebymyself] - check for updates to this ghost
                        executeUpdate(target: "self", options: [])
                    } else if first == "update" {
                        // \![update,http,url] or \![update,target,options...]
                        if args.count >= 3, args[1].lowercased() == "http" {
                            let params = Array(args.dropFirst(2))
                            executeHTTP(subcommand: "http-get", params: params)
                        } else {
                            let target = args.count >= 2 ? args[1] : "platform"
                            let options = Array(args.dropFirst(2))
                            executeUpdate(target: target, options: options)
                        }
                    } else if first == "updateother" {
                        // \![updateother] - check for updates to all other ghosts
                        executeUpdate(target: "other", options: [])
                    } else if first == "vanishbymyself" {
                        // \![vanishbymyself] - terminate this ghost
                        EventBridge.shared.notify(.OnVanishSelecting, params: [:])
                        EventBridge.shared.notify(.OnVanishSelected, params: [:])
                        executeVanish()
                    } else if first == "reloadsurface" {
                        executeReloadSurface()
                    } else if first == "reload", args.count >= 2 {
                        executeReload(target: args[1], params: Array(args.dropFirst(2)))
                    } else if first == "unload", args.count >= 2 {
                        executeUnload(target: args[1])
                    } else if first == "load", args.count >= 2 {
                        executeLoad(target: args[1])
                    } else if first == "anim", args.count >= 2 {
                        // Handle \![anim,*] commands - animation control
                        let subcmd = args[1].lowercased()
                        switch subcmd {
                        case "clear":
                            // \![anim,clear,ID] - clear specific animation/overlay
                            if args.count >= 3, let animID = Int(args[2]) {
                                handleAnimClear(id: animID)
                            }
                        case "pause":
                            // \![anim,pause,ID] - pause animation
                            if args.count >= 3, let animID = Int(args[2]) {
                                handleAnimPause(id: animID)
                            }
                        case "resume":
                            // \![anim,resume,ID] - resume animation
                            if args.count >= 3, let animID = Int(args[2]) {
                                handleAnimResume(id: animID)
                            }
                        case "stop":
                            // \![anim,stop] - stop all animations and clear all overlays
                            handleAnimStop()
                        case "offset":
                            // \![anim,offset,ID,x,y] - offset an animation/overlay
                            if args.count >= 5,
                               let overlayID = Int(args[2]),
                               let x = Int(args[3]),
                               let y = Int(args[4]) {
                                handleAnimOffset(id: overlayID, x: x, y: y)
                            }
                        case "add":
                            // \![anim,add,overlay,ID] or \![anim,add,base,ID] or \![anim,add,text,...]
                            if args.count >= 4 {
                                let addType = args[2].lowercased()
                                if addType == "overlay" {
                                    if let surfaceID = Int(args[3]) {
                                        handleAnimAddOverlay(id: surfaceID)
                                    }
                                } else if addType == "overlayfast" {
                                    if let surfaceID = Int(args[3]) {
                                        handleAnimAddOverlayFast(id: surfaceID)
                                    }
                                } else if addType == "base" {
                                    if let surfaceID = Int(args[3]) {
                                        handleAnimAddBase(id: surfaceID)
                                    }
                                } else if addType == "move" {
                                    if args.count >= 5,
                                       let moveX = Int(args[3]),
                                       let moveY = Int(args[4]) {
                                        handleAnimAddMove(x: moveX, y: moveY)
                                    }
                                } else if addType == "bind" {
                                    if let surfaceID = Int(args[3]) {
                                        handleSurfaceOverlay(surfaceID: surfaceID, type: .bind)
                                    }
                                } else if addType == "text" {
                                    // \![anim,add,text,x,y,width,height,text,time,r,g,b,size,font]
                                    if args.count >= 13 {
                                        let x = Int(args[3]) ?? 0
                                        let y = Int(args[4]) ?? 0
                                        let width = Int(args[5]) ?? 100
                                        let height = Int(args[6]) ?? 20
                                        let text = args[7]
                                        let time = Int(args[8]) ?? 1000
                                        let r = Int(args[9]) ?? 0
                                        let g = Int(args[10]) ?? 0
                                        let b = Int(args[11]) ?? 0
                                        let size = Int(args[12]) ?? 12
                                        let font = args.count >= 14 ? args[13] : "sans-serif"
                                        addTextAnimation(x: x, y: y, width: width, height: height, text: text, 
                                                       time: time, r: r, g: g, b: b, size: size, font: font)
                                    }
                                }
                            }
                        default:
                            break
                        }
                    } else if first == "bind", args.count >= 2 {
                        executeBindCommand(args: args)
                    } else if first == "effect", args.count >= 2 {
                        // \![effect,plugin,speed,params] - apply effect plugin
                        let plugin = args[1]
                        let speed = args.count >= 3 ? Double(args[2]) ?? 1.0 : 1.0
                        let params = Array(args.dropFirst(3))
                        applyEffect(plugin: plugin, speed: speed, params: params, surfaceID: nil)
                    } else if first == "effect2", args.count >= 3 {
                        // \![effect2,surfaceID,plugin,speed,params] - apply effect to specific surface
                        if let surfaceID = Int(args[1]) {
                            let plugin = args[2]
                            let speed = args.count >= 4 ? Double(args[3]) ?? 1.0 : 1.0
                            let params = Array(args.dropFirst(4))
                            applyEffect(plugin: plugin, speed: speed, params: params, surfaceID: surfaceID)
                        }
                    } else if first == "filter" {
                        if args.count >= 2 {
                            // \![filter,plugin,time,params] - apply filter plugin
                            let plugin = args[1]
                            let time = args.count >= 3 ? Double(args[2]) ?? 0 : 0
                            let params = Array(args.dropFirst(3))
                            applyFilter(plugin: plugin, time: time, params: params)
                        } else {
                            // \![filter] - clear all filters
                            clearFilters()
                        }
                    } else if first == "move" {
                        let params = Array(args.dropFirst())
                        if params.first?.lowercased() == "window" {
                            executeMoveCommand(args: Array(params.dropFirst()), async: false)
                        } else {
                            executeMoveCommand(args: params, async: false)
                        }
                    } else if first == "moveasync" {
                        let params = Array(args.dropFirst())
                        if params.first?.lowercased() == "cancel" {
                            let scopeID = params.count >= 2 ? Int(params[1]) : nil
                            cancelMoveWindowAsync(scope: scopeID)
                        } else if params.first?.lowercased() == "window" {
                            executeMoveCommand(args: Array(params.dropFirst()), async: true)
                        } else {
                            executeMoveCommand(args: params, async: true)
                        }
                    } else if first == "resize" {
                        let params = Array(args.dropFirst())
                        if params.first?.lowercased() == "window" {
                            executeResizeCommand(args: Array(params.dropFirst()))
                        } else {
                            executeResizeCommand(args: params)
                        }
                    } else if first == "open", args.count >= 2 {
                        // Handle \![open,browser,URL] and \![open,mailer,email]
                        let target = args[1].lowercased()
                        if target == "browser" && args.count >= 3 {
                            let url = args[2]
                            openURL(url)
                        } else if target == "mailer" && args.count >= 3 {
                            let email = args[2]
                            openEmail(email)
                        }
                    } else if ["*", "#", "x", "<", ">"].contains(first) {
                        // Choice marker shorthand: \![*], \![#], \![X], \![<], \![>]
                        let marker: String
                        switch first {
                        case "*": marker = "*"
                        case "#": marker = "#"
                        case "x": marker = "X"
                        case "<": marker = "<"
                        case ">": marker = ">"
                        default: marker = first
                        }
                        setBalloonMarker(marker)
                    }
                }
            case "_s":
                if args.isEmpty {
                    syncEnabled.toggle()
                    if syncEnabled && syncScopes.isEmpty { syncScopes = [0,1] }
                    if !syncEnabled { syncScopes = [] }
                } else {
                    syncEnabled = true
                    syncScopes = Set(args.compactMap { Int($0) })
                }
            
            case "q":
                // \q[title,ID] or various choice formats
                handleChoiceCommand(args: args)
            
            case "_a":
                // \_a[ID] or \_a[OnID,r0,r1,...] - anchor/clickable text
                if !args.isEmpty {
                    let eventID = args[0]
                    let references = Array(args.dropFirst())
                    Log.debug("[GhostManager] Anchor event: \(eventID) with refs: \(references)")
                    pendingAnchorAction = (action: .event(id: eventID, references: references), pluginOrigin: currentScriptIsPluginOrigin)
                    EventBridge.shared.notifyCustom("OnAnchorEnter", params: ["Reference0": eventID])
                    EventBridge.shared.notifyCustom("OnAnchorHover", params: ["Reference0": eventID])
                    if let vm = balloonViewModels[currentScope] {
                        vm.anchorActive = true
                    }
                }
            
            case "_b":
                // \_b[filepath,...] - balloon image display
                handleBalloonImage(args: args)

            case "_l":
                // \_l[x,y] - move cursor position
                if args.count >= 2 {
                    handleCursorMove(x: args[0], y: args[1])
                }
            
            case "_v":
                // \_v[filename] - play voice file
                if let filename = args.first {
                    playSound(filename: filename)
                }

            case "_u":
                // \_u[0xXXXX] - append Unicode scalar text
                if let scalar = decodeScalarLiteral(args.first) {
                    playbackQueue.append(.textChunk(String(scalar)))
                }

            case "_m":
                // \_m[0xNN] - append single-byte scalar text
                if let scalar = decodeScalarLiteral(args.first) {
                    playbackQueue.append(.textChunk(String(scalar)))
                }

            case "&":
                // \&[ID] - 識別子による実体参照（UKADOC）。アンカーイベントではない。
                if let entityID = args.first, !entityID.isEmpty {
                    if let text = Self.resolveEntityReference(entityID) {
                        playbackQueue.append(.textChunk(text))
                    } else {
                        Log.info("[GhostManager] \\&[\(entityID)] - unknown entity reference (ignored)")
                    }
                }

            case "j":
                // \j[ID] - ジャンプ（UKADOC）。URL はブラウザで開く。イベントIDは raise 相当。
                handleJumpCommand(args: args)

            case "m":
                // \m[umsg,wparam,lparam] - message dispatch
                if let umsg = args.first, !umsg.isEmpty {
                    var refs = [umsg]
                    refs.append(contentsOf: Array(args.dropFirst()))
                    _ = requestDialogEvent(eventID: "OnMessage", references: refs)
                }
            
            case "c":
                // \c[char,line,...] - clear text
                handleTextClear(args: args)
            
            case "f":
                // \f[align,...], \f[name,...], \f[height,...], \f[color,...], \f[shadowcolor,...], \f[shadowstyle,...], \f[bold,...], \f[italic,...], \f[strike,...], \f[underline,...], \f[sub,...], \f[sup,...], \f[default], \f[disable], \f[anchor.font.color,...]
                if args.isEmpty {
                    break
                }
                let subcmd = args[0].lowercased()
                DispatchQueue.main.async {
                    guard let vm = self.balloonViewModels[self.currentScope] else { return }
                    
                    switch subcmd {
                    case "align":
                        // \f[align,left/center/right]
                        if args.count >= 2 {
                            let align = args[1].lowercased()
                            switch align {
                            case "left":
                                vm.textAlign = .left
                            case "center":
                                vm.textAlign = .center
                            case "right":
                                vm.textAlign = .right
                            default:
                                Log.info("[GhostManager] Unknown text align: \(align)")
                            }
                            Log.debug("[GhostManager] Text align set to: \(align)")
                        }
                    case "valign":
                        // \f[valign,top/center/bottom]
                        if args.count >= 2 {
                            let valign = args[1].lowercased()
                            switch valign {
                            case "top":
                                vm.textVAlign = .top
                            case "center", "middle":
                                vm.textVAlign = .center
                            case "bottom":
                                vm.textVAlign = .bottom
                            default:
                                Log.info("[GhostManager] Unknown text valign: \(valign)")
                            }
                            Log.debug("[GhostManager] Text valign set to: \(valign)")
                        }
                    case "name":
                        // \f[name,fontname,...]
                        if args.count >= 2 {
                            let fontNames = Array(args.dropFirst()).joined(separator: ",")
                            vm.fontName = fontNames
                            Log.debug("[GhostManager] Font name set to: \(fontNames)")
                        }
                    case "height":
                        // \f[height,size]
                        if args.count >= 2 {
                            let sizeStr = args[1]
                            let size = self.parseFontHeight(sizeStr, baseFontSize: CGFloat(self.balloonConfig?.fontHeight ?? 12))
                            vm.fontSize = size
                            Log.debug("[GhostManager] Font height set to: \(size)")
                        }
                    case "color":
                        // \f[color,r,g,b] or \f[color,#RRGGBB] or \f[color,name]
                        if args.count >= 2 {
                            let color = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.fontColor)
                            vm.fontColor = color
                            Log.debug("[GhostManager] Font color set to: \(color)")
                        }
                    case "shadowcolor":
                        // \f[shadowcolor,r,g,b] or \f[shadowcolor,#RRGGBB] or \f[shadowcolor,name]
                        if args.count >= 2 {
                            let color = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.shadowColor)
                            vm.shadowColor = color
                            Log.debug("[GhostManager] Shadow color set to: \(color)")
                        }
                    case "shadowstyle":
                        // \f[shadowstyle,offset/outline]
                        if args.count >= 2 {
                            let style = args[1].lowercased()
                            switch style {
                            case "offset":
                                vm.shadowStyle = .offset
                            case "outline":
                                vm.shadowStyle = .outline
                            case "none":
                                vm.shadowStyle = .none
                            default:
                                Log.info("[GhostManager] Unknown shadow style: \(style)")
                            }
                            Log.debug("[GhostManager] Shadow style set to: \(style)")
                        }
                    case "bold":
                        // \f[bold,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            let isBold = self.parseTriState(value, currentValue: vm.fontWeight == .bold ? "1" : "0")
                            vm.fontWeight = isBold ? .bold : .regular
                            Log.debug("[GhostManager] Font bold set to: \(isBold)")
                        }
                    case "italic":
                        // \f[italic,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontItalic = self.parseTriState(value, currentValue: vm.fontItalic ? "1" : "0")
                            Log.debug("[GhostManager] Font italic set to: \(vm.fontItalic)")
                        }
                    case "strike":
                        // \f[strike,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontStrike = self.parseTriState(value, currentValue: vm.fontStrike ? "1" : "0")
                            Log.debug("[GhostManager] Font strike set to: \(vm.fontStrike)")
                        }
                    case "underline":
                        // \f[underline,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontUnderline = self.parseTriState(value, currentValue: vm.fontUnderline ? "1" : "0")
                            Log.debug("[GhostManager] Font underline set to: \(vm.fontUnderline)")
                        }
                    case "sub":
                        // \f[sub,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontSubscript = self.parseTriState(value, currentValue: vm.fontSubscript ? "1" : "0")
                            if vm.fontSubscript { vm.fontSuperscript = false }
                            Log.debug("[GhostManager] Font subscript set to: \(vm.fontSubscript)")
                        }
                    case "sup":
                        // \f[sup,0/1/true/false/default/disable]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            vm.fontSuperscript = self.parseTriState(value, currentValue: vm.fontSuperscript ? "1" : "0")
                            if vm.fontSuperscript { vm.fontSubscript = false }
                            Log.debug("[GhostManager] Font superscript set to: \(vm.fontSuperscript)")
                        }
                    case "default":
                        // \f[default] - reset to default
                        self.resetFontDefaults(vm: vm)
                    case "disable":
                        // \f[disable] - set all to disabled style
                        self.setFontDisabled(vm: vm)
                    case "anchor.font.color":
                        // \f[anchor.font.color,r,g,b] or \f[anchor.font.color,#RRGGBB] or \f[anchor.font.color,name]
                        if args.count >= 2 {
                            vm.anchorFontColor = self.parseColor(from: Array(args.dropFirst()), defaultValue: vm.anchorFontColor)
                            Log.debug("[GhostManager] Anchor font color set")
                        }
                    case "outline":
                        // \f[outline,width]
                        if args.count >= 2 {
                            let value = args[1].lowercased()
                            if value == "default" || value == "disable" || value == "0" || value == "false" {
                                vm.outlineWidth = 0
                                if vm.shadowStyle == .outline {
                                    vm.shadowStyle = .none
                                }
                            } else if let width = Double(value) {
                                vm.outlineWidth = max(0, CGFloat(width))
                                vm.shadowStyle = vm.outlineWidth > 0 ? .outline : vm.shadowStyle
                            } else {
                                vm.outlineWidth = 1
                                vm.shadowStyle = .outline
                            }
                            Log.debug("[GhostManager] Font outline width set to: \(vm.outlineWidth)")
                        }
                    default:
                        Log.info("[GhostManager] Unknown font command: \(subcmd)")
                    }
                }
            
            default:
                break
             }
        }
    }

    // MARK: - Helper Methods

    private func startPlaybackIfNeeded() {
        if !isPlaying {
            isPlaying = true
            DispatchQueue.main.async { self.processNextUnit() }
        }
    }

    func processNextUnit() {
        // Process immediate units (scope/surface/end) without delay; delay only text/newline
        while true {
            guard !playbackQueue.isEmpty else {
                isPlaying = false
                emitPluginTalkAfterIfNeeded()
                // OnClose 応答スクリプトの再生完了後に終了する（スクリプトが \- を含まない場合の保険）
                if terminateAfterPlayback {
                    finalizeTermination()
                } else if !pendingChoices.isEmpty {
                    // \q / \__q で蓄積された選択肢を再生完了後に提示する。
                    // 選択時に OnChoiceSelect(Ex) が発火し、プラグインへも横流しされる（showChoiceDialog 内）。
                    showChoiceDialog()
                }
                return
            }
            let unit = playbackQueue.removeFirst()
            switch unit {
            case .scope(let id):
                // Clear other scopes' balloons to ensure sequential dialogue (no parallel display)
                for (scopeId, vm) in balloonViewModels {
                    if scopeId != id {
                        vm.text = ""
                    }
                }
                
                // Clear current scope balloon text unless append mode is enabled
                if !appendModeEnabled {
                    balloonViewModels[id]?.text = ""
                }
                
                currentScope = id
                Log.debug("[GhostManager] Switched to scope \(id)")

                // Show the character window for this scope (遅延生成: 未作成スコープはここで生成)
                if let window = ensureCharacterWindow(for: id) {
                    window.orderFront(nil)
                    Log.debug("[GhostManager] Ordered scope \(id) window to front")
                }

                positionBalloonWindow()
                continue
            case .surface(let id):
                Log.debug("[GhostManager] Updating surface to id: \(id)")
                // Don't clear balloon - keep displaying until next script
                updateSurface(id: id)
                // Add a small delay after surface change to respect script timing
                scheduleNext(after: 0.05)
                return
            case .end:
                Log.debug("[GhostManager] Script end.")
                quickMode = false
                syncEnabled = false
                appendModeEnabled = false
                // \e でタイムクリティカルセクション終了（UKADOC: \t はスクリプトブレークか \e まで）
                timeCriticalActive = false
                continue
            case .resetPrecise:
                preciseBase = Date()
                continue
            case .waitUntil(let sec):
                let target = preciseBase.addingTimeInterval(sec)
                let now = Date()
                let delay = max(0.0, target.timeIntervalSince(now))
                scheduleNext(after: delay)
                return
            case .wait(let sec):
                scheduleNext(after: max(0.0, sec))
                return
            case .waitAnimation(let animID):
                // If the animation is currently active, set wait flag and pause processing.
                // When the animation finishes, onAnimationFinished will resume playback.
                if serikoExecutor.activeAnimations[animID] != nil {
                    waitingForAnimation = animID
                    return
                } else {
                    // Animation not active; continue immediately.
                    continue
                }
            case .clickWait(let noclear):
                pendingClick = noclear
                return
            case .text(let ch):
                // Character-by-character mode with typing effect
                appendText(String(ch))
                scheduleNext(after: typingInterval)
                return
            case .textChunk(let s):
                // Chunk mode (for quickMode) - display immediately
                appendText(s)
                continue
            case .newline:
                // Display newline with delay
                appendText("\n")
                scheduleNext(after: typingInterval)
                return
            case .deferredCommand(let command):
                // Execute deferred command immediately (it's already at the right time in the queue)
                NSLog("[GhostManager] Executing deferred command")
                command()
                continue
            }
        }
    }

    private func scheduleNext(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.processNextUnit()
        }
    }

    /// Try to obtain a boot script in order:
    /// 1) 初回起動のみ GET OnFirstBoot（Reference0 = vanish回数）
    /// 2) GET OnBoot（Reference0 = シェル名。2回目以降の起動もすべて OnBoot。UKADOC に OnSecondBoot は存在しない）
    /// 3) BridgeToSHIORI for OnBoot
    /// 4) Built-in minimal greeting
    private func obtainBootScript(using adapter: YayaAdapter, bootCount: Int) -> String? {
        let hdrs: [String: String] = ["Charset": "UTF-8", "SecurityLevel": "local", "Sender": "Ourin"]
        if bootCount == 0 {
            // UKADOC: OnFirstBoot Reference0 = vanish された回数（通常 0）
            let vanishCount = UserDefaults.standard.integer(forKey: "OurinVanishCount")
            if let r = adapter.request(method: "GET", id: "OnFirstBoot", headers: hdrs, refs: [String(vanishCount)], timeout: 4.0), r.ok {
                let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let pv = v.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
                NSLog("[GhostManager] OnFirstBoot response: ok=true, len=\(v.count), preview=\(pv)")
                if !v.isEmpty { return v }
            } else {
                NSLog("[GhostManager] OnFirstBoot request failed or no response")
            }
        }

        // 2) OnBoot（UKADOC: Reference0 = 起動したシェル名）
        let shellName = activeShellName
        if let r = adapter.request(method: "GET", id: "OnBoot", headers: hdrs, refs: [shellName], timeout: 4.0), r.ok {
            let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pv = v.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
            NSLog("[GhostManager] OnBoot response: ok=true, len=\(v.count), preview=\(pv)")
            if !v.isEmpty { return v }
        } else {
            NSLog("[GhostManager] OnBoot request failed or no response")
        }

        // 3) Bridge fallback
        let bridge = BridgeToSHIORI.handle(event: "OnBoot", references: [shellName])
        let bv = bridge.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bv.isEmpty {
            NSLog("[GhostManager] BridgeToSHIORI fallback used (len=\(bv.count))")
            return bridge
        }

        // 4) Built-in minimal greeting (SakuraScript)
        let builtin = "\\h\\s0こんにちは、起動しました。\\n\\e"
        NSLog("[GhostManager] Using built-in greeting fallback")
        return builtin
    }

    func startEventBridgeIfNeeded(enableAutoEvents: Bool = false) {
        // Start the event bridge only after the initial UI is ready
        guard (NSApplication.shared.delegate as? AppDelegate)?.eventBridge == nil else {
            // If bridge is already started and we need auto events, restart with auto events enabled
            if enableAutoEvents {
                let bridge = EventBridge.shared
                bridge.stop()
                bridge.start(enableAutoEvents: true)
                Log.debug("[GhostManager] EventBridge restarted with auto events enabled")
            }
            return
        }
        let bridge = EventBridge.shared
        bridge.start(enableAutoEvents: enableAutoEvents)
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.eventBridge = bridge
        }
        Log.debug("[GhostManager] EventBridge started with enableAutoEvents=\(enableAutoEvents)")
    }

    // MARK: - SHIORI Initialization NOTIFYs

    func sendInitializationNotifies(config: GhostConfiguration) {
        let bridge = EventBridge.shared

        // hwnd: Reference0 = comma-separated character window handles
        let hwndValues = characterWindows.sorted(by: { $0.key < $1.key })
            .map { String($0.value.windowNumber) }
        let hwndRef0 = hwndValues.joined(separator: ",")
        let balloonHwnds = balloonWindows.sorted(by: { $0.key < $1.key })
            .map { String($0.value.windowNumber) }
        let hwndRef1 = balloonHwnds.joined(separator: ",")
        bridge.notifyCustom("hwnd", params: [
            "Reference0": hwndRef0,
            "Reference1": hwndRef1
        ], ignoreResponseScript: true)

        // uniqueid
        let uniqueID = ghostURL.lastPathComponent
        bridge.notifyCustom("uniqueid", params: [
            "Reference0": uniqueID
        ], ignoreResponseScript: true)

        // basewareversion
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        bridge.notifyCustom("basewareversion", params: [
            "Reference0": "Ourin/\(version)"
        ], ignoreResponseScript: true)

        // capability
        bridge.notifyCustom("capability", params: [
            "Reference0": "response",
            "Reference1": "nobreak",
            "Reference2": "communicate",
            "Reference3": "lock",
            "Reference4": "notify"
        ], ignoreResponseScript: true)

        // OnNotifySelfInfo: ref0=ghostName, ref1=sakuraName, ref2=keroName,
        //   ref3=shellName, ref4=shellPath, ref5=balloonName, ref6=balloonPath
        let shellPath = loadShellPath()?.path ?? ""
        let shellName = activeShellName
        let balloonName = balloonConfig?.name ?? ""
        let balloonPath = self.ghostURL.appendingPathComponent("balloon").path
        bridge.notify(.OnNotifySelfInfo, params: [
            "Reference0": config.sakuraName,
            "Reference1": config.sakuraName,
            "Reference2": config.keroName ?? "",
            "Reference3": shellName,
            "Reference4": shellPath,
            "Reference5": balloonName,
            "Reference6": balloonPath
        ])

        // OnNotifyShellInfo: ref0=shellName, ref1=shellPath
        bridge.notify(.OnNotifyShellInfo, params: [
            "Reference0": shellName,
            "Reference1": shellPath
        ])

        // OnNotifyBalloonInfo: ref0=balloonName, ref1=balloonPath
        bridge.notify(.OnNotifyBalloonInfo, params: [
            "Reference0": balloonName,
            "Reference1": balloonPath
        ])
        if let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher {
            let windows = characterWindows.sorted(by: { $0.key < $1.key }).map { $0.value }
            dispatcher.onGhostBoot(
                windows: windows,
                ghostName: config.name,
                shellName: shellName,
                ghostID: config.id ?? ghostURL.lastPathComponent,
                path: ghostURL.path
            )
            dispatcher.onGhostInfoUpdate(
                windows: windows,
                ghostName: config.name,
                shellName: shellName,
                ghostID: config.id ?? ghostURL.lastPathComponent,
                path: ghostURL.path
            )
        }

        // OnNotifyUserInfo: ref0=userName
        let userName = NSFullUserName()
        bridge.notify(.OnNotifyUserInfo, params: [
            "Reference0": userName,
            "Reference1": userName,
            "Reference2": "",
            "Reference3": ""
        ])

        // OnNotifyOSInfo
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        bridge.notify(.OnNotifyOSInfo, params: [
            "Reference0": "macOS \(osVersion)"
        ])

        // ownerghostname: list of all running ghosts
        let ghostName = config.sakuraName
        bridge.notifyCustom("ownerghostname", params: [
            "Reference0": ghostName
        ], ignoreResponseScript: true)

        Log.info("[GhostManager] Sent initialization NOTIFY events (hwnd, uniqueid, capability, OnNotifySelfInfo, etc.)")
    }
}

// MARK: - Owner Draw Menu Actions
extension GhostManager {
    /// メニューアクションを処理
    func handleMenuAction(_ action: String) {
        if let config = ghostConfig,
           let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher {
            dispatcher.onMenuExec(
                windows: characterWindows.sorted(by: { $0.key < $1.key }).map { $0.value },
                ghostName: config.name,
                shellName: activeShellName,
                ghostID: config.id ?? ghostURL.lastPathComponent,
                path: ghostURL.path
            )
        }
        switch action {
        case "menu_ghost_info":
            showGhostInfo()
        case let action where action.hasPrefix("switch_ghost:"):
            let ghostID = String(action.dropFirst("switch_ghost:".count))
            switchGhost(to: ghostID)
        case let action where action.hasPrefix("switch_shell:"):
            let shellID = String(action.dropFirst("switch_shell:".count))
            switchShell(to: shellID)
        case let action where action.hasPrefix("switch_balloon:"):
            let balloonID = String(action.dropFirst("switch_balloon:".count))
            switchBalloon(to: balloonID)
        case let action where action.hasPrefix("dressup_bindgroup:"):
            let raw = String(action.dropFirst("dressup_bindgroup:".count))
            let parts = raw.split(separator: ":").map(String.init)
            if parts.count == 2, let scope = Int(parts[0]), let bindID = Int(parts[1]) {
                toggleDressupBindGroup(scope: scope, bindGroupID: bindID)
            } else if let bindID = Int(raw) {
                toggleDressupBindGroup(scope: currentScope, bindGroupID: bindID)
            }
        case "menu_communicate":
            showCommunicateBox()
        case "menu_reload":
            reloadGhost()
        case "menu_vanish":
            vanishCurrentGhost()
        case "menu_update":
            checkNetworkUpdate()
        case "menu_settings":
            showSettings()
        case "menu_quit":
            NSApplication.shared.terminate(nil)
        default:
            Log.info("[GhostManager] Unknown menu action: \(action)")
        }
    }
    
    /// ゴースト情報を表示
    private func showGhostInfo() {
        let alert = NSAlert()
        alert.messageText = ghostConfig?.name ?? NSLocalizedString("Ghost Info", comment: "ghost info dialog title")
        var lines: [String] = []
        lines.append("Path: \(ghostURL.path)")
        lines.append("Shell: \(activeShellName)")
        if let sakura = ghostConfig?.sakuraName, !sakura.isEmpty {
            lines.append("Sakura: \(sakura)")
        }
        if let kero = ghostConfig?.keroName, !kero.isEmpty {
            lines.append("Kero: \(kero)")
        }
        if let home = ghostConfig?.homeurl, !home.isEmpty {
            lines.append("Home URL: \(home)")
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "ok button"))
        alert.alertStyle = .informational
        alert.runModal()
    }
    
    /// 設定を表示
    private func showSettings() {
        DispatchQueue.main.async {
            if #available(macOS 13, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            let settingsID = NSUserInterfaceItemIdentifier("SettingsWindow")
            for window in NSApplication.shared.windows {
                if window.identifier == settingsID || window.title == NSLocalizedString("Settings", comment: "Settings window title") {
                    window.makeKeyAndOrderFront(nil)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    return
                }
            }
            let controller = NSHostingController(rootView: ContentView())
            let window = NSWindow(contentViewController: controller)
            window.identifier = settingsID
            window.title = NSLocalizedString("Settings", comment: "Settings window title")
            window.setContentSize(NSSize(width: 900, height: 600))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
    
    /// 話しかけるダイアログを表示
    private func showCommunicateBox() {
        DispatchQueue.main.async {
            self.showCommunicateBoxDialog(timeoutMs: nil, initialText: "")
        }
    }

    /// ゴーストを再読み込み
    private func reloadGhost() {
        let name = ghostConfig?.name ?? ""
        Log.info("[GhostManager] Reloading ghost: \(name)")
        EventBridge.shared.notify(.OnClose, params: ["Reference0": "reload"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.runGhost(at: self.ghostURL)
            }
        }
    }

    /// ゴーストを消滅させる
    private func vanishCurrentGhost() {
        let name = ghostConfig?.name ?? "Unknown"
        let alert = NSAlert()
        alert.messageText = "ゴーストの消滅"
        alert.informativeText = "「\(name)」を消滅させますか？\nこの操作は取り消せません。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "消滅")
        alert.addButton(withTitle: "キャンセル")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        EventBridge.shared.notify(.OnVanishSelecting, params: [:])
        EventBridge.shared.notify(.OnVanishSelected, params: ["Reference0": name])
    }

    /// ネットワーク更新を確認
    private func checkNetworkUpdate() {
        EventBridge.shared.notify(.OnUpdateBegin, params: ["Reference0": "manual"])
    }

    /// ゴーストを切り替え
    private func switchGhost(to ghostID: String) {
        let target = ghostID.trimmingCharacters(in: .whitespacesAndNewlines).removingPercentEncoding ?? ghostID
        guard !target.isEmpty else {
            Log.info("[GhostManager] switch_ghost ignored: empty target")
            return
        }
        switchGhost(named: target, options: ["--option=raise-event"])
    }
    
    /// シェルを切り替え
    private func switchShell(to shellID: String) {
        let rawTarget = shellID.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = rawTarget.removingPercentEncoding ?? rawTarget
        guard !target.isEmpty else {
            Log.info("[GhostManager] switch_shell ignored: empty target")
            return
        }

        if switchShell(named: target, raiseEvent: true) {
            return
        }

        // Fallback for menu actions that pass index-like values (e.g. "0" / "shell1")
        let shellRoot = ghostURL.appendingPathComponent("shell")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: shellRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            Log.info("[GhostManager] switch_shell failed: shell directory is unavailable")
            return
        }
        let shellNames = entries
            .filter { $0.hasDirectoryPath }
            .map(\.lastPathComponent)
            .sorted()

        let normalized = target.lowercased()
        var resolvedIndex: Int?
        if let n = Int(normalized) {
            resolvedIndex = n
        } else if normalized.hasPrefix("shell"), let n = Int(normalized.dropFirst("shell".count)) {
            resolvedIndex = n
        }

        guard let index = resolvedIndex, shellNames.indices.contains(index) else {
            Log.info("[GhostManager] switch_shell failed: unknown target \(target)")
            return
        }

        let resolvedName = shellNames[index]
        if !switchShell(named: resolvedName, raiseEvent: true) {
            Log.info("[GhostManager] switch_shell failed: resolved shell not available \(resolvedName)")
        }
    }
    
    /// バルーンを切り替え
    private func switchBalloon(to balloonID: String) {
        if let id = Int(balloonID) {
            switchBalloon(to: id, scope: currentScope)
        } else {
            Log.info("[GhostManager] Invalid balloon ID: \(balloonID)")
        }
    }
}
