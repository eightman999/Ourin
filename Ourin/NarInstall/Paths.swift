// Ourin/NarInstall/Paths.swift
import Foundation

enum OurinPaths {
    static func baseDirectory() throws -> URL {
        let appSup = try FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true)
        let base = appSup.appendingPathComponent("Ourin", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
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
