// Ourin/NarInstall/ZipUtil.swift
import Foundation

enum ZipUtil {
    /// 解凍先は空ディレクトリであること。/usr/bin/ditto を利用（10.15+ 標準で利用可）
    static func extractZip(_ zipURL: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        task.arguments = ["-x", "-k", zipURL.path, dst.path]
        let pipe = Pipe()
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let err = String(data: data, encoding: .utf8) ?? "unknown"
            throw NarInstaller.Error.unzipFailed(err)
        }
    }

    /// Zip Slip 対策：dst 内へのコピー時に、正規化した最終パスが必ずターゲット配下であることを確認
    static func secureCopyTree(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        guard let enumerator = fm.enumerator(at: src, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: nil) else { return }
        let bannedNames = Set([".DS_Store", "__MACOSX"])
        for case let fileURL as URL in enumerator {
            let rel = fileURL.path.replacingOccurrences(of: src.path, with: "")
            let last = fileURL.lastPathComponent
            if bannedNames.contains(last) || rel.contains("__MACOSX") { continue }
            // シンボリックリンクは無視
            let vals = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if vals.isSymbolicLink == true { continue }

            let relative = fileURL.path.replacingOccurrences(of: src.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let target = dst.appendingPathComponent(relative, isDirectory: vals.isDirectory == true)
            let resolved = target.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(dst.path) else {
                throw NarInstaller.Error.zipSlipDetected(target.path)
            }
            if vals.isDirectory == true {
                try fm.createDirectory(at: resolved, withIntermediateDirectories: true)
            } else {
                try fm.createDirectory(at: resolved.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: resolved.path) { try fm.removeItem(at: resolved) }
                try fm.copyItem(at: fileURL, to: resolved)
            }
        }
    }
}
