import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - アンカークリックのイベントルーティング

/// アンカークリック時のイベントルーティング。
enum AnchorClickRouting: Equatable {
    /// `\_a[OnID,r0,r1,...]`: 引数は Reference0+ に配置して OnID イベントを直接発火する。
    case directEvent(id: String, references: [String])
    /// `\_a[ID,r2,r3,...]`: クリックされたテキスト（Reference0）・ID（Reference1）・引数（Reference2+）で OnAnchorSelectEx を発火する。
    case anchorSelect(id: String, clickedText: String, selectedReferences: [String])
}

/// UKADOC に基づき、アンカーの ID 先頭 "On" の有無でイベントルーティングを決定する純関数。
func routeAnchorClick(_ anchor: BalloonAnchorRange) -> AnchorClickRouting {
    if anchor.id.hasPrefix("On") {
        return .directEvent(id: anchor.id, references: anchor.references)
    }
    return .anchorSelect(id: anchor.id, clickedText: anchor.text, selectedReferences: anchor.references)
}

/// UKADOC の OnAnchorSelectEx / OnAnchorEnter / OnAnchorHover 共通の参照列を作る。
/// Reference0=表示ラベル、Reference1=ID、Reference2以降=アンカー引数。
func anchorEventParameters(for anchor: BalloonAnchorRange) -> [String: String] {
    var params: [String: String] = [
        "Reference0": anchor.text,
        "Reference1": anchor.id
    ]
    for (index, reference) in anchor.references.enumerated() {
        params["Reference\(index + 2)"] = reference
    }
    return params
}


// MARK: - Balloon Management and Positioning

extension GhostManager {
    // MARK: - Balloon helpers
    func getBalloonVM(for scope: Int) -> BalloonViewModel {
        if let vm = balloonViewModels[scope] { return vm }
        let vm = BalloonViewModel()
        // アンカー装飾の既定値をバルーン設定（descript.txt の anchor.pen.color / anchor.font.color）から取る。
        vm.applyBalloonConfigAnchorDefaults(config: balloonConfig)
        // Initialize balloon ID from character view model
        if let charVM = characterViewModels[scope] {
            vm.balloonID = charVM.currentBalloonID
            if ghostConfig?.balloonSyncScale == true {
                vm.scaleX = charVM.scaleX
                vm.scaleY = charVM.scaleY
            }
        }
        balloonViewModels[scope] = vm

        let view = BalloonView(
            viewModel: vm,
            onClick: { [weak self] in self?.onBalloonClicked(fromScope: scope) },
            onAnchorClick: { [weak self] anchor in self?.onBalloonAnchorClicked(anchor, fromScope: scope) },
            onAnchorHover: { [weak self] anchor, hovering in
                self?.onBalloonAnchorHover(anchor, fromScope: scope, hovering: hovering)
            },
            config: balloonConfig,
            imageLoader: balloonImageLoader
        )
        let hc = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hc)
        win.isOpaque = false
        win.backgroundColor = NSColor.clear
        win.styleMask = [NSWindow.StyleMask.borderless]
        win.hasShadow = false
        // Balloon windows: highest level, above everything (ghost + other apps)
        // Use popUpMenu (101) to ensure balloons are always on top
        win.level = NSWindow.Level.popUpMenu
        win.hidesOnDeactivate = false
        win.collectionBehavior = [NSWindow.CollectionBehavior.canJoinAllSpaces, NSWindow.CollectionBehavior.fullScreenAuxiliary]

        // Enable dragging the balloon window by its content
        win.isMovableByWindowBackground = true
        win.isMovable = true

        // Start with a reasonable initial size; it will resize based on content
        win.setFrame(.init(x: 450, y: 300, width: 250, height: 100), display: true)
        win.identifier = NSUserInterfaceItemIdentifier("GhostBalloonWindow_\(scope)")
        win.orderOut(nil)
        balloonWindows[scope] = win

