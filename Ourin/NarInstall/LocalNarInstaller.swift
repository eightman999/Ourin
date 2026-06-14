// Ourin/NarInstall/LocalNarInstaller.swift
import Foundation
import os.log


final class NarInstaller {
    enum Error: Swift.Error, CustomStringConvertible {
        case notZip
        case unzipFailed(String)
        case installTxtNotFound
        case installTxtDecodeFailed
        case installTxtMissingKey(String)
        case unsupportedType(String)
        case zipSlipDetected(String)
        case directoryConflict(String)
        case invalidDeletePath(String)
        case updateDescriptorNotFound
        case updateDescriptorDecodeFailed

        var description: String {
            switch self {
            case .notZip: return "NAR (ZIP) ではありません"
            case .unzipFailed(let s): return "展開に失敗: \(s)"
            case .installTxtNotFound: return "install.txt が見つかりません"
            case .installTxtDecodeFailed: return "install.txt を読み取れません（UTF‑8/SJIS）"
            case .installTxtMissingKey(let k): return "install.txt の必須キーが不足: \(k)"
            case .unsupportedType(let t): return "未対応の type: \(t)"
            case .zipSlipDetected(let p): return "危険なパスが検出されました: \(p)"
            case .directoryConflict(let d): return "設置先が衝突: \(d)"
            case .invalidDeletePath(let p): return "delete.txt の危険なパス: \(p)"
            case .updateDescriptorNotFound: return "updates2.dau / updates.txt / update.txt が見つかりません"
            case .updateDescriptorDecodeFailed: return "更新定義ファイルをデコードできません"
            }
        }
    }

    private let log = CompatLogger(subsystem: "jp.ourin.installer", category: "nar")

    func install(fromNar narURL: URL) throws -> URL {
        // 1) 形式検証（拡張子 + 軽いヘッダチェック）
        let allowedExtensions = ["nar", "zip"]
        guard allowedExtensions.contains(narURL.pathExtension.lowercased()) else { throw Error.notZip }
        let data = try Data(contentsOf: narURL, options: .mappedIfSafe)
        guard data.starts(with: [0x50, 0x4b]) else { throw Error.notZip } // 'PK'

        // 2) 一時展開
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OurinNarInstall_\(UUID().uuidString)", isDirectory: true)
        let tmpExtract = tmpRoot.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpExtract, withIntermediateDirectories: true)

        log.info("extracting to tmp: \(tmpExtract.path,)")
        try ZipUtil.extractZip(narURL, to: tmpExtract)

        // 3) install.txt を読む
        let installTxt = tmpExtract.appendingPathComponent("install.txt")
        guard FileManager.default.fileExists(atPath: installTxt.path) else { throw Error.installTxtNotFound }
        let itData = try Data(contentsOf: installTxt)
        guard let itStr = TextEncodingDetector.decode(itData) else { throw Error.installTxtDecodeFailed }
        let manifest = try InstallTxtParser.parse(itStr)

        // 4) 設置先解決
        let target = try OurinPaths.installTarget(forType: manifest.type, directory: manifest.directory)
        log.info("resolved target: \(target.path,)")

        // 5) 上書きポリシー
        //   旧実装は「target が存在し accept 未設定」を常に conflict 扱いにしていたため、
        //   既存ゴーストの再インストール（更新）が必ず失敗していた。UKADOC では type=shell の
        //   accept は親ゴースト名の検証用であり、上書き判定とは関係ない。
        //   既存先がある場合は通常の更新インストールとして許容する。
        if manifest.type.lowercased() == "shell", let accept = manifest.accept, !accept.isEmpty {
            try validateShellAccept(accept)
        }

        // 6) refresh,1 が指定されていれば設置先をクリア（refreshundeletemask に合致するパスは保持）
        if manifest.refresh, FileManager.default.fileExists(atPath: target.path) {
            try refreshTarget(at: target, keepingMasks: manifest.refreshUndeleteMask)
        }

        // 7) 安全コピー（Zip Slip 対策）
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try ZipUtil.secureCopyTree(from: tmpExtract, to: target)
        try applyDeleteInstructions(from: tmpExtract, to: target)

        // 8) type=ghost に同梱されたバルーンを balloon/<name> へも展開
        if manifest.type.lowercased() == "ghost",
           let balloonDir = manifest.balloonDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !balloonDir.isEmpty {
            try installBundledBalloon(
                fromExtract: tmpExtract,
                balloonDirectory: balloonDir,
                balloonSourceDirectory: manifest.balloonSourceDirectory
            )
        }

