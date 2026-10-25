// Ourin/NarInstall/ZipUtil.swift
import Foundation

enum ZipUtil {
    /// Files and directories to ignore when creating NAR archives or extracting DAU files
    /// Per SSP/ukagaka specifications: https://ssp.shillest.net/ukadoc/manual/
    static let ignoredFiles: Set<String> = [
        "desktop.ini",     // Windows folder settings
        "thumbs.db",       // Windows thumbnail cache
        "folder.htt",      // Windows folder customization
        "mscreate.dir",    // Windows Media Player cache
        ".DS_Store",       // macOS folder metadata
        "_CATALOG.VIX"     // Windows catalog index
    ]

    static let ignoredDirectories: Set<String> = [
        "profile",         // SSP profile data (user-specific, should not be archived)
        "var",             // SSP variable data (runtime state)
        "__MACOSX",        // macOS resource fork metadata
        "XtraStuf.mac"     // Stuffit Expander metadata
    ]

    /// Check if a file should be ignored during NAR/DAU operations
    static func shouldIgnore(fileName: String) -> Bool {
        return ignoredFiles.contains(fileName)
    }

    /// Check if a directory should be ignored during NAR/DAU operations
    static func shouldIgnore(directoryName: String) -> Bool {
        return ignoredDirectories.contains(directoryName)
    }

    /// Check if a path contains any ignored directory components
    static func pathContainsIgnoredDirectory(_ path: String) -> Bool {
        let components = path.split(separator: "/").map(String.init)
        return components.contains { ignoredDirectories.contains($0) }
    }
    /// 解凍先は空ディレクトリであること。/usr/bin/ditto を利用（10.15+ 標準で利用可）。
    /// ditto は LZMA（zip の圧縮方式 14）などを展開できないため、失敗したら
    /// /usr/bin/bsdtar（libarchive）で展開し直す。bsdtar は `..` を含む項目を拒んで失敗し、
    /// 先頭の `/` は取り除く。設置先へは従来どおり secureCopyTree を通してコピーする。
    static func extractZip(_ zipURL: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)

        do {
            try runExtractor("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, dst.path])
        } catch let dittoError {
            // ditto が途中まで書き出したものを消してから展開し直す。
            for child in (try? fm.contentsOfDirectory(at: dst, includingPropertiesForKeys: nil)) ?? [] {
                try fm.removeItem(at: child)
            }
            do {
                try runExtractor("/usr/bin/bsdtar", arguments: ["-x", "-f", zipURL.path, "-C", dst.path])
            } catch NarInstaller.Error.unzipFailed(let bsdtarMessage) {
                guard case NarInstaller.Error.unzipFailed(let dittoMessage) = dittoError else { throw dittoError }
                throw NarInstaller.Error.unzipFailed("ditto: \(dittoMessage) / bsdtar: \(bsdtarMessage)")
            }
        }

        // Windows形式のパス区切り文字（バックスラッシュ）を含むファイルを正規化
        try normalizeWindowsPaths(at: dst)
    }

    private static func runExtractor(_ path: String, arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = FileHandle.nullDevice
        try task.run()
        // 警告が多いとパイプが詰まるので、終了を待つ前に読み切る。
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let err = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            throw NarInstaller.Error.unzipFailed(err.isEmpty ? "exit \(task.terminationStatus)" : err)
        }
    }

    /// Windows形式のパス（バックスラッシュ区切り）を含むファイルを、正しいディレクトリ構造に変換
    private static func normalizeWindowsPaths(at root: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsSubdirectoryDescendants]) else { return }

        var filesToMove: [(from: URL, to: URL)] = []

        // 最初のレベルのみをスキャンして、バックスラッシュを含むファイル/ディレクトリを検出
        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            if filename.contains("\\") {
                // バックスラッシュをスラッシュに置き換えてパスを正規化
                let normalizedPath = filename.replacingOccurrences(of: "\\", with: "/")
                let targetURL = root.appendingPathComponent(normalizedPath)
                filesToMove.append((from: fileURL, to: targetURL))
            }
        }

        // バックスラッシュを含むファイルを移動
        for (fromURL, toURL) in filesToMove {
            // ターゲットのディレクトリを作成
            let targetDir = toURL.deletingLastPathComponent()
            try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

            // ファイル/ディレクトリを移動
            if fm.fileExists(atPath: toURL.path) {
                try fm.removeItem(at: toURL)
            }
            try fm.moveItem(at: fromURL, to: toURL)
        }

        // 再帰的に全サブディレクトリを処理
        guard let fullEnumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        for case let dirURL as URL in fullEnumerator {
            let vals = try dirURL.resourceValues(forKeys: [.isDirectoryKey])
            if vals.isDirectory == true {
                try normalizeWindowsPaths(at: dirURL)
            }
        }
    }

    /// 展開した NAR の中身のルート。直下に install.txt が無く、隠しファイル（`.nar_icon` など）と
    /// `__MACOSX` を除くとフォルダ 1 つだけで、その中に install.txt があれば、そのフォルダをルートとする。
    /// フォルダごと圧縮した NAR（Taromati2.nar など）を、ninix-kagari と同じく 1 段上げて扱うため。
    static func packageRoot(in extracted: URL) -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: extracted.appendingPathComponent("install.txt").path) { return extracted }
        let entries = ((try? fm.contentsOfDirectory(at: extracted, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") && !shouldIgnore(directoryName: $0.lastPathComponent) }
        guard entries.count == 1,
              (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              fm.fileExists(atPath: entries[0].appendingPathComponent("install.txt").path) else {
            return extracted
        }
        return entries[0]
    }

    /// Zip Slip 対策：dst 内へのコピー時に、正規化した最終パスが必ずターゲット配下であることを確認
    static func secureCopyTree(from src: URL, to dst: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)
        guard let enumerator = fm.enumerator(at: src, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: nil) else { return }

        // enumerator の返す URL は /var → /private/var のように実体パスへ解決されることがあり、
        // 文字列置換による相対パス計算が壊れる（結果が <dst>/private/... へずれる）。
        // 基準側・列挙側の双方を resolvingSymlinksInPath で正規化してから比較する。
        let srcBase = src.resolvingSymlinksInPath().path
        let dstBase = dst.resolvingSymlinksInPath().path

        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent
            let resolvedFilePath = fileURL.resolvingSymlinksInPath().path
            guard isWithinRoot(resolvedFilePath, root: srcBase) else { continue }
            let relative = String(resolvedFilePath.dropFirst(srcBase.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // Skip ignored files
            if shouldIgnore(fileName: fileName) {
                continue
            }

            // Skip ignored directories and paths containing them
            if shouldIgnore(directoryName: fileName) || pathContainsIgnoredDirectory(relative) {
                continue
            }

            // シンボリックリンクは無視
            let vals = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if vals.isSymbolicLink == true { continue }

            let target = dst.appendingPathComponent(relative, isDirectory: vals.isDirectory == true)
            let resolved = target.resolvingSymlinksInPath()
            guard isWithinRoot(resolved.path, root: dstBase) else {
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

    private static func isWithinRoot(_ candidate: String, root: String) -> Bool {
        let normalizedRoot = root.hasSuffix("/") ? String(root.dropLast()) : root
        return candidate == normalizedRoot || candidate.hasPrefix(normalizedRoot + "/")
    }
}
