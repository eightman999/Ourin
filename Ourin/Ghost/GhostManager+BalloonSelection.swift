import AppKit
import CryptoKit
import Foundation
import SwiftUI

/// UserDefaults Data payload, schema 1. Paths are relative to either this ghost's
/// balloon directory or the shared balloon directory; absolute paths are not stored.
private struct StoredBalloonSelection: Codable {
    enum Location: String, Codable { case local, shared }
    let schemaVersion: Int
    let location: Location
    let relativePath: String
    let name: String
}

private func balloonRelativePath(_ directory: URL, inside root: URL) -> String? {
    // Resolve each ancestor for /var -> /private/var aliases without resolving
    // away a user-created symlink which is itself the selected balloon name.
    let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
    var current = directory.standardizedFileURL
    var components: [String] = []
    // Foundation's root URL deletion can vary with URL representation. Bound
    // traversal by the original lexical depth instead of relying on a fixed point.
    for _ in 0...current.pathComponents.count {
        if current.resolvingSymlinksInPath().path == rootPath { return components.joined(separator: "/") }
        guard !current.path.isEmpty, current.path != "/", !current.lastPathComponent.isEmpty else { return nil }
        let parent = current.deletingLastPathComponent()
        if parent.path == current.path { return nil }
        components.insert(current.lastPathComponent, at: 0)
        current = parent
    }
    return nil
}

extension GhostManager {
    /// Installed ghosts keep the same identity when the entire Ourin base moves.
    /// External ghosts use their canonical URL to avoid basename collisions.
    var balloonSelectionPreferenceKey: String {
        let installedRoot = (try? OurinPaths.baseDirectory())?.appendingPathComponent("ghost", isDirectory: true)
        let relative = installedRoot.flatMap { balloonRelativePath(ghostURL, inside: $0) }
        let identity = relative.map { "installed:" + $0 }
            ?? ("external:" + ghostURL.standardizedFileURL.resolvingSymlinksInPath().path)
        let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return "Ourin.BalloonSelection.v1." + digest
    }

    func rememberBalloonSelection(_ directory: URL) {
        let local = ghostURL.appendingPathComponent("balloon", isDirectory: true)
        let shared = try? OurinPaths.subdirectory("balloon")
        let location: StoredBalloonSelection.Location
        let relative: String
        if let path = balloonRelativePath(directory, inside: local) { location = .local; relative = path }
        else if let shared, let path = balloonRelativePath(directory, inside: shared) { location = .shared; relative = path }
        else { return }
        let record = StoredBalloonSelection(schemaVersion: 1, location: location,
                                            relativePath: relative, name: balloonConfig?.name ?? "")
        if let encoded = try? JSONEncoder().encode(record) {
            balloonSelectionDefaults.set(encoded, forKey: balloonSelectionPreferenceKey)
        }
    }

