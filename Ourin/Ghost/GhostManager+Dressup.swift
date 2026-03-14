import Foundation
import AppKit

// MARK: - Dressup System

extension GhostManager {

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
    func applyDressup(category: String, part: String, value: String) {
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
            guard let vm = self.characterViewModels[self.currentScope] else { return }

            // Load dressup part image
            if let shellPath = self.loadShellPath() {
                let imagePath = shellPath.appendingPathComponent("surface\(binding.surfaceID).png")
                if let image = NSImage(contentsOf: imagePath) {
                    // Remove existing overlays with same part name
                    vm.overlays.removeAll { $0.id.hasPrefix("dressup_\(part)_") }

                    // Add new overlay
                    let overlay = SurfaceOverlay(
                        id: "dressup_\(part)_\(UUID().uuidString)",
                        image: image,
                        offset: CGPoint(x: Double(binding.x), y: Double(binding.y)),
                        alpha: 1.0
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
}
