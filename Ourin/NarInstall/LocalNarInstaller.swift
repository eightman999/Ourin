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

        // 5) 衝突確認（accept 等の運用は上位で UI 提示。ここでは最小限チェック）
        if FileManager.default.fileExists(atPath: target.path) && manifest.accept == nil {
            throw Error.directoryConflict(target.lastPathComponent)
        }

        // 6) 安全コピー（Zip Slip 対策）
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try ZipUtil.secureCopyTree(from: tmpExtract, to: target)
        try applyDeleteInstructions(from: tmpExtract, to: target)

        // 7) 後始末
        try? FileManager.default.removeItem(at: tmpRoot)
        log.info("install finished")
        return target
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