    private func restoreBalloonSelection(sharedDirectory: URL?) -> URL? {
        guard let data = balloonSelectionDefaults.data(forKey: balloonSelectionPreferenceKey), data.count <= 16384,
              let record = try? JSONDecoder().decode(StoredBalloonSelection.self, from: data), record.schemaVersion == 1 else { return nil }
        let path = record.relativePath.replacingOccurrences(of: "\\", with: "/")
        guard !path.hasPrefix("/"), !path.contains(":"), !path.contains("\0"),
              !path.split(separator: "/").contains("..") else { return nil }
        let root: URL
        switch record.location {
        case .local: root = ghostURL.appendingPathComponent("balloon", isDirectory: true)
        case .shared:
            guard let shared = sharedDirectory ?? (try? OurinPaths.subdirectory("balloon")) else { return nil }
            root = shared
        }
        let direct = path.isEmpty ? root : root.appendingPathComponent(path, isDirectory: true)
        if BalloonConfig.load(from: direct.appendingPathComponent("descript.txt").path) != nil { return direct }
        // A renamed shared directory may still be the user's chosen balloon.
        // Only a unique descriptor-name match in the same location is accepted.
        guard !record.name.isEmpty else { return nil }
        var candidates: [URL] = [root]
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
            for case let child as URL in enumerator {
                if candidates.count >= 4096 { break }
                guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if FileManager.default.fileExists(atPath: child.appendingPathComponent("descript.txt").path) {
                    candidates.append(child)
                    enumerator.skipDescendants()
                }
            }
        }
        let matches = candidates.filter {
            BalloonConfig.load(from: $0.appendingPathComponent("descript.txt").path)?.name.caseInsensitiveCompare(record.name) == .orderedSame
        }
        return matches.count == 1 ? matches.first : nil
    }

    /// Balloon paths in descript.txt are relative to the baseware's balloon directory.
    /// Also accept its explicit `balloon/` prefix and Windows path separators.
    func resolveBalloonDirectory(named identifier: String, sharedDirectory: URL? = nil) -> URL? {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\0"),
              !value.split(separator: "/").contains(".."),
              !value.contains(":") else { return nil }
        var parts = value.split(separator: "/").filter { $0 != "." }.map(String.init)
        if parts.first?.caseInsensitiveCompare("balloon") == .orderedSame { parts.removeFirst() }
        guard !parts.isEmpty else { return nil }
        let local = ghostURL.appendingPathComponent("balloon", isDirectory: true)
        let shared = sharedDirectory ?? (try? OurinPaths.subdirectory("balloon"))
        let roots = [local] + (shared.map { [$0] } ?? [])
        let fm = FileManager.default
        func valid(_ directory: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return fm.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue
                && BalloonConfig.load(from: directory.appendingPathComponent("descript.txt").path) != nil
        }
        func relative(_ components: [String], from root: URL) -> URL? {
            var current = root
            for part in components {
                guard let children = try? fm.contentsOfDirectory(at: current, includingPropertiesForKeys: nil) else { return nil }
                let matches = children.filter { $0.lastPathComponent.caseInsensitiveCompare(part) == .orderedSame }
                guard matches.count == 1, let found = matches.first else { return nil }
                current = found
            }
            return valid(current) ? current : nil
        }
        for root in roots {
            if let found = relative(parts, from: root) { return found }
        }
        // Display-name lookup is distinct from directory-name lookup. Never silently
        // select the local default when the requested name does not exist.
        if parts.count == 1 {
            for root in roots {
                let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
                let candidates = [root] + children.sorted { $0.lastPathComponent < $1.lastPathComponent }
                for candidate in candidates {
                    guard valid(candidate), let config = BalloonConfig.load(from: candidate.appendingPathComponent("descript.txt").path),
                          config.name.caseInsensitiveCompare(value) == .orderedSame else { continue }
                    return candidate
                }
            }
        }
        return nil
    }

    /// Defaults select only at startup; an explicit live choice remains authoritative.
    @discardableResult
    func loadStartupBalloon(sharedDirectory: URL? = nil) -> Bool {
        if let selected = explicitlySelectedBalloonDirectoryURL, activateBalloonDirectory(selected) { return true }
        if let selected = restoreBalloonSelection(sharedDirectory: sharedDirectory), activateBalloonDirectory(selected) {
            explicitlySelectedBalloonDirectoryURL = selected
            rememberBalloonSelection(selected)
            return true
        }
        // Preserve the published base/balloon/ghost-relative path resolution.
        // Explicit and saved user selections remain authoritative above it.
        if let config = ghostConfig,
           let base = sharedDirectory?.deletingLastPathComponent() ?? (try? OurinPaths.baseDirectory()),
           let directory = Self.configuredBalloonDirectory(for: config, ghostURL: ghostURL, baseDirectory: base),
           activateBalloonDirectory(directory) { return true }
        let settings = [ghostConfig?.recommendedBalloonPath, ghostConfig?.recommendedBalloon,
                        ghostConfig?.defaultBalloonPath, ghostConfig?.balloon]
        for identifier in settings.compactMap({ $0 }) {
            if let directory = resolveBalloonDirectory(named: identifier, sharedDirectory: sharedDirectory),
               activateBalloonDirectory(directory) { return true }
        }
        let local = ghostURL.appendingPathComponent("balloon", isDirectory: true)
        if activateBalloonDirectory(local) { return true }
        if let directory = resolveBalloonDirectory(named: "default", sharedDirectory: sharedDirectory),
           activateBalloonDirectory(directory) { return true }
        Log.info("[GhostManager] No configured balloon found for \(ghostURL.lastPathComponent)")
        return false
    }

    @discardableResult
    func activateBalloonDirectory(_ directory: URL) -> Bool {
        guard let config = BalloonConfig.load(from: directory.appendingPathComponent("descript.txt").path) else { return false }
        balloonConfig = config
        balloonImageLoader = BalloonImageLoader(balloonPath: directory.path)
        activeBalloonDirectoryURL = directory
        let refresh = {
            for (scope, vm) in self.balloonViewModels {
                vm.applyBalloonConfigAnchorDefaults(config: config)
                guard let controller = self.balloonWindows[scope]?.contentViewController as? NSHostingController<BalloonView> else { continue }
                controller.rootView = BalloonView(
                    viewModel: vm,
                    onClick: { [weak self] in self?.onBalloonClicked(fromScope: scope) },
                    onAnchorClick: { [weak self] anchor in self?.onBalloonAnchorClicked(anchor, fromScope: scope) },
                    onAnchorHover: { [weak self] anchor, hovering in self?.onBalloonAnchorHover(anchor, fromScope: scope, hovering: hovering) },
                    config: config, imageLoader: self.balloonImageLoader)
            }
        }
        if !balloonViewModels.isEmpty {
            if Thread.isMainThread { refresh() } else { DispatchQueue.main.sync(execute: refresh) }
        }
        Log.info("[GhostManager] Loaded balloon configuration: \(config.name) at \(directory.path)")
        return true
    }
}
