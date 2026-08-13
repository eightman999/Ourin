import Foundation
import AppKit

// MARK: - Dressup Binding Plan (UKADOC \![bind,...] / \![bind-noevent,...])

/// `\![bind,...]` / `\![bind-noevent,...]` の単一着せ替え操作計画。
/// 純粋な値オブジェクトで、コマンド解析・イベント可否・カテゴリ単位/トグル判定をテスト可能にする。
struct DressupBindPlan: Equatable {
    var category: String
    var part: String
    /// nil または空文字 = 現在の状態のトグル（ON/OFF 繰り返し）
    var value: String?
    /// false は `\![bind-noevent,...]`（イベントを発生させない）
    var emitsEvents: Bool

    var isCategoryWide: Bool { part.isEmpty }
    var isToggle: Bool { (value ?? "").isEmpty }
}

// MARK: - Dressup System

extension GhostManager {
    /// `\![bind,...]` / `\![bind-noevent,...]` の引数配列を bind 操作計画へ変換する。
    ///
    /// UKADOC 仕様（https://ssp.shillest.net/ukadoc/manual/list_sakura_script.html）:
    /// - `value` の 1 = 着衣（有効化）、0 = 脱衣（無効化）
    /// - パーツ名を空欄にするとカテゴリ単位の操作になる
    /// - 数値欄を空欄または省略すると ON/OFF の繰り返し（トグル）になる
    /// - `bind-noevent` は同操作だが OnDressupChanged/OnNotifyDressupInfo を発生させない
    ///
    /// args は `SakuraScriptEngine.parseArguments` が出力した形（先頭要素が "bind" または "bind-noevent"）。
    /// 複数タプル `\![bind,cat,part,val,cat2,part2,val2,...]` にも対応し、
    /// 末尾が「カテゴリ,パーツ」で終わる場合は値省略 = トグルとして扱う。
    static func parseDressupBindPlans(args: [String]) -> [DressupBindPlan] {
        guard let first = args.first?.lowercased() else { return [] }
        let emitsEvents: Bool
        switch first {
        case "bind":
            emitsEvents = true
        case "bind-noevent":
            emitsEvents = false
        default:
            return []
        }
        guard args.count >= 2 else { return [] }

        // 繰り返しタプル: \![bind,cat,part,val,cat2,part2,val2,...]
        let params = Array(args.dropFirst())
        var plans: [DressupBindPlan] = []
        var idx = 0
        while idx < params.count {
            guard idx + 1 < params.count else { break }
            let category = params[idx]
            let part = params[idx + 1]
            let hasValue = idx + 2 < params.count
            plans.append(DressupBindPlan(
                category: category,
                part: part,
                value: hasValue ? params[idx + 2] : nil,
                emitsEvents: emitsEvents
            ))
            idx += hasValue ? 3 : 2
        }
        return plans
    }
    func dressupOverlayPrefix(category: String, part: String) -> String {
        let normalizedCategory = category.replacingOccurrences(of: " ", with: "_")
        let normalizedPart = part.replacingOccurrences(of: " ", with: "_")
        return "dressup_\(normalizedCategory)_\(normalizedPart)_"
    }

    /// Parse individual dressup configuration file
    private func parseDressupConfigFile(filePath: URL, category: String) -> DressupConfig? {
        guard let content = try? String(contentsOf: filePath, encoding: .utf8) else {
            // Try Shift-JIS fallback
            guard let sjisContent = try? String(contentsOf: filePath, encoding: .shiftJIS) else {
                Log.info("[GhostManager] Failed to read dressup config: \(filePath.path)")
                return nil
            }
            return parseDressupContent(content: sjisContent, category: category)
        }

        return parseDressupContent(content: content, category: category)
    }

    /// Parse dressup configuration content
    private func parseDressupContent(content: String, category: String) -> DressupConfig {
        var parts: [DressupPartBinding] = []

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("//") else { continue }

            // Parse format: partName,surfaceID,x,y,overlay
            let components = trimmedLine.split(separator: ",", maxSplits: 4)
            if components.count >= 3 {
                let partName = String(components[0]).trimmingCharacters(in: .whitespaces)
                let surfaceID = Int(components[1]) ?? 0
                let x = Int(components[2]) ?? 0
                let y = components.count >= 4 ? Int(components[3]) ?? 0 : 0
                let overlay = components.count >= 5 ? String(components[4]).lowercased() == "true" : true

                parts.append(DressupPartBinding(
                    partName: partName,
                    surfaceID: surfaceID,
                    x: x,
                    y: y,
                    overlay: overlay
                ))
            }
        }

