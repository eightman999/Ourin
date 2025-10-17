import SwiftUI
import AppKit

// MARK: - ViewModels

/// ViewModel for the character view.
class CharacterViewModel: ObservableObject {
    @Published var image: NSImage?
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

    // Window management
    private var characterWindow: NSWindow?
    private var balloonWindow: NSWindow?

    // ViewModels
    private let characterViewModel = CharacterViewModel()
    private let balloonViewModel = BalloonViewModel()

    private var currentScope: Int = 0

    // MARK: - Initialization

    init(ghostURL: URL) {
        self.ghostURL = ghostURL
        super.init()
        self.sakuraEngine.delegate = self
    }

    deinit {
        shutdown()
    }

    // MARK: - Public API

    func start() {
        NSLog("[GhostManager] start() called for ghost at: \(ghostURL.path)")
        setupWindows()
        NSLog("[GhostManager] Windows setup complete")

        DispatchQueue.global(qos: .userInitiated).async {
            let ghostRoot = self.ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
            NSLog("[GhostManager] Ghost root: \(ghostRoot.path)")
            let fm = FileManager.default

            guard let contents = try? fm.contentsOfDirectory(at: ghostRoot, includingPropertiesForKeys: nil) else {
                NSLog("[GhostManager] Failed to read contents of \(ghostRoot.path)")
                return
            }

            let dics = contents.filter { $0.pathExtension.lowercased() == "dic" }.map { $0.lastPathComponent }
            NSLog("[GhostManager] Found \(dics.count) .dic files: \(dics)")

            guard let adapter = YayaAdapter() else {
                NSLog("[GhostManager] Failed to initialize YayaAdapter.")
                return
            }
            NSLog("[GhostManager] YayaAdapter initialized successfully")

            self.yayaAdapter = adapter

            guard adapter.load(ghostRoot: ghostRoot, dics: dics) else {
                NSLog("[GhostManager] Failed to load ghost with Yaya.")
                return
            }

            NSLog("[GhostManager] Ghost loaded, requesting OnBoot...")
            let res = adapter.request(method: "GET", id: "OnBoot")
            NSLog("[GhostManager] OnBoot response: ok=\(res?.ok ?? false), value=\(res?.value?.prefix(100) ?? "nil")")

            if let res = res, res.ok, let script = res.value {
                NSLog("[GhostManager] OnBoot script received: \(script.prefix(200))")
                DispatchQueue.main.async {
                    self.runScript(script)
                }
            } else {
                NSLog("[GhostManager] OnBoot script request failed or returned no script. Showing default surface.")
                // Even if OnBoot fails, we might want to show a default surface.
                DispatchQueue.main.async {
                    self.updateSurface(id: 0)
                }
            }
        }
    }

    func shutdown() {
        characterWindow?.orderOut(nil)
        balloonWindow?.orderOut(nil)
        characterWindow = nil
        balloonWindow = nil
        yayaAdapter?.unload()
        yayaAdapter = nil
    }

    // MARK: - Window Setup

    private func setupWindows() {
        NSLog("[GhostManager] Setting up windows")
        // Create Character Window
        let characterView = CharacterView(viewModel: self.characterViewModel)
        let hostingController = NSHostingController(rootView: characterView)

        let window = NSWindow(contentViewController: hostingController)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.styleMask = [.borderless]
        window.ignoresMouseEvents = true // Click-through
        window.level = .normal
        window.setFrame(.init(x: 200, y: 200, width: 300, height: 400), display: true)
        window.makeKeyAndOrderFront(nil)
        self.characterWindow = window
        NSLog("[GhostManager] Character window created at (200, 200, 300x400)")

        // Create Balloon Window
        let balloonView = BalloonView(viewModel: self.balloonViewModel)
        let balloonHostingController = NSHostingController(rootView: balloonView)

        let bWindow = NSWindow(contentViewController: balloonHostingController)
        bWindow.isOpaque = false
        bWindow.backgroundColor = .clear
        bWindow.styleMask = [.borderless]
        bWindow.hasShadow = false
        bWindow.level = .normal
        bWindow.setFrame(.init(x: 450, y: 300, width: 250, height: 200), display: true)
        bWindow.makeKeyAndOrderFront(nil)
        self.balloonWindow = bWindow
        NSLog("[GhostManager] Balloon window created at (450, 300, 250x200)")
    }

    // MARK: - Scripting

    func runScript(_ script: String) {
        NSLog("[GhostManager] runScript called with: \(script.prefix(200))")
        // Reset balloon text for new script
        balloonViewModel.text = ""
        sakuraEngine.run(script: script)
    }

    // MARK: - SakuraScriptEngineDelegate

    func sakuraEngine(_ engine: SakuraScriptEngine, didEmit token: SakuraScriptEngine.Token) {
        switch token {
        case .scope(let id):
            currentScope = id
            NSLog("[GhostManager] Switched to scope \(id)")

        case .surface(let id):
            NSLog("[GhostManager] Updating surface to id: \(id)")
            updateSurface(id: id)

        case .text(let text):
            balloonViewModel.text += text

        case .newline:
            balloonViewModel.text += "\n"

        case .end:
            // The view updates automatically. We could do cleanup here if needed.
            NSLog("[GhostManager] Script end. Final text: \(balloonViewModel.text)")

        case .animation, .command:
            // TODO: Handle other tokens
            NSLog("[GhostManager] Received unhandled token: \(token)")
        }
    }

    // MARK: - Helper Methods

    private func updateSurface(id: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = self.loadImage(surfaceId: id)
            DispatchQueue.main.async {
                self.characterViewModel.image = image
                if let image = image {
                    // Resize window to fit the new surface
                    self.characterWindow?.setContentSize(image.size)
                }
            }
        }
    }

    private func loadImage(surfaceId: Int) -> NSImage? {
        // In Ukagaka, scope 1 (u) surfaces are often prefixed with '1'
        // e.g., \u\s[10] -> surface1010.png
        let surfacePrefix = currentScope == 1 ? "1" : ""

        let shellURL = ghostURL.appendingPathComponent("shell/master")
        // TODO: This needs to handle shell.txt for surface definitions properly.
        // This is a simplified loader for now.
        let surfaceFilename = String(format: "surface%@%d.png", surfacePrefix, surfaceId)
        let imageURL = shellURL.appendingPathComponent(surfaceFilename)

        NSLog("[GhostManager] Loading image: \(imageURL.path)")
        guard FileManager.default.fileExists(atPath: imageURL.path) else {
            NSLog("[GhostManager] Image not found at path: \(imageURL.path)")
            return nil
        }

        let image = NSImage(contentsOf: imageURL)
        NSLog("[GhostManager] Image loaded successfully: \(image != nil)")
        return image
    }
}