        // 9) 後始末
        try? FileManager.default.removeItem(at: tmpRoot)
        log.info("install finished")
        return target
    }

    /// type=shell の accept ヘッダで指定された親ゴーストがインストール済みか確認する。
    /// 未インストールでも処理を継続するが、警告ログを出す（UKADOC のままでは厳格すぎるため寛容寄り）。
    private func validateShellAccept(_ accept: String) throws {
        let base = try OurinPaths.baseDirectory()
        let ghostDir = base.appendingPathComponent("ghost", isDirectory: true)
        let candidate = ghostDir.appendingPathComponent(accept, isDirectory: true)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            log.warning("shell.accept=\(accept,) : 親ゴーストが見つかりません（インストールは継続）")
        }
    }

    /// refresh,1 のインストール時に設置先を空にする。refreshundeletemask に合致するパスは残す。
    /// マスクはターゲット相対パスへの正規表現として評価する（UKADOC）。
    private func refreshTarget(at target: URL, keepingMasks masks: [String]) throws {
        let fm = FileManager.default
        let regexes: [NSRegularExpression] = masks.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        guard let entries = try? fm.contentsOfDirectory(at: target, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }
        for entry in entries {
            let relative = entry.path.replacingOccurrences(of: target.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if matchesAny(regexes: regexes, path: relative) {
                continue
            }
            try? fm.removeItem(at: entry)
        }
    }

    private func matchesAny(regexes: [NSRegularExpression], path: String) -> Bool {
        guard !regexes.isEmpty else { return false }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        for regex in regexes {
            if regex.firstMatch(in: path, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }

    /// 同梱バルーンを balloon/<dest> へ追加インストールする。
    /// ソース位置は (1) balloon.source.directory が NAR ルート相対の有効なパスならそれを使い、
    /// (2) 既定は <NAR root>/balloon/<balloonDirectory>、(3) なければ <NAR root>/<balloon.source.directory> を試す。
    private func installBundledBalloon(fromExtract extractRoot: URL, balloonDirectory: String, balloonSourceDirectory: String?) throws {
        let fm = FileManager.default
        let trimmedSource = balloonSourceDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sourceName = trimmedSource.isEmpty ? balloonDirectory : trimmedSource
        let candidates: [URL] = [
            extractRoot.appendingPathComponent("balloon", isDirectory: true).appendingPathComponent(sourceName, isDirectory: true),
            extractRoot.appendingPathComponent(sourceName, isDirectory: true)
        ]
        guard let srcDir = candidates.first(where: { isDirectory($0) }) else {
            log.warning("balloon.directory=\(balloonDirectory,) : ソースディレクトリが見つかりません")
            return
        }
        let balloonTarget = try OurinPaths.installTarget(forType: "balloon", directory: balloonDirectory)
        try fm.createDirectory(at: balloonTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ZipUtil.secureCopyTree(from: srcDir, to: balloonTarget)
        log.info("bundled balloon installed to: \(balloonTarget.path,)")
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// updates2.dau / updates.txt / update.txt を順に解決して更新候補 URL を返す
    func checkUpdates(homeURLString: String, completion: @escaping (Result<[URL], Swift.Error>) -> Void) {
        let base: URL
        if let parsed = URL(string: homeURLString) {
            base = parsed
        } else {
            completion(.failure(Error.updateDescriptorNotFound))
            return
        }

        let baseWithSlash: String = homeURLString.hasSuffix("/") ? homeURLString : "\(homeURLString)/"
        let candidates = ["updates2.dau", "updates.txt", "update.txt"].compactMap { URL(string: "\(baseWithSlash)\($0)") }
        fetchUpdateDescriptor(from: candidates, baseURL: URL(string: baseWithSlash) ?? base, completion: completion)
    }

    /// 更新記述子で列挙されたファイルを実ダウンロードし設置先へ適用する。
    /// - `.nar`/`.zip` は `install(fromNar:)` でパッケージ展開（install.txt に従う）。
    /// - それ以外は `homeURLString` を基準にした相対パスで `targetRoot` 配下へ保存（増分更新）。
    /// - Parameters:
    ///   - entries: ダウンロード対象 URL（checkUpdates の結果）
    ///   - homeURLString: 相対パス算出の基準（ゴーストの homeurl）
    ///   - targetRoot: 増分ファイルの設置先ルート（通常はゴーストのルート URL）
    ///   - completion: 適用できたファイル名（lastPathComponent）の配列を返す
    func downloadAndApply(entries: [URL], homeURLString: String, targetRoot: URL,
                          completion: @escaping ([String]) -> Void) {
        guard !entries.isEmpty else { completion([]); return }
        let baseWithSlash = homeURLString.hasSuffix("/") ? homeURLString : "\(homeURLString)/"
        let group = DispatchGroup()
        let lock = NSLock()
        var applied: [String] = []

        for entry in entries {
            group.enter()
            URLSession.shared.downloadTask(with: entry) { [weak self] local, response, error in
                defer { group.leave() }
                guard let self, let local else { return }
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
                guard (200..<300).contains(statusCode) else {
                    self.log.warning("update download failed status=\(statusCode,) url=\(entry.absoluteString,)")
                    return
                }
                let ext = entry.pathExtension.lowercased()
                do {
                    if ext == "nar" || ext == "zip" {
                        // パッケージ更新: 一時ファイルへ拡張子付きでコピーしてから install
                        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                            .appendingPathComponent("OurinUpd_\(UUID().uuidString).\(ext)")
                        try? FileManager.default.removeItem(at: tmp)
                        try FileManager.default.moveItem(at: local, to: tmp)
                        defer { try? FileManager.default.removeItem(at: tmp) }
                        _ = try self.install(fromNar: tmp)
                    } else {
                        // 増分ファイル更新: homeurl 基準の相対パスへ保存
                        try self.applyIncrementalFile(downloaded: local, entry: entry,
                                                      baseWithSlash: baseWithSlash, targetRoot: targetRoot)
                    }
                    lock.lock(); applied.append(entry.lastPathComponent); lock.unlock()
                } catch {
                    self.log.warning("update apply failed: \(String(describing: error),) url=\(entry.absoluteString,)")
                }
            }.resume()
        }
        group.notify(queue: .global()) { completion(applied) }
    }

    /// 増分更新ファイルを homeurl 基準の相対パスで targetRoot 配下へ保存する（パストラバーサル防止つき）。
    private func applyIncrementalFile(downloaded: URL, entry: URL, baseWithSlash: String, targetRoot: URL) throws {
        var relative = entry.absoluteString
        if relative.hasPrefix(baseWithSlash) {
            relative = String(relative.dropFirst(baseWithSlash.count))
        } else {
            relative = entry.lastPathComponent
        }
        relative = (relative.removingPercentEncoding ?? relative)
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.isEmpty, !relative.contains("..") else {
            throw Error.invalidDeletePath(relative)
        }
        let dest = targetRoot.appendingPathComponent(relative)
        let resolved = dest.resolvingSymlinksInPath()
        let rootResolved = targetRoot.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(rootResolved.path) || dest.path.hasPrefix(targetRoot.path) else {
            throw Error.zipSlipDetected(dest.path)
        }
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: downloaded, to: dest)
    }

    private func fetchUpdateDescriptor(from candidates: [URL], baseURL: URL, completion: @escaping (Result<[URL], Swift.Error>) -> Void) {
        guard let current = candidates.first else {
            completion(.failure(Error.updateDescriptorNotFound))
            return
        }
        URLSession.shared.dataTask(with: current) { data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let data, error == nil, (200..<300).contains(statusCode) {
                guard let text = TextEncodingDetector.decode(data) else {
                    completion(.failure(Error.updateDescriptorDecodeFailed))
                    return
                }
                let entries = UpdateDescriptorParser.parse(text, baseURL: baseURL)
                completion(.success(entries))
                return
            }
            self.fetchUpdateDescriptor(from: Array(candidates.dropFirst()), baseURL: baseURL, completion: completion)
        }.resume()
    }

    private func applyDeleteInstructions(from extractedRoot: URL, to installTarget: URL) throws {
        let deleteTxt = extractedRoot.appendingPathComponent("delete.txt")
        guard FileManager.default.fileExists(atPath: deleteTxt.path) else { return }

        let data = try Data(contentsOf: deleteTxt)
        guard let text = TextEncodingDetector.decode(data) else { throw Error.installTxtDecodeFailed }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix(";"), !line.hasPrefix("#") else { continue }
            let normalized = line.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !normalized.contains("..") else { throw Error.invalidDeletePath(normalized) }
            let target = installTarget.appendingPathComponent(normalized)
            let resolved = target.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(installTarget.path) else { throw Error.invalidDeletePath(normalized) }
            if FileManager.default.fileExists(atPath: resolved.path) {
                try FileManager.default.removeItem(at: resolved)
            }
        }
    }
}

