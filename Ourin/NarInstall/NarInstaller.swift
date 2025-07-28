// Ourin/NarInstall/NarInstaller.swift
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
            }
        }
    }

    private let log = Logger(subsystem: "jp.ourin.installer", category: "nar")

    func install(fromNar narURL: URL) throws {
        // 1) 形式検証（拡張子 + 軽いヘッダチェック）
        guard narURL.pathExtension.lowercased() == "nar" else { throw Error.notZip }
        let data = try Data(contentsOf: narURL, options: .mappedIfSafe)
        guard data.starts(with: [0x50, 0x4b]) else { throw Error.notZip } // 'PK'

        // 2) 一時展開
        let tmpRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("OurinNarInstall_\(UUID().uuidString)", isDirectory: true)
        let tmpExtract = tmpRoot.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpExtract, withIntermediateDirectories: true)

        log.info("extracting to tmp: \(tmpExtract.path, privacy: .public)")
        try ZipUtil.extractZip(narURL, to: tmpExtract)

        // 3) install.txt を読む
        let installTxt = tmpExtract.appendingPathComponent("install.txt")
        guard FileManager.default.fileExists(atPath: installTxt.path) else { throw Error.installTxtNotFound }
        let itData = try Data(contentsOf: installTxt)
        guard let itStr = TextEncodingDetector.decode(itData) else { throw Error.installTxtDecodeFailed }
        let manifest = try InstallTxtParser.parse(itStr)

        // 4) 設置先解決
        let target = try OurinPaths.installTarget(forType: manifest.type, directory: manifest.directory)
        log.info("resolved target: \(target.path, privacy: .public)")

        // 5) 衝突確認（accept 等の運用は上位で UI 提示。ここでは最小限チェック）
        if FileManager.default.fileExists(atPath: target.path) && manifest.accept == nil {
            throw Error.directoryConflict(target.lastPathComponent)
        }

        // 6) 安全コピー（Zip Slip 対策）
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try ZipUtil.secureCopyTree(from: tmpExtract, to: target)

        // 7) 後始末
        try? FileManager.default.removeItem(at: tmpRoot)
        log.info("install finished")
    }
}