        // Observe balloon window movement to save position
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(balloonWindowDidChangeFrame(_:)),
            name: NSWindow.didMoveNotification,
            object: win
        )

        // show/hide per visible balloon state and resize window to fit content.
        // 本文が空でも balloonmarker / balloonnum / onlinemode は表示対象になるため、
        // text publisher だけを監視すると強制オンラインマーカーがウィンドウへ出ない。
        // objectWillChange はこれら全ての @Published 状態をまとめて捕捉する。
        balloonTextCancellables[scope] = vm.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self, weak win, weak hc] _ in
                guard let self = self, let win = win, let hc = hc else { return }
                let hasBalloonNumber = vm.balloonNumberVisible
                    && (!vm.balloonNumberFileName.isEmpty
                        || !vm.balloonNumberCurrent.isEmpty
                        || !vm.balloonNumberMaximum.isEmpty)
                let hasOnlineMarker = vm.onlineModeActive
                    && self.balloonImageLoader?.loadOnlineMarker(
                        index: vm.onlineMarkerIndex,
                        filenamePrefix: self.balloonConfig?.onlineMarkerFilename ?? "online"
                    ) != nil
                let hasVisibleContent = !vm.text.isEmpty
                    || !vm.balloonImages.isEmpty
                    || !vm.balloonMarkerText.isEmpty
                    || hasBalloonNumber
                    || hasOnlineMarker
                if !hasVisibleContent {
                    if win.isVisible {
                        win.orderOut(nil)
                    }
                } else {
                    let wasVisible = win.isVisible

                    // Resize window to fit content
                    let fittingSize = hc.view.fittingSize
                    // 通常倍率では従来の上限を維持する。同期倍率が 100% を超える場合は
                    // 変換後のコンテンツをクリップしないよう、拡大後のサイズをそのまま採用する。
                    let scaledBeyondDefault = abs(vm.scaleX) > 1.0 || abs(vm.scaleY) > 1.0
                    let width = scaledBeyondDefault ? fittingSize.width : min(fittingSize.width, 400)
                    let height = scaledBeyondDefault ? fittingSize.height : min(fittingSize.height, 600)
                    let newSize = CGSize(width: max(250, width), height: max(50, height))

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

    func appendText(_ s: String) {
        // Always use current scope only - no parallel display for character dialogue
        // if syncEnabled {
        //     let targets = syncScopes.isEmpty ? [0,1] : Array(syncScopes)
        //     for sc in targets { getBalloonVM(for: sc).text += s }
        // } else {
            let vm = getBalloonVM(for: currentScope)
            // 途中に含まれる改行も lineAdvances と同期させる（`\n` タグ経由でない改行は送り倍率 1.0）。
            let parts = s.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if index > 0 { vm.appendNewline(advance: 1.0) }
                if !part.isEmpty { vm.text += String(part) }
            }
            scheduleBalloonTimeout(for: currentScope)
            triggerSerikoTalkAnimationIfEnabled()
        // }
    }

    /// `\n[half]` / `\n[パーセント]` / 通常 `\n` の改行を、垂直送り倍率つきで表示する。
    func appendNewline(advance: CGFloat) {
        let vm = getBalloonVM(for: currentScope)
        vm.appendNewline(advance: advance)
        scheduleBalloonTimeout(for: currentScope)
        triggerSerikoTalkAnimationIfEnabled()
    }

    func onBalloonClicked(fromScope: Int) {
        if let noclear = pendingClick {
            if noUserBreakModeActive {
                Log.debug("[GhostManager] Balloon click ignored: nouserbreakmode active")
                return
            }
            pendingClick = nil
            if !noclear {
                // UKADOC: OnBalloonBreak R0=中断時に表示中のスクリプト, R1=スコープ(本体0/相方1), R2=中断位置(文字数)
                //         OnBalloonClose R0=閉じる際に表示されていたスクリプト
                // 元の SakuraScript は保持していないため、表示中テキストを最良近似として用いる。
                let vm = getBalloonVM(for: fromScope)
                let displayedScript = vm.text
                vm.resetBalloonContent()
                EventBridge.shared.notify(.OnBalloonBreak, refs: [
                    "displayedScript": displayedScript,
                    "scope": String(fromScope),
                    "breakPosition": String(displayedScript.count)
                ])
                EventBridge.shared.notify(.OnBalloonClose, refs: ["displayedScript": displayedScript])
            }
            processNextUnit()
            return
        }
        // アンカー範囲外のバルーンクリックは無視する（アンカーは onBalloonAnchorClicked で処理）。
    }

    /// `\_a` 範囲アンカーがクリックされたときの処理。
    func onBalloonAnchorClicked(_ anchor: BalloonAnchorRange, fromScope: Int) {
        if noUserBreakModeActive {
            Log.debug("[GhostManager] Anchor click ignored: nouserbreakmode active")
            return
        }
        let pluginOrigin = anchor.pluginOrigin

        let vm = getBalloonVM(for: fromScope)
        vm.anchorActive = false
        // クリックされたアンカーを訪問済みとして記録し、以後 `anchorvisited*` 装飾で描画する。
        vm.markAnchorVisited(id: anchor.id, range: anchor.range)

        switch routeAnchorClick(anchor) {
        case .directEvent(let id, let references):
            var params: [String: String] = [:]
            for (index, ref) in references.enumerated() {
                params["Reference\(index)"] = ref
            }
            _ = EventBridge.shared.requestCustom(id, params: params, to: self)
            if pluginOrigin {
                forwardEventToPlugins(id: id, references: references)
            }
        case .anchorSelect(let id, let clickedText, let selectedReferences):
            // UKADOC: OnAnchorSelectEx は Reference0=クリックされたテキスト, Reference1=ID, Reference2+=引数。
            let selected = BalloonAnchorRange(
                id: id,
                references: selectedReferences,
                text: clickedText,
                range: anchor.range,
                pluginOrigin: anchor.pluginOrigin,
                visited: anchor.visited
            )
            let handledByEx = EventBridge.shared.requestCustom(
                "OnAnchorSelectEx",
                params: anchorEventParameters(for: selected),
                to: self
            )
            // UKADOC: OnAnchorSelect は Ex が空応答のときだけ発火する。
            if !handledByEx {
                _ = EventBridge.shared.requestCustom(
                    "OnAnchorSelect",
                    params: EventReferenceTable.params(forEvent: "OnAnchorSelect", refs: ["anchorID": id]),
                    to: self
                )
            }
            if pluginOrigin {
                forwardEventToPlugins(id: "OnAnchorSelect", references: [id])
                forwardEventToPlugins(id: "OnAnchorSelectEx", references: [clickedText, id] + selectedReferences)
            }
        }
    }

    /// 実際のアンカー文字列へポインタが入った／外れたときのイベントを発火する。
    /// スクリプトの `\_a` 開始時はまだ表示テキストが確定していないため、ここでは発火しない。
    func onBalloonAnchorHover(_ anchor: BalloonAnchorRange, fromScope scope: Int, hovering: Bool) {
        let timerKey = "anchor-hover-\(scope)"
        let key = "\(anchor.id)|\(anchor.range.location)|\(anchor.range.length)"

        if hovering {
            if hoveredAnchorKeysByScope[scope] == key {
                return
            }

            localEventTimers[timerKey]?.invalidate()
            localEventTimers.removeValue(forKey: timerKey)
            if hoveredAnchorKeysByScope[scope] != nil {
                // SwiftUI の再構成で入退場順が入れ替わっても、前のアンカーを閉じる。
                _ = EventBridge.shared.requestCustom("OnAnchorEnter", params: [:], to: self)
            }
            hoveredAnchorKeysByScope[scope] = key

            _ = EventBridge.shared.requestCustom(
                "OnAnchorEnter",
                params: anchorEventParameters(for: anchor),
                to: self
            )

            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                guard let self, self.hoveredAnchorKeysByScope[scope] == key else { return }
                _ = EventBridge.shared.requestCustom(
                    "OnAnchorHover",
                    params: anchorEventParameters(for: anchor),
                    to: self
                )
                self.localEventTimers.removeValue(forKey: timerKey)
            }
            localEventTimers[timerKey] = timer
        } else {
            guard hoveredAnchorKeysByScope[scope] == key else { return }
            localEventTimers[timerKey]?.invalidate()
            localEventTimers.removeValue(forKey: timerKey)
            hoveredAnchorKeysByScope.removeValue(forKey: scope)
            // UKADOC: アンカーから外れた OnAnchorEnter は Reference なし。
            _ = EventBridge.shared.requestCustom("OnAnchorEnter", params: [:], to: self)
        }
    }

    private func scheduleBalloonTimeout(for scope: Int) {
        let key = "balloon-timeout-\(scope)"
        if let timer = localEventTimers[key] {
            timer.invalidate()
            localEventTimers.removeValue(forKey: key)
        }
        guard let vm = balloonViewModels[scope], vm.balloonTimeout > 0 else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: vm.balloonTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            let balloonVM = self.getBalloonVM(for: scope)
            let displayedScript = balloonVM.text
            balloonVM.resetBalloonContent()
            // UKADOC: OnBalloonTimeout R0=タイムアウト時に表示されていたスクリプト、R1=残り時間。
            // タイマーの発火時点では残り時間は 0 とする。
            EventBridge.shared.notify(.OnBalloonTimeout, refs: [
                "displayedScript": displayedScript,
                "remainingTime": "0"
            ])
            // UKADOC: OnBalloonClose R0=閉じる際に表示されていたスクリプト（表示中テキストで近似）
            EventBridge.shared.notify(.OnBalloonClose, refs: ["displayedScript": displayedScript])
            self.localEventTimers.removeValue(forKey: key)
        }
        localEventTimers[key] = timer
    }
    // MARK: - Balloon Positioning

    @objc func characterWindowDidChangeFrame(_ notification: Notification) {
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
                updateDisplayHandover(for: window, scope: scope)
            }
        }
    }

    @objc func balloonWindowDidChangeFrame(_ notification: Notification) {
        // Save balloon window positions when moved by user
        guard !isResettingBalloonPositions else { return }
        if let window = notification.object as? NSWindow,
           let identifier = window.identifier?.rawValue,
           identifier.hasPrefix("GhostBalloonWindow_") {
            let scopeStr = identifier.replacingOccurrences(of: "GhostBalloonWindow_", with: "")
            if let scope = Int(scopeStr) {
                let frame = window.frame
                resourceManager.setBalloonLeft(scope: scope, value: Int(frame.origin.x))
                resourceManager.setBalloonTop(scope: scope, value: Int(frame.origin.y))
                Log.debug("[GhostManager] Saved balloon \(scope) position: (\(Int(frame.origin.x)), \(Int(frame.origin.y)))")
            }
        }
    }

    func positionBalloonWindow() {
        let margin: CGFloat = 8
        let verticalOffset: CGFloat = 80 // Move balloon higher above character head

        // Position each balloon next to its corresponding character window
        for (scope, balloonWin) in balloonWindows {
            guard let charWin = characterWindows[scope] else { continue }
            let cFrame = charWin.frame

            var f = balloonWin.frame

            // Priority 1: User saved position (highest priority)
            if let savedX = resourceManager.getBalloonLeft(scope: scope),
               let savedY = resourceManager.getBalloonTop(scope: scope) {
                f.origin.x = CGFloat(savedX)
                f.origin.y = CGFloat(savedY)
                Log.debug("[GhostManager] Using saved balloon position for scope \(scope): (\(savedX), \(savedY))")
            }
            // Priority 2: YAYA script position (from SakuraScript \![set,balloondistance,...])
            // This is handled by SakuraScriptEngine commands
            // Priority 3: Default position relative to character (lowest priority)
            else {
                // Position balloon to the right of character for all scopes
                // This provides consistent positioning regardless of scope
                f.origin.x = cFrame.maxX + margin
                f.origin.y = cFrame.maxY - f.height + verticalOffset
            }

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

    /// `\![execute,resetballoonpos]` — 各バルーンの保存位置を消し、初期位置へ戻す。
    func resetBalloonPositions() {
        let reset = { [weak self] in
            guard let self else { return }
            self.isResettingBalloonPositions = true
            self.resourceManager.resetBalloonPositions()
            self.positionBalloonWindow()
            // NSWindow.didMoveNotification が次の run loop で届く場合も、
            // その移動をユーザー操作として永続化しない。
            DispatchQueue.main.async { [weak self] in
                self?.isResettingBalloonPositions = false
            }
            Log.info("[GhostManager] All balloon positions reset")
        }

        if Thread.isMainThread {
            reset()
        } else {
            DispatchQueue.main.async(execute: reset)
        }
    }

    // MARK: - Balloon Image Display
    
    /// Handle balloon image display - \_b[filepath,x,y,...] or \_b[filepath,inline,...]
    func handleBalloonImage(args: [String]) {
        guard !args.isEmpty else {
            Log.info("[GhostManager] Invalid balloon image command: no filepath")
            return
        }
        
        let filepath = args[0]
        
        // Parse options
        var isInline = false
        var x: CGFloat = 0
        var y: CGFloat = 0
        var isOpaque = false
        var useSelfAlpha = false
        var clipping: CGRect? = nil
        var isForeground = false
        var isFixed = false

        // Check for inline mode
        if args.count >= 2 && args[1].lowercased() == "inline" {
            isInline = true
            // Parse options after "inline"
            let options = Array(args.dropFirst(2))
            for option in options {
                parseBalloonImageOption(option, &isOpaque, &useSelfAlpha, &clipping, &isForeground, &isFixed)
            }
        } else if args.count >= 3 {
            // Positioned mode: filepath,x,y[,options...]
            if let xPos = Int(args[1]), let yPos = Int(args[2]) {
                x = CGFloat(xPos)
                y = CGFloat(yPos)
                // Parse options after x,y
                let options = Array(args.dropFirst(3))
                for option in options {
                    parseBalloonImageOption(option, &isOpaque, &useSelfAlpha, &clipping, &isForeground, &isFixed)
                }
            } else {
                Log.info("[GhostManager] Invalid balloon image coordinates: \(args[1]), \(args[2])")
                return
            }
        }

        // Load image
        let image = loadBalloonImage(filepath: filepath, isOpaque: isOpaque, useSelfAlpha: useSelfAlpha)

        DispatchQueue.main.async {
            // スコープ切替直後など、バルーンウィンドウがまだ遅延生成されていない
            // 場合でも \_b の画像を捨てず、通常の表示経路と同じVMを生成する。
            let vm = self.getBalloonVM(for: self.currentScope)
            let inlineTextOffset: Int?
            if isInline, image != nil {
                inlineTextOffset = vm.appendInlineImagePlaceholder()
            } else {
                inlineTextOffset = nil
            }

            let balloonImage = BalloonViewModel.BalloonImage(
                filepath: filepath,
                x: x,
                y: y,
                isInline: isInline,
                isOpaque: isOpaque,
                useSelfAlpha: useSelfAlpha,
                clipping: clipping,
                isForeground: isForeground,
                isFixed: isFixed,
                inlineTextOffset: inlineTextOffset,
                image: image
            )
            
            if isInline {
                // 文字内配置の本実装は後続のリッチテキスト作業で扱うが、画像自体は
                // 現在の描画経路へ登録して寿命・clear対象を統一する。
                Log.debug("[GhostManager] Inline image: \(filepath)")
            }
            
            vm.balloonImages.append(balloonImage)
            Log.debug("[GhostManager] Added balloon image: \(filepath) at (\(x), \(y)), inline: \(isInline)")
        }
    }
    
    /// Parse balloon image option
    private func parseBalloonImageOption(_ option: String, _ isOpaque: inout Bool, _ useSelfAlpha: inout Bool, _ clipping: inout CGRect?, _ isForeground: inout Bool, _ isFixed: inout Bool) {
        let opt = option.lowercased()
        if opt == "opaque" || opt == "--option=opaque" {
            isOpaque = true
        } else if opt == "--option=use_self_alpha" {
            useSelfAlpha = true
        } else if opt.hasPrefix("--clipping=") {
            let parts = opt.replacingOccurrences(of: "--clipping=", with: "").split(separator: " ").map(String.init)
            if parts.count >= 4,
               let left = Double(parts[0]), let top = Double(parts[1]),
               let right = Double(parts[2]), let bottom = Double(parts[3]) {
                clipping = CGRect(x: left, y: top, width: right - left, height: bottom - top)
            }
        } else if opt == "--option=fixed" {
            // スクロール時に画像を動かさない（UKADOC \_b 仕様）。
            // 非指定時は既定でテキスト送り（\_l によるカーソル移動）に追従してスクロールする。
            isFixed = true
        } else if opt == "--option=background" {
            isForeground = false
        } else if opt == "--option=foreground" {
            isForeground = true
        }
    }
    
    /// Load balloon image from ghost directory
    private func loadBalloonImage(filepath: String, isOpaque: Bool, useSelfAlpha: Bool) -> NSImage? {
        // Build full path relative to ghost directory
        let imagePath: URL
        if filepath.hasPrefix("/") || filepath.contains(":/") {
            // Absolute path or URL
            imagePath = URL(string: filepath)!
        } else {
            // Relative path - prepend ghost path
            let masterPath = ghostURL.appendingPathComponent("ghost/master").path
            imagePath = URL(fileURLWithPath: masterPath).appendingPathComponent(filepath)
        }
        
        guard let image = NSImage(contentsOf: imagePath) else {
            Log.info("[GhostManager] Failed to load balloon image: \(filepath)")
            return nil
        }
        
        // Apply transparency if not opaque
        if !isOpaque {
            // For PNG with alpha channel, use self alpha if specified
            if useSelfAlpha {
                // The image already has alpha, so just use it as-is
            } else {
                // Default behavior (SSP互換): アルファチャンネルを持たない画像は
                // 左上(0,0)ピクセルの色を透過色として扱う（レガシー画像仕様）。
                if let rep = image.representations.first as? NSBitmapImageRep,
                   rep.pixelsWide > 0 && rep.pixelsHigh > 0,
                   !rep.hasAlpha,
                   let keyed = applyTopLeftPixelChromakey(to: image) {
                    return keyed
                }
            }
        }

        return image
    }

    /// アルファチャンネルを持たない古いバルーン画像向けに、左上(0,0)ピクセルの色を透明化する（SSP互換のレガシー透過仕様）。
    private func applyTopLeftPixelChromakey(to image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        // 左上(0,0)ピクセルの色を透過色として取得
        let keyRed = pixels[0]
        let keyGreen = pixels[1]
        let keyBlue = pixels[2]

        var changed = false
        for offset in stride(from: 0, to: pixels.count, by: bytesPerPixel) {
            let red = pixels[offset]
            let green = pixels[offset + 1]
            let blue = pixels[offset + 2]
            if red == keyRed && green == keyGreen && blue == keyBlue {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
                changed = true
            }
        }
        guard changed else { return nil }

        guard let outputContext = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let outputCG = outputContext.makeImage() else {
            return nil
        }

        return NSImage(cgImage: outputCG, size: image.size)
    }

    /// Handle cursor position move - \_l[x,y]
    func handleCursorMove(x: String, y: String) {
        let baseX = getBalloonVM(for: currentScope).cursorX
        let baseY = getBalloonVM(for: currentScope).cursorY
        let newX = parseCursorCoordinate(value: x, base: baseX)
        let newY = parseCursorCoordinate(value: y, base: baseY)
        
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            vm.cursorX = newX
            vm.cursorY = newY
            Log.debug("[GhostManager] Cursor moved to: (\(newX), \(newY))")
        }
    }

    /// Parse cursor coordinate value
    private func parseCursorCoordinate(value: String, base: CGFloat) -> CGFloat {
        let config = balloonConfig
        
        if value == "" || value == "@" {
            // Keep current value
            return base
        }
        
        // Check for relative (@) prefix
        var isRelative = false
        var cleanValue = value
        if value.hasPrefix("@") {
            isRelative = true
            cleanValue = String(value.dropFirst())
        }
        
        // Parse value
        if let numValue = Double(cleanValue) {
            // Numeric value in pixels
            if isRelative {
                return base + numValue
            }
            return numValue
        } else if cleanValue.hasSuffix("em") {
            // Font height units
            let emValue = Double(cleanValue.dropLast(2)) ?? 0
            let fontSize = CGFloat(config?.fontHeight ?? 12)
            let result = emValue * fontSize
            return isRelative ? base + result : result
        } else if cleanValue.hasSuffix("lh") {
            // Line height units
            let lhValue = Double(cleanValue.dropLast(2)) ?? 0
            let fontSize = CGFloat(config?.fontHeight ?? 12)
            // Assume line height = font height * 1.2 (typical)
            let lineHeight = fontSize * 1.2
            let result = lhValue * lineHeight
            return isRelative ? base + result : result
        } else if cleanValue.hasSuffix("%") {
            // Percentage of font height
            let pctValue = Double(cleanValue.dropLast()) ?? 0
            let fontSize = CGFloat(config?.fontHeight ?? 12)
            let result = (pctValue / 100.0) * fontSize
            return isRelative ? base + result : result
        }
        
        // Default: parse as pixel value
        return base
    }

    /// Handle balloon offset - \![set,balloonoffset,x,y]
    func handleBalloonOffset(x: String, y: String, isRelative: Bool = false) {
        let baseX = getBalloonVM(for: currentScope).balloonOffsetX
        let baseY = getBalloonVM(for: currentScope).balloonOffsetY
        
        let newX = parseBalloonCoordinate(value: x, base: baseX, isRelative: isRelative)
        let newY = parseBalloonCoordinate(value: y, base: baseY, isRelative: isRelative)
        
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            vm.balloonOffsetX = newX
            vm.balloonOffsetY = newY
            vm.useCustomOffset = true
            Log.debug("[GhostManager] Balloon offset set to: (\(newX), \(newY))")
            self.positionBalloonWindow()
        }
    }

    /// Parse balloon offset coordinate value
    private func parseBalloonCoordinate(value: String, base: CGFloat, isRelative: Bool) -> CGFloat {
        if value == "" || value == "@" {
            return base
        }
        
        var isValueRelative = false
        var cleanValue = value
        if value.hasPrefix("@") {
            isValueRelative = true
            cleanValue = String(value.dropFirst())
        }
        
        if let numValue = Double(cleanValue) {
            if isValueRelative || isRelative {
                return base + numValue
            }
            return numValue
        }
        
        return base
    }

    /// Handle balloon alignment - \![set,balloonalign,direction]
    func handleBalloonAlignment(direction: String) {
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            
            switch direction {
            case "left":
                vm.balloonAlignment = .left
            case "center":
                vm.balloonAlignment = .center
            case "top":
                vm.balloonAlignment = .top
            case "right":
                vm.balloonAlignment = .right
            case "bottom":
                vm.balloonAlignment = .bottom
            case "none":
                vm.balloonAlignment = .none
            default:
                Log.info("[GhostManager] Unknown balloon alignment: \(direction)")
            }
            
            Log.debug("[GhostManager] Balloon alignment set to: \(direction)")
            self.positionBalloonWindow()
        }
    }

    /// Parse font height value
    func parseFontHeight(_ value: String, baseFontSize: CGFloat) -> CGFloat {
        if value == "default" {
            return baseFontSize
        }
        
        if value.hasPrefix("+") {
            // Relative increase
            let deltaStr = String(value.dropFirst())
            if let delta = Double(deltaStr) {
                return baseFontSize + delta
            }
            return baseFontSize
        } else if value.hasPrefix("-") {
            // Relative decrease
            let deltaStr = String(value.dropFirst())
            if let delta = Double(deltaStr) {
                return baseFontSize - delta
            }
            return baseFontSize
        } else if value.hasSuffix("%") {
            // Percentage of default
            let pctStr = String(value.dropLast())
            if let pct = Double(pctStr) {
                return baseFontSize * (pct / 100.0)
            }
            return baseFontSize
        } else if let numValue = Double(value) {
            // Absolute pixel value
            return numValue
        }
        
        return baseFontSize
    }

    /// Parse color value
    func parseColor(from value: String, defaultValue: NSColor) -> NSColor {
        if value == "default" || value == "" {
            return defaultValue
        }
        
        // Check for hex color #RRGGBB or #RRGGBBAA
        if value.hasPrefix("#") {
            let hexValue = String(value.dropFirst())
            if hexValue.count == 6 {
                // #RRGGBB format
                let rStr = String(hexValue.prefix(2))
                let gStr = String(hexValue.dropFirst(2).prefix(2))
                let bStr = String(hexValue.dropFirst(4).prefix(2))
                if let r = UInt8(rStr, radix: 16),
                   let g = UInt8(gStr, radix: 16),
                   let b = UInt8(bStr, radix: 16) {
                    return NSColor(red: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: 1.0)
                }
            } else if hexValue.count == 8 {
                // #RRGGBBAA format
                let rStr = String(hexValue.prefix(2))
                let gStr = String(hexValue.dropFirst(2).prefix(2))
                let bStr = String(hexValue.dropFirst(4).prefix(2))
                let aStr = String(hexValue.dropFirst(6).prefix(2))
                if let r = UInt8(rStr, radix: 16),
                   let g = UInt8(gStr, radix: 16),
                   let b = UInt8(bStr, radix: 16),
                   let a = UInt8(aStr, radix: 16) {
                    return NSColor(red: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: CGFloat(a)/255.0)
                }
            }
            return defaultValue
        } else if value.hasPrefix("rgb(") || value.hasPrefix("r,g,b") || value.hasPrefix("r g b") {
            // RGB format: r,g,b or r g b
            let parts = value.components(separatedBy: CharacterSet(charactersIn: "rgb, ").inverted).joined(separator: ",").components(separatedBy: .whitespaces)
            if parts.count >= 3,
               let r = Double(parts[0]), let g = Double(parts[1]), let b = Double(parts[2]) {
                return NSColor(red: CGFloat(r)/255.0, green: CGFloat(g)/255.0, blue: CGFloat(b)/255.0, alpha: 1.0)
            }
            return defaultValue
        } else if value == "none" {
            return .clear
        } else {
            // Named colors
            let colorLower = value.lowercased()
            switch colorLower {
            case "red": return .red
            case "green": return .green
            case "blue": return .blue
            case "yellow": return .yellow
            case "cyan": return .cyan
            case "magenta": return .magenta
            case "black": return .black
            case "white": return .white
            case "gray": return .gray
            case "darkgray": return .darkGray
            default: return defaultValue
            }
        }
    }

    /// Parse color from command args (supports r,g,b positional triplets and scalar color spec).
    func parseColor(from values: [String], defaultValue: NSColor) -> NSColor {
        let normalized = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return defaultValue }
        if normalized.count >= 3,
           let r = Double(normalized[0]),
           let g = Double(normalized[1]),
           let b = Double(normalized[2]) {
            return NSColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
        }
        return parseColor(from: normalized.joined(separator: ","), defaultValue: defaultValue)
    }

    /// Parse tri-state value (0/1/true/false/default/disable)
    func parseTriState(_ value: String, currentValue: String) -> Bool {
        let v = value.lowercased()
        if v == "1" || v == "true" {
            return true
        } else if v == "0" || v == "false" {
            return false
        }
        // default/disable - return current value
        return currentValue == "1"
    }

    /// Reset font to default values
    func resetFontDefaults(vm: BalloonViewModel) {
        let config = balloonConfig
        vm.fontName = ""
        vm.fontSize = CGFloat(config?.fontHeight ?? 12)
        vm.fontWeight = .regular
        vm.fontItalic = false
        vm.fontUnderline = false
        vm.fontStrike = false
        vm.fontSubscript = false
        vm.fontSuperscript = false
        vm.fontColor = config?.fontColor ?? .textColor
        vm.shadowColor = .clear
        vm.shadowStyle = .none
        vm.outlineWidth = 0
        if let config {
            vm.cursorStyle = AnchorDecorationStyle(shape: config.cursorStyle) ?? .square
            vm.cursorBrushColor = config.cursorBrushColor
            vm.cursorPenColor = config.cursorPenColor
            vm.cursorFontColor = config.cursorFontColor
            vm.cursorMethod = AnchorRasterOperation(name: config.cursorBlendMethod) ?? .none
        } else {
            vm.cursorStyle = .square
            vm.cursorBrushColor = .clear
            vm.cursorPenColor = .linkColor
            vm.cursorFontColor = .textColor
            vm.cursorMethod = .none
        }
        vm.cursorNotSelectStyle = .none
        vm.cursorNotSelectBrushColor = .clear
        vm.cursorNotSelectPenColor = .linkColor
        vm.cursorNotSelectFontColor = .textColor
        vm.cursorNotSelectMethod = .none
    }

    /// Set font to disabled style
    func setFontDisabled(vm: BalloonViewModel) {
        // Use system disabled font styling
        vm.fontName = ""
        vm.fontSize = 12
        vm.fontWeight = .regular
        vm.fontItalic = false
        vm.fontUnderline = false
        vm.fontStrike = true
        vm.fontSubscript = false
        vm.fontSuperscript = false
        vm.fontColor = .gray
        vm.shadowColor = .clear
        vm.shadowStyle = .none
        vm.outlineWidth = 0
    }

    /// Clear text - \c[char,line,...]
    func handleTextClear(args: [String]) {
        guard let vm = balloonViewModels[currentScope] else { return }
        
        var charsToClear = 0
        var linesToClear = 0
        
        if args.isEmpty {
            // Clear all text
            vm.resetBalloonContent()
            Log.debug("[GhostManager] Cleared all text")
            return
        }
        
        // 位置引数形式（UKADOC 準拠）: \c[char,N] / \c[line,N] / \c[char,N,start] / \c[all]。
        // 旧 `char=N` / `line=N` 形式も後方互換で受理する。
        switch args.first {
        case "all":
            vm.resetBalloonContent()
            Log.debug("[GhostManager] Cleared all text")
            return
        case "char":
            if args.count >= 2, let count = Int(args[1]) { charsToClear = count }
        case "line":
            if args.count >= 2, let count = Int(args[1]) { linesToClear = count }
        default:
            for arg in args {
                if arg == "all" {
                    vm.resetBalloonContent()
                    Log.debug("[GhostManager] Cleared all text")
                    return
                }
                let parts = arg.split(separator: "=")
                if parts.count >= 2, let count = Int(parts[1]) {
                    if arg.hasPrefix("char") { charsToClear = count }
                    else if arg.hasPrefix("line") { linesToClear = count }
                }
            }
        }
        
        DispatchQueue.main.async {
            if charsToClear > 0 {
                vm.truncateSuffixCharacters(charsToClear)
                Log.debug("[GhostManager] Cleared \(charsToClear) chars")
            } else if linesToClear > 0 {
                vm.truncateSuffixLines(linesToClear)
                Log.debug("[GhostManager] Cleared \(linesToClear) lines")
            }
        }
    }

    /// Handle newline with custom height - \n[half] or \n[percent]
    func handleNewline(type: String) {
        let typeLower = type.lowercased()
        let apply = { [weak self] in
            guard let self else { return }
            let advance: CGFloat
            switch typeLower {
            case "half":
                advance = 0.5
                Log.debug("[GhostManager] Half-height newline")
            case let percent where typeLower.hasSuffix("%"):
                // Percentage-based newline - adjust line spacing
                advance = BalloonViewModel.newlineAdvance(for: percent)
                Log.debug("[GhostManager] \(percent) height newline")
            default:
                advance = BalloonViewModel.newlineAdvance(for: typeLower)
                Log.debug("[GhostManager] Newline advance: \(advance)")
            }
            self.appendNewline(advance: advance)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
    
    
}
