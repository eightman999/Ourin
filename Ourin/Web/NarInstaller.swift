import Foundation
import os.log

/// `.nar` アーカイブをダウンロードして展開する簡易インストーラ。
/// 挙動の詳細仕様は docs/NAR_INSTALL_1.0M_SPEC.md を参照。

public enum NarInstaller {
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
            case .notZip: return "NAR (ZIP) \u3067\u306F\u3042\u308A\u307E\u305B\u3093"
            case .unzipFailed(let s): return "\u5c55\u958b\u306b\u5931\u6557: \(s)"
            case .installTxtNotFound: return "install.txt \u304c\u898b\u3064\u304b\u308a\u307e\u305b\u3093"
            case .installTxtDecodeFailed: return "install.txt \u3092\u8aad\u307f\u53d6\u308c\u307e\u305b\u3093\uff08UTF-8/SJIS\uff09"
            case .installTxtMissingKey(let k): return "install.txt \u306e\u5fc5\u8981\u30ad\u30fc\u304c\u4e0d\u8db3: \(k)"
            case .unsupportedType(let t): return "\u672a\u5bfe\u5fdc\u306e type: \(t)"
            case .zipSlipDetected(let p): return "\u5371\u967a\u306a\u30d1\u30b9\u304c\u691c\u51fa\u3055\u308c\u307e\u3057\u305f: \(p)"
            case .directoryConflict(let d): return "\u8a2d\u7f6e\u5148\u304c\u885d\u7a81: \(d)"
            }
        }
    }

    private static let log = Logger(subsystem: "jp.ourin.web", category: "nar")
    /// Download and install a NAR archive from https URL

    public static func install(from urlString: String) {
        // URL の妥当性チェック。https 以外は拒否
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            NSLog("[NarInstaller] invalid url: \(urlString)")
            return
        }

        // URLSession で非同期ダウンロード
        let task = URLSession.shared.downloadTask(with: url) { local, response, error in
            if let error = error {
                NSLog("[NarInstaller] download error: \(error)")
                return
            }
            guard let local = local else { return }
            log.info("downloaded: \(local.path, privacy: .public)")
            do {
                try installLocalNar(local)
                log.info("install finished")
            } catch {
                log.error("install failed: \(String(describing: error), privacy: .public)")
            }

            NSLog("[NarInstaller] downloaded: \(local.path)")


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

        log.info("extracting to tmp: \(tmpExtract.path, privacy: .public)")
        try ZipUtil.extractZip(narURL, to: tmpExtract)

        // 3) read install.txt
        let installTxt = tmpExtract.appendingPathComponent("install.txt")
        guard FileManager.default.fileExists(atPath: installTxt.path) else { throw Error.installTxtNotFound }
        let itData = try Data(contentsOf: installTxt)
        guard let itStr = TextEncodingDetector.decode(itData) else { throw Error.installTxtDecodeFailed }
        let manifest = try InstallTxtParser.parse(itStr)

        // 4) resolve target
        let target = try OurinPaths.installTarget(forType: manifest.type, directory: manifest.directory)
        log.info("resolved target: \(target.path, privacy: .public)")

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
