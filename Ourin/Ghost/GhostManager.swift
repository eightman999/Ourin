import SwiftUI
import AppKit
import CoreImage
import Combine

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

    private let ghostURL: URL
    private var yayaAdapter: YayaAdapter?
    private let sakuraEngine = SakuraScriptEngine()
    private var eventToken: UUID?
    private let resourceManager = ResourceManager()
    private var ghostConfig: GhostConfiguration?

    // Window management
    private var characterWindows: [Int: NSWindow] = [:] // Support multiple scopes (0=master, 1=partner)
    private var balloonWindows: [Int: NSWindow] = [:]

    // ViewModels
    private var characterViewModels: [Int: CharacterViewModel] = [:] // One per scope
    private var balloonViewModels: [Int: BalloonViewModel] = [:]

    private var currentScope: Int = 0
    private var balloonTextCancellables: [Int: AnyCancellable] = [:]
    
    // Context tracking for URL/email commands
    private var pendingURL: String?
    private var pendingEmail: String?

    // Typing playback state
    private enum PlaybackUnit {
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
    }
    private var playbackQueue: [PlaybackUnit] = []
    private var isPlaying: Bool = false
    private var quickMode: Bool = false
    private var preciseBase: Date = Date()
    private let defaultTypingInterval: TimeInterval = 0.1
    private var typingInterval: TimeInterval = 0.1
    private var syncEnabled: Bool = false
    private var syncScopes: Set<Int> = []
    private var pendingClick: Bool? = nil
    
    // Sound playback tracking
    private var currentSounds: [NSSound] = []
    
    // Animation engine
    private var animationEngine: AnimationEngine = AnimationEngine()
    private var waitingForAnimation: Int? = nil  // Animation ID we're waiting for

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
                            self.runScript(trimmed)
                            self.startEventBridgeIfNeeded()
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

    // MARK: - Window Setup

    private func setupWindows() {
        Log.debug("[GhostManager] Setting up windows")
        // Create Character Windows for scope 0 (master), 1 (partner), and potentially 2-3 (additional characters)
        // Always create at least scope 0 and 1; additional scopes can be created dynamically
        for scope in 0..<4 {
            setupCharacterWindow(for: scope)
        }
    }

    private func setupCharacterWindow(for scope: Int) {
        let dragDropHandler: (ShioriEvent) -> Void = { event in
            // Forward drag-drop events to EventBridge for broadcasting
            EventBridge.shared.notify(event.id, params: event.params)
        }

        let vm = CharacterViewModel()
        characterViewModels[scope] = vm

        let characterView = CharacterView(viewModel: vm, onDragDropEvent: dragDropHandler)
        let hostingController = NSHostingController(rootView: characterView)

        let window = NSWindow(contentViewController: hostingController)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask = [.borderless]
        window.ignoresMouseEvents = false
        // Ghost windows: above normal windows but below balloons
        // Use .statusBar (25) so ghosts are above normal apps but below popUpMenu (balloons)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Enable dragging the window by its content
        window.isMovableByWindowBackground = true
        window.isMovable = true

        // Position character windows
        let characterWidth: CGFloat = 300
        let characterHeight: CGFloat = 400

        // Try to restore saved position first
        var didRestore = false
        if let savedX = resourceManager.getCharDefaultLeft(scope: scope),
           let savedY = resourceManager.getCharDefaultTop(scope: scope) {
            window.setFrame(.init(x: CGFloat(savedX), y: CGFloat(savedY), width: characterWidth, height: characterHeight), display: true)
            Log.debug("[GhostManager] Scope \(scope) window restored to saved position (\(savedX), \(savedY))")
            didRestore = true
        }

        // Otherwise use default positions
        if !didRestore {
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let margin: CGFloat = 10 // Small margin between characters
                let baseY = screenFrame.minY + 5

                // Calculate positions: all characters line up from right side
                // Scope 0 (sakura/master) is rightmost
                // Scope 1+ (kero/partners) are to the left of scope 0
                let baseX = screenFrame.maxX - characterWidth - 20
                let x = baseX - (CGFloat(scope) * (characterWidth + margin))

                window.setFrame(.init(x: x, y: baseY, width: characterWidth, height: characterHeight), display: true)
                Log.debug("[GhostManager] Scope \(scope) window at default position (\(x), \(baseY))")
            } else {
                // Fallback positioning
                let x: CGFloat = 200 + (CGFloat(scope) * 320)
                window.setFrame(.init(x: x, y: 200, width: characterWidth, height: characterHeight), display: true)
            }
        }

        window.identifier = NSUserInterfaceItemIdentifier("GhostCharacterWindow_\(scope)")

        // Always show ghost window - it stays visible until explicit shutdown command
        window.makeKeyAndOrderFront(nil)

        // Keep window visible and prevent auto-hiding
        window.isReleasedWhenClosed = false

        characterWindows[scope] = window

        // Track window movement/resize
        NotificationCenter.default.addObserver(self, selector: #selector(characterWindowDidChangeFrame(_:)), name: NSWindow.didMoveNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(characterWindowDidChangeFrame(_:)), name: NSWindow.didResizeNotification, object: window)
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
        case .newlineVariation(let variation):
            // \n[half] or \n[percent] - custom newline height
            // TODO: Implement variable height newlines
            // For now, treat as regular newline
            playbackQueue.append(.newline)
        case .balloon(let id):
            // \bN or \b[ID] - change balloon ID
            // TODO: Implement balloon ID switching
            Log.debug("[GhostManager] Balloon ID switch to \(id) not yet implemented")
        case .appendMode:
            // \C - append to previous balloon
            // TODO: Implement append mode
            Log.debug("[GhostManager] Append mode not yet implemented")
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
        case .moveAway:
            // \4 - Move away from other character
            // TODO: Implement character movement logic
            break
        case .moveClose:
            // \5 - Move close to other character
            // TODO: Implement character movement logic
            break
        
        // New token types - added for comprehensive Sakura Script support
        case .wait:
            // \t - Quick wait/click wait
            playbackQueue.append(.clickWait(noclear: false))
        
        case .endConversation(let clearBalloon):
            // \x or \x[noclear] - End conversation
            playbackQueue.append(.clickWait(noclear: !clearBalloon))
        
        case .choiceCancel:
            // \z - Choice cancellation
            Log.debug("[GhostManager] Choice cancel marker")
            // Mark that choices can be cancelled with right-click or ESC
            // This is typically handled by the choice display system
            break
        
        case .choiceMarker:
            // \* - Choice marker (indicates start of choice section)
            Log.debug("[GhostManager] Choice marker")
            break
        
        case .anchor:
            // \a - Anchor marker (for clickable text)
            Log.debug("[GhostManager] Anchor marker")
            break
        
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
                NSApp.sendAction(#selector(NSApplication.showPreferencesWindow), to: nil, from: nil)
            }
        
        case .openURL:
            // \6 - Open URL in browser
            if let url = pendingURL {
                openURL(url)
                pendingURL = nil
            } else {
                Log.warning("[GhostManager] Open URL command but no URL in context")
            }
        
        case .openEmail:
            // \7 - Open email client
            if let email = pendingEmail {
                openEmail(email)
                pendingEmail = nil
            } else {
                Log.warning("[GhostManager] Open email command but no email in context")
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
                if let first = args.first?.lowercased() {
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
                        if args.count >= 3, args[2].lowercased() == "setup" {
                            DispatchQueue.main.async {
                                self.showNameInputDialog()
                            }
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
                                          let window = self.characterWindows[self.currentScope] else { return }
                                    
                                    switch direction {
                                    case "top": vm.alignment = .top
                                    case "bottom": vm.alignment = .bottom
                                    case "left": vm.alignment = .left
                                    case "right": vm.alignment = .right
                                    case "free": vm.alignment = .free
                                    case "default": vm.alignment = .free
                                    default: break
                                    }
                                    
                                    // Apply window position constraints based on alignment
                                    if let screen = NSScreen.main {
                                        let screenFrame = screen.visibleFrame
                                        var newOrigin = window.frame.origin
                                        let windowSize = window.frame.size
                                        
                                        switch vm.alignment {
                                        case .top:
                                            newOrigin.y = screenFrame.maxY - windowSize.height
                                        case .bottom:
                                            newOrigin.y = screenFrame.minY
                                        case .left:
                                            newOrigin.x = screenFrame.minX
                                        case .right:
                                            newOrigin.x = screenFrame.maxX - windowSize.width
                                        case .free:
                                            break
                                        }
                                        
                                        if vm.alignment != .free {
                                            window.setFrameOrigin(newOrigin)
                                            // Save new position
                                            self.resourceManager.saveWindowPosition(scope: self.currentScope, position: newOrigin)
                                        }
                                    }
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

    private func processNextUnit() {
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
            }
        }
    }

    private func scheduleNext(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.processNextUnit()
        }
    }

    // MARK: - Balloon helpers
    private func getBalloonVM(for scope: Int) -> BalloonViewModel {
        if let vm = balloonViewModels[scope] { return vm }
        let vm = BalloonViewModel()
        balloonViewModels[scope] = vm

        let view = BalloonView(viewModel: vm, onClick: { [weak self] in self?.onBalloonClicked(fromScope: scope) })
        let hc = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hc)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.styleMask = [.borderless]
        win.hasShadow = false
        // Balloon windows: highest level, above everything (ghost + other apps)
        // Use popUpMenu (101) to ensure balloons are always on top
        win.level = .popUpMenu
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Enable dragging the balloon window by its content
        win.isMovableByWindowBackground = true
        win.isMovable = true

        // Start with a reasonable initial size; it will resize based on content
        win.setFrame(.init(x: 450, y: 300, width: 250, height: 100), display: true)
        win.identifier = NSUserInterfaceItemIdentifier("GhostBalloonWindow_\(scope)")
        win.orderOut(nil)
        balloonWindows[scope] = win

        // show/hide per text and resize window to fit content
        // Use debouncing to prevent flickering from rapid text updates
        balloonTextCancellables[scope] = vm.$text
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self, weak win, weak hc] text in
                guard let self = self, let win = win, let hc = hc else { return }
                if text.isEmpty {
                    if win.isVisible {
                        win.orderOut(nil)
                    }
                } else {
                    let wasVisible = win.isVisible

                    // Resize window to fit content
                    let fittingSize = hc.view.fittingSize
                    let newSize = CGSize(width: max(250, min(fittingSize.width, 400)),
                                       height: max(50, min(fittingSize.height, 600)))

                    // Only update if size changed significantly (avoid micro-adjustments)
                    let currentSize = win.frame.size
                    if abs(currentSize.width - newSize.width) > 5 || abs(currentSize.height - newSize.height) > 5 {
                        var frame = win.frame
                        frame.size = newSize
                        win.setFrame(frame, display: false, animate: false)
                        self.positionBalloonWindow()
                    }

                    // Only call orderFront if not already visible
                    if !wasVisible {
                        win.orderFront(nil)
                    }
                }
            }
        positionBalloonWindow()
        return vm
    }

    private func appendText(_ s: String) {
        // Always use current scope only - no parallel display for character dialogue
        // if syncEnabled {
        //     let targets = syncScopes.isEmpty ? [0,1] : Array(syncScopes)
        //     for sc in targets { getBalloonVM(for: sc).text += s }
        // } else {
            getBalloonVM(for: currentScope).text += s
        // }
    }

    private func onBalloonClicked(fromScope: Int) {
        guard let waitNoclear = pendingClick else { return }
        if !waitNoclear {
            for vm in balloonViewModels.values { vm.text = "" }
        }
        currentScope = 0
        positionBalloonWindow()
        pendingClick = nil
        scheduleNext(after: 0)
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

    private func startEventBridgeIfNeeded() {
        // Start the event bridge only after the initial UI is ready
        guard (NSApplication.shared.delegate as? AppDelegate)?.eventBridge == nil else { return }
        let bridge = EventBridge.shared
        bridge.start()
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.eventBridge = bridge
        }
        Log.debug("[GhostManager] EventBridge started (post-initialization)")
    }

    private func updateSurface(id: Int) {
        let scope = currentScope
        
        // Clear overlays when surface changes (per UKADOC spec)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let vm = self.characterViewModels[scope] {
                vm.overlays.removeAll()
                Log.debug("[GhostManager] Cleared overlays for scope \(scope) due to surface change")
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let image = self.loadImage(surfaceId: id, scope: scope)
            DispatchQueue.main.async {
                // If the requested surface doesn't exist, keep the current surface
                guard let image = image else {
                    Log.info("[GhostManager] Surface \(id) not found for scope \(scope), keeping current surface")
                    return
                }

                if let vm = self.characterViewModels[scope] {
                    vm.image = image
                }
                if let win = self.characterWindows[scope] {
                    // Resize window to fit the new surface
                    win.setContentSize(image.size)
                    self.positionBalloonWindow()
                }
            }
        }
    }

    private func loadImage(surfaceId: Int, scope: Int) -> NSImage? {
        let shellURL = ghostURL.appendingPathComponent("shell/master")
        // いくつかのシェルは surface0000.png のような4桁ゼロ埋めを使う。
        func pad4(_ n: Int) -> String { String(format: "%04d", n) }

        var candidates: [String] = []
        // スコープ付きの命名: surface{scope}{id}.png / surface{scope}{0000id}.png
        if scope == 1 {
            candidates.append("surface1\(surfaceId).png")
            candidates.append("surface1\(pad4(surfaceId)).png")
        }
        // 共通命名: surface{n}.png / surface{000n}.png
        candidates.append("surface\(surfaceId).png")
        candidates.append("surface\(pad4(surfaceId)).png")

        for name in candidates {
            let url = shellURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path), let img = NSImage(contentsOf: url) {
                // PNA マスクがあれば適用（白=不透明、黒=透明として扱う想定）
                let pnaURL = url.deletingPathExtension().appendingPathExtension("pna")
                if FileManager.default.fileExists(atPath: pnaURL.path),
                   let masked = applyPNAMask(baseURL: url, maskURL: pnaURL) {
                    Log.debug("[GhostManager] Image loaded with PNA mask: \(name)")
                    return masked
                }
                Log.debug("[GhostManager] Image loaded: \(name)")
                return img
            }
        }
        Log.info("[GhostManager] No surface image found for id=\(surfaceId) scope=\(scope). Tried: \(candidates)")
        return nil
    }

    // PNA マスクを適用して透過画像を生成
    private func applyPNAMask(baseURL: URL, maskURL: URL) -> NSImage? {
        guard let baseCI = CIImage(contentsOf: baseURL),
              let maskCI = CIImage(contentsOf: maskURL) else { return nil }
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: baseCI.extent)
        guard let output = CIFilter(name: "CIBlendWithMask",
                                    parameters: [kCIInputImageKey: baseCI,
                                                 kCIInputBackgroundImageKey: clear,
                                                 kCIInputMaskImageKey: maskCI])?.outputImage else { return nil }
        let ctx = CIContext(options: nil)
        guard let cg = ctx.createCGImage(output, from: baseCI.extent) else { return nil }
        let size = NSSize(width: cg.width, height: cg.height)
        let nsimg = NSImage(size: size)
        nsimg.lockFocus()
        NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(origin: .zero, size: size))
        nsimg.unlockFocus()
        return nsimg
    }

    // MARK: - Balloon Positioning

    @objc private func characterWindowDidChangeFrame(_ notification: Notification) {
        positionBalloonWindow()

        // Save window positions when moved
        if let window = notification.object as? NSWindow,
           let identifier = window.identifier?.rawValue,
           identifier.hasPrefix("GhostCharacterWindow_") {
            let scopeStr = identifier.replacingOccurrences(of: "GhostCharacterWindow_", with: "")
            if let scope = Int(scopeStr) {
                let frame = window.frame
                resourceManager.setCharDefaultLeft(scope: scope, value: Int(frame.origin.x))
                resourceManager.setCharDefaultTop(scope: scope, value: Int(frame.origin.y))
                Log.debug("[GhostManager] Saved scope \(scope) position: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
            }
        }
    }

    private func positionBalloonWindow() {
        let margin: CGFloat = 8
        let verticalOffset: CGFloat = 80 // Move balloon higher above character head

        // Position each balloon next to its corresponding character window
        for (scope, balloonWin) in balloonWindows {
            guard let charWin = characterWindows[scope] else { continue }
            let cFrame = charWin.frame

            var f = balloonWin.frame

            // Position balloon to the right of character for all scopes
            // This provides consistent positioning regardless of scope
            f.origin.x = cFrame.maxX + margin
            f.origin.y = cFrame.maxY - f.height + verticalOffset

            // Keep balloon within screen bounds
            if let screen = charWin.screen?.visibleFrame {
                if f.maxX > screen.maxX { f.origin.x = screen.maxX - f.width - margin }
                if f.minX < screen.minX { f.origin.x = screen.minX + margin }
                if f.maxY > screen.maxY { f.origin.y = screen.maxY - f.height - margin }
                if f.minY < screen.minY { f.origin.y = screen.minY + margin }
            }
            balloonWin.setFrameOrigin(f.origin)
        }
    }

    // MARK: - Ghost Configuration Application

    /// Apply ghost configuration settings loaded from descript.txt
    private func applyGhostConfiguration(_ config: GhostConfiguration, ghostRoot: URL) {
        Log.debug("[GhostManager] Applying ghost configuration...")

        // Store homeurl in ResourceManager if specified
        if let homeurl = config.homeurl {
            resourceManager.homeurl = homeurl
            Log.debug("[GhostManager]   - Set homeurl: \(homeurl)")
        }

        // Apply default surface positions if specified
        if let sakuraX = config.sakuraDefaultX {
            resourceManager.sakuraDefaultX = sakuraX
        }
        if let sakuraY = config.sakuraDefaultY {
            resourceManager.sakuraDefaultY = sakuraY
        }
        if let keroX = config.keroDefaultX {
            resourceManager.keroDefaultX = keroX
        }
        if let keroY = config.keroDefaultY {
            resourceManager.keroDefaultY = keroY
        }

        // Apply default display positions if specified and alignment is free
        let sakuraAlignmentIsFree = (config.sakuraAlignment ?? config.alignmentToDesktop) == .free
        let keroAlignmentIsFree = (config.keroAlignment ?? config.alignmentToDesktop) == .free

        if sakuraAlignmentIsFree {
            if let left = config.sakuraDefaultLeft {
                resourceManager.sakuraDefaultLeft = left
            }
            if let top = config.sakuraDefaultTop {
                resourceManager.sakuraDefaultTop = top
            }
        }

        if keroAlignmentIsFree {
            if let left = config.keroDefaultLeft {
                resourceManager.keroDefaultLeft = left
            }
            if let top = config.keroDefaultTop {
                resourceManager.keroDefaultTop = top
            }
        }

        // Apply additional character positions
        for (charNum, x) in config.charDefaultX {
            if let key = "char\(charNum).defaultx" as String? {
                resourceManager.set(key, value: String(x))
            }
        }
        for (charNum, y) in config.charDefaultY {
            if let key = "char\(charNum).defaulty" as String? {
                resourceManager.set(key, value: String(y))
            }
        }
        for (charNum, left) in config.charDefaultLeft {
            resourceManager.setCharDefaultLeft(scope: charNum, value: left)
        }
        for (charNum, top) in config.charDefaultTop {
            resourceManager.setCharDefaultTop(scope: charNum, value: top)
        }

        // Note: Other configuration values are used directly when needed:
        // - SHIORI settings (shiori, shioriVersion, etc.) are used by adapter loading
        // - Surface defaults are used by SERIKO engine
        // - SSTP settings are used by SSTP server
        // - UI settings (cursors, icons) are applied when creating UI elements
        // - Balloon settings are used by balloon system

        Log.debug("[GhostManager] Ghost configuration applied successfully")
    }

    // MARK: - Configuration Dialog

    private func showNameInputDialog() {
        let alert = NSAlert()
        alert.messageText = "あなたのお名前は？"
        alert.informativeText = "お名前を入力してください"
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "名前"

        // Load existing name from UserDefaults if available
        let defaults = UserDefaults.standard
        if let savedName = defaults.string(forKey: "OurinUserName") {
            textField.stringValue = savedName
        }

        alert.accessoryView = textField
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")

        alert.window.initialFirstResponder = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let userName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !userName.isEmpty {
                // Save to both UserDefaults (legacy) and ResourceManager
                defaults.set(userName, forKey: "OurinUserName")
                resourceManager.username = userName
                sakuraEngine.envExpander.username = userName
                Log.info("[GhostManager] User name set to: \(userName)")

                // Notify YAYA of the name change via NOTIFY OnNameChanged
                EventBridge.shared.notify(.OnNameChanged, params: ["Reference0": userName])
            }
        }
    }
    
    // MARK: - Sound Playback
    
    /// Play a sound file from the ghost's sound directory
    private func playSound(filename: String) {
        guard !filename.isEmpty else { return }
        
        // Resolve sound file path relative to ghost directory
        let soundPath = ghostURL.appendingPathComponent("sound").appendingPathComponent(filename)
        
        // Check if file exists
        guard FileManager.default.fileExists(atPath: soundPath.path) else {
            Log.warning("[GhostManager] Sound file not found: \(soundPath.path)")
            return
        }
        
        // Play sound using NSSound
        DispatchQueue.global(qos: .userInitiated).async {
            if let sound = NSSound(contentsOf: soundPath, byReference: false) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.currentSounds.append(sound)
                    sound.play()
                    Log.debug("[GhostManager] Playing sound: \(filename)")
                }
            } else {
                Log.warning("[GhostManager] Failed to load sound: \(filename)")
            }
        }
    }
    
    /// Stop all currently playing sounds
    private func stopAllSounds() {
        for sound in currentSounds {
            if sound.isPlaying {
                sound.stop()
            }
        }
        currentSounds.removeAll()
        Log.debug("[GhostManager] Stopped all sounds")
    }
    
    // MARK: - URL and Email Handling
    
    /// Open a URL in the default browser
    private func openURL(_ urlString: String) {
        guard !urlString.isEmpty else {
            Log.warning("[GhostManager] Empty URL string")
            return
        }
        
        // Ensure URL has a scheme
        var finalURL = urlString
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            finalURL = "https://" + urlString
        }
        
        guard let url = URL(string: finalURL) else {
            Log.warning("[GhostManager] Invalid URL: \(urlString)")
            return
        }
        
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
            Log.debug("[GhostManager] Opened URL: \(finalURL)")
        }
    }
    
    /// Open email client with the specified email address
    private func openEmail(_ emailAddress: String) {
        guard !emailAddress.isEmpty else {
            Log.warning("[GhostManager] Empty email address")
            return
        }
        
        // Create mailto URL
        let mailtoString = emailAddress.hasPrefix("mailto:") ? emailAddress : "mailto:\(emailAddress)"
        
        guard let url = URL(string: mailtoString) else {
            Log.warning("[GhostManager] Invalid email address: \(emailAddress)")
            return
        }
        
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
            Log.debug("[GhostManager] Opened email client for: \(emailAddress)")
        }
    }
    
    // MARK: - Ghost Booting via SSTP
    
    /// Boot another ghost using SSTP NOTIFY command
    private func bootOtherGhost(name: String? = nil) {
        // If no name provided, try to boot a random available ghost
        // In a real implementation, this would query FMO for available ghosts
        // For now, we'll send a generic SSTP NOTIFY to localhost
        
        let ghostName = name ?? "default"
        Log.debug("[GhostManager] Attempting to boot ghost: \(ghostName)")
        
        // Send SSTP NOTIFY to localhost
        sendSSTPNotify(event: "OnBoot", references: ["Reference0": ghostName])
    }
    
    /// Boot all ghosts by broadcasting SSTP
    private func bootAllGhosts() {
        Log.debug("[GhostManager] Broadcasting boot command to all ghosts")
        
        // Send broadcast SSTP NOTIFY
        sendSSTPNotify(event: "OnBootAll", references: [:])
    }
    
    /// Send an SSTP NOTIFY request
    private func sendSSTPNotify(event: String, references: [String: String]) {
        DispatchQueue.global(qos: .utility).async {
            // Construct SSTP NOTIFY request
            var request = "NOTIFY SSTP/1.1\r\n"
            request += "Sender: Ourin\r\n"
            request += "Event: \(event)\r\n"
            request += "Charset: UTF-8\r\n"
            
            // Add references
            for (key, value) in references.sorted(by: { $0.key < $1.key }) {
                request += "\(key): \(value)\r\n"
            }
            request += "\r\n"
            
            // Try to send to localhost:9801 (default SSTP port)
            self.sendSSTPToLocalhost(request: request)
        }
    }
    
    /// Send SSTP request to localhost
    private func sendSSTPToLocalhost(request: String) {
        let host = "127.0.0.1"
        let port = 9801
        
        var sock: Int32 = -1
        var hints = addrinfo()
        var result: UnsafeMutablePointer<addrinfo>?
        
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        
        let portString = String(port)
        guard getaddrinfo(host, portString, &hints, &result) == 0 else {
            Log.warning("[GhostManager] Failed to resolve SSTP host: \(host):\(port)")
            return
        }
        
        defer {
            if let result = result {
                freeaddrinfo(result)
            }
            if sock >= 0 {
                close(sock)
            }
        }
        
        guard let addr = result else {
            Log.warning("[GhostManager] No address info for SSTP")
            return
        }
        
        sock = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
        guard sock >= 0 else {
            Log.warning("[GhostManager] Failed to create socket for SSTP")
            return
        }
        
        // Set timeout
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        guard connect(sock, addr.pointee.ai_addr, addr.pointee.ai_addrlen) >= 0 else {
            Log.debug("[GhostManager] No SSTP server at \(host):\(port) - this is normal if no other ghosts are running")
            return
        }
        
        // Send request
        let data = request.data(using: .utf8) ?? Data()
        let sent = data.withUnsafeBytes { ptr in
            send(sock, ptr.baseAddress, data.count, 0)
        }
        
        if sent > 0 {
            Log.debug("[GhostManager] Sent SSTP request to \(host):\(port)")
        } else {
            Log.warning("[GhostManager] Failed to send SSTP request")
        }
    }
    
    // MARK: - Choice Command Support
    
    /// Handle choice command - \q[title,ID] or variants
    private func handleChoiceCommand(args: [String]) {
        guard args.count >= 2 else {
            Log.warning("[GhostManager] Invalid choice command: insufficient arguments")
            return
        }
        
        let title = args[0]
        let idOrScript = args[1]
        
        // Check if this is a script: format
        if idOrScript.hasPrefix("script:") {
            let script = String(idOrScript.dropFirst(7)) // Remove "script:" prefix
            Log.debug("[GhostManager] Choice '\(title)' will execute script: \(script)")
            // TODO: Store choice and script for display
        } else {
            // Event ID format
            let eventID = idOrScript
            let references = Array(args.dropFirst(2))
            Log.debug("[GhostManager] Choice '\(title)' will trigger event: \(eventID) with refs: \(references)")
            // TODO: Store choice and event for display
        }
    }
    
    // MARK: - Balloon Image Display
    
    /// Handle balloon image display - \_b[filepath,x,y,...] or \_b[filepath,inline,...]
    private func handleBalloonImage(args: [String]) {
        guard !args.isEmpty else {
            Log.warning("[GhostManager] Invalid balloon image command: no filepath")
            return
        }
        
        let filepath = args[0]
        
        // Check for inline mode
        if args.count >= 2 && args[1].lowercased() == "inline" {
            Log.debug("[GhostManager] Balloon inline image: \(filepath)")
            // TODO: Load and display inline image in balloon
            // Parse additional options (opaque, --option=value, etc.)
            let options = Array(args.dropFirst(2))
            for option in options {
                if option.lowercased() == "opaque" {
                    Log.debug("[GhostManager]   - Opaque mode")
                } else if option.hasPrefix("--") {
                    Log.debug("[GhostManager]   - Option: \(option)")
                }
            }
        } else if args.count >= 3 {
            // Positioned mode: filepath,x,y[,options...]
            if let x = Int(args[1]), let y = Int(args[2]) {
                Log.debug("[GhostManager] Balloon positioned image: \(filepath) at (\(x), \(y))")
                // TODO: Load and display image at specified position
                let options = Array(args.dropFirst(3))
                for option in options {
                    if option.lowercased() == "opaque" {
                        Log.debug("[GhostManager]   - Opaque mode")
                    } else if option.hasPrefix("--") {
                        Log.debug("[GhostManager]   - Option: \(option)")
                    }
                }
            }
        }
    }
    
    // MARK: - Surface Compositing
    
    /// Handle surface overlay/compositing - \![anim,add,overlay,ID]
    private func handleSurfaceOverlay(surfaceID: Int) {
        Log.debug("[GhostManager] Adding surface overlay: \(surfaceID)")
        
        // Load the surface image from the shell directory
        guard let shellPath = loadShellPath() else {
            Log.warning("[GhostManager] Cannot add overlay - shell path not found")
            return
        }
        
        // Surface files are named surface<ID>.png
        let surfaceFileName = "surface\(surfaceID).png"
        let surfacePath = shellPath.appendingPathComponent(surfaceFileName)
        
        guard FileManager.default.fileExists(atPath: surfacePath.path) else {
            Log.warning("[GhostManager] Surface file not found: \(surfacePath.path)")
            return
        }
        
        guard let image = NSImage(contentsOf: surfacePath) else {
            Log.warning("[GhostManager] Failed to load surface image: \(surfaceFileName)")
            return
        }
        
        // Add overlay to current scope's character view model
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            let overlay = CharacterViewModel.SurfaceOverlay(
                id: surfaceID,
                image: image,
                offset: .zero,
                alpha: 1.0
            )
            
            vm.overlays.append(overlay)
            Log.debug("[GhostManager] Added surface overlay \(surfaceID) to scope \(self.currentScope)")
        }
    }
    
    /// Get the current shell directory path
    private func loadShellPath() -> URL? {
        // Try to get shell path from ghost configuration
        // Default to "master" shell if not specified
        let shellName = "master" // TODO: Get from ghost config
        return ghostURL.appendingPathComponent("shell").appendingPathComponent(shellName)
    }
    
    /// Clear all overlays for the current scope
    private func clearSurfaceOverlays() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            vm.overlays.removeAll()
            Log.debug("[GhostManager] Cleared all surface overlays for scope \(self.currentScope)")
        }
    }
    
    /// Clear a specific overlay by ID
    private func clearSpecificOverlay(id: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            vm.overlays.removeAll { $0.id == id }
            Log.debug("[GhostManager] Cleared overlay \(id) for scope \(self.currentScope)")
        }
    }
    
    /// Offset a specific overlay
    private func offsetOverlay(id: Int, x: Double, y: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            if let index = vm.overlays.firstIndex(where: { $0.id == id }) {
                vm.overlays[index].offset = CGPoint(x: x, y: y)
                Log.debug("[GhostManager] Offset overlay \(id) by (\(x), \(y))")
            }
        }
    }
    
    // MARK: - Animation Engine Integration
    
    /// Setup animation engine callbacks
    private func setupAnimationCallbacks() {
        animationEngine.onAnimationUpdate = { [weak self] animID, pattern in
            guard let self = self, let pattern = pattern else { return }
            
            // Update surface overlay based on animation pattern
            if pattern.surfaceID >= 0 {
                self.handleSurfaceOverlay(surfaceID: pattern.surfaceID)
                
                // Apply offset if specified
                if pattern.x != 0 || pattern.y != 0 {
                    self.offsetOverlay(id: pattern.surfaceID, x: Double(pattern.x), y: Double(pattern.y))
                }
            }
        }
        
        animationEngine.onAnimationComplete = { [weak self] animID in
            guard let self = self else { return }
            
            // If we were waiting for this animation, resume playback
            if self.waitingForAnimation == animID {
                self.waitingForAnimation = nil
                if self.isPlaying {
                    self.processNextUnit()
                }
            }
        }
    }
    
    /// Play an animation
    private func playAnimation(id: Int, wait: Bool) {
        // Load animations from surfaces.txt if not already loaded
        loadAnimationsForCurrentSurface()
        
        animationEngine.playAnimation(id: id, wait: wait)
    }
    
    /// Play an animation and wait for completion
    private func playAnimationAndWait(id: Int) {
        waitingForAnimation = id
        playAnimation(id: id, wait: true)
        // Playback will resume when animation completes via callback
    }
    
    /// Load animations from surfaces.txt for the current surface
    private func loadAnimationsForCurrentSurface() {
        guard let shellPath = loadShellPath() else { return }
        
        let surfacesPath = shellPath.appendingPathComponent("surfaces.txt")
        guard FileManager.default.fileExists(atPath: surfacesPath.path) else {
            Log.warning("[GhostManager] surfaces.txt not found at: \(surfacesPath.path)")
            return
        }
        
        // Try to load with different encodings
        var content: String?
        if let utf8Content = try? String(contentsOf: surfacesPath, encoding: .utf8) {
            content = utf8Content
        } else if let shiftJISContent = try? String(contentsOf: surfacesPath, encoding: .shiftJIS) {
            content = shiftJISContent
        }
        
        guard let surfacesContent = content else {
            Log.warning("[GhostManager] Failed to read surfaces.txt")
            return
        }
        
        // Get current surface ID from character view model
        guard let vm = characterViewModels[currentScope] else { return }
        
        // Parse surface ID from image if available
        // For now, assume surface 0 - in production, track current surface ID
        let surfaceID = 0 // TODO: Track actual current surface ID
        
        animationEngine.loadAnimations(surfaceID: surfaceID, content: surfacesContent)
        Log.debug("[GhostManager] Loaded animations for surface \(surfaceID)")
    }
    
    // MARK: - System Commands Implementation
    
    /// Set desktop wallpaper
    private func setWallpaper(filename: String, options: String) {
        let wallpaperURL = ghostURL.appendingPathComponent(filename)
        
        guard FileManager.default.fileExists(atPath: wallpaperURL.path) else {
            Log.warning("[GhostManager] Wallpaper file not found: \(filename)")
            return
        }
        
        DispatchQueue.main.async {
            do {
                let workspace = NSWorkspace.shared
                if let screen = NSScreen.main {
                    try workspace.setDesktopImageURL(wallpaperURL, for: screen, options: [:])
                    Log.debug("[GhostManager] Set wallpaper: \(filename)")
                }
            } catch {
                Log.error("[GhostManager] Failed to set wallpaper: \(error)")
            }
        }
    }
    
    /// Set task tray (dock) icon
    private func setTaskTrayIcon(filename: String, text: String) {
        let iconURL = ghostURL.appendingPathComponent(filename)
        
        DispatchQueue.main.async {
            if let image = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = image
                Log.debug("[GhostManager] Set dock icon: \(filename)")
            } else {
                Log.warning("[GhostManager] Failed to load icon: \(filename)")
            }
        }
    }
    
    /// Set tray balloon (notification)
    private func setTrayBalloon(options: [String]) {
        // Parse options like title=..., message=..., icon=...
        var title = "Ourin"
        var message = ""
        var sound = true
        
        for option in options {
            let parts = option.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].lowercased()
                let value = String(parts[1])
                switch key {
                case "title": title = value
                case "message", "text": message = value
                case "sound": sound = value.lowercased() != "false"
                default: break
                }
            } else {
                // If no key, assume it's the message
                if message.isEmpty {
                    message = option
                }
            }
        }
        
        DispatchQueue.main.async {
            let notification = NSUserNotification()
            notification.title = title
            notification.informativeText = message
            if sound {
                notification.soundName = NSUserNotificationDefaultSoundName
            }
            NSUserNotificationCenter.default.deliver(notification)
            Log.debug("[GhostManager] Delivered notification: \(title) - \(message)")
        }
    }
    
    /// Set other ghost talk mode
    private func setOtherGhostTalk(mode: String) {
        // Store setting for whether to show other ghosts' conversations
        // Options: true, false, before, after
        Log.debug("[GhostManager] Set other ghost talk mode: \(mode)")
        // TODO: Store in user preferences and implement filtering
    }
    
    /// Set whether to observe other ghosts' surface changes
    private func setOtherSurfaceChange(enabled: Bool) {
        Log.debug("[GhostManager] Set other surface change observation: \(enabled)")
        // TODO: Subscribe/unsubscribe from SSTP surface change notifications
    }
    
    /// Execute SNTP time synchronization
    private func executeSNTP() {
        Log.debug("[GhostManager] Executing SNTP time synchronization")
        // TODO: Implement SNTP client to sync system time
        DispatchQueue.global(qos: .utility).async {
            // Would connect to NTP server and sync time
            // For now, just log the request
            Log.info("[GhostManager] SNTP sync requested (not yet implemented)")
        }
    }
    
    /// Execute headline (RSS feed check)
    private func executeHeadline(name: String) {
        Log.debug("[GhostManager] Executing headline check: \(name)")
        // TODO: Fetch RSS feed specified in headline configuration
        DispatchQueue.global(qos: .utility).async {
            // Would fetch RSS/Atom feed and trigger OnHeadline event
            Log.info("[GhostManager] Headline check for '\(name)' (not yet implemented)")
        }
    }
    
    /// Execute mail check (biff)
    private func executeBiff() {
        Log.debug("[GhostManager] Executing mail check (biff)")
        // TODO: Check configured mail accounts for new messages
        DispatchQueue.global(qos: .utility).async {
            // Would check POP3/IMAP servers and trigger OnBIFF event
            Log.info("[GhostManager] Mail check requested (not yet implemented)")
        }
    }
    
    /// Execute update check
    private func executeUpdate(target: String, options: [String]) {
        Log.debug("[GhostManager] Executing update check for: \(target)")
        
        DispatchQueue.global(qos: .utility).async {
            // Determine what to update
            switch target.lowercased() {
            case "self", "ghost":
                // Check for updates to this ghost
                self.checkGhostUpdate(options: options)
            case "platform", "baseware":
                // Check for updates to Ourin itself
                self.checkPlatformUpdate(options: options)
            case "other", "all":
                // Check for updates to all installed ghosts
                self.checkAllGhostsUpdate(options: options)
            default:
                Log.warning("[GhostManager] Unknown update target: \(target)")
            }
        }
    }
    
    /// Check for ghost updates
    private func checkGhostUpdate(options: [String]) {
        guard let updateURL = ghostConfig?.homeurl else {
            Log.info("[GhostManager] No update URL configured for ghost")
            return
        }
        
        Log.info("[GhostManager] Checking for ghost updates at: \(updateURL)")
        // TODO: Fetch update.txt/updates2.dau, compare versions, download if needed
        // Trigger OnUpdateReady or OnUpdateComplete events
    }
    
    /// Check for platform (Ourin) updates
    private func checkPlatformUpdate(options: [String]) {
        Log.info("[GhostManager] Checking for Ourin platform updates")
        // TODO: Check GitHub releases or update server for new Ourin versions
    }
    
    /// Check for updates to all ghosts
    private func checkAllGhostsUpdate(options: [String]) {
        Log.info("[GhostManager] Checking for updates to all installed ghosts")
        // TODO: Enumerate all ghosts and check their update URLs
    }
    
    /// Terminate this ghost (vanish)
    private func executeVanish() {
        Log.info("[GhostManager] Ghost terminating (vanish)")
        
        DispatchQueue.main.async {
            // Trigger OnVanished event first
            if let yaya = self.yayaAdapter {
                _ = yaya.request(id: "OnVanished", references: [:])
            }
            
            // Close all windows
            for window in self.characterWindows.values {
                window.close()
            }
            for window in self.balloonWindows.values {
                window.close()
            }
            
            // Clean up resources
            self.characterWindows.removeAll()
            self.balloonWindows.removeAll()
            self.stopPlayback()
            
            Log.debug("[GhostManager] Ghost vanished successfully")
        }
    }
    
    // MARK: - Window Position and Display Control
    
    /// Move window to back (behind other windows)
    private func moveWindowToBack(scope: Int) {
        Log.debug("[GhostManager] Moving scope \(scope) window to back")
        DispatchQueue.main.async {
            if let window = self.characterWindows[scope] {
                window.orderBack(nil)
                window.level = .normal
                Log.info("[GhostManager] Moved scope \(scope) to background")
            }
        }
    }
    
    /// Move window to front (above other windows)
    private func moveWindowToFront(scope: Int) {
        Log.debug("[GhostManager] Moving scope \(scope) window to front")
        DispatchQueue.main.async {
            if let window = self.characterWindows[scope] {
                window.orderFront(nil)
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
                Log.info("[GhostManager] Moved scope \(scope) to foreground")
            }
        }
    }
    
    /// Synchronous window move
    private func moveWindow(scope: Int, x: Int, y: Int, time: Int, method: String) {
        Log.debug("[GhostManager] Moving scope \(scope) to (\(x), \(y)) over \(time)ms with method '\(method)'")
        DispatchQueue.main.async {
            guard let window = self.characterWindows[scope] else {
                Log.warning("[GhostManager] No window found for scope \(scope)")
                return
            }
            
            let targetFrame = NSRect(x: CGFloat(x), y: CGFloat(y), width: window.frame.width, height: window.frame.height)
            
            if time > 0 {
                // Animated move
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = TimeInterval(time) / 1000.0
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    window.animator().setFrame(targetFrame, display: true)
                }, completionHandler: {
                    Log.debug("[GhostManager] Window move animation completed for scope \(scope)")
                })
            } else {
                // Instant move
                window.setFrame(targetFrame, display: true)
            }
            
            // Save new position
            self.resourceManager.setCharDefaultLeft(scope: scope, value: x)
            self.resourceManager.setCharDefaultTop(scope: scope, value: y)
        }
    }
    
    /// Asynchronous window move (non-blocking)
    private func moveWindowAsync(scope: Int, x: Int, y: Int, time: Int, method: String) {
        Log.debug("[GhostManager] Moving scope \(scope) asynchronously to (\(x), \(y))")
        // Move asynchronously without blocking script execution
        DispatchQueue.main.async {
            self.moveWindow(scope: scope, x: x, y: y, time: time, method: method)
        }
        // Don't wait for completion - script continues immediately
    }
    
    /// Set window position for specific scope
    private func setWindowPosition(x: Int, y: Int, scopeID: Int) {
        Log.debug("[GhostManager] Setting window position for scope \(scopeID) to (\(x), \(y))")
        DispatchQueue.main.async {
            guard let window = self.characterWindows[scopeID] else {
                Log.warning("[GhostManager] No window found for scope \(scopeID)")
                return
            }
            
            let newFrame = NSRect(x: CGFloat(x), y: CGFloat(y), width: window.frame.width, height: window.frame.height)
            window.setFrame(newFrame, display: true)
            
            // Lock window position (prevent user dragging)
            window.isMovable = false
            
            // Save position
            self.resourceManager.setCharDefaultLeft(scope: scopeID, value: x)
            self.resourceManager.setCharDefaultTop(scope: scopeID, value: y)
            
            Log.info("[GhostManager] Scope \(scopeID) position locked to (\(x), \(y))")
        }
    }
    
    /// Reset window position to default (allow user movement)
    private func resetWindowPosition() {
        Log.debug("[GhostManager] Resetting window positions")
        DispatchQueue.main.async {
            for (scope, window) in self.characterWindows {
                // Unlock window movement
                window.isMovable = true
                
                // Restore default position if available
                let savedX = self.resourceManager.getCharDefaultLeft(scope: scope)
                let savedY = self.resourceManager.getCharDefaultTop(scope: scope)
                
                if savedX != 0 || savedY != 0 {
                    let newFrame = NSRect(x: CGFloat(savedX), y: CGFloat(savedY), 
                                        width: window.frame.width, height: window.frame.height)
                    window.setFrame(newFrame, display: true)
                }
                
                Log.info("[GhostManager] Scope \(scope) position unlocked")
            }
        }
    }
    
    /// Set Z-order (window layering)
    private func setWindowZOrder(scopes: [Int]) {
        Log.debug("[GhostManager] Setting Z-order: \(scopes)")
        DispatchQueue.main.async {
            // Order windows from back to front based on scopes array
            for (index, scope) in scopes.enumerated() {
                if let window = self.characterWindows[scope] {
                    if index == scopes.count - 1 {
                        // Last window (topmost)
                        window.orderFront(nil)
                    } else {
                        // Order behind the next window
                        if let nextWindow = self.characterWindows[scopes[index + 1]] {
                            window.order(.below, relativeTo: nextWindow.windowNumber)
                        }
                    }
                }
            }
            Log.info("[GhostManager] Z-order set successfully")
        }
    }
    
    /// Reset Z-order to default
    private func resetWindowZOrder() {
        Log.debug("[GhostManager] Resetting Z-order to default")
        DispatchQueue.main.async {
            // Restore default floating window level for all
            for (scope, window) in self.characterWindows {
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
                window.orderFront(nil)
                Log.info("[GhostManager] Scope \(scope) Z-order reset")
            }
        }
    }
    
    /// Set sticky window (window follows another window)
    private var stickyWindowRelationships: [Int: Set<Int>] = [:] // Master scope -> follower scopes
    
    private func setStickyWindow(masterScope: Int, followerScopes: [Int]) {
        Log.debug("[GhostManager] Setting sticky windows: \(followerScopes) follow scope \(masterScope)")
        DispatchQueue.main.async {
            // Store relationships
            self.stickyWindowRelationships[masterScope] = Set(followerScopes)
            
            // Add observer for master window movement
            if let masterWindow = self.characterWindows[masterScope] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(self.stickyMasterWindowMoved(_:)),
                    name: NSWindow.didMoveNotification,
                    object: masterWindow
                )
                Log.info("[GhostManager] Sticky window relationships established")
            }
        }
    }
    
    @objc private func stickyMasterWindowMoved(_ notification: Notification) {
        guard let masterWindow = notification.object as? NSWindow,
              let masterScope = characterWindows.first(where: { $0.value == masterWindow })?.key,
              let followers = stickyWindowRelationships[masterScope] else {
            return
        }
        
        let masterFrame = masterWindow.frame
        
        // Move all follower windows relative to master
        for followerScope in followers {
            if let followerWindow = characterWindows[followerScope] {
                let offset: CGFloat = CGFloat((followerScope - masterScope) * 100) // Simple offset logic
                let newFrame = NSRect(
                    x: masterFrame.origin.x + offset,
                    y: masterFrame.origin.y,
                    width: followerWindow.frame.width,
                    height: followerWindow.frame.height
                )
                followerWindow.setFrame(newFrame, display: true)
            }
        }
    }
    
    /// Reset sticky window relationships
    private func resetStickyWindow() {
        Log.debug("[GhostManager] Resetting sticky window relationships")
        DispatchQueue.main.async {
            // Remove all observers
            for window in self.characterWindows.values {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didMoveNotification,
                    object: window
                )
            }
            
            // Clear relationships
            self.stickyWindowRelationships.removeAll()
            
            Log.info("[GhostManager] All sticky window relationships removed")
        }
    }
    
    /// Reset all window positions to default
    private func executeResetWindowPos() {
        Log.debug("[GhostManager] Executing window position reset")
        DispatchQueue.main.async {
            // Reset each window to its default/saved position
            for (scope, window) in self.characterWindows {
                // Get saved position or use default
                let savedX = self.resourceManager.getCharDefaultLeft(scope: scope)
                let savedY = self.resourceManager.getCharDefaultTop(scope: scope)
                
                if savedX != 0 || savedY != 0 {
                    let newFrame = NSRect(
                        x: CGFloat(savedX),
                        y: CGFloat(savedY),
                        width: window.frame.width,
                        height: window.frame.height
                    )
                    window.setFrame(newFrame, display: true)
                } else {
                    // Use default positions (scope-based)
                    self.positionWindowAtDefault(scope: scope, window: window)
                }
                
                // Unlock window
                window.isMovable = true
            }
            
            Log.info("[GhostManager] All window positions reset")
        }
    }
    
    /// Position window at default location based on scope
    private func positionWindowAtDefault(scope: Int, window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        
        let screenFrame = screen.visibleFrame
        let windowWidth = window.frame.width
        let windowHeight = window.frame.height
        
        // Default positions based on scope
        let x: CGFloat
        let y: CGFloat
        
        switch scope {
        case 0: // Master at right-center
            x = screenFrame.maxX - windowWidth - 100
            y = screenFrame.midY - windowHeight / 2
        case 1: // Partner at left-center
            x = screenFrame.minX + 100
            y = screenFrame.midY - windowHeight / 2
        default: // Others spaced out
            x = screenFrame.midX - windowWidth / 2 + CGFloat(scope * 50)
            y = screenFrame.midY - windowHeight / 2
        }
        
        let newFrame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        window.setFrame(newFrame, display: true)
    }
    
    // MARK: - Display Settings Commands
    
    /// Set window state (stayontop, minimize, etc.)
    private func setWindowState(state: String) {
        Log.debug("[GhostManager] Setting window state: \(state)")
        DispatchQueue.main.async {
            guard let window = self.characterWindows[self.currentScope] else { return }
            
            let stateLC = state.lowercased()
            if stateLC == "stayontop" {
                window.level = .floating
                Log.info("[GhostManager] Window set to stay on top")
            } else if stateLC == "!stayontop" {
                window.level = .normal
                Log.info("[GhostManager] Window stay on top disabled")
            } else if stateLC == "minimize" {
                window.miniaturize(nil)
                Log.info("[GhostManager] Window minimized")
            }
        }
    }
    
    // MARK: - Effect and Filter Commands
    
    /// Apply effect plugin
    private func applyEffect(plugin: String, speed: Double, params: [String], surfaceID: Int?) {
        Log.debug("[GhostManager] Applying effect: \(plugin), speed: \(speed), surface: \(surfaceID?.description ?? "current")")
        
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            // Store effect parameters
            let effect = EffectConfig(plugin: plugin, speed: speed, params: params, surfaceID: surfaceID)
            vm.activeEffects.append(effect)
            
            // TODO: Implement actual effect rendering through plugin system
            Log.info("[GhostManager] Effect '\(plugin)' applied (rendering not yet implemented)")
        }
    }
    
    /// Apply filter plugin
    private func applyFilter(plugin: String, time: Double, params: [String]) {
        Log.debug("[GhostManager] Applying filter: \(plugin), time: \(time)")
        
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            // Store filter parameters
            let filter = FilterConfig(plugin: plugin, time: time, params: params)
            vm.activeFilters.append(filter)
            
            // Schedule filter removal if time specified
            if time > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + time / 1000.0) {
                    vm.activeFilters.removeAll { $0.plugin == plugin }
                }
            }
            
            // TODO: Implement actual filter rendering through plugin system
            Log.info("[GhostManager] Filter '\(plugin)' applied (rendering not yet implemented)")
        }
    }
    
    /// Clear all filters
    private func clearFilters() {
        Log.debug("[GhostManager] Clearing all filters")
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            vm.activeFilters.removeAll()
            Log.info("[GhostManager] All filters cleared")
        }
    }
    
    // MARK: - Dressup Command
    
    /// Handle bind/dressup command
    private func handleBindDressup(category: String, part: String, value: String) {
        Log.debug("[GhostManager] Bind dressup: category=\(category), part=\(part), value=\(value)")
        
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            // Store dressup binding
            if vm.dressupBindings[category] == nil {
                vm.dressupBindings[category] = [:]
            }
            vm.dressupBindings[category]?[part] = value
            
            // TODO: Implement actual dressup rendering
            // This would load additional surface layers based on bindings
            Log.info("[GhostManager] Dressup binding set (rendering not yet implemented)")
        }
    }
    
    // MARK: - Text Animation Command
    
    /// Add text animation overlay
    private func addTextAnimation(x: Int, y: Int, width: Int, height: Int, text: String, 
                                 time: Int, r: Int, g: Int, b: Int, size: Int, font: String) {
        Log.debug("[GhostManager] Adding text animation: '\(text)' at (\(x),\(y))")
        
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            let textAnim = TextAnimationConfig(
                x: x, y: y, width: width, height: height,
                text: text, duration: time,
                r: r, g: g, b: b,
                fontSize: size, fontName: font
            )
            
            vm.textAnimations.append(textAnim)
            
            // Schedule removal after duration
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(time) / 1000.0) {
                vm.textAnimations.removeAll { $0.text == text && $0.x == x && $0.y == y }
            }
            
            // TODO: Implement actual text rendering overlay
            Log.info("[GhostManager] Text animation added (rendering not yet implemented)")
        }
    }
}

// MARK: - Supporting Structures

/// Effect configuration
struct EffectConfig {
    let plugin: String
    let speed: Double
    let params: [String]
    let surfaceID: Int?
}

/// Filter configuration
struct FilterConfig {
    let plugin: String
    let time: Double
    let params: [String]
}

/// Text animation configuration
struct TextAnimationConfig {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let text: String
    let duration: Int // milliseconds
    let r: Int
    let g: Int
    let b: Int
    let fontSize: Int
    let fontName: String
}

