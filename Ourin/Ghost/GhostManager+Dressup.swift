import Foundation
import AppKit

// MARK: - Dressup System

extension GhostManager {
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

                    // Trigger OnDressupChanged event
                    let params: [String: String] = [
                        "Reference0": category,
                        "Reference1": part,
                        "Reference2": value
                    ]
                    EventBridge.shared.notifyCustom("OnDressupChanged", params: params)
                }
            }
        }
    }

    /// Notify current dressup configuration
    func notifyDressupInfo() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            var params: [String: String] = [:]
            var index = 0

            for overlay in vm.overlays {
                if overlay.id.hasPrefix("dressup_") {
                    params["Reference\(index)"] = overlay.id
                    index += 1
                }
            }

            EventBridge.shared.notifyCustom("OnNotifyDressupInfo", params: params)
            Log.debug("[GhostManager] Notified dressup info: \(params)")
        }
    }

    /// Clear all dressup overlays
    func clearDressup() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let vm = self.characterViewModels[self.currentScope] else { return }

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
        handleBindDressup(category: meta.category, part: meta.part, value: currentlyEnabled ? "false" : "true", scope: scope)
    }

    func applyDefaultDressupBindings(for scope: Int) {
        let defaults = dressupMenuEntries(for: scope).filter(\.isDefault)
        for item in defaults {
            handleBindDressup(category: item.category, part: item.part, value: "true", scope: scope)
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