        return DressupConfig(category: category, parts: parts)
    }

    /// Apply dressup configuration for a category
    func applyDressup(category: String, part: String, value: String, scope: Int? = nil) {
        let targetScope = scope ?? currentScope
        guard let config = dressupConfigurations.first(where: { $0.category == category }) else {
            Log.info("[GhostManager] No dressup config found for category: \(category)")
            return
        }

        guard let binding = config.parts.first(where: { $0.partName == part }) else {
            Log.info("[GhostManager] No binding found for part: \(part) in category: \(category)")
            return
        }

        // Apply dressup binding
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[targetScope] else { return }

            // UKADOC: bind+runonce の最終フレームは dressup 変更で無効になる。
            self.clearPersistentSerikoOverlays(scope: targetScope)

            // Load dressup part image
            if let shellPath = self.loadShellPath() {
                let imagePath = shellPath.appendingPathComponent("surface\(binding.surfaceID).png")
                if let image = NSImage(contentsOf: imagePath) {
                    // Remove existing overlays with same part name
                    let prefix = self.dressupOverlayPrefix(category: category, part: part)
                    vm.overlays.removeAll { $0.id.hasPrefix(prefix) }

                    // Add new overlay
                    let overlay = SurfaceOverlay(
                        id: "\(prefix)\(UUID().uuidString)",
                        image: image,
                        offset: CGPoint(x: Double(binding.x), y: Double(binding.y)),
                        alpha: 1.0,
                        zOrder: 200,
                        insertionOrder: (vm.overlays.map(\.insertionOrder).max() ?? -1) + 1
                    )
                    vm.overlays.append(overlay)

                    Log.debug("[GhostManager] Applied dressup: \(category)/\(part) with surface \(binding.surfaceID)")
                }
            }
        }
    }

    /// bind 操作成功時の SHIORI イベント送出。UKADOC 規定の順序で
    /// OnDressupChanged を通知し、その後に OnNotifyDressupInfo を通知する。
    /// `\![bind-noevent,...]` では呼び出さない（イベント抑止）。
    func emitDressupEvents(
        category: String,
        part: String,
        value: String,
        scope: Int,
        source: String,
        changedUsesGET: Bool = true,
        infoUsesGET: Bool = false
    ) {
        notifyDressupChanged(
            category: category,
            part: part,
            value: value,
            scope: scope,
            source: source,
            requestResponse: changedUsesGET
        )
        notifyDressupInfo(scope: scope, requestResponse: infoUsesGET)
    }

    /// OnDressupChanged イベント送出。
    ///
    /// UKADOC: Reference0=character ID / Reference1=part / Reference2=enabled
    /// / Reference3=category / Reference4=source (script or user).
    /// @objc: 拡張メソッドでもテストスイートからオーバーライド可能にするため（イベント順序・抑止の検証用）。
    @objc func notifyDressupChanged(
        category: String,
        part: String,
        value: String,
        scope: Int,
        source: String,
        requestResponse: Bool = false
    ) {
        let params = EventReferenceTable.params(forEvent: "OnDressupChanged", refs: [
            "characterID": String(scope),
            "part": part,
            "value": value,
            "category": category,
            "source": source
        ])
        if requestResponse {
            EventBridge.shared.requestCustom("OnDressupChanged", params: params)
        } else {
            // OnDressupChanged の中間差分は NOTIFY。応答スクリプトは無視する。
            EventBridge.shared.notifyCustom("OnDressupChanged", params: params, ignoreResponseScript: true)
        }
    }

    /// Notify the current dressup configuration for all loaded character scopes.
    ///
    /// Each ReferenceN is a byte-value-1-delimited record:
    /// character ID, category, part, options, enabled flag, thumbnail path.
    /// `scope` identifies the changed scope for callers/tests; the payload itself
    /// includes all scopes so SHIORI can reconstruct the complete configuration.
    @objc func notifyDressupInfo(scope: Int, requestResponse: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let separator = "\u{1}"
            var params: [String: String] = [:]
            var index = 0
            let scopes = Set(self.characterViewModels.keys)
                .union(self.dressupBindGroupsByScope.keys)
                .sorted()

            for characterID in scopes {
                let vm = self.characterViewModels[characterID]
                var definitions: [(category: String, part: String, thumbnail: String?)] = []
                var seen: Set<String> = []

                for config in self.dressupConfigurations {
                    for binding in config.parts {
                        let key = "\(config.category)\u{1}\(binding.partName)"
                        guard seen.insert(key).inserted else { continue }
                        let thumbnail = self.dressupBindGroupsByScope[characterID]?.values
                            .first(where: { $0.category == config.category && $0.part == binding.partName })?.thumbnail
                        definitions.append((config.category, binding.partName, thumbnail))
                    }
                }

                // A bind group may exist even when the shell's dressup line is
                // absent. Include it so the notification still describes the
                // definition exposed by the shell menu.
                if let metas = self.dressupBindGroupsByScope[characterID]?.values {
                    for meta in metas {
                        let key = "\(meta.category)\u{1}\(meta.part)"
                        guard seen.insert(key).inserted else { continue }
                        definitions.append((meta.category, meta.part, meta.thumbnail))
                    }
                }

                for definition in definitions.sorted(by: {
                    $0.category == $1.category ? $0.part < $1.part : $0.category < $1.category
                }) {
                    let enabledValue = vm?.dressupBindings[definition.category]?[definition.part]
                    let enabled = enabledValue != nil && enabledValue?.lowercased() != "0"
                    let options = self.dressupBindOptionsByScope[characterID]?[definition.category]?.serialized ?? ""
                    let record = [
                        String(characterID),
                        definition.category,
                        definition.part,
                        options,
                        enabled ? "1" : "0",
                        definition.thumbnail ?? ""
                    ].joined(separator: separator)
                    params["Reference\(index)"] = record
                    index += 1
                }
            }

            if requestResponse {
                EventBridge.shared.requestCustom("OnNotifyDressupInfo", params: params)
            } else {
                EventBridge.shared.notifyCustom("OnNotifyDressupInfo", params: params, ignoreResponseScript: true)
            }
            Log.debug("[GhostManager] Notified dressup info for scope \(scope): \(params)")
        }
    }

    /// Compatibility convenience for callers that do not have an explicit scope.
    @objc func notifyDressupInfo() {
        notifyDressupInfo(scope: currentScope)
    }

    /// Clear all dressup overlays
    func clearDressup() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            // UKADOC: bind+runonce の最終フレームは dressup 解除で無効になる。
            self.clearPersistentSerikoOverlays(scope: self.currentScope)

            vm.overlays.removeAll { $0.id.hasPrefix("dressup_") }
            Log.debug("[GhostManager] Cleared all dressup")
        }
    }

    func dressupMenuEntries(for scope: Int) -> [DressupBindGroupMeta] {
        guard let groups = dressupBindGroupsByScope[scope], !groups.isEmpty else {
            return []
        }

        let menuItems = dressupMenuItemsByScope[scope] ?? [:]
        if menuItems.isEmpty {
            return groups.values.sorted(by: { $0.bindGroupID < $1.bindGroupID })
        }

        var used: Set<Int> = []
        var ordered: [DressupBindGroupMeta] = []
        for (_, bindID) in menuItems.sorted(by: { $0.key < $1.key }) {
            if let item = groups[bindID] {
                ordered.append(item)
                used.insert(bindID)
            }
        }
        let remained = groups.values
            .filter { !used.contains($0.bindGroupID) }
            .sorted(by: { $0.bindGroupID < $1.bindGroupID })
        ordered.append(contentsOf: remained)
        return ordered
    }

    func isDressupBindGroupEnabled(scope: Int, bindGroupID: Int) -> Bool {
        guard let meta = dressupBindGroupsByScope[scope]?[bindGroupID],
              let vm = characterViewModels[scope] else {
            return false
        }
        return vm.dressupBindings[meta.category]?[meta.part] != nil
    }

    func toggleDressupBindGroup(scope: Int, bindGroupID: Int) {
        guard let meta = dressupBindGroupsByScope[scope]?[bindGroupID] else { return }
        let currentlyEnabled = isDressupBindGroupEnabled(scope: scope, bindGroupID: bindGroupID)
        handleBindDressup(
            category: meta.category,
            part: meta.part,
            value: currentlyEnabled ? "false" : "true",
            scope: scope,
            source: "user",
            requestChangedResponse: true,
            requestInfoResponse: true
        )
    }

    func applyDefaultDressupBindings(for scope: Int) {
        let defaults = dressupMenuEntries(for: scope).filter(\.isDefault)
        for item in defaults {
            // 初期状態の反映では差分イベントを発火せず、起動後の
            // sendInitializationNotifies() から OnNotifyDressupInfo を1回送る。
            handleBindDressup(
                category: item.category,
                part: item.part,
                value: "true",
                scope: scope,
                emitEvents: false,
                emitInfo: false
            )
        }
    }

    func dressupThumbnailImage(for entry: DressupBindGroupMeta) -> NSImage? {
        guard let relativePath = entry.thumbnail, !relativePath.isEmpty,
              let shellPath = loadShellPath() else {
            return nil
        }
        let absolute = shellPath.appendingPathComponent(relativePath)
        return NSImage(contentsOf: absolute)
    }
}
