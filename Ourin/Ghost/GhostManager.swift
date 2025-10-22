import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications

// MARK: - ViewModels

/// ViewModel for the character view.
class CharacterViewModel: ObservableObject {
    @Published var image: NSImage?

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
    var activeEffects: [EffectConfig] = []
    var activeFilters: [FilterConfig] = []
    
    // Dressup bindings
    var dressupBindings: [String: [String: String]] = [:] // category -> part -> value
    
    // Text animations
    var textAnimations: [TextAnimationConfig] = []

    // Window stacking
    var zOrderGroup: [Int]? = nil  // nil = default, or array of scope IDs in front-to-back order
    var stickyGroup: [Int]? = nil  // nil = independent, or array of scope IDs that move together
    
    /// Surface overlay data
    struct SurfaceOverlay: Identifiable {
        let id: Int
        let image: NSImage
        var offset: CGPoint = .zero
        var alpha: Double = 1.0
    }

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
    
    // Sound playback tracking
    var currentSounds: [NSSound] = []
    
    // Animation engine
    var animationEngine: AnimationEngine = AnimationEngine()
    var waitingForAnimation: Int? = nil  // Animation ID we're waiting for

    // Window management (used by Window extension)
    var stickyWindowRelationships: [Int: Set<Int>] = [:] // Master scope -> follower scopes

    // Choice dialog state (used by System extension)
    var pendingChoices: [(title: String, action: ChoiceAction)] = []
    var choiceHasCancelOption: Bool = false
    var choiceTimeout: TimeInterval? = nil

    enum ChoiceAction {
        case event(id: String, references: [String])
        case script(String)
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
        
        // Setup animation engine callbacks
        setupAnimationCallbacks()
        
        // Setup screen change observer for desktop alignment
        setupScreenChangeObserver()
    }

    deinit {
        shutdown()
    }

    // MARK: - Public API

