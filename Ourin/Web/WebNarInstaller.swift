import Foundation
import AppKit
import os.log

/// `.nar` アーカイブをダウンロードして通常の NAR インストール経路へ渡す。
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
        // URL の妥当性チェック。既定は https のみ許可。設定で http を明示許可可。
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            NSLog("[WebNarInstaller] invalid url: \(urlString)")
            return
        }
        let allowHttp = allowInsecureHTTPInstall()
        if !(scheme == "https" || (scheme == "http" && allowHttp)) {
            NSLog("[WebNarInstaller] insecure http blocked: \(urlString)")
            EventBridge.shared.notifyCustom("OnSecurityWarning", refs: [
                "source": "nar_install_blocked",
                "detail": "http_scheme",
                "url": urlString
            ])
            return
        }
        if scheme == "http" && allowHttp {
            EventBridge.shared.notifyCustom("OnSecurityWarning", refs: [
                "source": "nar_install_insecure_allowed",
                "detail": "http_scheme",
                "url": urlString
            ])
        }

        // URLSession で非同期ダウンロード
        let task = URLSession.shared.downloadTask(with: url) { local, response, error in
            if let error = error {
                NSLog("[WebNarInstaller] download error: \(error)")
                EventBridge.shared.notifyCustom("OnInstallFailure", refs: ["reason": "network"])
                return
            }
            guard let local = local else { return }
            let archiveURL: URL
            do {
                archiveURL = try normalizedArchiveURL(
                    localURL: local,
                    response: response,
                    sourceURL: url
                )
                defer { try? FileManager.default.removeItem(at: archiveURL) }

                log.info("downloaded: \(archiveURL.path)")
                if let appDelegate = NSApp.delegate as? AppDelegate,
                   let ghostManager = appDelegate.ghostManager {
                    switch ghostManager.installNarFile(archiveURL) {
                    case .installed:
                        log.info("install finished")
                    case .refused:
                        log.info("install refused")
                    case .failed(let error):
                        log.error("install failed: \(error.localizedDescription)")
                    }
                } else {
                    EventBridge.shared.notifyCustom("OnInstallBegin", params: [:])
                    let result = try installLocalNar(archiveURL)
                    if let object = result.objects.first {
                        EventBridge.shared.notifyCustom("OnInstallComplete", refs: [
                            "identifier": object.identifier,
                            "name": object.name
                        ])
                    }
                }
            } catch {
                log.error("install failed: \(String(describing: error))")
                EventBridge.shared.notifyCustom("OnInstallFailure", refs: ["reason": "unsupported"])
            }

            NSLog("[WebNarInstaller] downloaded: \(local.path)")


        }
        task.resume()
    }

    /// http を許可するかを環境変数/ユーザデフォルトから判定
    /// - Env: OURIN_ALLOW_HTTP_NAR=1 で有効
    /// - UserDefaults: OurinAllowInsecureNarInstall=true で有効
    private static func allowInsecureHTTPInstall(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment["OURIN_ALLOW_HTTP_NAR"] == "1" { return true }
        return UserDefaults.standard.bool(forKey: "OurinAllowInsecureNarInstall")
    }

    private static func installLocalNar(_ narURL: URL) throws -> NarInstallResult {
        try NarInstaller().installWithResult(fromNar: narURL)
    }

    private static func normalizedArchiveURL(
        localURL: URL,
        response: URLResponse?,
        sourceURL: URL
    ) throws -> URL {
        let existingExtension = localURL.pathExtension.lowercased()
        guard existingExtension != "nar" && existingExtension != "zip" else {
            return localURL
        }

        let responseExtension = response?.suggestedFilename?.split(separator: ".").last.map(String.init)?.lowercased()
        let sourceExtension = sourceURL.pathExtension.lowercased()
        let extensionName: String
        if let responseExtension, responseExtension == "nar" || responseExtension == "zip" {
            extensionName = responseExtension
        } else if sourceExtension == "nar" || sourceExtension == "zip" {
            extensionName = sourceExtension
        } else {
            extensionName = "nar"
        }
        let destination = localURL.deletingLastPathComponent()
            .appendingPathComponent(localURL.lastPathComponent + ".\(extensionName)")
        try FileManager.default.moveItem(at: localURL, to: destination)
        return destination
    }
}
