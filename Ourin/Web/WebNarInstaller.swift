import Foundation
import os.log

/// `.nar` アーカイブをダウンロードして展開する簡易インストーラ。
/// 挙動の詳細仕様は docs/NAR_INSTALL_1.0M_SPEC.md を参照。

public enum WebNarInstaller {
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
            case .installTxtDecodeFailed: return "install.txt を読み取れません（UTF-8/SJIS）"
            case .installTxtMissingKey(let k): return "install.txt の必須キーが不足: \(k)"
            case .unsupportedType(let t): return "未対応の type: \(t)"
            case .zipSlipDetected(let p): return "危険なパスが検出されました: \(p)"
            case .directoryConflict(let d): return "設置先が衝突: \(d)"
            }
        }
    }

    private static let log = CompatLogger(subsystem: "jp.ourin.web", category: "nar")
    /// Download and install a NAR archive from https URL

    public static func install(from urlString: String) {
        // URL の妥当性チェック。https 以外は拒否
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            NSLog("[WebNarInstaller] invalid url: \(urlString)")
            return
        }

        // URLSession で非同期ダウンロード
        let task = URLSession.shared.downloadTask(with: url) { local, response, error in
            if let error = error {
                NSLog("[WebNarInstaller] download error: \(error)")
                return
            }
            guard let local = local else { return }
            log.info("downloaded: \(local.path)")
            do {
                try installLocalNar(local)
                log.info("install finished")
            } catch {
                log.fault("install failed: \(String(describing: error))")
            }

            NSLog("[WebNarInstaller] downloaded: \(local.path)")


        }
        task.resume()
    }

    private static func installLocalNar(_ narURL: URL) throws {
        // 1) validate zip header
        guard narURL.pathExtension.lowercased() == "nar" else { throw Error.notZip }
        let data = try Data(contentsOf: narURL, options: .mappedIfSafe)
        guard data.starts(with: [0x50, 0x4b]) else { throw Error.notZip }

        // 2) temporary extraction
        let tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinNarInstall_\(UUID().uuidString)", isDirectory: true)
        let tmpExtract = tmpRoot.appendingPathComponent("extract", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpExtract, withIntermediateDirectories: true)

        log.info("extracting to tmp: \(tmpExtract.path)")
        try ZipUtil.extractZip(narURL, to: tmpExtract)

        // 3) read install.txt
        let installTxt = tmpExtract.appendingPathComponent("install.txt")
        guard FileManager.default.fileExists(atPath: installTxt.path) else { throw Error.installTxtNotFound }
        let itData = try Data(contentsOf: installTxt)
        guard let itStr = TextEncodingDetector.decode(itData) else { throw Error.installTxtDecodeFailed }
        let manifest = try InstallTxtParser.parse(itStr)

        // 4) resolve target
        let target = try OurinPaths.installTarget(forType: manifest.type, directory: manifest.directory)
        log.info("resolved target: \(target.path)")

        // 5) conflict check
        if FileManager.default.fileExists(atPath: target.path) && manifest.accept == nil {
            throw Error.directoryConflict(target.lastPathComponent)
        }

        // 6) secure copy
        let parent = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try ZipUtil.secureCopyTree(from: tmpExtract, to: target)

        // 7) cleanup
        try? FileManager.default.removeItem(at: tmpRoot)
    }
}