    func start() {
        Log.info("[GhostManager] start() called for ghost at: \(ghostURL.path)")
        setupWindows()
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
                Log.info("[GhostManager] Loaded ghost configuration: \(config.name)")
                Log.debug("[GhostManager]   - Sakura: \(config.sakuraName), Kero: \(config.keroName ?? "none")")
                Log.debug("[GhostManager]   - SHIORI: \(config.shiori)")
                Log.debug("[GhostManager]   - Default shell: \(config.defaultShellDirectory)")

                // Apply configuration settings to environment
                self.applyGhostConfiguration(config, ghostRoot: ghostRoot)
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
            var dics: [String] = []
            let yayaTxtPath = ghostRoot.appendingPathComponent("yaya.txt")
            if let yayaContent = (try? String(contentsOf: yayaTxtPath, encoding: .utf8)) ??
                                 (try? String(contentsOf: yayaTxtPath, encoding: .shiftJIS)) {
                Log.debug("[GhostManager] Found yaya.txt, parsing dictionary list with includes...")
                parseYayaConfigFile(content: yayaContent, baseURL: ghostRoot, dicFiles: &dics, visited: [])
                Log.debug("[GhostManager] Found \(dics.count) dictionaries (including from includes): \(dics.prefix(5))...")
            } else {
                // yaya.txt がない場合は全ファイルをロード
                dics = contents.filter { $0.pathExtension.lowercased() == "dic" }.map { $0.lastPathComponent }
                Log.debug("[GhostManager] yaya.txt not found, loading all \(dics.count) .dic files")
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
            guard adapter.load(ghostRoot: ghostRoot, dics: dics) else {
                Log.info("[GhostManager] Failed to load ghost with Yaya.")
                return
            }
            let loadTime = Date().timeIntervalSince(loadStart)
            Log.debug("[GhostManager] Dictionary load complete in \(String(format: "%.2f", loadTime))s")

            // Per UKADOC, OnFirstBoot/OnBoot are GET events (not NOTIFY).
            // Only emit an internal OnInitialize notify; GET is handled below via obtainBootScript().
            DispatchQueue.main.async {
                EventBridge.shared.notify(.OnInitialize)
                let defaults = UserDefaults.standard
                let count = defaults.integer(forKey: "OurinBootCount")
                defaults.set(count + 1, forKey: "OurinBootCount")
            }

            // Request boot script with a timeout; keep placeholder visible meanwhile.
            Log.info("[GhostManager] Requesting boot script (OnFirstBoot/OnBoot)...")
            let sem = DispatchSemaphore(value: 0)

            DispatchQueue.global(qos: .userInitiated).async {
                let script = self.obtainBootScript(using: adapter)
                if let script = script {
                    let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        Log.debug("[GhostManager] Boot script resolved (len=\(trimmed.count))")
                        // Print a safe preview via NSLog so it always appears in logs
                        let preview = trimmed.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
                        NSLog("[GhostManager] Boot script preview: \(preview)")
                        DispatchQueue.main.async {
                            // Start EventBridge at the moment OnBoot begins
                            self.startEventBridgeIfNeeded()
                            self.runScript(trimmed)
                        }
                    } else {
                        NSLog("[GhostManager] Boot script is whitespace-only after trim; skipping display")
                        DispatchQueue.main.async {
                            self.startEventBridgeIfNeeded()
                        }
                    }
                } else {
                    Log.info("[GhostManager] Boot script could not be resolved; starting EventBridge only.")
                    DispatchQueue.main.async {
                        self.startEventBridgeIfNeeded()
                    }
                }
                sem.signal()
            }

            // If OnBoot takes too long, start EventBridge so NOTIFY can begin, keeping placeholder.
            let timeout: DispatchTime = .now() + .seconds(5)
            if sem.wait(timeout: timeout) == .timedOut {
                Log.info("[GhostManager] OnBoot timed out (5s). Starting EventBridge and keeping placeholder.")
                DispatchQueue.main.async {
                    self.startEventBridgeIfNeeded()
                }
                // The request will still complete later and update the UI when ready.
            }
        }
    }

    func shutdown() {
        NotificationCenter.default.removeObserver(self)
        for w in characterWindows.values { w.orderOut(nil) }
        for w in balloonWindows.values { w.orderOut(nil) }
        characterWindows.removeAll()
        balloonWindows.removeAll()
        yayaAdapter?.unload()
        yayaAdapter = nil
        if let token = eventToken { EventBridge.shared.unregister(token); eventToken = nil }
    }

    // MARK: - Scripting

    func runScript(_ script: String) {
        let preview = script.prefix(200)
        Log.debug("[GhostManager] runScript called with: \(preview)")
        // Avoid clearing the balloon when script is effectively empty (whitespace only)
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Reset playback state and balloon text for new script
        playbackQueue.removeAll()
        isPlaying = false
        quickMode = false
        preciseBase = Date()
        for vm in balloonViewModels.values { vm.text = "" }
        typingInterval = defaultTypingInterval
        sakuraEngine.run(script: trimmed)
        startPlaybackIfNeeded()
    }

    /// Run a script originating from NOTIFY. If the script contains no visible text
    /// tokens, keep the current balloon text and apply only commands (surface/scope/etc.).
    func runNotifyScript(_ script: String) {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let hasText = sakuraEngine.containsText(in: trimmed)
        if hasText {
            // New visible text: cancel pending playback and clear balloon
            playbackQueue.removeAll()
            isPlaying = false
            quickMode = false
            preciseBase = Date()
            for vm in balloonViewModels.values { vm.text = "" }
            typingInterval = defaultTypingInterval
        }
        sakuraEngine.run(script: trimmed)
        startPlaybackIfNeeded()
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
        case .text(let text):
            // Display text character by character with typing effect
            for ch in text { playbackQueue.append(.text(ch)) }
        case .newline:
            playbackQueue.append(.newline)
        case .newlineVariation(_):
            // \n[half] or \n[percent] - custom newline height
            // TODO: Implement variable height newlines
            // For now, treat as regular newline
            playbackQueue.append(.newline)
        case .balloon(let id):
            // \bN or \b[ID] - change balloon ID
            Log.debug("[GhostManager] Switching to balloon ID: \(id)")
            switchBalloon(to: id, scope: currentScope)
            
        case .appendMode:
            // \C - append to previous balloon
            Log.debug("[GhostManager] Append mode - maintaining current balloon")
            // Append mode keeps the current balloon open and adds new text
            // This is implemented by not clearing the text buffer
            // The balloon view will continue displaying the previous content
        case .end:
            playbackQueue.append(.end)
        case .animation(let id, let wait):
            // \i[ID] or \i[ID,wait] - play surface animation
            if wait {
                // Wait for animation to complete before continuing
                playAnimationAndWait(id: id)
            } else {
                // Play animation without waiting
                playAnimation(id: id, wait: false)
            }
        // New token types - added for comprehensive Sakura Script support
        case .wait:
            // \t - Quick wait (short pause, not click wait)
            // According to Sakura Script spec, \t is a brief pause, not a click wait
            // Click wait should be done with \x or \_w commands
            playbackQueue.append(.wait(0.1)) // 100ms pause
        
        case .endConversation(let clearBalloon):
            // \x or \x[noclear] - End conversation
            playbackQueue.append(.clickWait(noclear: !clearBalloon))
        
        case .choiceCancel:
            // \z - Choice cancellation
            Log.debug("[GhostManager] Choice cancel marker")
            choiceHasCancelOption = true
        
        case .choiceMarker:
            // \* - Choice marker (indicates start of choice section)
            Log.debug("[GhostManager] Choice marker - displaying choices")
            // Display accumulated choices
            showChoiceDialog()
        
        case .anchor:
            // \a - Anchor marker (for clickable text)
            Log.debug("[GhostManager] Anchor marker")
            // Anchor is similar to choice but inline in text
            // For now, treat as choice marker
            showChoiceDialog()
        
        case .choiceLineBr:
            // \- - Line break in choice
            playbackQueue.append(.newline)
        
        case .moveAway:
            // \4 - Move window to back (away from other windows)
            moveWindowToBack(scope: currentScope)
        
        case .moveClose:
            // \5 - Move window to front (close to user)
            moveWindowToFront(scope: currentScope)
        
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
            // \v - Open preferences dialog
            DispatchQueue.main.async {
                // Open Settings window (macOS 13+) or Preferences (older macOS)
                if #available(macOS 13, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }
        
        case .openURL:
            // \6 - Open URL in browser
            if let url = pendingURL {
                openURL(url)
                pendingURL = nil
            } else {
                Log.info("[GhostManager] Open URL command but no URL in context")
            }
        
        case .openEmail:
            // \7 - Open email client
            if let email = pendingEmail {
                openEmail(email)
                pendingEmail = nil
            } else {
                Log.info("[GhostManager] Open email command but no email in context")
            }
        
        case .playSound(let filename):
            // \8[filename] - Play sound file
            playSound(filename: filename)
        
        case .command(let name, let args):
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
                    } else if let ms = Double(first) {
                        playbackQueue.append(.waitUntil(ms/1000.0))
                    }
                }
            case "x":
                let noclear = (args.first?.lowercased() == "noclear")
                playbackQueue.append(.clickWait(noclear: noclear))
            case "_q":
                quickMode.toggle()
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
                    } else if first == "get", args.count >= 3, args[1].lowercased() == "property" {
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
                    } else if first == "set", args.count >= 3, args[1].lowercased() == "property" {
                        // \![set,property,プロパティ名,値]
                        // Set property value
                        let propertyKey = args[2]
                        let propertyValue = args.count >= 4 ? args[3] : ""
                        let success = sakuraEngine.propertyManager.set(propertyKey, value: propertyValue)
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
                    } else if first == "signal", args.count >= 2, args[1].lowercased() == "syncobject" {
                        let name = args.count >= 3 ? args[2] : ""
                        SyncCenter.shared.signal(name: name)
                    } else if first == "open", args.count >= 2, args[1].lowercased() == "configurationdialog" {
                        // \![open,configurationdialog,setup] - Show name input dialog
                        // This command should execute AFTER the script finishes, not immediately
                        if args.count >= 3, args[2].lowercased() == "setup" {
                            NSLog("[GhostManager] Queueing deferred command: showNameInputDialog")
                            playbackQueue.append(.deferredCommand {
                                NSLog("[GhostManager] Deferred command closure executing: showNameInputDialog")
                                DispatchQueue.main.async {
                                    self.showNameInputDialog()
                                }
                            })
                        }
                    } else if first == "set", args.count >= 2 {
                        // Handle \![set,*] commands
                        let subcmd = args[1].lowercased()
                        switch subcmd {
                        case "scaling":
                            // \![set,scaling,ratio] or \![set,scaling,x,y] or \![set,scaling,x,y,time]
                            if args.count >= 3 {
                                if let ratio = Double(args[2]) {
                                    let scaleValue = ratio / 100.0  // Convert percentage to scale factor
                                    DispatchQueue.main.async {
                                        guard let vm = self.characterViewModels[self.currentScope] else { return }
                                        
                                        let targetScaleX: Double
                                        let targetScaleY: Double
                                        
                                        if args.count >= 4, let yRatio = Double(args[3]) {
                                            // Non-uniform scaling
                                            targetScaleX = scaleValue
                                            targetScaleY = yRatio / 100.0
                                        } else {
                                            // Uniform scaling
                                            targetScaleX = scaleValue
                                            targetScaleY = scaleValue
                                        }
                                        
                                        // Check if animation time specified
                                        if args.count >= 5, let timeMs = Double(args[4]), timeMs > 0 {
                                            // Animated scaling
                                            NSAnimationContext.runAnimationGroup({ context in
                                                context.duration = timeMs / 1000.0
                                                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                                                vm.scaleX = targetScaleX
                                                vm.scaleY = targetScaleY
                                            })
                                        } else {
                                            // Instant scaling
                                            vm.scaleX = targetScaleX
                                            vm.scaleY = targetScaleY
                                        }
                                    }
                                }
                            }
                        case "alpha":
                            // \![set,alpha,value] (0-100)
                            if args.count >= 3, let alphaValue = Double(args[2]) {
                                DispatchQueue.main.async {
                                    guard let vm = self.characterViewModels[self.currentScope] else { return }
                                    vm.alpha = alphaValue / 100.0  // Convert 0-100 to 0.0-1.0
                                }
                            }
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
                            // \![set,zorder,ID1,ID2,...] - front to back
                            if args.count >= 3 {
                                let scopeIDs = args.dropFirst(2).compactMap { Int($0) }
                                setWindowZOrder(scopes: scopeIDs)
                            }
                        case "sticky-window":
                            // \![set,sticky-window,ID1,ID2,...] - windows move together
                            if args.count >= 3 {
                                let scopeIDs = args.dropFirst(2).compactMap { Int($0) }
                                if let master = scopeIDs.first {
                                    let followers = Array(scopeIDs.dropFirst())
                                    setStickyWindow(masterScope: master, followerScopes: followers)
                                }
                            }
                        case "wallpaper":
                            // \![set,wallpaper,filename,options]
                            if args.count >= 3 {
                                let filename = args[2]
                                let options = args.count >= 4 ? args[3] : ""
                                setWallpaper(filename: filename, options: options)
                            }
                        case "tasktrayicon":
                            // \![set,tasktrayicon,filename,text]
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
                                setOtherSurfaceChange(enabled: args[2].lowercased() == "true")
                            }
                        case "windowstate":
                            // \![set,windowstate,stayontop/!stayontop/minimize]
                            if args.count >= 3 {
                                setWindowState(state: args[2])
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
                        }
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
                        // \![update,platform] or \![update,target,options...]
                        let target = args.count >= 2 ? args[1] : "platform"
                        let options = Array(args.dropFirst(2))
                        executeUpdate(target: target, options: options)
                    } else if first == "updateother" {
                        // \![updateother] - check for updates to all other ghosts
                        executeUpdate(target: "other", options: [])
                    } else if first == "vanishbymyself" {
                        // \![vanishbymyself] - terminate this ghost
                        executeVanish()
                    } else if first == "anim", args.count >= 2 {
                        // Handle \![anim,*] commands - animation control
                        let subcmd = args[1].lowercased()
                        switch subcmd {
                        case "clear":
                            // \![anim,clear,ID] - clear specific animation/overlay
                            if args.count >= 3, let overlayID = Int(args[2]) {
                                animationEngine.clearAnimation(id: overlayID)
                                clearSpecificOverlay(id: overlayID)
                            }
                        case "pause":
                            // \![anim,pause,ID] - pause animation
                            if args.count >= 3, let animID = Int(args[2]) {
                                animationEngine.pauseAnimation(id: animID)
                            }
                        case "resume":
                            // \![anim,resume,ID] - resume animation
                            if args.count >= 3, let animID = Int(args[2]) {
                                animationEngine.resumeAnimation(id: animID)
                            }
                        case "stop":
                            // \![anim,stop] - stop all animations and clear all overlays
                            animationEngine.stopAllAnimations()
                            clearSurfaceOverlays()
                        case "offset":
                            // \![anim,offset,ID,x,y] - offset an animation/overlay
                            if args.count >= 5, let overlayID = Int(args[2]),
                               let x = Double(args[3]), let y = Double(args[4]) {
                                animationEngine.offsetAnimation(id: overlayID, x: x, y: y)
                                offsetOverlay(id: overlayID, x: x, y: y)
                            }
                        case "add":
                            // \![anim,add,overlay,ID] or \![anim,add,base,ID] or \![anim,add,text,...]
                            if args.count >= 4 {
                                let addType = args[2].lowercased()
                                if addType == "overlay" {
                                    if let surfaceID = Int(args[3]) {
                                        handleSurfaceOverlay(surfaceID: surfaceID)
                                    }
                                } else if addType == "base" {
                                    Log.debug("[GhostManager] Animation add base not yet implemented")
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
                    } else if first == "bind", args.count >= 4 {
                        // Handle \![bind,category,part,value] - dressup control
                        let category = args[1]
                        let part = args[2]
                        let value = args[3]
                        handleBindDressup(category: category, part: part, value: value)
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
                    } else if first == "move", args.count >= 3 {
                        // Handle \![move,x,y,time,method,scopeID] - synchronous window move
                        if let x = Int(args[1]), let y = Int(args[2]) {
                            let time = args.count >= 4 ? Int(args[3]) ?? 0 : 0
                            let method = args.count >= 5 ? args[4] : ""
                            let scopeID = args.count >= 6 ? Int(args[5]) ?? currentScope : currentScope
                            moveWindow(scope: scopeID, x: x, y: y, time: time, method: method)
                        }
                    } else if first == "moveasync", args.count >= 3 {
                        // Handle \![moveasync,x,y,time,method,scopeID] - asynchronous window move
                        if let x = Int(args[1]), let y = Int(args[2]) {
                            let time = args.count >= 4 ? Int(args[3]) ?? 0 : 0
                            let method = args.count >= 5 ? args[4] : ""
                            let scopeID = args.count >= 6 ? Int(args[5]) ?? currentScope : currentScope
                            moveWindowAsync(scope: scopeID, x: x, y: y, time: time, method: method)
                        }
                    } else if first == "effect" || first == "effect2" || first == "filter" {
                        // Handle \![effect,...], \![effect2,...], \![filter,...]
                        // TODO: Implement visual effects/filters via plugins
                        Log.debug("[GhostManager] Effect/filter command not yet implemented: \(first)")
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
                    // TODO: Store anchor for clickable text display
                }
            
            case "_b":
                // \_b[filepath,...] - balloon image display
                handleBalloonImage(args: args)
            
            case "_v":
                // \_v[filename] - play voice file
                if let filename = args.first {
                    playSound(filename: filename)
                }
            
            case "_V":
                // \_V - stop voice playback
                stopAllSounds()
            
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
            guard !playbackQueue.isEmpty else { isPlaying = false; return }
            let unit = playbackQueue.removeFirst()
            switch unit {
            case .scope(let id):
                // Clear other scopes' balloons to ensure sequential dialogue (no parallel display)
                for (scopeId, vm) in balloonViewModels {
                    if scopeId != id {
                        vm.text = ""
                    }
                }
                currentScope = id
                Log.debug("[GhostManager] Switched to scope \(id)")

                // Show the character window for this scope (in case it was hidden)
                if let window = characterWindows[id] {
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
    /// 1) GET OnFirstBoot (YAYA)
    /// 2) GET OnBoot (YAYA)
    /// 3) BridgeToSHIORI for OnBoot (may return placeholder)
    /// 4) Built-in minimal greeting
    private func obtainBootScript(using adapter: YayaAdapter) -> String? {
        // 1) OnFirstBoot
        if let r = adapter.request(method: "GET", id: "OnFirstBoot", timeout: 4.0), r.ok {
            let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pv = v.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
            NSLog("[GhostManager] OnFirstBoot response: ok=true, len=\(v.count), preview=\(pv)")
            if !v.isEmpty { return v }
        } else {
            NSLog("[GhostManager] OnFirstBoot request failed or no response")
        }

        // 2) OnBoot
        if let r = adapter.request(method: "GET", id: "OnBoot", timeout: 4.0), r.ok {
            let v = r.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let pv = v.replacingOccurrences(of: "\n", with: "\\n").prefix(160)
            NSLog("[GhostManager] OnBoot response: ok=true, len=\(v.count), preview=\(pv)")
            if !v.isEmpty { return v }
        } else {
            NSLog("[GhostManager] OnBoot request failed or no response")
        }

        // 3) Bridge fallback
        let bridge = BridgeToSHIORI.handle(event: "OnBoot", references: [])
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
}
