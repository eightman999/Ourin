// Ourin/NarInstall/Paths.swift
import Foundation

enum OurinPaths {
    static func baseDirectory() throws -> URL {
        let fm = FileManager.default
        let appSup = try fm.url(for: .applicationSupportDirectory,
                                in: .userDomainMask,
                                appropriateFor: nil,
                                create: true)
        let base = appSup.appendingPathComponent("Ourin", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)

        // If ghost directory is empty, check the sandboxed container path for migrated data
        let ghostDir = base.appendingPathComponent("ghost", isDirectory: true)
        let hasGhosts = (try? fm.contentsOfDirectory(atPath: ghostDir.path))?.isEmpty == false
        if !hasGhosts {
            let home = fm.homeDirectoryForCurrentUser
            let containerBase = home
                .appendingPathComponent("Library/Containers/furin-lab.Ourin/Data/Library/Application Support/Ourin", isDirectory: true)
            let containerGhostDir = containerBase.appendingPathComponent("ghost", isDirectory: true)
            if (try? fm.contentsOfDirectory(atPath: containerGhostDir.path))?.isEmpty == false {
                NSLog("[OurinPaths] Found ghosts in sandbox container, using: \(containerBase.path)")
                return containerBase
            }
        }

        return base
    }
    static func installTarget(forType type: String, directory: String) throws -> URL {
        let base = try baseDirectory()
        let kind: String
        switch type.lowercased() {
        case "ghost":  kind = "ghost"
        case "balloon":kind = "balloon"
        case "shell":  kind = "shell"
        case "plugin": kind = "plugin"
        case "package":kind = "package"
        default: throw NarInstaller.Error.unsupportedType(type)
        }
        return base.appendingPathComponent(kind, isDirectory: true)
                   .appendingPathComponent(directory, isDirectory: true)
    }
}
