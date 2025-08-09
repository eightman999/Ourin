import Foundation

/// A structure to represent a found NAR package component.
struct NarPackageItem: Identifiable, Hashable {
    let id = UUID()
    let type: String
    let name: String
    let path: URL
}

/// Discovers installed NAR packages (ghosts, balloons, etc.) from the file system.
class NarRegistry {
    /// A shared singleton instance for easy access.
    static let shared = NarRegistry()

    private let fileManager = FileManager.default

    /// Returns the base directory where NAR packages are installed.
    /// - Throws: An error if the base directory cannot be determined.
    /// - Returns: The URL of the base directory.
    func baseDirectory() throws -> URL {
        return try OurinPaths.baseDirectory()
    }

    /// Fetches all installed items of a specific type (e.g., "ghost", "balloon").
    /// - Parameter type: The category of package to look for.
    /// - Returns: An array of `NarPackageItem` for the given type.
    func installedItems(ofType type: String) -> [NarPackageItem] {
        guard let base = try? baseDirectory() else {
            return []
        }

        let directory = base.appendingPathComponent(type, isDirectory: true)
        guard let children = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var items: [NarPackageItem] = []
        for childURL in children {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: childURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                items.append(NarPackageItem(type: type, name: childURL.lastPathComponent, path: childURL))
            }
        }
        return items
    }

    /// A convenience method to get the names of all installed ghosts.
    /// - Returns: An array of strings containing the names of the ghosts.
    func installedGhosts() -> [String] {
        return installedItems(ofType: "ghost").map { $0.name }
    }

    /// A convenience method to get the names of all installed shells for a given ghost.
    /// - Parameter ghostName: The name of the ghost to look for shells in.
    /// - Returns: An array of strings containing the names of the shells.
    func installedShells(for ghostName: String) -> [String] {
        // Assuming shells are installed within a ghost's directory structure, which might be incorrect.
        // For now, let's assume a global shell directory.
        return installedItems(ofType: "shell").map { $0.name }
    }

    /// A convenience method to get the names of all installed balloons.
    /// - Returns: An array of strings containing the names of the balloons.
    func installedBalloons() -> [String] {
        return installedItems(ofType: "balloon").map { $0.name }
    }
}
