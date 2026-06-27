// Ourin/NarInstall/Paths.swift
import Foundation

enum OurinPaths {
    enum PathError: Error { case invalidComponent(String) }

    /// SSP 標準の公開サブフォルダ。基準フォルダ直下に必ず用意する。
    /// （`data/profile` は `data` のネスト。`withIntermediateDirectories` で同時生成される）
    static let standardSubfolders = [
        "ghost", "balloon", "plugin", "headline",
        "calendar", "data", "data/profile", "temp", "package", "saori"
    ]

    /// テスト専用の base override。テストコードから直接注入する場合に使う。
    /// 本番では常に nil。
    private static let testBaseOverrideKey = "OurinPaths.testBaseOverride"
    static var testBaseOverride: URL? {
        get {
            Thread.current.threadDictionary[testBaseOverrideKey] as? URL
        }
        set {
            if let newValue {
                Thread.current.threadDictionary[testBaseOverrideKey] = newValue
            } else {
                Thread.current.threadDictionary.removeObject(forKey: testBaseOverrideKey)
            }
        }
    }

    /// テスト/明示注入時の base を解決する。本番（override 無し・非XCTest）では nil。
    private static func resolveTestBase() -> URL? {
        if let override = testBaseOverride { return override }
        let env = ProcessInfo.processInfo.environment
        if let path = env["OURIN_TEST_BASE_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        // XCTest 実行中は ~/Documents への TCC ダイアログを避けるため一時ディレクトリへ隔離する。
        if env["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("OurinTestBase", isDirectory: true)
        }
        return nil
    }

    /// 基準フォルダを返す。本番は `~/Documents/Ourin`。
    /// - テスト/override 時はそちらを優先。
    /// - `~/Documents` が利用不可（TCC 拒否等）なら旧 `~/Library/Application Support/Ourin` へフォールバック。
    /// いずれの経路でも SSP 標準サブフォルダを冪等生成する。
    static func baseDirectory() throws -> URL {
        let fm = FileManager.default

        if let testBase = resolveTestBase() {
            try fm.createDirectory(at: testBase, withIntermediateDirectories: true)
            ensureSubfolders(testBase)
            return testBase
        }

        do {
            let docs = try fm.url(for: .documentDirectory,
                                  in: .userDomainMask,
                                  appropriateFor: nil,
                                  create: true)
            let base = docs.appendingPathComponent("Ourin", isDirectory: true)
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            ensureSubfolders(base)
            return base
        } catch {
            NSLog("[OurinPaths] Documents unavailable (\(error.localizedDescription)); falling back to Application Support")
            let appSup = try fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
            let base = appSup.appendingPathComponent("Ourin", isDirectory: true)
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            ensureSubfolders(base)
            return base
        }
    }

    /// SSP 標準サブフォルダをまとめて冪等生成する（best-effort、失敗してもログのみ）。
    static func ensureSubfolders(_ base: URL) {
        let fm = FileManager.default
        for sub in standardSubfolders {
            let url = base.appendingPathComponent(sub, isDirectory: true)
            do {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                NSLog("[OurinPaths] failed to create subfolder \(sub): \(error.localizedDescription)")
            }
        }
    }

    /// 基準フォルダ直下の既知サブフォルダを返す（存在保証）。
    /// パス逸脱防止のため `/`・`..`・先頭 `.` を含む名前は拒否する。
    static func subdirectory(_ name: String) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), !name.contains(".."), !name.hasPrefix(".") else {
            throw PathError.invalidComponent(name)
        }
        let url = try baseDirectory().appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// ゴースト別プロファイル置き場 `data/profile/<ghost>/` を返す（存在保証）。
    static func profileDirectory(for ghost: String) throws -> URL {
        guard !ghost.isEmpty, !ghost.contains("/"), !ghost.contains("..") else {
            throw PathError.invalidComponent(ghost)
        }
        let url = try baseDirectory()
            .appendingPathComponent("data/profile", isDirectory: true)
            .appendingPathComponent(ghost, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 旧データ（`~/Library/Application Support/Ourin` および旧サンドボックスコンテナ）を
    /// 新基準 `~/Documents/Ourin` へ一度だけ移行する。冪等・部分移行耐性あり。
    ///
    /// - `.migrated_v1` センチネルで一度きりを担保（全件成功 or 正常 skip のときのみ作成）。
    /// - エントリ単位で `moveItem`。dest 既存は「skip（Documents が正）」で正常扱い。
    /// - move 失敗が 1 件でもあればセンチネルを作らずログに残し、次回起動で再試行。
    /// - base が `~/Documents/Ourin` でない（フォールバック/テスト）場合は何もしない。
    static func migrateLegacyDataIfNeeded() {
        let fm = FileManager.default

        // テスト/override 時は移行しない。
        if resolveTestBase() != nil { return }

        guard let base = try? baseDirectory() else { return }

        // base が本番の Documents 配下でなければ（フォールバック等）移行しない。
        guard let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else {
            NSLog("[OurinPaths] Documents unavailable; skipping legacy migration")
            return
        }
        let expectedBase = docs.appendingPathComponent("Ourin", isDirectory: true)
        guard base.standardizedFileURL.path == expectedBase.standardizedFileURL.path else {
            NSLog("[OurinPaths] base not under Documents; skipping legacy migration")
            return
        }

        let sentinel = base.appendingPathComponent(".migrated_v1")
        if fm.fileExists(atPath: sentinel.path) { return }

        let home = fm.homeDirectoryForCurrentUser
        // App Support を先に（直近の現行データ）、次に旧サンドボックスコンテナ各所で欠けを補完。
        // - 旧コンテナ App Support: サンドボックス時代の保存先
        // - 旧コンテナ Documents/Ourin: サンドボックス有効時に本コードが作った基準（コンテナ内 Documents へリダイレクトされていた）
        let sources = [
            home.appendingPathComponent("Library/Application Support/Ourin", isDirectory: true),
            home.appendingPathComponent("Library/Containers/furin-lab.Ourin/Data/Library/Application Support/Ourin", isDirectory: true),
            home.appendingPathComponent("Library/Containers/furin-lab.Ourin/Data/Documents/Ourin", isDirectory: true)
        ]
        // 移行対象は公開リソースの各サブフォルダ。
        let subfolders = ["ghost", "balloon", "plugin", "headline", "calendar", "data", "package", "saori"]

        var movedCount = 0
        var allOK = true
        for source in sources {
            guard fm.fileExists(atPath: source.path) else { continue }
            if source.standardizedFileURL.path == base.standardizedFileURL.path { continue }
            for sub in subfolders {
                let srcSub = source.appendingPathComponent(sub, isDirectory: true)
                guard let entries = try? fm.contentsOfDirectory(at: srcSub,
                                                                includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles]) else { continue }
                let destSub = base.appendingPathComponent(sub, isDirectory: true)
                try? fm.createDirectory(at: destSub, withIntermediateDirectories: true)
                for entry in entries {
                    let dest = destSub.appendingPathComponent(entry.lastPathComponent)
                    if fm.fileExists(atPath: dest.path) {
                        NSLog("[OurinPaths] migrate skip (exists): \(sub)/\(entry.lastPathComponent)")
                        continue
                    }
                    do {
                        try fm.moveItem(at: entry, to: dest)
                        movedCount += 1
                    } catch {
                        NSLog("[OurinPaths] migrate FAILED \(sub)/\(entry.lastPathComponent): \(error.localizedDescription)")
                        allOK = false
                    }
                }
            }
        }

        if allOK {
            fm.createFile(atPath: sentinel.path, contents: Data())
            NSLog("[OurinPaths] legacy migration complete (moved \(movedCount) entries); sentinel written")
        } else {
            NSLog("[OurinPaths] legacy migration had failures (moved \(movedCount) entries); sentinel NOT written (retry next launch)")
        }
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
