import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications


// MARK: - Effects, Filters, Dressup, and Text Animations

extension GhostManager {
    private struct DressupChange {
        let part: String
        let value: String
    }

    // MARK: - Effect and Filter Commands
    
    /// Apply effect plugin
    func applyEffect(plugin: String, speed: Double, params: [String], surfaceID: Int?) {
        Log.debug("[GhostManager] Applying effect: \(plugin), speed: \(speed), surface: \(surfaceID?.description ?? "current")")
        
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            
            // Store effect parameters
            let effect = EffectConfig(plugin: plugin, speed: speed, params: params, surfaceID: surfaceID)
            vm.activeEffects.append(effect)
            Log.info("[GhostManager] Effect '\(plugin)' applied")
        }
    }
    
    /// Apply filter plugin
    func applyFilter(plugin: String, time: Double, params: [String]) {
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
            
            Log.info("[GhostManager] Filter '\(plugin)' applied")
        }
    }
    
    /// Clear all filters
    func clearFilters() {
        Log.debug("[GhostManager] Clearing all filters")
        DispatchQueue.main.async {
            guard let vm = self.characterViewModels[self.currentScope] else { return }
            vm.activeFilters.removeAll()
            Log.info("[GhostManager] All filters cleared")
        }
    }
    
    // MARK: - Dressup Command

    /// Handle bind/dressup command（UKADOC `\![bind,...]` / `\![bind-noevent,...]`）
    ///
    /// - `value`: "0"・"false"・"off"・"none"・"default" は脱衣（無効化）、それ以外は着衣（有効化）。
    ///   nil または空文字の場合は現在の状態をトグルする。
    /// - `part` が空文字の場合はカテゴリ単位で操作する。
    /// - `emitEvents` が false（`bind-noevent`）の場合は状態・描画のみ行い
    ///   OnDressupChanged / OnNotifyDressupInfo を送出しない。
    /// - `emitInfo` を false にすると OnDressupChanged だけを送出する。複数タプルの
    ///   コマンドでは最後に一度だけ OnNotifyDressupInfo を送出するために使う。
    func handleBindDressup(
        category: String,
        part: String,
        value: String?,
        scope: Int? = nil,
        emitEvents: Bool = true,
        emitInfo: Bool = true,
        source: String = "script",
        requestChangedResponse: Bool = false,
        requestInfoResponse: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        let targetScope = scope ?? currentScope
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowered = trimmedValue.lowercased()
        let wantsToggle = trimmedValue.isEmpty
        let disableRequested = lowered == "0" || lowered == "false" || lowered == "off" || lowered == "none" || lowered == "default"
        Log.debug("[GhostManager] Bind dressup: scope=\(targetScope), category=\(category), part=\(part), value=\(value ?? "<toggle>"), emitEvents=\(emitEvents)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[targetScope] else { return }

            // 値省略（トグル）時は現在の装着状態から目標値を決定する
            let shouldDisable: Bool
            let eventValue: String
            if wantsToggle {
                let enabled: Bool
                if part.isEmpty {
                    enabled = (vm.dressupBindings[category]?.isEmpty == false)
                } else {
                    enabled = vm.dressupBindings[category]?[part] != nil
                }
                shouldDisable = enabled
                eventValue = enabled ? "0" : "1"
            } else {
                shouldDisable = disableRequested
                eventValue = shouldDisable ? "0" : "1"
            }

            var changes: [DressupChange] = []
            let configuredParts = self.dressupConfigurations
                .first(where: { $0.category == category })?.parts
                .map(\.partName) ?? []
            let bindOptions = self.dressupBindOptionsByScope[targetScope]?[category]
            let requiresSelection = bindOptions?.mustSelect == true
            let allowsMultiple = bindOptions?.allowsMultiple == true
            let existingParts = vm.dressupBindings[category].map { Array($0.keys).sorted() } ?? []

            func disablePart(_ targetPart: String, eventValue: String = "0") {
                vm.dressupBindings[category]?[targetPart] = nil
                if vm.dressupBindings[category]?.isEmpty == true {
                    vm.dressupBindings[category] = nil
                }
                let prefix = self.dressupOverlayPrefix(category: category, part: targetPart)
                vm.overlays.removeAll { $0.id.hasPrefix(prefix) }
                changes.append(DressupChange(part: targetPart, value: eventValue))
            }

            func enablePart(_ targetPart: String, eventValue: String = "1") {
                if vm.dressupBindings[category] == nil {
                    vm.dressupBindings[category] = [:]
                }
                vm.dressupBindings[category]?[targetPart] = eventValue
                if !targetPart.isEmpty {
                    self.applyDressup(category: category, part: targetPart, value: eventValue, scope: targetScope)
                }
                changes.append(DressupChange(part: targetPart, value: eventValue))
            }

            if shouldDisable {
                if part.isEmpty {
                    if requiresSelection {
                        // `mustselect` はカテゴリを空にできない。複数選択状態が
                        // 既に存在する場合だけ、決定的に1つを残して他を外す。
                        for existingPart in existingParts.dropFirst() {
                            disablePart(existingPart, eventValue: eventValue)
                        }
                        if existingParts.count > 1 {
                            Log.debug("[GhostManager] Preserved one dressup part due to mustselect: \(category)")
                        }
                    } else {
                        vm.dressupBindings[category] = nil
                        let categoryPrefix = "dressup_\(category.replacingOccurrences(of: " ", with: "_"))_"
                        vm.overlays.removeAll { $0.id.hasPrefix(categoryPrefix) }

                        var affectedParts = configuredParts
                        for existingPart in existingParts where !affectedParts.contains(existingPart) {
                            affectedParts.append(existingPart)
                        }
                        if affectedParts.isEmpty {
                            changes.append(DressupChange(part: "", value: eventValue))
                        } else {
                            changes.append(contentsOf: affectedParts.map { DressupChange(part: $0, value: eventValue) })
                        }
                    }
                } else {
                    let isEnabled = vm.dressupBindings[category]?[part] != nil
                    if requiresSelection && isEnabled && existingParts.count <= 1 {
                        // `mustselect` では最後の有効パーツを脱衣できない。
                        Log.debug("[GhostManager] Refused to clear last mustselect dressup part: \(category)/\(part)")
                    } else {
                        disablePart(part, eventValue: eventValue)
                    }
                }
                Log.debug("[GhostManager] Disabled dressup: \(category)/\(part)")
            } else {
                if vm.dressupBindings[category] == nil {
                    vm.dressupBindings[category] = [:]
                }
                if part.isEmpty {
                    // `multiple` があるカテゴリだけ全パーツを同時に着衣する。
                    // 指定がないカテゴリは、現在の1パーツを維持し、未選択なら
                    // 設定順の先頭だけを選択する（UKADOCの既定値）。
                    let configParts = self.dressupConfigurations.first(where: { $0.category == category })?.parts ?? []
                    if allowsMultiple {
                        for binding in configParts {
                            enablePart(binding.partName, eventValue: eventValue)
                        }
                        if configParts.isEmpty {
                            // 設定なしカテゴリでも、従来どおり空パーツを状態として
                            // 保持し、後続のトグル判定を成立させる。
                            enablePart(part, eventValue: eventValue)
                        }
                    } else if let selectedPart = existingParts.first ?? configParts.first?.partName {
                        for existingPart in existingParts where existingPart != selectedPart {
                            disablePart(existingPart)
                        }
                        if vm.dressupBindings[category]?[selectedPart] == nil {
                            enablePart(selectedPart, eventValue: eventValue)
                        } else {
                            changes.append(DressupChange(part: selectedPart, value: eventValue))
                        }
                    } else {
                        // 設定が見つからない場合もカテゴリ自体を有効として記録する（トグル判定用）
                        enablePart(part, eventValue: eventValue)
                    }
                } else {
                    if !allowsMultiple {
                        for existingPart in existingParts where existingPart != part {
                            disablePart(existingPart)
                        }
                    }
                    enablePart(part, eventValue: eventValue)
                }
            }

            // 通常 bind は描画（applyDressup の main キュー処理）完了後に
            // OnDressupChanged → OnNotifyDressupInfo の順で送出する。
            // 複数タプルは completion から次の操作へ進めることで、変更通知を
            // すべて送出してから OnNotifyDressupInfo を1回だけ送出できる。
            if emitEvents || emitInfo || completion != nil {
                DispatchQueue.main.async {
                    if emitEvents {
                        if changes.count >= 100 {
                            // UKADOC: large dressup diffs are delivered through
                            // OnNotifyDressupInfo instead of a long Changed sequence.
                            Log.info("[GhostManager] Skipping OnDressupChanged for large dressup diff: \(changes.count) parts")
                        } else {
                            for (index, change) in changes.enumerated() {
                                self.notifyDressupChanged(
                                    category: category,
                                    part: change.part,
                                    value: change.value,
                                    scope: targetScope,
                                    source: source,
                                    requestResponse: requestChangedResponse && index == changes.count - 1
                                )
                            }
                        }
                        if emitInfo {
                            self.notifyDressupInfo(scope: targetScope, requestResponse: requestInfoResponse)
                        }
                    }
                    completion?()
                }
            }
        }
    }

    func executeBindCommand(args: [String]) {
        let plans = Self.parseDressupBindPlans(args: args)
        guard !plans.isEmpty else { return }
        let infoScope = currentScope

        func process(_ index: Int) {
            guard index < plans.count else {
                if plans.contains(where: { $0.emitsEvents }) {
                    // Sakura Script 起因の OnNotifyDressupInfo は NOTIFY。
                    notifyDressupInfo(scope: infoScope, requestResponse: false)
                }
                return
            }

            let plan = plans[index]
            let hasLaterEvent = plans.dropFirst(index + 1).contains(where: { $0.emitsEvents })
            handleBindDressup(
                category: plan.category,
                part: plan.part,
                value: plan.value,
                scope: infoScope,
                emitEvents: plan.emitsEvents,
                emitInfo: false,
                source: "script",
                requestChangedResponse: plan.emitsEvents && !hasLaterEvent,
                completion: { process(index + 1) }
            )
        }

        process(0)
    }
    
    // MARK: - Text Animation Command
    
    /// Add text animation overlay
    func addTextAnimation(x: Int, y: Int, width: Int, height: Int, text: String, 
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
            
            Log.info("[GhostManager] Text animation added")
        }
    }
    
    // MARK: - Balloon Switching
    
    /// Switch to a different balloon style
    func switchBalloon(to balloonID: Int, scope: Int) {
        guard let vm = characterViewModels[scope] else {
            Log.info("[GhostManager] Cannot switch balloon: no viewmodel for scope \(scope)")
            return
        }

        let apply = { [weak self] in
            guard let self else { return }
            vm.currentBalloonID = balloonID
            if let balloonVM = self.balloonViewModels[scope] {
                balloonVM.balloonID = balloonID
            }
            Log.info("[GhostManager] Switched to balloon ID \(balloonID) for scope \(scope)")
        }

        // Hide balloon if ID is -1
        if balloonID == -1 {
            let hide = { [weak self] in
                guard let self else { return }
                if let balloonWindow = self.balloonWindows[scope] {
                    balloonWindow.orderOut(nil)
                    Log.info("[GhostManager] Hiding balloon for scope \(scope)")
                }
            }
            if Thread.isMainThread { hide() } else { DispatchQueue.main.async(execute: hide) }
            return
        }

        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    /// 指定順で存在するバルーン画像を選び、最初の候補へ切り替える。
    /// 画像ローダーが未初期化の場合は、互換性のため先頭候補をそのまま使う。
    func switchBalloon(to candidates: [Int], scope: Int) {
        guard let first = candidates.first else { return }
        let selected = candidates.first { id in
            id == -1 || balloonImageLoader?.surfaceExists(index: id, type: "s") == true
        } ?? first
        switchBalloon(to: selected, scope: scope)
    }

    /// Switch balloon by numeric ID or balloon directory/name.
    @discardableResult
    func switchBalloon(named identifier: String, scope: Int, raiseEvent: Bool = false) -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.info("[GhostManager] change,balloon ignored: empty identifier")
            return false
        }

        let previousBalloon = balloonConfig?.name ?? ""
        if raiseEvent {
            EventBridge.shared.notify(.OnBalloonChange, refs: ["prevBalloonName": previousBalloon, "newBalloonName": trimmed, "phase": "changing"])
        }

        if let id = Int(trimmed) {
            switchBalloon(to: id, scope: scope)
            EventBridge.shared.notify(.OnBalloonChange, refs: ["prevBalloonName": previousBalloon, "newBalloonName": trimmed, "phase": "changed"])
            return true
        }

        let baseBalloonDir = ghostURL.appendingPathComponent("balloon", isDirectory: true)
        let namedBalloonDir = baseBalloonDir.appendingPathComponent(trimmed, isDirectory: true)
        let descriptCandidates = [
            namedBalloonDir.appendingPathComponent("descript.txt").path,
            baseBalloonDir.appendingPathComponent("descript.txt").path
        ]

        for path in descriptCandidates {
            guard let config = BalloonConfig.load(from: path) else { continue }
            let dirPath = (path as NSString).deletingLastPathComponent
            balloonConfig = config
            balloonImageLoader = BalloonImageLoader(balloonPath: dirPath)
            Log.info("[GhostManager] Switched balloon config to \(config.name)")
            EventBridge.shared.notify(.OnBalloonChange, refs: ["prevBalloonName": previousBalloon, "newBalloonName": config.name, "phase": "changed"])
            NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
            return true
        }

        Log.info("[GhostManager] Balloon not found: \(trimmed)")
        return false
    }

    // MARK: - Desktop Alignment
}
