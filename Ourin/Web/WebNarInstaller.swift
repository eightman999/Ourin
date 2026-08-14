import Foundation
import AppKit
import os.log

/// `.nar` アーカイブをダウンロードして通常の NAR インストール経路へ渡す。
/// 挙動の詳細仕様は docs/NAR_INSTALL_1.0M_SPEC.md を参照。

public enum WebNarInstaller {
    private final class DownloadSessionHolder {
        var session: URLSession?
    }

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
        let allowHttp = allowInsecureHTTPInstall()
        guard let parsedURL = URL(string: urlString),
              let parsedScheme = parsedURL.scheme?.lowercased() else {
            NSLog("[WebNarInstaller] invalid url: \(urlString)")
            return
        }
        if parsedScheme == "http" && !allowHttp {
            NSLog("[WebNarInstaller] insecure http blocked: \(urlString)")
            EventBridge.shared.notifyCustom("OnSecurityWarning", refs: [
                "source": "nar_install_blocked",
                "detail": "http_scheme",
                "url": urlString
            ])
            return
        }
        guard let url = URLDropPolicy.remoteURL(
            from: urlString,
            allowInsecureHTTP: allowHttp,
            resolveHost: false
        ), let scheme = url.scheme?.lowercased() else {
            NSLog("[WebNarInstaller] invalid url: \(urlString)")
            return
        }
        if scheme == "http" && allowHttp {
            EventBridge.shared.notifyCustom("OnSecurityWarning", refs: [
                "source": "nar_install_insecure_allowed",
                "detail": "http_scheme",
                "url": urlString
            ])
        }

        // DNS検査はURL受理元のメインスレッドを止めない。リダイレクト先は
        // URLDropDownloadDelegate が同じ公開アドレス検査を再適用する。
        DispatchQueue.global(qos: .utility).async {
            guard URLDropPolicy.isPublicRemoteHost(url.host ?? "") else {
                EventBridge.shared.notifyCustom("OnSecurityWarning", refs: [
                    "source": "nar_install_blocked",
                    "detail": "private_host",
                    "url": urlString
                ])
                EventBridge.shared.notifyCustom("OnInstallFailure", refs: ["reason": "fileio"])
                return
            }
            DispatchQueue.main.async {
                startDownload(url: url, sourceURLString: urlString)
            }
        }
    }

    private static func startDownload(url: URL, sourceURLString: String) {
        let holder = DownloadSessionHolder()
        let delegate = URLDropDownloadDelegate(
            allowInsecureHTTP: allowInsecureHTTPInstall(),
            maximumBytes: URLDropPolicy.maxDownloadBytes
        ) { localURL, response, error in
            DispatchQueue.main.async {
                holder.session?.finishTasksAndInvalidate()
                holder.session = nil
                finishDownload(
                    localURL: localURL,
                    response: response,
                    sourceURL: url,
                    sourceURLString: sourceURLString,
                    error: error
                )
            }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = URLDropPolicy.requestTimeout
        configuration.timeoutIntervalForResource = URLDropPolicy.resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        holder.session = session
        session.downloadTask(with: url).resume()
    }

    private static func finishDownload(
        localURL: URL?,
        response: URLResponse?,
        sourceURL: URL,
        sourceURLString: String,
        error: Swift.Error?
    ) {
        var archiveURL: URL?
        defer {
            if let archiveURL {
                try? FileManager.default.removeItem(at: archiveURL)
            }
            if let localURL, localURL != archiveURL {
                try? FileManager.default.removeItem(at: localURL)
            }
        }

        if let error {
            NSLog("[WebNarInstaller] download error: \(error)")
            EventBridge.shared.notifyCustom("OnInstallFailure", refs: [
                "reason": URLDropFailureReason.forDownload(error: error)
            ])
            return
        }
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            EventBridge.shared.notifyCustom("OnInstallFailure", refs: [
                "reason": URLDropFailureReason.httpStatus(httpResponse.statusCode)
            ])
            return
        }
        guard let localURL else {
            EventBridge.shared.notifyCustom("OnInstallFailure", refs: ["reason": "fileio"])
            return
        }

        do {
            archiveURL = try normalizedArchiveURL(
                localURL: localURL,
                response: response,
                sourceURL: sourceURL
            )
            log.info("downloaded: \(archiveURL?.path ?? localURL.path)")
            if let appDelegate = NSApp.delegate as? AppDelegate,
               let ghostManager = appDelegate.ghostManager {
                switch ghostManager.installNarFile(archiveURL ?? localURL) {
                case .installed(let result):
                    // Web 経路は AppDelegate.installNars を経由しないため、
                    // SHIORI 側で完了イベントを発火しても PLUGIN には届かない。
                    // D&D／関連付けと同じ実設置対象一覧を通知する。
                    appDelegate.pluginDispatcher?.onInstallComplete(objects: result.objects)
                    log.info("install finished")
                case .refused:
                    log.info("install refused")
                case .failed(let error):
                    log.error("install failed: \(error.localizedDescription)")
                }
            } else {
                EventBridge.shared.notifyCustom("OnInstallBegin", params: [:])
                let result = try installLocalNar(archiveURL ?? localURL)
                if let object = result.objects.first {
                    EventBridge.shared.notifyCustom("OnInstallComplete", refs: [
                        "identifier": object.identifier,
                        "name": object.name
                    ])
                }
                (NSApp.delegate as? AppDelegate)?.pluginDispatcher?.onInstallComplete(objects: result.objects)
            }
        } catch {
            log.error("install failed: \(String(describing: error))")
            EventBridge.shared.notifyCustom("OnInstallFailure", refs: [
                "reason": URLDropFailureReason.forInstallation(error: error)
            ])
        }

        NSLog("[WebNarInstaller] downloaded: \(sourceURLString)")
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
