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
    /// install.txt の type/directory/accept から設置先 URL を解決する。
    /// - shell      → ghost/<accept>/shell/<directory>   （対象ゴーストの配下にネスト）
    /// - supplement → ghost/<accept>/                     （対象ゴーストへ追加マージ。directory は空可）
    /// - その他      → <kind>/<directory>
    /// `accept` は対象ゴーストの解決済みディレクトリ名（descript.txt の name から逆引き済み）を渡す。
    static func installTarget(forType type: String, directory: String, accept: String? = nil) throws -> URL {
        let base = try baseDirectory()
        let trimmedAccept = accept?.trimmingCharacters(in: .whitespaces)

        switch type.lowercased() {
        case "ghost":
            return base.appendingPathComponent("ghost", isDirectory: true)
                       .appendingPathComponent(directory, isDirectory: true)
        case "balloon":
            return base.appendingPathComponent("balloon", isDirectory: true)
                       .appendingPathComponent(directory, isDirectory: true)
        case "plugin":
            return base.appendingPathComponent("plugin", isDirectory: true)
                       .appendingPathComponent(directory, isDirectory: true)
        case "headline":
            return base.appendingPathComponent("headline", isDirectory: true)
                       .appendingPathComponent(directory, isDirectory: true)
        case "package":
            return base.appendingPathComponent("package", isDirectory: true)
                       .appendingPathComponent(directory, isDirectory: true)
        case "shell":
            // 対象ゴースト配下の shell/<directory> へネストして設置する。
            guard let accept = trimmedAccept, !accept.isEmpty else {
                throw NarInstaller.Error.installTxtMissingKey("accept")
            }
            return base.appendingPathComponent("ghost", isDirectory: true)
                       .appendingPathComponent(accept, isDirectory: true)
                       .appendingPathComponent("shell", isDirectory: true)
                       .appendingPathComponent(directory, isDirectory: true)
        case "supplement":
            // 対象ゴーストのルートへ追加ファイルをマージする。directory は任意。
            guard let accept = trimmedAccept, !accept.isEmpty else {
                throw NarInstaller.Error.installTxtMissingKey("accept")
            }
            let ghostRoot = base.appendingPathComponent("ghost", isDirectory: true)
                                .appendingPathComponent(accept, isDirectory: true)
            if directory.isEmpty {
                return ghostRoot
            }
            return ghostRoot.appendingPathComponent(directory, isDirectory: true)
        default:
            throw NarInstaller.Error.unsupportedType(type)
        }
    }
}
