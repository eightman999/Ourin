import SwiftUI
import AppKit
import CoreImage
import Combine
import UserNotifications
import Network
import Security
import UniformTypeIdentifiers
import Darwin

enum NarInstallDispatchOutcome {
    case installed(NarInstallResult)
    case refused
    case failed(Swift.Error)
}

private struct ArchiveCommandOptions {
    let eventID: String?
    let password: String?

    init(_ raw: [String]) {
        var parsedEventID: String?
        var parsedPassword: String?
        var index = 0

        while index < raw.count {
            let option = raw[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = option.splitOnce(after: "--event=") {
                parsedEventID = value.isEmpty ? nil : value
            } else if let value = option.splitOnce(after: "--password=") {
                parsedPassword = value
            } else if option == "--event", index + 1 < raw.count {
                index += 1
                let value = raw[index].trimmingCharacters(in: .whitespacesAndNewlines)
                parsedEventID = value.isEmpty ? nil : value
            } else if option == "--password", index + 1 < raw.count {
                index += 1
                parsedPassword = raw[index]
            }
            index += 1
        }

        eventID = parsedEventID
        password = parsedPassword
    }
}

/// URLドロップで本体が行う処理と、OnURLQueryへ渡す値を一元化する。
enum URLDropPolicy {
    static let maxDownloadBytes: Int64 = 256 * 1024 * 1024
    static let requestTimeout: TimeInterval = 30
    static let resourceTimeout: TimeInterval = 300

    static func remoteURL(
        from rawValue: String,
        allowInsecureHTTP: Bool,
        resolveHost: Bool = true
    ) -> URL? {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty,
              let url = URL(string: rawValue),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }

        guard scheme == "https" || (scheme == "http" && allowInsecureHTTP) else {
            return nil
        }
        guard !resolveHost || isPublicRemoteHost(host) else {
            return nil
        }
        return url
    }

    /// URLSession の DNS 解決・接続先がローカルネットワークや予約帯域へ向かわないよう、
    /// ホスト名を解決した全アドレスを検査する。名前解決できない場合は fail closed とする。
    static func isPublicRemoteHost(_ host: String) -> Bool {
        let normalizedHost = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard !normalizedHost.isEmpty,
              normalizedHost != "localhost",
              !normalizedHost.hasSuffix(".localhost"),
              !normalizedHost.hasSuffix(".local"),
              !normalizedHost.hasSuffix(".internal") else {
            return false
        }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let resolutionCode = normalizedHost.withCString { value in
            getaddrinfo(value, nil, &hints, &result)
        }
        guard resolutionCode == 0, let first = result else {
            return false
        }
        defer { freeaddrinfo(first) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        var foundAddress = false
        while let info = cursor {
            if let address = info.pointee.ai_addr {
                switch info.pointee.ai_family {
                case AF_INET:
                    let socketAddress = address.withMemoryRebound(
                        to: sockaddr_in.self,
                        capacity: 1
                    ) { $0.pointee }
                    let bytes = withUnsafeBytes(of: socketAddress.sin_addr) { Array($0) }
                    foundAddress = true
                    if isBlockedIPv4(bytes) {
                        return false
                    }
                case AF_INET6:
                    let socketAddress = address.withMemoryRebound(
                        to: sockaddr_in6.self,
                        capacity: 1
                    ) { $0.pointee }
                    let bytes = withUnsafeBytes(of: socketAddress.sin6_addr) { Array($0) }
                    foundAddress = true
                    if isBlockedIPv6(bytes) {
                        return false
                    }
                default:
                    break
                }
            }
            cursor = info.pointee.ai_next
        }
        return foundAddress
    }

    private static func isBlockedIPv4(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 4 else { return true }
        let value = (UInt32(bytes[0]) << 24)
            | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8)
            | UInt32(bytes[3])

        return value == 0
            || (value & 0xff000000) == 0x0a000000       // 10.0.0.0/8
            || (value & 0xffc00000) == 0x64400000       // 100.64.0.0/10
            || (value & 0xff000000) == 0x7f000000       // 127.0.0.0/8
            || (value & 0xffff0000) == 0xa9fe0000       // 169.254.0.0/16
            || (value & 0xfff00000) == 0xac100000       // 172.16.0.0/12
            || (value & 0xffffff00) == 0xc0000000       // 192.0.0.0/24
            || (value & 0xffffff00) == 0xc0000200       // 192.0.2.0/24
            || (value & 0xffff0000) == 0xc0a80000       // 192.168.0.0/16
            || (value & 0xfffffe00) == 0xc6120000       // 198.18.0.0/15
            || (value & 0xffffff00) == 0xc6336400       // 198.51.100.0/24
            || (value & 0xffffff00) == 0xcb007100       // 203.0.113.0/24
            || (value & 0xf0000000) == 0xe0000000       // multicast
            || (value & 0xf0000000) == 0xf0000000       // reserved
    }

    private static func isBlockedIPv6(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == 16 else { return true }
        let isZero = bytes.allSatisfy { $0 == 0 }
        let isUniqueLocal = (bytes[0] & 0xfe) == 0xfc
        let isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
        let isMulticast = bytes[0] == 0xff
        let isDocumentation = bytes[0] == 0x20
            && bytes[1] == 0x01
            && bytes[2] == 0x0d
            && bytes[3] == 0xb8
        let isIPv4Compatible = bytes.prefix(12).allSatisfy { $0 == 0 }
        let isIPv4Mapped = bytes.prefix(10).allSatisfy { $0 == 0 }
            && bytes[10] == 0xff
            && bytes[11] == 0xff
        if isIPv4Mapped {
            return isBlockedIPv4(Array(bytes[12...]))
        }
        // ::/96 は IPv4-compatible と loopback (::1) を含む予約帯域であり、
        // URLSession の接続先として公開アドレス扱いしてはならない。
        return isZero || isIPv4Compatible || isUniqueLocal || isLinkLocal
            || isMulticast || isDocumentation
    }

    static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
    }

    static func plannedAction(for url: URL) -> String {
        if url.path.isEmpty || url.hasDirectoryPath {
            return "homeurl"
        }
        switch url.pathExtension.lowercased() {
        case "nar", "zip":
            return "nar"
        case "rss", "rdf", "atom", "xml":
            return "feed"
        default:
            return "unknown"
        }
    }

    static func queryReferences(for url: URL, scopeID: Int) -> [String: String] {
        [
            "url": url.absoluteString,
            "scopeID": String(scopeID),
            "mimeType": mimeType(for: url),
            "plannedAction": plannedAction(for: url)
        ]
    }

    static func allowsInsecureHTTP(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        if environment["OURIN_ALLOW_HTTP_NAR"] == "1" {
            return true
        }
        return userDefaults.bool(forKey: "OurinAllowInsecureNarInstall")
    }
}

/// UKADOC の OnURLDropFailure Reference1 に渡す失敗理由を、URL ドロップ専用に正規化する。
/// 通常の OnInstallFailure は既存の理由語彙を維持するため、installFailureReason とは分離する。
enum URLDropFailureReason {
    static func httpStatus(_ statusCode: Int) -> String {
        String(statusCode)
    }

    static func forDownload(error: Error?) -> String {
        guard let error else { return "fileio" }
        if error is URLDropDownloadError {
            return "fileio"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "timeout"
            case .cancelled:
                return "artificial"
            default:
                return "fileio"
            }
        }
        return "fileio"
    }

    static func forInstallation(error: Error) -> String {
        guard let narError = error as? NarInstaller.Error else { return "fileio" }
        switch narError {
        case .notZip, .unsupportedType,
             .updateDescriptorNotFound, .updateDescriptorDecodeFailed,
             .updateDescriptorInvalid, .basewareArchiveUnsupported:
            return "unsupported"
        case .unzipFailed:
            return "extraction"
        case .installTxtNotFound, .installTxtDecodeFailed, .installTxtMissingKey,
             .zipSlipDetected, .invalidDeletePath,
             .deleteInstructionDecodeFailed, .attachedComponentSourceNotFound:
            return "invalid type"
        case .directoryConflict, .updateDownloadFailed:
            return "unsupported"
        case .updateMD5Mismatch:
            return "md5 miss"
        }
    }
}

enum URLDropDownloadError: Swift.Error {
    case responseTooLarge
    case missingDownloadedFile
    case redirectRejected
}

/// URLSession の一時ファイルを URLSession のコールバック寿命から切り離し、
/// サイズ制限・リダイレクト制限を適用してから GhostManager へ引き渡す。
final class URLDropDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    typealias Completion = (URL?, URLResponse?, Error?) -> Void

    private let allowInsecureHTTP: Bool
    private let maximumBytes: Int64
    private let completion: Completion
    private var temporaryFileURL: URL?
    private var terminalError: Error?
    private var didDeliverCompletion = false

    init(
        allowInsecureHTTP: Bool,
        maximumBytes: Int64,
        completion: @escaping Completion
    ) {
        self.allowInsecureHTTP = allowInsecureHTTP
        self.maximumBytes = maximumBytes
        self.completion = completion
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard terminalError == nil else { return }
        if totalBytesWritten > maximumBytes
            || (totalBytesExpectedToWrite > maximumBytes && totalBytesExpectedToWrite >= 0) {
            reject(.responseTooLarge, task: downloadTask)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        guard terminalError == nil else { return }
        if fileOffset > maximumBytes
            || (expectedTotalBytes > maximumBytes && expectedTotalBytes >= 0) {
            reject(.responseTooLarge, task: downloadTask)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard terminalError == nil else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OurinURLDrops", isDirectory: true)
        let destination = directory.appendingPathComponent(
            "\(UUID().uuidString).download",
            isDirectory: false
        )
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: location, to: destination)
            temporaryFileURL = destination
        } catch {
            terminalError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
              let validatedURL = URLDropPolicy.remoteURL(
                  from: redirectedURL.absoluteString,
                  allowInsecureHTTP: allowInsecureHTTP
              ) else {
            terminalError = URLDropDownloadError.redirectRejected
            completionHandler(nil)
            task.cancel()
            return
        }
        var validatedRequest = request
        validatedRequest.url = validatedURL
        completionHandler(validatedRequest)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !didDeliverCompletion else { return }
        didDeliverCompletion = true
        let finalError = terminalError
            ?? error
            ?? (temporaryFileURL == nil ? URLDropDownloadError.missingDownloadedFile : nil)
        completion(temporaryFileURL, task.response, finalError)
    }

    private func reject(_ error: URLDropDownloadError, task: URLSessionDownloadTask) {
        if terminalError == nil {
            terminalError = error
        }
        task.cancel()
    }
}

private struct ArchiveStatistics {
    let fileCount: Int
    let byteCount: Int64

    static func fileTree(at root: URL) -> ArchiveStatistics {
        let fileManager = FileManager.default
        var count = 0
        var bytes: Int64 = 0

        func addFile(_ url: URL) {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { return }
            count += 1
            bytes += Int64(values.fileSize ?? 0)
        }

        guard let rootValues = try? root.resourceValues(forKeys: [.isDirectoryKey]) else {
            return ArchiveStatistics(fileCount: 0, byteCount: 0)
        }
        if rootValues.isDirectory == true {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: []
            ) else {
                return ArchiveStatistics(fileCount: 0, byteCount: 0)
            }
            for case let url as URL in enumerator {
                addFile(url)
            }
        } else {
            addFile(root)
        }

        return ArchiveStatistics(fileCount: count, byteCount: bytes)
    }

    static func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return 0 }
        return Int64(values.fileSize ?? 0)
    }
}

enum SSTPEventDeliveryResult: Equatable {
    case sent
    case response(statusCode: Int, status: String?)
    case failure(reason: String)
}

struct ParsedSSTPResponse: Equatable {
    let statusCode: Int
    let status: String?
}

struct OtherGhostFailure: Equatable {
    let reason: String
    let ghostName: String
}

struct OtherGhostDispatchTarget: Equatable {
    let order: Int
    let ghostName: String
    let receiverGhostName: String?
}

private extension String {
    func splitOnce(after prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}

// MARK: - System Commands and Ghost Booting

extension GhostManager: NSWindowDelegate {
    // Note: This extension uses the following properties declared in the main GhostManager class:
    // - pendingChoices, choiceHasCancelOption, choiceTimeout

    private struct UpdateCommandOptions {
        struct Selector {
            let type: String
            let name: String
        }

        let checkOnly: Bool
        let testOnly: Bool
        let reason: String
        let explicitURL: String?
        let selectors: [Selector]
        let unsupportedSelectors: [Selector]

        var componentSelectors: [Selector] {
            selectors.filter { ComponentUpdateTargetDiscovery.supportedTypes.contains($0.type) }
        }

        init(_ raw: [String]) {
            let normalized = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            checkOnly = normalized.contains { $0 == "checkonly" || $0 == "--checkonly" }
            testOnly = normalized.contains { $0 == "testonly" || $0 == "--testonly" }
            reason = normalized.first(where: { $0.hasPrefix("--reason=") })
                .map { String($0.dropFirst("--reason=".count)) } ?? "script"
            explicitURL = raw.first(where: {
                let lower = $0.lowercased()
                return lower.hasPrefix("--url=") || lower.hasPrefix("url=")
            }).map {
                if $0.lowercased().hasPrefix("--url=") {
                    return String($0.dropFirst("--url=".count))
                }
                return String($0.dropFirst("url=".count))
            }

            var parsedSelectors: [Selector] = []
            var unsupported: [Selector] = []
            let supportedTypes: Set<String> = ["ghost"]
            let selectorTypes: Set<String> = ["ghost", "balloon", "shell", "plugin", "headline", "language"]
            for rawValue in raw {
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = value.hasPrefix("--") ? String(value.dropFirst(2)) : value
                guard let separator = body.firstIndex(of: "=") else {
                    let lower = body.lowercased()
                    if !["checkonly", "testonly", "recovery"].contains(lower),
                       !lower.hasPrefix("reason"), !lower.hasPrefix("url") {
                        parsedSelectors.append(Selector(type: "ghost", name: value))
                    }
                    continue
                }
                let type = String(body[..<separator]).lowercased()
                let name = String(body[body.index(after: separator)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard selectorTypes.contains(type), !name.isEmpty else { continue }
                let selector = Selector(type: type, name: name)
                parsedSelectors.append(selector)
                if !supportedTypes.contains(type) {
                    unsupported.append(selector)
                }
            }
            selectors = parsedSelectors
            unsupportedSelectors = unsupported
        }
    }

    /// HTTP/RSS コマンドのオプション。`parseCommandArguments` は一般コマンド用に
    /// 単一値へ正規化するため、HTTP の複数 `--param` / `--header` はここで保持する。
    struct HTTPCommandOptions {
        let positionals: [String]
        let asyncID: String
        let customEventID: String?
        let waitForCompletion: Bool
        let noFile: Bool
        let noFileEncoding: String.Encoding
        let fileName: String?
        let cookie: String
        let headers: [(String, String)]
        let parameters: [String]
        let parameterInputData: Data?
        let parameterInputFileError: String?
        let parameterEncoding: String.Encoding
        let body: String?
        let contentType: String?
        let timeout: TimeInterval?
        let progressNotify: Bool
        let noCache: Bool
        let streaming: Bool

        init(arguments: [String], parameterRoot: URL? = nil) {
            var positionals: [String] = []
            var asyncID = ""
            var customEventID: String?
            var waitForCompletion = false
            var noFile = false
            var noFileEncoding: String.Encoding = .utf8
            var fileName: String?
            var cookie = ""
            var headers: [(String, String)] = []
            var parameters: [String] = []
            var parameterInputData: Data?
            var parameterInputFileError: String?
            var parameterEncoding: String.Encoding = .utf8
            var body: String?
            var contentType: String?
            var timeout: TimeInterval?
            var progressNotify = false
            var noCache = false
            var streaming = false

            for argument in arguments {
                let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.hasPrefix("--") else {
                    if !trimmed.isEmpty { positionals.append(trimmed) }
                    continue
                }

                let option = String(trimmed.dropFirst(2))
                let separator = option.firstIndex(of: "=")
                let key = String(option[..<(separator ?? option.endIndex)]).lowercased()
                let value = separator.map { String(option[option.index(after: $0)...]) }

                switch key {
                case "async", "sync":
                    asyncID = value ?? ""
                    waitForCompletion = key == "sync"
                    if let value, value.hasPrefix("On"), !value.isEmpty {
                        customEventID = value
                    }
                case "nofile":
                    noFile = true
                    if let value, !value.isEmpty { noFileEncoding = Self.encoding(for: value) }
                case "file":
                    fileName = value
                case "cookie":
                    cookie = value ?? ""
                case "header":
                    if let pair = value, let header = Self.header(from: pair) { headers.append(header) }
                case "authorization", "accept", "accept-language", "user-agent":
                    if let value { headers.append((key, value)) }
                case "param":
                    if let value { parameters.append(value) }
                case "param-input-file":
                    guard let value, !value.isEmpty else {
                        parameterInputFileError = "missing_path"
                        break
                    }
                    let rawURL = URL(fileURLWithPath: value)
                    let candidate = value.hasPrefix("/")
                        ? rawURL
                        : parameterRoot?.appendingPathComponent(value)
                    guard let candidate else {
                        parameterInputFileError = "missing_parameter_root"
                        break
                    }
                    let normalized = candidate.standardizedFileURL
                    if let parameterRoot {
                        let root = parameterRoot.standardizedFileURL
                        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                        guard normalized.path == root.path || normalized.path.hasPrefix(rootPrefix) else {
                            parameterInputFileError = "path_outside_ghost"
                            break
                        }
                    }
                    do {
                        parameterInputData = try Data(contentsOf: normalized)
                    } catch {
                        parameterInputFileError = "file_not_found"
                    }
                case "param-charset":
                    if let value { parameterEncoding = Self.encoding(for: value) }
                case "body":
                    body = value
                case "content-type":
                    contentType = value
                case "timeout":
                    timeout = value.flatMap(TimeInterval.init).map { min(max($0, 0), 300) }
                case "progress-notify":
                    progressNotify = true
                case "no-cache":
                    noCache = true
                case "streaming":
                    streaming = true
                default:
                    break
                }
            }

            self.positionals = positionals
            self.asyncID = asyncID
            self.customEventID = customEventID
            self.waitForCompletion = waitForCompletion
            self.noFile = noFile
            self.noFileEncoding = noFileEncoding
            self.fileName = fileName
            self.cookie = cookie
            self.headers = headers
            self.parameters = parameters
            self.parameterInputData = parameterInputData
            self.parameterInputFileError = parameterInputFileError
            self.parameterEncoding = parameterEncoding
            self.body = body
            self.contentType = contentType
            self.timeout = timeout
            self.progressNotify = progressNotify
            self.noCache = noCache
            self.streaming = streaming
        }

        private static func header(from raw: String) -> (String, String)? {
            guard let separator = raw.firstIndex(of: ":") else { return nil }
            let key = String(raw[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(raw[raw.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return (key, value)
        }

        private static func encoding(for raw: String) -> String.Encoding {
            switch raw.lowercased().replacingOccurrences(of: "-", with: "_") {
            case "shift_jis", "sjis", "cp932", "windows_31j", "ms932": return .shiftJIS
            case "euc_jp", "eucjp": return .japaneseEUC
            case "utf8", "utf_8": return .utf8
            default: return .utf8
            }
        }
    }


    // MARK: - Ghost Booting via SSTP

    private struct GhostEventInfo {
        let mainName: String
        let ghostName: String
        let path: String
        let shellName: String
    }

    private var currentGhostEventInfo: GhostEventInfo {
        let ghostName = ghostConfig?.name ?? ghostURL.lastPathComponent
        return GhostEventInfo(
            mainName: ghostConfig?.sakuraName ?? ghostName,
            ghostName: ghostName,
            path: ghostURL.path,
            shellName: activeShellName
        )
    }

    private func ghostEventInfo(named name: String) -> GhostEventInfo {
        let item = NarRegistry.shared.installedItems(ofType: "ghost").first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        let fallbackName = item?.name ?? name
        guard let path = item?.path else {
            return GhostEventInfo(
                mainName: fallbackName,
                ghostName: fallbackName,
                path: "",
                shellName: "master"
            )
        }

        let root = path.appendingPathComponent("ghost/master", isDirectory: true)
        let config = GhostConfiguration.load(from: root)
        let ghostName = config?.name ?? fallbackName
        return GhostEventInfo(
            mainName: config?.sakuraName ?? ghostName,
            ghostName: ghostName,
            path: path.path,
            shellName: config?.defaultShellDirectory.isEmpty == false
                ? config?.defaultShellDirectory ?? "master"
                : "master"
        )
    }

    private func notifyOtherGhostBooted(
        target: GhostManager,
        result: GhostBootResult,
        excluding source: GhostManager
    ) {
        let info = target.currentGhostEventInfo
        let params = EventReferenceTable.params(
            forEvent: EventID.OnOtherGhostBooted.rawValue,
            refs: [
                "ghostName": info.mainName,
                "bootScript": result.script,
                "ghostNameSSP": info.ghostName,
                "shellName": result.shellName
            ]
        )
        EventBridge.shared.request(
            .OnOtherGhostBooted,
            params: params,
            excluding: [source, target]
        )
    }

    /// Boot another ghost (\+). 複数ゴースト同時実行に対応: 対象ゴーストを別 GhostManager として
    /// 同時起動する。起動できない場合は従来の SSTP NOTIFY 通知にフォールバックする。
    func bootOtherGhost(
        name: String? = nil,
        bootRequest: GhostBootRequest? = nil,
        completion: ((GhostManager, GhostBootResult) -> Void)? = nil
    ) {
        let installedGhosts = NarRegistry.shared.installedGhosts()
        let currentGhostName = ghostConfig?.name
        let candidates = installedGhosts.filter { $0 != currentGhostName }
        let provided = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ghostName = provided.isEmpty
            ? (candidates.randomElement() ?? currentGhostName ?? "default")
            : provided
        Log.debug("[GhostManager] Attempting to boot ghost: \(ghostName)")

        // 追加ゴーストとして in-process で同時起動する（プライマリは置き換えない）。
        DispatchQueue.main.async {
            if let appDelegate = NSApp.delegate as? AppDelegate,
               appDelegate.launchAdditionalGhost(
                   named: ghostName,
                   bootRequest: bootRequest,
                   completion: { [weak self] target, result in
                       guard result.succeeded else { return }
                       // A call starts a target and is paired with OnGhostCallComplete;
                       // an ordinary \+ boot has no caller.  A switch is a change event,
                       // not an additional boot notification.
                       if result.isNewBoot && bootRequest?.eventID != .OnGhostChanged {
                           self?.notifyOtherGhostBooted(target: target, result: result, excluding: self ?? target)
                       }
                       completion?(target, result)
                   }
               ) != nil {
                return
            }
            // フォールバック: 外部インスタンス向け SSTP 通知
            self.sendSSTPNotify(event: "OnBoot", references: ["Reference0": ghostName])
        }
    }

    /// Boot all ghosts by broadcasting SSTP
    func bootAllGhosts() {
        let installedGhosts = NarRegistry.shared.installedGhosts()
        let currentGhostName = ghostConfig?.name
        let targets = installedGhosts.filter { $0 != currentGhostName }
        Log.debug("[GhostManager] Broadcasting boot command to ghosts: \(targets)")
        if targets.isEmpty {
            sendSSTPNotify(event: "OnBootAll", references: [:])
            return
        }
        for target in targets {
            sendSSTPNotify(event: "OnBoot", references: ["Reference0": target], receiverGhostName: target)
        }
    }

    /// Send an SSTP NOTIFY request used by baseware lifecycle notifications.
    func sendSSTPNotify(event: String, references: [String: String], receiverGhostName: String? = nil) {
        sendSSTPEvent(
            method: "NOTIFY",
            event: event,
            references: references,
            receiverGhostName: receiverGhostName
        )
    }

    private func sendSSTPEvent(
        method: String,
        event: String,
        references: [String: String],
        receiverGhostName: String? = nil,
        completion: ((SSTPEventDeliveryResult) -> Void)? = nil
    ) {
        DispatchQueue.global(qos: .utility).async {
            let request = Self.makeSSTPEventRequest(
                method: method,
                event: event,
                references: references,
                receiverGhostName: receiverGhostName
            )
            let result = self.sendSSTPToLocalhost(
                request: request,
                waitForResponse: completion != nil
            )
            completion?(result)
        }
    }

    static func makeSSTPEventRequest(
        method: String,
        event: String,
        references: [String: String],
        receiverGhostName: String? = nil
    ) -> String {
        var request = "\(method.uppercased()) SSTP/1.1\r\n"
        request += "Sender: Ourin\r\n"
        request += "Event: \(event)\r\n"
        request += "Charset: UTF-8\r\n"
        if let receiverGhostName, !receiverGhostName.isEmpty {
            request += "ReceiverGhostName: \(receiverGhostName)\r\n"
        }

        for (key, value) in references.sorted(by: referenceHeaderSort) {
            request += "\(key): \(value)\r\n"
        }
        request += "\r\n"
        return request
    }

    private static func referenceHeaderSort(
        _ lhs: (key: String, value: String),
        _ rhs: (key: String, value: String)
    ) -> Bool {
        let lhsIndex = Int(lhs.key.dropFirst("Reference".count))
        let rhsIndex = Int(rhs.key.dropFirst("Reference".count))
        if let lhsIndex, let rhsIndex, lhs.key.hasPrefix("Reference"), rhs.key.hasPrefix("Reference") {
            return lhsIndex == rhsIndex ? lhs.key < rhs.key : lhsIndex < rhsIndex
        }
        return lhs.key < rhs.key
    }

    /// `__SYSTEM_ALL_GHOST__` を実際の SSTP ReceiverGhostName へ展開する。
    ///
    /// SSTP は特殊トークン自体を受信先として解決しないため、nil のまま送ると
    /// プライマリゴーストへフォールバックしてしまう。起動中ゴーストが存在しない
    /// 場合は receiver を nil にせず、呼び出し側で notfound として扱える計画を返す。
    static func planOtherGhostTargets(
        _ requestedTargets: [String],
        allGhostNames: [String]
    ) -> [OtherGhostDispatchTarget] {
        var uniqueAllNames: [String] = []
        var seenAllNames = Set<String>()
        for rawName in allGhostNames {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard seenAllNames.insert(name.lowercased()).inserted else { continue }
            uniqueAllNames.append(name)
        }

        var result: [OtherGhostDispatchTarget] = []
        var order = 0
        for requested in requestedTargets {
            if requested.caseInsensitiveCompare("__SYSTEM_ALL_GHOST__") == .orderedSame {
                if uniqueAllNames.isEmpty {
                    result.append(.init(order: order, ghostName: requested, receiverGhostName: nil))
                    order += 1
                } else {
                    for name in uniqueAllNames {
                        result.append(.init(order: order, ghostName: name, receiverGhostName: name))
                        order += 1
                    }
                }
            } else {
                result.append(.init(order: order, ghostName: requested, receiverGhostName: requested))
                order += 1
            }
        }
        return result
    }

    func raiseOtherGhostEvent(ghostSpec: String, event: String, references: [String], notifyOnly: Bool) {
        let requestedTargets = parseGhostTargets(ghostSpec)
        guard !requestedTargets.isEmpty else {
            Log.info("[GhostManager] raiseother/notifyother failed: empty ghost target")
            dispatchOtherGhostEventFailure(
                notifyOnly: notifyOnly,
                failures: [OtherGhostFailure(reason: "notfound", ghostName: ghostSpec)],
                event: event,
                references: references
            )
            return
        }

        let targets = Self.planOtherGhostTargets(
            requestedTargets,
            allGhostNames: EventBridge.shared.runningGhostNames()
        )
        let referenceMap = Dictionary(uniqueKeysWithValues: references.enumerated().map { ("Reference\($0.offset)", $0.element) })
        let dispatchGroup = DispatchGroup()
        let lock = NSLock()
        var failures: [(index: Int, failure: OtherGhostFailure)] = targets.compactMap { target in
            guard target.receiverGhostName == nil else { return nil }
            return (index: target.order, failure: OtherGhostFailure(reason: "notfound", ghostName: target.ghostName))
        }
        let method = notifyOnly ? "NOTIFY" : "SEND"

        for target in targets {
            guard let receiver = target.receiverGhostName else { continue }
            dispatchGroup.enter()
            sendSSTPEvent(
                method: method,
                event: event,
                references: referenceMap,
                receiverGhostName: receiver
            ) { result in
                defer { dispatchGroup.leave() }
                guard let reason = Self.otherGhostFailureReason(for: result) else { return }
                lock.lock()
                failures.append((index: target.order, failure: OtherGhostFailure(reason: reason, ghostName: target.ghostName)))
                lock.unlock()
            }
        }

        dispatchGroup.notify(queue: .global(qos: .utility)) { [weak self] in
            lock.lock()
            let orderedFailures = failures
                .sorted { $0.index < $1.index }
                .map(\.failure)
            lock.unlock()
            guard !orderedFailures.isEmpty else { return }
            self?.dispatchOtherGhostEventFailure(
                notifyOnly: notifyOnly,
                failures: orderedFailures,
                event: event,
                references: references
            )
        }

        let mode = notifyOnly ? "notifyother" : "raiseother"
        Log.debug("[GhostManager] \(mode) dispatched via \(method): event=\(event), targets=\(targets.map(\.ghostName))")
    }

    static func otherGhostFailureReason(for result: SSTPEventDeliveryResult) -> String? {
        switch result {
        case .sent:
            return nil
        case .failure(let reason):
            return reason.isEmpty ? "error" : reason
        case .response(let statusCode, let status):
            if let status {
                let normalizedStatus = status.lowercased()
                let statusTokens = normalizedStatus.split(whereSeparator: { $0 == "," || $0.isWhitespace })
                if statusTokens.contains("timecritical") {
                    return "timecritical"
                }
                if statusTokens.contains("passive") {
                    return "passivemode"
                }
                if statusTokens.contains("induction") {
                    return "inductionmode"
                }
                if statusTokens.contains("minimizing") {
                    return "minimized"
                }
            }
            switch statusCode {
            case 200:
                return nil
            case 404:
                return "notfound"
            case 512:
                return "minimized"
            default:
                return String(statusCode)
            }
        }
    }

    /// `raiseother` / `notifyother` の配送失敗を、発生元ゴーストへGETで通知する。
    /// 複数対象の失敗は仕様どおりバイト値1区切りでReference0/1へ集約する。
    func dispatchOtherGhostEventFailure(
        notifyOnly: Bool,
        failures: [OtherGhostFailure],
        event: String,
        references: [String]
    ) {
        guard !failures.isEmpty else { return }
        let failureEvent: EventID = notifyOnly ? .OnNotifyOtherFailure : .OnRaiseOtherFailure
        let separator = "\u{1}"
        let refs: [String: String] = [
            "reason": failures.map(\.reason).joined(separator: separator),
            "ghostName": failures.map(\.ghostName).joined(separator: separator),
            "event": event
        ].merging(
            Dictionary(uniqueKeysWithValues: references.enumerated().map { ("Reference\($0.offset + 3)", $0.element) })
        ) { _, value in value }
        let params = EventReferenceTable.params(forEvent: failureEvent.rawValue, refs: refs)
        _ = EventBridge.shared.request(failureEvent, params: params, to: self)
    }

    func scheduleTimerRaiseOther(intervalMs: Int, repeatSpec: String, ghostSpec: String, event: String, references: [String], notifyOnly: Bool) {
        let timerKey = remoteEventTimerKey(ghostSpec: ghostSpec, event: event, notifyOnly: notifyOnly)

        DispatchQueue.main.async {
            if let existing = self.remoteEventTimers.removeValue(forKey: timerKey) {
                existing.invalidate()
            }
        }

        guard intervalMs > 0 else {
            Log.debug("[GhostManager] remote timer canceled: key=\(timerKey)")
            return
        }

        let shouldRepeat = isRepeatingTimerSpec(repeatSpec)
        let interval = TimeInterval(intervalMs) / 1000.0

        if shouldRepeat {
            DispatchQueue.main.async {
                let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    self.raiseOtherGhostEvent(ghostSpec: ghostSpec, event: event, references: references, notifyOnly: notifyOnly)
                }
                self.remoteEventTimers[timerKey] = timer
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                self?.raiseOtherGhostEvent(ghostSpec: ghostSpec, event: event, references: references, notifyOnly: notifyOnly)
            }
        }
    }

    private func parseGhostTargets(_ raw: String) -> [String] {
        return raw
            .split(separator: "\u{1}")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func isRepeatingTimerSpec(_ repeatSpec: String) -> Bool {
        if let intValue = Int(repeatSpec.trimmingCharacters(in: .whitespacesAndNewlines)) {
            // ukadoc: 0=repeat, 1以上=one-shot
            return intValue == 0
        }
        let normalized = repeatSpec.lowercased()
        return normalized == "repeat" || normalized == "loop" || normalized == "true" || normalized == "yes"
    }

    private func remoteEventTimerKey(ghostSpec: String, event: String, notifyOnly: Bool) -> String {
        let mode = notifyOnly ? "notifyother" : "raiseother"
        return "\(mode)|\(ghostSpec.lowercased())|\(event.lowercased())"
    }

    private func localEventTimerKey(event: String, notifyOnly: Bool) -> String {
        let mode = notifyOnly ? "timernotify" : "timerraise"
        return "\(mode)|\(event.lowercased())"
    }

    private func pluginEventTimerKey(pluginSpec: String, event: String, notifyOnly: Bool) -> String {
        let mode = notifyOnly ? "timernotifyplugin" : "timerraiseplugin"
        return "\(mode)|\(pluginSpec.lowercased())|\(event.lowercased())"
    }

    private func currentPluginRegistry() -> PluginRegistry? {
        (NSApp.delegate as? AppDelegate)?.pluginRegistry
    }

    func dispatchPluginEvent(pluginSpec: String, event: String, references: [String], notifyOnly: Bool) {
        if let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher {
            if notifyOnly {
                dispatcher.dispatchNotifyPlugin(pluginSpec: pluginSpec, event: event, references: references, callerGhost: self)
                return
            }
            dispatcher.dispatch(pluginSpec: pluginSpec, event: event, references: references, notifyOnly: notifyOnly, callerGhost: self)
            return
        }

        guard let registry = currentPluginRegistry() else {
            Log.info("[GhostManager] Plugin registry unavailable")
            dispatchPluginEventFailure(
                notifyOnly: notifyOnly,
                reason: "notfound",
                plugin: pluginSpec,
                event: event,
                references: references
            )
            return
        }
        let bridge = OurinPluginEventBridge(
            registry: registry,
            runScript: { [weak self] action in
                guard let script = action.script else { return }
                DispatchQueue.main.async {
                    self?.runPluginScript(script, options: action.scriptOptions.union(["plugin-script"]))
                }
            },
            emitEvent: { action in
                guard let eventName = action.eventName else { return false }
                return EventBridge.shared.dispatchPluginResponseEvent(
                    eventName,
                    params: action.references,
                    notifyOnly: action.sendsEventAsNotify,
                    target: action.target,
                    caller: self,
                    scriptOptions: action.scriptOptions
                )
            }
        )
        if notifyOnly {
            bridge.dispatchNotify(
                pluginSpec: pluginSpec,
                event: event,
                references: references,
                onFailure: { [weak self] reason, plugin in
                    self?.dispatchPluginEventFailure(
                        notifyOnly: true,
                        reason: reason,
                        plugin: plugin,
                        event: event,
                        references: references
                    )
                }
            )
            return
        }
        bridge.dispatch(
            pluginSpec: pluginSpec,
            event: event,
            references: references,
            notifyOnly: false,
            onFailure: { [weak self] reason, plugin in
                self?.dispatchPluginEventFailure(
                    notifyOnly: false,
                    reason: reason,
                    plugin: plugin,
                    event: event,
                    references: references
                )
            }
        )
    }

    /// `raiseplugin` / `notifyplugin` が配送できなかったときの SHIORI 失敗イベント。
    /// UKADOC の Reference0～2 と、実行対象イベントの Reference3～を保持する。
    func dispatchPluginEventFailure(
        notifyOnly: Bool,
        reason: String,
        plugin: String,
        event: String,
        references: [String]
    ) {
        let failureEvent: EventID = notifyOnly ? .OnNotifyPluginFailure : .OnRaisePluginFailure
        var refs: [String: String] = [
            "reason": reason.isEmpty ? "error" : reason,
            "plugin": plugin,
            "event": event
        ]
        for (index, reference) in references.enumerated() {
            refs["Reference\(index + 3)"] = reference
        }
        let params = EventReferenceTable.params(forEvent: failureEvent.rawValue, refs: refs)
        _ = EventBridge.shared.request(failureEvent, params: params, to: self)
    }

    func scheduleTimerPluginEvent(intervalMs: Int, repeatSpec: String, pluginSpec: String, event: String, references: [String], notifyOnly: Bool) {
        let timerKey = pluginEventTimerKey(pluginSpec: pluginSpec, event: event, notifyOnly: notifyOnly)
        DispatchQueue.main.async {
            if let existing = self.pluginEventTimers.removeValue(forKey: timerKey) {
                existing.invalidate()
            }
            guard intervalMs > 0 else {
                Log.debug("[GhostManager] plugin timer canceled: key=\(timerKey)")
                return
            }
            let shouldRepeat = self.isRepeatingTimerSpec(repeatSpec)
            let interval = TimeInterval(intervalMs) / 1000.0
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: shouldRepeat) { [weak self] _ in
                guard let self else { return }
                self.dispatchPluginEvent(pluginSpec: pluginSpec, event: event, references: references, notifyOnly: notifyOnly)
                if !shouldRepeat {
                    self.pluginEventTimers.removeValue(forKey: timerKey)
                }
            }
            self.pluginEventTimers[timerKey] = timer
        }
    }
    
    /// Send SSTP request to localhost. 失敗通知が必要な呼び出しだけ応答を待つ。
    @discardableResult
    func sendSSTPToLocalhost(request: String, waitForResponse: Bool = false) -> SSTPEventDeliveryResult {
        let host = "127.0.0.1"
        let port = 9801

        var sock: Int32 = -1
        var hints = addrinfo()
        var result: UnsafeMutablePointer<addrinfo>?
        
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        
        let portString = String(port)
        guard getaddrinfo(host, portString, &hints, &result) == 0 else {
            Log.info("[GhostManager] Failed to resolve SSTP host: \(host):\(port)")
            return .failure(reason: "error")
        }
        
        defer {
            if let result = result {
                freeaddrinfo(result)
            }
            if sock >= 0 {
                close(sock)
            }
        }
        
        guard let addr = result else {
            Log.info("[GhostManager] No address info for SSTP")
            return .failure(reason: "error")
        }
        
        sock = socket(addr.pointee.ai_family, addr.pointee.ai_socktype, addr.pointee.ai_protocol)
        guard sock >= 0 else {
            Log.info("[GhostManager] Failed to create socket for SSTP")
            return .failure(reason: "error")
        }
        
        // Set timeout
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        guard connect(sock, addr.pointee.ai_addr, addr.pointee.ai_addrlen) >= 0 else {
            Log.debug("[GhostManager] No SSTP server at \(host):\(port) - this is normal if no other ghosts are running")
            return .failure(reason: "notfound")
        }
        
        // Send request
        let data = request.data(using: .utf8) ?? Data()
        guard !data.isEmpty else {
            Log.info("[GhostManager] Failed to encode SSTP request")
            return .failure(reason: "error")
        }
        let sent = data.withUnsafeBytes { ptr -> Int in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            var total = 0
            while total < data.count {
                let count = send(sock, baseAddress.advanced(by: total), data.count - total, 0)
                guard count > 0 else { return -1 }
                total += count
            }
            return total
        }
        guard sent == data.count else {
            Log.info("[GhostManager] Failed to send SSTP request")
            return .failure(reason: "error")
        }
        Log.debug("[GhostManager] Sent SSTP request to \(host):\(port)")
        guard waitForResponse else { return .sent }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while response.count <= 64 * 1024 {
            let received = buffer.withUnsafeMutableBytes { ptr -> Int in
                guard let baseAddress = ptr.baseAddress else { return -1 }
                return recv(sock, baseAddress, ptr.count, 0)
            }
            if received > 0 {
                response.append(contentsOf: buffer.prefix(received))
                if response.range(of: Data([13, 10, 13, 10])) != nil
                    || response.range(of: Data([10, 10])) != nil {
                    break
                }
                continue
            }
            if received == 0 { break }
            Log.info("[GhostManager] Failed to receive SSTP response")
            return .failure(reason: "error")
        }

        guard let parsedResponse = Self.parseSSTPResponse(from: response) else {
            Log.info("[GhostManager] Invalid SSTP response")
            return .failure(reason: "error")
        }
        return .response(statusCode: parsedResponse.statusCode, status: parsedResponse.status)
    }

    static func parseSSTPStatusCode(from data: Data) -> Int? {
        parseSSTPResponse(from: data)?.statusCode
    }

    static func parseSSTPResponse(from data: Data) -> ParsedSSTPResponse? {
        let text = String(decoding: data, as: UTF8.self)
        // `String` treats CRLF as one extended grapheme cluster, so comparing
        // characters with `"\r"`/`"\n"` misses standard SSTP line endings.
        let lines = text.split(whereSeparator: { $0.isNewline })
        guard let firstLine = lines.first else {
            return nil
        }
        let parts = firstLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard parts.count >= 2,
              parts[0].uppercased().hasPrefix("SSTP/"),
              let statusCode = Int(parts[1]) else {
            return nil
        }
        let status = lines.dropFirst().compactMap { line -> String? in
            guard let separator = line.firstIndex(of: ":"),
                  String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "status" else {
                return nil
            }
            return String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.first
        return ParsedSSTPResponse(statusCode: statusCode, status: status)
    }
    
    // MARK: - Choice Command Support
    
    // Choice state and type are defined on GhostManager (main file)
    
    /// Handle choice command - \q[title,ID] or variants
    func handleChoiceCommand(args: [String]) {
        guard args.count >= 2 else {
            Log.info("[GhostManager] Invalid choice command: insufficient arguments")
            return
        }
        
        let title = args[0]
        let idOrScript = args[1]
        
        // Check if this is a script: format
        if idOrScript.hasPrefix("script:") {
            let script = String(idOrScript.dropFirst(7)) // Remove "script:" prefix
            Log.debug("[GhostManager] Choice '\(title)' will execute script: \(script)")
            pendingChoices.append((title: title, action: .script(script), pluginOrigin: currentScriptIsPluginOrigin))
        } else {
            // Event ID format
            let eventID = idOrScript
            let references = Array(args.dropFirst(2))
            Log.debug("[GhostManager] Choice '\(title)' will trigger event: \(eventID) with refs: \(references)")
            pendingChoices.append((title: title, action: .event(id: eventID, references: references), pluginOrigin: currentScriptIsPluginOrigin))
        }
    }

    /// Execute an embedded event and inline its script result.
    /// ukadoc: \![embed,event,ref0,ref1,...]
    func executeEmbeddedEvent(event: String, references: [String]) {
        guard let response = shioriRuntime?.request(method: "GET", id: event, refs: references, timeout: 4.0),
              response.ok,
              let script = response.value,
              !script.isEmpty else {
            Log.info("[GhostManager] embed event failed or returned empty: \(event)")
            return
        }

        guard !Self.shouldIgnoreNumericEventResponse(script, eventID: event) else {
            Log.info("[GhostManager] Ignoring numeric embedded event response: event=\(event) value=\(script.trimmingCharacters(in: .whitespacesAndNewlines))")
            return
        }

        let embeddedTokens = sakuraEngine.parse(script: script)
        for token in embeddedTokens {
            sakuraEngine(sakuraEngine, didEmit: token)
        }
    }

    func dispatchLocalEvent(
        event: String,
        references: [String],
        notifyOnly: Bool,
        preserveFollowingPlayback: Bool = false
    ) {
        guard !event.isEmpty else { return }

        // スクリプト由来のイベントは実行元ゴーストだけへ送る。EventBridge は
        // システムイベントの全ゴースト配信路なので、ここへ流すと別ゴーストまで
        // raise/notify を受け取ってしまう。
        if let runtime = shioriRuntime {
            let method = notifyOnly ? "NOTIFY" : "GET"
            let headers = ["Charset": "UTF-8", "Sender": "Ourin", "SecurityLevel": "local"]
            let response = runtime.request(
                method: method,
                id: event,
                headers: headers,
                refs: references,
                timeout: notifyOnly ? 2.0 : 4.0
            )
            guard !notifyOnly,
                  let response,
                  response.ok,
                  let script = response.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !script.isEmpty else { return }
            if preserveFollowingPlayback {
                // SakuraScript の `raise` は再生位置で発火するが、同じスクリプトに
                // 後続タグがある場合は、そのタグをイベント応答の初期化で捨てない。
                // 応答スクリプトを先に再生し、保存した後続キューをその後へ戻す。
                let followingPlayback = playbackQueue
                playbackQueue.removeAll()
                runScript(
                    script,
                    translationContext: .init(eventID: event, references: references)
                )
                let responsePlayback = playbackQueue
                playbackQueue = responsePlayback + followingPlayback
            } else {
                runScript(
                    script,
                    translationContext: .init(eventID: event, references: references)
                )
            }
            return
        }

        let params = Dictionary(uniqueKeysWithValues: references.enumerated().map { ("Reference\($0.offset)", $0.element) })
        if notifyOnly {
            EventBridge.shared.notifyCustom(event, params: params, to: self, ignoreResponseScript: true)
            return
        }
        if let eventID = EventID(rawValue: event) {
            // `raise` は GET。SHIORI の返答スクリプトを再生する。
            _ = EventBridge.shared.request(eventID, params: params, to: self)
        } else {
            // EventID にないカスタム名も raise では GET として実行する。
            _ = EventBridge.shared.requestCustom(event, params: params, to: self)
        }
    }

    /// Schedule delayed local event dispatch.
    /// ukadoc: \![timerraise|timernotify,ms,repeat,event,ref0,ref1,...]
    func scheduleLocalEventTimer(intervalMs: Int, repeatSpec: String, event: String, references: [String], notifyOnly: Bool) {
        let timerKey = localEventTimerKey(event: event, notifyOnly: notifyOnly)

        DispatchQueue.main.async {
            if let existing = self.localEventTimers.removeValue(forKey: timerKey) {
                existing.invalidate()
            }

            guard intervalMs > 0 else {
                Log.debug("[GhostManager] local timer canceled: key=\(timerKey)")
                return
            }

            let shouldRepeat = self.isRepeatingTimerSpec(repeatSpec)
            let interval = TimeInterval(intervalMs) / 1000.0
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: shouldRepeat) { [weak self] _ in
                guard let self else { return }
                self.dispatchLocalEvent(event: event, references: references, notifyOnly: notifyOnly)
                if !shouldRepeat {
                    self.localEventTimers.removeValue(forKey: timerKey)
                }
            }
            self.localEventTimers[timerKey] = timer
        }
    }
    
    /// Display choice dialog when choices are ready
    /// 選択肢/アンカー選択イベントを、登録済みプラグインへも横流しする（PLUGIN_EVENT/2.0M）。
    /// EventBridge への notifyCustom と並行して PluginEventDispatcher.onArbitraryEvent を呼ぶ。
    func forwardEventToPlugins(id: String, references: [String], notify: Bool = false) {
        guard let dispatcher = (NSApp.delegate as? AppDelegate)?.pluginDispatcher else { return }
        dispatcher.onArbitraryEvent(id: id, refs: references, notify: notify)
    }

    /// `\f[cursor*]` の指定を NSAlert の実ボタンへ反映する。
    /// macOS の標準 hover/highlight は NSAlert 側に任せ、文字色・下線・枠・塗りを
    /// ゴースト指定から設定することで、指定を無視せず選択 UI に伝える。
    private func applyChoiceButtonAppearance(_ buttons: [NSButton], viewModel vm: BalloonViewModel) {
        for button in buttons {
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: vm.cursorFontColor
            ]
            if vm.cursorStyle == .underline || vm.cursorStyle == .squareUnderline {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = vm.cursorPenColor
            }
            button.attributedTitle = NSAttributedString(string: button.title, attributes: attributes)
            button.contentTintColor = vm.cursorFontColor
            button.wantsLayer = true
            switch vm.cursorStyle {
            case .square, .squareUnderline:
                button.bezelStyle = .rounded
                button.layer?.borderWidth = 1
                button.layer?.borderColor = vm.cursorPenColor.cgColor
                button.layer?.backgroundColor = vm.cursorBrushColor.cgColor
            case .underline:
                button.bezelStyle = .regularSquare
                button.layer?.borderWidth = 0
                button.layer?.backgroundColor = NSColor.clear.cgColor
            case .none:
                button.bezelStyle = .regularSquare
                button.layer?.borderWidth = 0
                button.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }

    private func choiceEventReferences(for choice: (title: String, action: ChoiceAction, pluginOrigin: Bool)) -> [String] {
        switch choice.action {
        case .event(let id, let references):
            return [choice.title, id] + references
        case .script:
            return [choice.title, ""]
        }
    }

    private func choiceButtonIndex(atWindowPoint point: NSPoint, alert: NSAlert) -> Int? {
        alert.buttons.firstIndex { button in
            let pointInButton = button.convert(point, from: nil)
            return button.bounds.contains(pointInButton)
        }
    }

    func showChoiceDialog() {
        guard !pendingChoices.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("選択してください", comment: "Please choose")
            alert.alertStyle = .informational
            
            // Add choice buttons in order
            for choice in self.pendingChoices {
                alert.addButton(withTitle: choice.title)
            }
            
            // Add cancel button if \z was present
            if self.choiceHasCancelOption {
                alert.addButton(withTitle: NSLocalizedString("キャンセル", comment: "Cancel"))
            }
            let choiceViewModel = self.balloonViewModels[self.currentScope] ?? self.getBalloonVM(for: self.currentScope)
            self.applyChoiceButtonAppearance(alert.buttons, viewModel: choiceViewModel)

            // NSAlert は NSButton の subclass 差し替えを公開していないため、ローカルな
            // mouseMoved monitor で実ボタンの境界を判定する。これにより選択肢の入場・退場
            // と静止（500ms）を、表示時の一括通知ではなく実際のポインタ状態から発火する。
            var hoveredChoiceIndex: Int?
            var hoverTimer: Timer?
            var initialHoverTimer: Timer?
            var eventMonitor: Any?

            let updateHover: (Int?) -> Void = { [weak self] nextIndex in
                guard let self else { return }
                guard nextIndex != hoveredChoiceIndex else { return }

                hoverTimer?.invalidate()
                hoverTimer = nil

                if hoveredChoiceIndex != nil {
                    // UKADOC: 選択肢から外れた OnChoiceEnter は Reference なし。
                    _ = self.requestDialogEvent(eventID: "OnChoiceEnter", references: [])
                }

                hoveredChoiceIndex = nextIndex
                guard let nextIndex,
                      nextIndex >= 0,
                      nextIndex < self.pendingChoices.count else { return }

                let choice = self.pendingChoices[nextIndex]
                _ = self.requestDialogEvent(
                    eventID: "OnChoiceEnter",
                    references: self.choiceEventReferences(for: choice)
                )

                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                    guard let self,
                          hoveredChoiceIndex == nextIndex,
                          nextIndex < self.pendingChoices.count else { return }
                    _ = self.requestDialogEvent(
                        eventID: "OnChoiceHover",
                        references: self.choiceEventReferences(for: self.pendingChoices[nextIndex])
                    )
                }
            }

            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self, weak alert] event in
                guard let self,
                      let alert,
                      alert.window.isVisible else { return event }
                updateHover(self.choiceButtonIndex(atWindowPoint: event.locationInWindow, alert: alert))
                return event
            }

            // Handle timeout if specified
            var timeoutTimer: Timer? = nil
            var didTimeout = false
            if let timeout = self.choiceTimeout, timeout > 0 {
                let startTime = Date()
                alert.informativeText = String(format: NSLocalizedString("残り時間: %.0f秒", comment: "time remaining"), timeout)
                
                timeoutTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                    let elapsed = Date().timeIntervalSince(startTime)
                    let remaining = max(0, timeout - elapsed)
                    
                    if remaining <= 0 {
                        timer.invalidate()
                        didTimeout = true
                        NSApp.abortModal()
                    } else {
                        alert.informativeText = String(format: NSLocalizedString("残り時間: %.0f秒", comment: "time remaining"), remaining)
                    }
                }
            }

            // The pointer may already be over a button when the modal window opens, so do one
            // initial hit test after the nested modal run loop has become active.
            initialHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: false) { [weak self, weak alert] _ in
                guard let self,
                      let alert else { return }
                updateHover(self.choiceButtonIndex(atWindowPoint: alert.window.mouseLocationOutsideOfEventStream, alert: alert))
            }
            
            // Show dialog
            let response = alert.runModal()
            timeoutTimer?.invalidate()
            initialHoverTimer?.invalidate()
            hoverTimer?.invalidate()
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
            }
            if hoveredChoiceIndex != nil {
                // Modal window close is also a pointer exit from the active choice.
                _ = self.requestDialogEvent(eventID: "OnChoiceEnter", references: [])
                hoveredChoiceIndex = nil
            }

            // Process response
            let buttonIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

            if didTimeout {
                // OnChoiceTimeout: Reference0 = タイムアウトしたスクリプト（UKADOC）。
                // 通常は実行元スクリプトを渡し、古い生成経路で保持できない場合は
                // 現在表示中の本文をフォールバックにする。
                let sourceScript = self.choiceSourceScript.isEmpty
                    ? self.getBalloonVM(for: self.currentScope).text
                    : self.choiceSourceScript
                _ = self.requestDialogEvent(eventID: "OnChoiceTimeout", references: [sourceScript])
            } else if buttonIndex >= 0 && buttonIndex < self.pendingChoices.count {
                // User selected a choice
                let choice = self.pendingChoices[buttonIndex]

                switch Self.choiceSelectionDispatch(title: choice.title, action: choice.action) {
                case .directEvent(let id, let references):
                    // \q[title,OnID,r0,...] は指定イベントだけを直接発火する。
                    _ = self.requestDialogEvent(eventID: id, references: references)
                    if choice.pluginOrigin {
                        self.forwardEventToPlugins(id: id, references: references)
                    }

                case .choiceEvents(let label, let choiceID, let extendedReferences):
                    // UKADOC: 通常の選択肢は OnChoiceSelectEx を先に発火し、続いて
                    // OnChoiceSelect を発火する。choiceID 自体を GET する仕様ではない。
                    let selectExReferences = [label, choiceID] + extendedReferences
                    _ = self.requestDialogEvent(
                        eventID: "OnChoiceSelectEx",
                        references: selectExReferences
                    )
                    _ = self.requestDialogEvent(eventID: "OnChoiceSelect", references: [choiceID])

                    if choice.pluginOrigin {
                        self.forwardEventToPlugins(id: "OnChoiceSelectEx", references: selectExReferences)
                        self.forwardEventToPlugins(id: "OnChoiceSelect", references: [choiceID])
                    }

                case .script(let script):
                    // \q[title,script:...] は SHIORI イベントを発火せず、インライン
                    // SakuraScript だけを実行する。
                    self.sakuraEngine.run(script: script)
                }
            } else {
                // Cancel was selected
                if let response = self.shioriRuntime?.request(method: "GET", id: "OnChoiceCancel", timeout: 4.0), response.ok {
                    if let script = response.value {
                        self.runScript(
                            script,
                            translationContext: .init(eventID: "OnChoiceCancel")
                        )
                    }
                }
            }

            // Clear choice state
            self.pendingChoices.removeAll()
            self.choiceHasCancelOption = false
        }
    }
    
    // MARK: - System Commands Implementation

    private func wallpaperScreenKey(_ screen: NSScreen) -> String {
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return "display:\(number.uint32Value)"
        }
        return "screen:\(screen.localizedName):\(screen.frame.origin.x):\(screen.frame.origin.y)"
    }

    /// Save the current desktop wallpaper for every connected screen.
    func saveWallpaper() {
        DispatchQueue.main.async {
            let workspace = NSWorkspace.shared
            self.savedWallpaperURLs = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                guard let url = workspace.desktopImageURL(for: screen) else { return nil }
                return (self.wallpaperScreenKey(screen), url)
            })
            Log.debug("[GhostManager] Saved wallpapers for \(self.savedWallpaperURLs.count) screen(s)")
        }
    }

    /// Restore the wallpaper URLs saved by `save,wallpaper`.
    func restoreWallpaper() {
        DispatchQueue.main.async {
            guard !self.savedWallpaperURLs.isEmpty else {
                Log.info("[GhostManager] No saved wallpaper to restore")
                return
            }
            let workspace = NSWorkspace.shared
            for screen in NSScreen.screens {
                guard let url = self.savedWallpaperURLs[self.wallpaperScreenKey(screen)] else { continue }
                do {
                    try workspace.setDesktopImageURL(url, for: screen, options: [:])
                } catch {
                    Log.info("[GhostManager] Failed to restore wallpaper on \(screen.localizedName): \(error)")
                }
            }
            Log.debug("[GhostManager] Restored saved wallpapers")
        }
    }
    
    /// ゴースト相対のファイル指定を解決する。SSP互換として ghost 本体直下と
    /// ghost/master の両方を許容し、絶対パスはそのまま扱う。
    private func resolveGhostAssetPath(_ filename: String) -> URL {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        let candidates = [
            ghostURL.appendingPathComponent(trimmed),
            ghostURL.appendingPathComponent("ghost/master", isDirectory: true).appendingPathComponent(trimmed)
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) ?? candidates[0]
    }

    /// `set,wallpaper` のオプションを NSWorkspace の実際のデスクトップ画像設定へ変換する。
    private func wallpaperOptions(_ rawOptions: [String]) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        let options = rawOptions
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let mode = options.first ?? "center"
        let scaling: NSImageScaling
        let allowClipping: Bool
        switch mode {
        case "tile":
            scaling = .scaleNone
            allowClipping = false
        case "stretch":
            scaling = .scaleAxesIndependently
            allowClipping = false
        case "stretch-x", "stretch-y":
            // NSWorkspace は片軸指定を持たないため、縦横比維持＋画面内収容へ寄せる。
            scaling = .scaleProportionallyUpOrDown
            allowClipping = false
        case "span":
            // マルチモニタ全体への一枚画像指定は macOS API に相当 API がないため、
            // 呼び出し側で各画面へ同じ画像を設定し、比例拡大＋クリップで意味を保つ。
            scaling = .scaleProportionallyUpOrDown
            allowClipping = true
        default:
            scaling = .scaleProportionallyUpOrDown
            allowClipping = false
        }
        return [
            .imageScaling: NSNumber(value: scaling.rawValue),
            .allowClipping: NSNumber(value: allowClipping)
        ]
    }

    /// Set desktop wallpaper. Empty filename restores the snapshot captured by `save,wallpaper`.
    func setWallpaper(filename: String, options rawOptions: [String] = []) {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            restoreWallpaper()
            return
        }
        let wallpaperURL = resolveGhostAssetPath(trimmed)
        guard FileManager.default.fileExists(atPath: wallpaperURL.path) else {
            Log.info("[GhostManager] Wallpaper file not found: \(filename)")
            EventBridge.shared.notifyCustom("OnWallpaperFailure", refs: ["filename": filename, "reason": "file_not_found"])
            return
        }

        DispatchQueue.main.async {
            let workspace = NSWorkspace.shared
            let options = self.wallpaperOptions(rawOptions)
            let targets = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
            var failed = false
            for screen in targets {
                do {
                    try workspace.setDesktopImageURL(wallpaperURL, for: screen, options: options)
                } catch {
                    failed = true
                    Log.info("[GhostManager] Failed to set wallpaper on \(screen.localizedName): \(error)")
                }
            }
            if failed {
                EventBridge.shared.notifyCustom("OnWallpaperFailure", refs: ["filename": filename, "reason": "set_failed"])
            } else {
                // UKADOC: 標準イベント名は OnWallpaperChange、Reference0 は変更後のファイルパス。
                EventBridge.shared.notify(.OnWallpaperChange, refs: ["filePath": wallpaperURL.path])
                Log.debug("[GhostManager] Set wallpaper: \(filename) (options=\(rawOptions))")
            }
        }
    }

    private func taskTrayAnimationURLs(baseURL: URL) -> [URL] {
        guard !baseURL.pathExtension.isEmpty else { return [baseURL] }
        var frames: [URL] = []
        let stem = baseURL.deletingPathExtension().path
        let ext = baseURL.pathExtension
        for index in 0..<1000 {
            let candidate = URL(fileURLWithPath: "\(stem)\(String(format: "%02d", index)).\(ext)")
            guard FileManager.default.fileExists(atPath: candidate.path) else { break }
            frames.append(candidate)
        }
        return frames.isEmpty ? [baseURL] : frames
    }

    /// Set task-tray/menu-bar icon. This is deliberately separate from the Dock app icon.
    func setTaskTrayIcon(filename: String, text: String, options rawOptions: [String] = []) {
        let iconURL = resolveGhostAssetPath(filename)
        let parsed = parseCommandArguments(rawOptions)
        let durationMs = parsed.options["duration"].flatMap(Int.init).map { max(1, $0) }
        let runCount = parsed.options["runcount"].flatMap(Int.init).map { max(0, $0) }
        let frames = durationMs == nil ? [iconURL] : taskTrayAnimationURLs(baseURL: iconURL)
        let tooltip = text.isEmpty
            ? "Ourin/\(ghostConfig?.name ?? ghostURL.lastPathComponent)"
            : text

        DispatchQueue.main.async {
            guard let firstImage = NSImage(contentsOf: frames[0]) else {
                Log.info("[GhostManager] Failed to load task-tray icon: \(filename)")
                return
            }
            let statusItem = self.taskTrayStatusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            self.taskTrayStatusItem = statusItem
            statusItem.button?.image = firstImage
            statusItem.button?.image?.size = NSSize(width: 18, height: 18)
            statusItem.button?.toolTip = tooltip
            statusItem.button?.setAccessibilityLabel(tooltip)

            self.taskTrayAnimationTimer?.invalidate()
            self.taskTrayAnimationTimer = nil
            guard let durationMs, frames.count > 1 else {
                Log.debug("[GhostManager] Set task-tray icon: \(filename)")
                return
            }

            var frameIndex = 0
            var completedLoops = 0
            let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(durationMs) / 1000.0, repeats: true) { [weak self, weak statusItem] timer in
                guard let self, let button = statusItem?.button else {
                    timer.invalidate()
                    return
                }
                frameIndex += 1
                if frameIndex >= frames.count {
                    frameIndex = 0
                    completedLoops += 1
                    if let runCount, runCount > 0, completedLoops >= runCount {
                        timer.invalidate()
                        self.taskTrayAnimationTimer = nil
                        return
                    }
                }
                if let image = NSImage(contentsOf: frames[frameIndex]) {
                    button.image = image
                    button.image?.size = NSSize(width: 18, height: 18)
                }
            }
            self.taskTrayAnimationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    /// Set tray balloon (notification)
    func setTrayBalloon(options: [String]) {
        // Parse options like title=..., message=..., icon=...
        var title = "Ourin"
        var message = ""
        var sound = true
        var timeoutSeconds: Double = 5
        
        for option in options {
            let parts = option.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].lowercased()
                let value = String(parts[1])
                switch key {
                case "title": title = value
                case "message", "text": message = value
                case "sound": sound = value.lowercased() != "false"
                case "timeout", "time":
                    if let raw = Double(value) {
                        timeoutSeconds = raw > 1000 ? raw / 1000.0 : raw
                    }
                default: break
                }
            } else {
                // If no key, assume it's the message
                if message.isEmpty {
                    message = option
                }
            }
        }
        
        DispatchQueue.main.async {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            if sound {
                content.sound = .default
            }
            content.userInfo = [
                "ourinTrayBalloon": "1",
                "title": title,
                "message": message
            ]

            let identifier = "ourin.tray.\(UUID().uuidString)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    Log.info("[GhostManager] Failed to deliver notification: \(error)")
                } else {
                    Log.debug("[GhostManager] Delivered notification: \(title) - \(message)")
                }
            }

            if timeoutSeconds > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds) {
                    EventBridge.shared.notify(.OnTrayBalloonTimeout, refs: [
                        "identifier": identifier,
                        "title": title
                    ])
                }
            }
        }
    }
    
    /// Set other ghost talk mode
    func setOtherGhostTalk(mode: String) {
        let normalized = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed: Set<String> = ["true", "false", "before", "after"]
        guard allowed.contains(normalized) else {
            Log.info("[GhostManager] Invalid other ghost talk mode: \(mode)")
            return
        }
        UserDefaults.standard.set(normalized, forKey: "OurinOtherGhostTalkMode")
        Log.debug("[GhostManager] Set other ghost talk mode: \(normalized)")
    }
    
    /// Set whether to observe other ghosts' surface changes
    func setOtherSurfaceChange(enabled: Bool) {
        observesOtherSurfaceChange = enabled
        UserDefaults.standard.set(enabled, forKey: "OurinObserveOtherSurfaceChange")
        Log.debug("[GhostManager] Set other surface change observation: \(enabled)")
    }
    
    /// Execute an actual SNTP time query (`\7` / `\![executesntp]`).
    func executeSNTP() {
        executeSNTP(requestCorrection: false)
    }

    private func executeSNTP(requestCorrection: Bool) {
        let configuredServer = UserDefaults.standard.string(forKey: "OurinSNTPServer")
        let server = configuredServer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? configuredServer!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "pool.ntp.org"

        Log.debug("[GhostManager] Executing SNTP time synchronization: \(server)")
        pendingSntpCorrection = requestCorrection
        lastSntpServerDate = nil
        lastSntpServerDateTime = nil
        lastSntpTimezone = nil
        lastSntpMeasurement = nil
        lastSntpServer = nil
        _ = EventBridge.shared.request(.OnSNTPBegin, refs: ["server": server], to: self)

        SNTPClient().query(server: server) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let measurement):
                _ = self.processSNTPMeasurement(measurement)

            case .failure(let error):
                self.lastSntpServerDate = nil
                self.lastSntpServerDateTime = nil
                self.lastSntpTimezone = nil
                self.lastSntpMeasurement = nil
                self.lastSntpServer = nil
                self.pendingSntpCorrection = false
                Log.info("[GhostManager] SNTP query failed: \(error)")
                Log.info("[GhostManager] SNTP failure reason: \(self.normalizeSNTPFailureReason(error))")
                _ = EventBridge.shared.request(.OnSNTPFailure, refs: ["server": server], to: self)
            }
        }
    }

    /// SNTP 応答を保存し、比較イベントと必要な補正イベントを発火する。
    @discardableResult
    func processSNTPMeasurement(
        _ measurement: SNTPMeasurement,
        clockAdjuster: @escaping SNTPClockAdjuster.Setter = SNTPClockAdjuster.adjust(to:)
    ) -> Bool {
        let server = measurement.server
        let serverTimeEx = sntpDateString(measurement.serverDate, includeMilliseconds: true)
        let localTimeEx = sntpDateString(measurement.localDate, includeMilliseconds: true)
        let serverTime = sntpDateString(measurement.serverDate, includeMilliseconds: false)
        let localTime = sntpDateString(measurement.localDate, includeMilliseconds: false)
        let signedSeconds = String(format: "%.3f", measurement.offset)
        let absoluteSeconds = String(format: "%.0f", abs(measurement.offset))
        let signedMilliseconds = String(measurement.offsetMilliseconds)
        let absoluteMilliseconds = String(abs(measurement.offsetMilliseconds))

        lastSntpServerDate = measurement.serverDate
        lastSntpServerDateTime = serverTimeEx
        lastSntpTimezone = TimeZone.current.identifier
        lastSntpMeasurement = measurement
        lastSntpServer = server
        let compareRefs = [
            "server": server,
            "serverTime": serverTime,
            "localTime": localTime,
            "deltaSeconds": absoluteSeconds,
            "deltaMilliseconds": absoluteMilliseconds
        ]
        let compareExRefs = [
            "server": server,
            "serverTime": serverTimeEx,
            "localTime": localTimeEx,
            "deltaSeconds": signedSeconds,
            "deltaMilliseconds": signedMilliseconds
        ]
        _ = requestSNTPEventWithLegacyFallback(
            extended: .OnSNTPCompareEx,
            legacy: .OnSNTPCompare,
            extendedRefs: compareExRefs,
            legacyRefs: compareRefs
        )
        Log.debug("[GhostManager] SNTP query succeeded: offset=\(signedMilliseconds)ms")

        guard pendingSntpCorrection else { return false }
        pendingSntpCorrection = false

        let localDate = Date()
        let elapsed = max(0, localDate.timeIntervalSince(measurement.localDate))
        let targetDate = measurement.serverDate.addingTimeInterval(elapsed)
        return applySNTPCorrection(
            server: server,
            serverDate: targetDate,
            localDate: localDate,
            clockAdjuster: clockAdjuster
        )
    }

    /// Execute SNTP correction action for `\6`.
    @discardableResult
    func executeSNTPApply(
        clockAdjuster: @escaping SNTPClockAdjuster.Setter = SNTPClockAdjuster.adjust(to:)
    ) -> Bool {
        guard let serverDate = lastSntpServerDate else {
            Log.info("[GhostManager] SNTP apply requested without cached server time; starting sync first")
            executeSNTP(requestCorrection: true)
            return false
        }

        let localDate = Date()
        let measurement = lastSntpMeasurement
        let elapsed = measurement.map { max(0, localDate.timeIntervalSince($0.localDate)) } ?? 0
        let targetDate = measurement.map {
            $0.serverDate.addingTimeInterval(elapsed)
        } ?? serverDate
        let server = lastSntpServer ?? configuredSNTPServer()
        pendingSntpCorrection = false
        return applySNTPCorrection(
            server: server,
            serverDate: targetDate,
            localDate: localDate,
            clockAdjuster: clockAdjuster
        )
    }

    @discardableResult
    private func applySNTPCorrection(
        server: String,
        serverDate: Date,
        localDate: Date,
        clockAdjuster: @escaping SNTPClockAdjuster.Setter
    ) -> Bool {
        let delta = serverDate.timeIntervalSince(localDate)
        let correctionRefs = [
            "server": server,
            "serverTime": sntpDateString(serverDate, includeMilliseconds: false),
            "localTime": sntpDateString(localDate, includeMilliseconds: false),
            "deltaSeconds": String(format: "%.0f", abs(delta)),
            "deltaMilliseconds": String(abs(Int((delta * 1_000).rounded())))
        ]
        let correctionExRefs = [
            "server": server,
            "serverTime": sntpDateString(serverDate, includeMilliseconds: true),
            "localTime": sntpDateString(localDate, includeMilliseconds: true),
            "deltaSeconds": String(format: "%.3f", delta),
            "deltaMilliseconds": String(Int((delta * 1_000).rounded()))
        ]

        switch clockAdjuster(serverDate) {
        case .success:
            _ = requestSNTPEventWithLegacyFallback(
                extended: .OnSNTPCorrectEx,
                legacy: .OnSNTPCorrect,
                extendedRefs: correctionExRefs,
                legacyRefs: correctionRefs
            )
            Log.info("[GhostManager] SNTP correction succeeded: deltaMs=\(correctionExRefs["deltaMilliseconds"] ?? "0")")
            return true
        case .failure(let error):
            Log.info("[GhostManager] SNTP correction failed: \(error)")
            _ = EventBridge.shared.request(.OnSNTPFailure, refs: ["server": server], to: self)
            return false
        }
    }

    /// SSPの拡張イベントを優先し、応答が無い場合だけ旧イベントへフォールバックする。
    /// Ex/無印を両方実行すると、無印だけを実装するゴーストと拡張対応ゴーストの双方で
    /// 応答スクリプトが二重に再生されるため、GETの応答有無で分岐する。
    @discardableResult
    private func requestSNTPEventWithLegacyFallback(
        extended: EventID,
        legacy: EventID,
        extendedRefs: [String: String],
        legacyRefs: [String: String]
    ) -> Bool {
        if EventBridge.shared.request(extended, refs: extendedRefs, to: self) {
            return true
        }
        return EventBridge.shared.request(legacy, refs: legacyRefs, to: self)
    }

    private func configuredSNTPServer() -> String {
        let configuredServer = UserDefaults.standard.string(forKey: "OurinSNTPServer")
        return configuredServer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? configuredServer!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "pool.ntp.org"
    }

    private func sntpDateString(_ date: Date, includeMilliseconds: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let base = "\(components.year ?? 0),\(components.month ?? 0),\(components.day ?? 0),\(components.hour ?? 0),\(components.minute ?? 0),\(components.second ?? 0)"
        guard includeMilliseconds else { return base }
        let milliseconds = (components.nanosecond ?? 0) / 1_000_000
        return "\(base),\(milliseconds)"
    }

    private func normalizeSNTPFailureReason(_ error: Error) -> String {
        if let clientError = error as? SNTPClientError {
            switch clientError {
            case .timeout: return "timeout"
            case .invalidPacket, .invalidServerResponse: return "invalid_response"
            case .connection(let message): return message
            }
        }
        return error.localizedDescription.isEmpty ? "connection_failed" : error.localizedDescription
    }
    
    /// Execute a HEADLINE/2.0 module (`\![execute,headline,name]`).
    ///
    /// Headline modules are loaded by `HeadlineRegistry` at application startup. The
    /// previous implementation fetched `homeurl` directly and emitted a private
    /// `OnHeadlineCheck` event, which bypassed the HEADLINE protocol and could never
    /// execute an installed module. This path now selects the requested module,
    /// sends a real HEADLINE request, filters already reported entries, and emits the
    /// standard Headlinesense events.
    func executeHeadline(name: String) {
        let requestedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target = resolveHeadlineTarget(name: requestedName) else {
            Log.info("[GhostManager] Headline module not found: \(requestedName)")
            _ = dispatchRSSFailure(reason: "can't analyze")
            return
        }
        let path = target.meta.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            Log.info("[GhostManager] Headline module has no URL: \(target.meta.name)")
            _ = dispatchRSSFailure(reason: "can't download")
            return
        }

        let siteName = target.meta.name
        if dispatchRSSBegin(siteName: siteName, url: path) {
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let request = HeadlineWireEngine.buildHeadlineRequest(
                path: path,
                version: .v2_0M,
                charset: target.meta.charset
            )
            let response = target.module.send(request)
            guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                _ = self.dispatchRSSFailure(reason: "can't download")
                return
            }
            let entries = HeadlineWireEngine.parseLines(response)
            guard !entries.isEmpty else {
                _ = self.dispatchRSSComplete(siteName: siteName, url: path, items: [])
                return
            }

            let historyKey = self.headlineHistoryKey(for: target)
            let oldHistory = Set(UserDefaults.standard.stringArray(forKey: historyKey) ?? [])
            let candidates = entries.map {
                RSSFeedItem(
                    title: $0.0,
                    url: $0.1 ?? "",
                    publishedAt: nil,
                    author: "",
                    summary: $0.0
                )
            }
            let fresh = candidates.filter { entry in
                let identity = self.headlineIdentity(text: entry.title, url: entry.url)
                return !oldHistory.contains(identity)
            }
            let allIdentities = candidates.map {
                self.headlineIdentity(text: $0.title, url: $0.url)
            }
            UserDefaults.standard.set(Array(oldHistory.union(allIdentities)).sorted(), forKey: historyKey)

            guard !fresh.isEmpty else {
                _ = self.dispatchRSSComplete(siteName: siteName, url: path, items: [])
                return
            }

            _ = self.dispatchRSSComplete(siteName: siteName, url: path, items: fresh)
            Log.debug("[GhostManager] Headlinesense completed: module=\(siteName), new=\(fresh.count)")
        }
    }

    /// RSSイベントを対象ゴーストへGETで送り、未応答時はHEADLINE開始へフォールバックする。
    @discardableResult
    func dispatchRSSBegin(siteName: String, url: String) -> Bool {
        let refs = ["siteName": siteName, "url": url]
        let handled = EventBridge.shared.request(.OnRSSBegin, refs: refs, to: self)
        if !handled {
            _ = EventBridge.shared.request(.OnHeadlinesenseBegin, refs: refs, to: self)
        }
        return handled
    }

    /// RSS完了を対象ゴーストへGETで送り、未応答時はHEADLINE通知へフォールバックする。
    ///
    /// 更新がある場合、OnRSSComplete の Reference2 以降に RSS wire value を並べる。
    /// RSSイベントが未処理の場合だけ、HEADLINEの OnFind を各項目へ送る。
    @discardableResult
    func dispatchRSSComplete(siteName: String, url: String, items: [RSSFeedItem]) -> Bool {
        let params: [String: String]
        if items.isEmpty {
            params = ["Reference0": "no update"]
        } else {
            var values = [
                "Reference0": siteName,
                "Reference1": url
            ]
            for (index, item) in items.enumerated() {
                values["Reference\(index + 2)"] = sanitizeRSSWireValue(item.wireValue)
            }
            params = values
        }

        if EventBridge.shared.request(.OnRSSComplete, params: params, to: self) {
            return true
        }

        guard !items.isEmpty else {
            _ = EventBridge.shared.request(
                .OnHeadlinesenseComplete,
                refs: ["reason": "no update"],
                to: self
            )
            return false
        }

        for (index, item) in items.enumerated() {
            let phase: String
            if items.count == 1 {
                phase = "First and Last"
            } else if index == 0 {
                phase = "First"
            } else if index == items.count - 1 {
                phase = "Last"
            } else {
                phase = "Next"
            }
            let findParams = EventReferenceTable.params(forEvent: "OnHeadlinesense.OnFind", refs: [
                    "siteName": siteName,
                    "url": url,
                    "phase": phase,
                    "content": sanitizeHeadlineContent(item.summary)
                ])
            _ = EventBridge.shared.requestCustom(
                "OnHeadlinesense.OnFind",
                params: findParams,
                to: self
            )
        }
        return false
    }

    /// RSS失敗を対象ゴーストへGETで送り、未応答時はHEADLINE失敗へフォールバックする。
    @discardableResult
    func dispatchRSSFailure(reason: String) -> Bool {
        let handled = EventBridge.shared.request(
            .OnRSSFailure,
            refs: ["reason": reason],
            to: self
        )
        if !handled {
            _ = EventBridge.shared.request(
                .OnHeadlinesenseFailure,
                refs: ["reason": reason],
                to: self
            )
        }
        return handled
    }

    private func resolveHeadlineTarget(name: String) -> (module: HeadlineModule, meta: HeadlineMeta)? {
        guard let registry = (NSApp.delegate as? AppDelegate)?.headlineRegistry else { return nil }
        let targets = registry.modules.compactMap { module -> (HeadlineModule, HeadlineMeta)? in
            guard let meta = registry.metas[module] else { return nil }
            return (module, meta)
        }
        guard !targets.isEmpty else { return nil }

        let normalized = name.lowercased()
        if normalized.isEmpty || normalized == "random" {
            return targets.randomElement()
        }
        if normalized == "lastinstalled" {
            let lastName = UserDefaults.standard.string(forKey: "OurinLastInstalledHeadlineName")?.lowercased() ?? ""
            return targets.first(where: { $0.1.name.lowercased() == lastName || $0.1.filename.lowercased() == lastName })
                ?? targets.last
        }
        return targets.first {
            $0.1.name.lowercased() == normalized
                || $0.1.filename.lowercased() == normalized
                || $0.0.bundle.bundleURL.deletingPathExtension().lastPathComponent.lowercased() == normalized
        }
    }

    private func headlineHistoryKey(for target: (module: HeadlineModule, meta: HeadlineMeta)) -> String {
        let stableName = target.meta.name.isEmpty ? target.module.bundle.bundleURL.path : target.meta.name
        let encoded = Data(stableName.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "OurinHeadlineHistory.\(encoded)"
    }

    private func headlineIdentity(text: String, url: String) -> String {
        "\(url)\u{1}\(text)"
    }

    private func sanitizeHeadlineContent(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Execute mail check (BIFF). `account` is the configured Mail account name.
    func executeBiff(account: String? = nil) {
        let accountName = account?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Log.debug("[GhostManager] Executing mail check (biff): \(accountName)")
        _ = EventBridge.shared.request(.OnBIFFBegin, refs: ["account": accountName], to: self)

        MailBiffClient().query(account: accountName.isEmpty ? nil : accountName) { [weak self] result in
            guard let self else { return }
            let key = accountName
            switch result {
            case .success(let biff):
                let previous = self.lastBiffUnreadCounts[key]
                self.lastBiffUnreadCounts[key] = biff.unreadCount
                self.dispatchBiffSuccess(
                    accountName: accountName,
                    result: biff,
                    previousUnreadCount: previous
                )
                Log.debug("[GhostManager] BIFF completed: unread=\(biff.unreadCount)")

            case .failure(let error):
                self.lastBiffUnreadCounts.removeValue(forKey: key)
                _ = EventBridge.shared.request(
                    .OnBIFFFailure,
                    refs: ["reason": error.localizedDescription, "account": accountName],
                    to: self
                )
                Log.info("[GhostManager] BIFF failed: \(error)")
            }
        }
    }

    /// BIFF成功イベントを対象ゴーストへGETで送り、未応答時だけ旧形式へフォールバックする。
    func dispatchBiffSuccess(
        accountName: String,
        result: MailBiffResult,
        previousUnreadCount: Int?
    ) {
        let delta = result.unreadCount - (previousUnreadCount ?? result.unreadCount)
        let completeParams = EventReferenceTable.params(
            forEvent: EventID.OnBIFFComplete.rawValue,
            refs: [
                "mailCount": String(result.unreadCount),
                "mailBytes": String(result.unreadBytes),
                "account": accountName,
                "newMailDelta": String(delta),
                "topResult": result.topResult,
                "listResult": "",
                "uidlResult": "",
                "senderAndSubject": result.senderAndSubject
            ]
        )
        let handled = EventBridge.shared.request(
            .OnBIFFComplete,
            params: completeParams,
            to: self
        )
        guard !handled,
              let previousUnreadCount,
              result.unreadCount > previousUnreadCount else { return }

        _ = EventBridge.shared.request(
            .OnBIFF2Complete,
            refs: [
                "mailCount": String(result.unreadCount),
                "mailBytes": String(result.unreadBytes),
                "account": accountName,
                "topResult": result.topResult
            ],
            to: self
        )
    }

    /// Execute HTTP commands for `\![execute,http-*]`.
    func executeHTTP(subcommand: String, params: [String]) {
        let options = HTTPCommandOptions(arguments: Array(params.dropFirst()), parameterRoot: httpParameterRoot())
        if options.streaming {
            let suffix = String(subcommand.dropFirst("http-".count))
            executeHTTPStreaming(subcommand: "http-stream-\(suffix)", params: params, options: options)
            return
        }
        let method = httpMethod(for: subcommand, prefix: "http-")
        let rawURL = params.first ?? ""
        if let inputError = options.parameterInputFileError {
            notifyHTTPEvent(.OnExecuteHTTPFailure, method: method, options: options,
                            url: rawURL, data: "", result: "param_input_\(inputError)", cookie: "", responseHeaders: "")
            return
        }
        guard let url = URL(string: rawURL), !rawURL.isEmpty else {
            notifyHTTPEvent(.OnExecuteHTTPFailure, method: method, options: options,
                            url: rawURL, data: "", result: "invalid_url", cookie: "", responseHeaders: "")
            return
        }

        var request = makeHTTPRequest(url: url, method: method, options: options)
        request.httpShouldHandleCookies = false
        let outputURL = options.noFile ? nil : httpOutputURL(fileName: options.fileName, sourceURL: url)
        let taskID = UUID()
        let runner = HTTPDataTaskRunner(request: request, onData: { [weak self] _, accumulated, response in
            guard let self, options.progressNotify else { return }
            let output = self.httpEventData(options: options, data: accumulated, outputURL: outputURL)
            self.notifyHTTPEvent(.OnExecuteHTTPProgress, method: method, options: options,
                                 url: url.absoluteString, data: output,
                                 result: response.map { String($0.statusCode) } ?? "0",
                                 cookie: self.httpResponseCookie(response, url: url),
                                 responseHeaders: self.httpResponseHeaders(response))
        }, onComplete: { [weak self] data, response, metrics, error in
            guard let self else { return }
            self.completeHTTPWait(taskID)
            self.httpRequestRunners.removeValue(forKey: taskID)

            let responseHeaders = self.httpResponseHeaders(response)
            let responseCookie = self.httpResponseCookie(response, url: url)
            if url.scheme?.lowercased() == "https", self.hasTLSConnection(response: response, metrics: metrics) {
                self.notifyHTTPSSLInfo(asyncID: options.asyncID, url: url.absoluteString,
                                       statusCode: response.map { String($0.statusCode) } ?? "0",
                                       metrics: metrics)
            }

            if let error {
                let result = self.httpFailureResult(error)
                self.notifyHTTPEvent(.OnExecuteHTTPFailure, method: method, options: options,
                                     url: url.absoluteString,
                                     data: outputURL?.path ?? "", result: result,
                                     cookie: responseCookie, responseHeaders: responseHeaders)
                return
            }
            guard let response else {
                self.notifyHTTPEvent(.OnExecuteHTTPFailure, method: method, options: options,
                                     url: url.absoluteString,
                                     data: outputURL?.path ?? "", result: "invalid_response",
                                     cookie: responseCookie, responseHeaders: responseHeaders)
                return
            }

            let result = String(response.statusCode)
            let dataValue: String
            do {
                if let outputURL {
                    try FileManager.default.createDirectory(
                        at: outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try data.write(to: outputURL, options: [.atomic])
                    dataValue = outputURL.path
                } else {
                    dataValue = self.httpEventData(options: options, data: data, outputURL: nil)
                }
            } catch {
                self.notifyHTTPEvent(.OnExecuteHTTPFailure, method: method, options: options,
                                     url: url.absoluteString,
                                     data: outputURL?.path ?? "", result: "fileio",
                                     cookie: responseCookie, responseHeaders: responseHeaders)
                return
            }

            self.notifyHTTPEvent(.OnExecuteHTTPComplete, method: method, options: options,
                                 url: url.absoluteString, data: dataValue, result: result,
                                 cookie: responseCookie, responseHeaders: responseHeaders)
            if options.progressNotify {
                self.notifyHTTPEvent(.OnExecuteHTTPProgress, method: method, options: options,
                                     url: url.absoluteString, data: dataValue, result: result,
                                     cookie: responseCookie, responseHeaders: responseHeaders)
            }
        })
        httpRequestRunners[taskID] = runner
        if options.waitForCompletion {
            pendingHTTPWaits.insert(taskID)
            playbackQueue.append(.waitForHTTP(taskID))
        }
        runner.start()
    }

    /// Execute streaming HTTP for `\![execute,http-stream,*]`.
    /// UKADOC では受信チャンクごとに OnExecuteHTTPStreaming を通知する。
    func executeHTTPStreaming(subcommand: String, params: [String], options suppliedOptions: HTTPCommandOptions? = nil) {
        let options = suppliedOptions ?? HTTPCommandOptions(arguments: Array(params.dropFirst()), parameterRoot: httpParameterRoot())
        let method = httpMethod(for: subcommand, prefix: "http-stream-")
        let rawURL = params.first ?? ""
        if let inputError = options.parameterInputFileError {
            notifyHTTPEvent(.OnExecuteHTTPFailure, method: method, options: options,
                            url: rawURL, data: "", result: "param_input_\(inputError)", cookie: "", responseHeaders: "")
            return
        }
        guard let url = URL(string: rawURL), !rawURL.isEmpty else {
            notifyHTTPEvent(.OnExecuteHTTPFailure, method: method, options: options,
                            url: rawURL, data: "", result: "invalid_url", cookie: "", responseHeaders: "")
            return
        }

        let request = makeHTTPRequest(url: url, method: method, options: options)
        let key = url.absoluteString
        httpStreamingRunners[key]?.cancel()
        httpStreamingRunners.removeValue(forKey: key)
        httpStreamingTasks.removeValue(forKey: key)
        httpStreamingPendingData.removeValue(forKey: key)

        let waitID = options.waitForCompletion ? UUID() : nil
        let runner = HTTPDataTaskRunner(request: request, onData: { [weak self] chunk, _, response in
            guard let self, !chunk.isEmpty else { return }
            let body = self.httpStreamingText(chunk, key: key, encoding: options.noFileEncoding)
            guard !body.isEmpty else { return }
            self.notifyHTTPEvent(.OnExecuteHTTPStreaming, method: method, options: options,
                                 url: key, data: "", result: body,
                                 cookie: self.httpResponseCookie(response, url: url),
                                 responseHeaders: self.httpResponseHeaders(response))
        }, onComplete: { [weak self] _, response, metrics, error in
            guard let self else { return }
            if let waitID {
                self.completeHTTPWait(waitID)
                self.httpStreamingWaitIDs.removeValue(forKey: key)
            }
            self.httpStreamingRunners.removeValue(forKey: key)
            self.httpStreamingTasks.removeValue(forKey: key)
            self.httpStreamingPendingData.removeValue(forKey: key)
            if let error {
                if (error as NSError).code == NSURLErrorCancelled {
                    // \![cancel,http,URL] による意図的な中断。失敗イベントは送らない。
                    return
                }
                self.notifyHTTPEvent(.OnExecuteHTTPFailure, method: method, options: options,
                                     url: key, data: "", result: self.httpFailureResult(error),
                                     cookie: self.httpResponseCookie(response, url: url),
                                     responseHeaders: self.httpResponseHeaders(response))
                return
            }
            guard let response else {
                self.notifyHTTPEvent(.OnExecuteHTTPFailure, method: method, options: options,
                                     url: key, data: "", result: "invalid_response",
                                     cookie: "", responseHeaders: "")
                return
            }
            if url.scheme?.lowercased() == "https", self.hasTLSConnection(response: response, metrics: metrics) {
                self.notifyHTTPSSLInfo(asyncID: options.asyncID, url: key,
                                       statusCode: String(response.statusCode), metrics: metrics)
            }
        })
        httpStreamingRunners[key] = runner
        if let waitID {
            pendingHTTPWaits.insert(waitID)
            httpStreamingWaitIDs[key] = waitID
            playbackQueue.append(.waitForHTTP(waitID))
        }
        runner.start()
        httpStreamingTasks[key] = runner.task
    }

    /// \![cancel,http,URL] — 実行中の HTTP ストリーミング要求を即時中断する。
    func cancelHTTPStreaming(params: [String]) {
        guard let rawURL = params.first, let url = URL(string: rawURL) else { return }
        let key = url.absoluteString
        let runner = httpStreamingRunners.removeValue(forKey: key)
        let task = httpStreamingTasks.removeValue(forKey: key)
        httpStreamingPendingData.removeValue(forKey: key)
        if let waitID = httpStreamingWaitIDs.removeValue(forKey: key) {
            completeHTTPWait(waitID)
        }
        runner?.cancel()
        task?.cancel()
    }

    private func httpMethod(for subcommand: String, prefix: String) -> String {
        let suffix = String(subcommand.dropFirst(prefix.count)).uppercased()
        let supported = Set(["GET", "POST", "HEAD", "PUT", "DELETE", "PATCH", "OPTIONS"])
        return supported.contains(suffix) ? suffix : "GET"
    }

    private func httpParameterRoot() -> URL {
        ghostURL
            .appendingPathComponent("ghost", isDirectory: true)
            .appendingPathComponent("master", isDirectory: true)
            .standardizedFileURL
    }

    /// URLSession の完了通知は delegate queue 上で届くため、再生キューと同じ
    /// メインスレッド上で待機集合を解放する。
    private func completeHTTPWait(_ taskID: UUID) {
        let complete = { [weak self] in
            _ = self?.pendingHTTPWaits.remove(taskID)
        }
        if Thread.isMainThread {
            complete()
        } else {
            DispatchQueue.main.async(execute: complete)
        }
    }

    private func makeHTTPRequest(url: URL, method: String, options: HTTPCommandOptions) -> URLRequest {
        let parameters = options.parameters + options.positionals
        var requestURL = url
        if ["GET", "HEAD", "DELETE", "OPTIONS"].contains(method) {
            if let parameterInputData = options.parameterInputData,
               let rawQuery = String(data: parameterInputData, encoding: options.parameterEncoding),
               !rawQuery.isEmpty {
                requestURL = appendHTTPRawQuery(rawQuery, to: url)
            } else if !parameters.isEmpty {
                requestURL = appendHTTPQuery(parameters, to: url)
            }
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        if let timeout = options.timeout, timeout > 0 {
            request.timeoutInterval = timeout
        }
        if options.noCache {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        if !options.cookie.isEmpty {
            request.setValue(options.cookie, forHTTPHeaderField: "Cookie")
        }

        if !["GET", "HEAD", "DELETE", "OPTIONS"].contains(method) {
            if let parameterInputData = options.parameterInputData {
                request.httpBody = parameterInputData
            } else if let body = options.body {
                request.httpBody = body.data(using: options.parameterEncoding)
            } else if !parameters.isEmpty {
                let contentType = options.contentType?.lowercased() ?? "application/x-www-form-urlencoded"
                let body = contentType.contains("application/x-www-form-urlencoded")
                    ? parameters.map(formEncode).joined(separator: "&")
                    : parameters.joined(separator: "\r\n")
                request.httpBody = body.data(using: options.parameterEncoding)
            }
            if let contentType = options.contentType, !contentType.isEmpty {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            } else if request.httpBody != nil {
                request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            }
        }
        for (key, value) in options.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    private func appendHTTPQuery(_ parameters: [String], to url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let encoded = parameters.map(formEncode).joined(separator: "&")
        if encoded.isEmpty { return url }
        if let existing = components.percentEncodedQuery, !existing.isEmpty {
            components.percentEncodedQuery = existing + "&" + encoded
        } else {
            components.percentEncodedQuery = encoded
        }
        return components.url ?? url
    }

    /// `--param-input-file` は既に送信用に組み立てられたデータを受け取るため、
    /// `--param` と異なり再エンコードせずクエリへ連結する。
    private func appendHTTPRawQuery(_ rawQuery: String, to url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return url }
        if let existing = components.percentEncodedQuery, !existing.isEmpty {
            components.percentEncodedQuery = existing + "&" + query
        } else {
            components.percentEncodedQuery = query
        }
        return components.url ?? url
    }

    private func formEncode(_ raw: String) -> String {
        guard let separator = raw.firstIndex(of: "=") else {
            return percentEncode(raw)
        }
        let key = String(raw[..<separator])
        let value = String(raw[raw.index(after: separator)...])
        return "\(percentEncode(key))=\(percentEncode(value))"
    }

    private func percentEncode(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    private func httpOutputURL(fileName: String?, sourceURL: URL) -> URL {
        let root = ghostURL
            .appendingPathComponent("ghost", isDirectory: true)
            .appendingPathComponent("master", isDirectory: true)
            .appendingPathComponent("var", isDirectory: true)
            .standardizedFileURL
        let fallback = sourceURL.lastPathComponent.isEmpty ? "index.html" : sourceURL.lastPathComponent
        let rawName = fileName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (rawName?.isEmpty == false ? rawName! : fallback)
        let candidate: URL
        if name.hasPrefix("/") {
            candidate = root.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
        } else {
            candidate = root.appendingPathComponent(name).standardizedFileURL
        }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            return root.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent)
        }
        return candidate
    }

    private func httpEventData(options: HTTPCommandOptions, data: Data, outputURL: URL?) -> String {
        guard options.noFile else { return outputURL?.path ?? "" }
        let decoded = String(data: data, encoding: options.noFileEncoding)
            ?? String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return httpWireText(decoded)
    }

    private func httpStreamingText(_ data: Data, key: String, encoding: String.Encoding) -> String {
        var combined = httpStreamingPendingData[key, default: Data()]
        combined.append(data)
        if let decoded = String(data: combined, encoding: encoding) {
            httpStreamingPendingData.removeValue(forKey: key)
            return httpWireText(decoded)
        }

        // String(data:encoding:) rejects an incomplete multibyte suffix. Keep the
        // shortest suffix that cannot yet be decoded and emit the valid prefix.
        if combined.count > 1 {
            for prefixLength in stride(from: combined.count - 1, through: 1, by: -1) {
                let prefix = Data(combined.prefix(prefixLength))
                guard let decoded = String(data: prefix, encoding: encoding) else { continue }
                httpStreamingPendingData[key] = Data(combined.dropFirst(prefixLength))
                return httpWireText(decoded)
            }
        }

        // Invalid data is not allowed to block the stream forever. Preserve the
        // existing replacement-character behavior after dropping the bad prefix.
        httpStreamingPendingData.removeValue(forKey: key)
        let decoded = String(data: data, encoding: encoding)
            ?? String(decoding: data, as: UTF8.self)
        return httpWireText(decoded)
    }

    private func httpWireText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\u{1}")
            .replacingOccurrences(of: "\r", with: "\u{1}")
            .replacingOccurrences(of: "\n", with: "\u{1}")
    }

    private func notifyHTTPEvent(_ id: EventID,
                                 method: String,
                                 options: HTTPCommandOptions,
                                 url: String,
                                 data: String,
                                 result: String,
                                 cookie: String,
                                 responseHeaders: String) {
        var refs = [
            "method": method,
            "asyncID": options.asyncID,
            "url": url,
            "data": data,
            "cookie": cookie,
            "responseHeaders": responseHeaders
        ]
        if id == .OnExecuteHTTPStreaming {
            refs["body"] = result
        } else {
            refs["result"] = result
        }
        let params = EventReferenceTable.params(forEvent: id.rawValue, refs: refs)
        if let customEventID = options.customEventID {
            EventBridge.shared.notifyCustom(httpEventName(for: id, customEventID: customEventID), params: params)
        } else {
            EventBridge.shared.notify(id, params: params)
        }
    }

    private func httpEventName(for id: EventID, customEventID: String) -> String {
        switch id {
        case .OnExecuteHTTPComplete, .OnExecuteRSSComplete:
            return customEventID
        case .OnExecuteHTTPProgress:
            return customEventID + "Progress"
        case .OnExecuteHTTPFailure, .OnExecuteRSSFailure:
            return customEventID + "Failure"
        case .OnExecuteHTTPStreaming:
            return customEventID + "Streaming"
        default:
            return id.rawValue
        }
    }

    private func httpResponseHeaders(_ response: HTTPURLResponse?) -> String {
        guard let response else { return "" }
        return response.allHeaderFields
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "\u{1}")
    }

    private func httpResponseCookie(_ response: HTTPURLResponse?, url: URL) -> String {
        guard let response else { return "" }
        let rawHeaders = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key)] = String(describing: pair.value)
        }
        guard let setCookie = rawHeaders.first(where: { $0.key.caseInsensitiveCompare("Set-Cookie") == .orderedSame })?.value else {
            return ""
        }
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": setCookie], for: url)
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private func httpFailureResult(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "timeout"
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return "cancelled"
        }
        return error.localizedDescription.isEmpty ? "connection_failed" : error.localizedDescription
    }

    private func notifyHTTPSSLInfo(eventID: EventID = .OnExecuteHTTPSSLInfo,
                                   asyncID: String,
                                   url: String,
                                   statusCode: String,
                                   metrics: URLSessionTaskMetrics?) {
        let tlsVersion = metrics?.transactionMetrics.reversed()
            .compactMap { $0.negotiatedTLSProtocolVersion }
            .first
            .map(tlsVersionName) ?? ""
        EventBridge.shared.notify(eventID, params: [
            "Reference0": asyncID,
            "Reference1": url,
            "Reference2": statusCode,
            "Reference3": tlsVersion
        ])
    }

    private func hasTLSConnection(response: HTTPURLResponse?, metrics: URLSessionTaskMetrics?) -> Bool {
        if response != nil { return true }
        return metrics?.transactionMetrics.contains {
            $0.negotiatedTLSProtocolVersion != nil
        } == true
    }

    private func tlsVersionName(_ value: tls_protocol_version_t) -> String {
        switch value {
        case .TLSv10: return "TLSv1"
        case .TLSv11: return "TLSv1.1"
        case .TLSv12: return "TLSv1.2"
        case .TLSv13: return "TLSv1.3"
        default: return ""
        }
    }

    /// Execute RSS commands for `\![execute,rss-*]`.
    func executeRSS(subcommand: String, params: [String]) {
        let options = HTTPCommandOptions(arguments: Array(params.dropFirst()), parameterRoot: httpParameterRoot())
        let rawURL = params.first ?? ""
        let methodSuffix = String(subcommand.dropFirst("rss-".count)).uppercased()
        let method = Set(["GET", "POST"]).contains(methodSuffix) ? methodSuffix : "GET"
        if let inputError = options.parameterInputFileError {
            notifyExecuteRSSFailure(method: method, options: options, url: rawURL,
                                     reason: "param_input_\(inputError)", data: "", cookie: "", responseHeaders: "")
            return
        }
        guard let url = URL(string: rawURL), !rawURL.isEmpty else {
            notifyExecuteRSSFailure(method: method, options: options, url: rawURL, reason: "invalid_url",
                                    data: "", cookie: "", responseHeaders: "")
            return
        }
        let request = makeHTTPRequest(url: url, method: method, options: options)
        let taskID = UUID()
        let waitID = options.waitForCompletion ? UUID() : nil
        let runner = HTTPDataTaskRunner(request: request, onData: { _, _, _ in
            // RSS はレスポンス全体を XML として解析するため、途中イベントは発火しない。
        }, onComplete: { [weak self] data, response, metrics, error in
            guard let self else { return }
            if let waitID { self.completeHTTPWait(waitID) }
            self.httpRequestRunners.removeValue(forKey: taskID)
            let responseHeaders = self.httpResponseHeaders(response)
            let responseCookie = self.httpResponseCookie(response, url: url)
            if url.scheme?.lowercased() == "https", self.hasTLSConnection(response: response, metrics: metrics) {
                self.notifyHTTPSSLInfo(eventID: .OnExecuteRSS_SSLInfo, asyncID: options.asyncID, url: url.absoluteString,
                                       statusCode: response.map { String($0.statusCode) } ?? "0",
                                       metrics: metrics)
            }
            if let error {
                self.notifyExecuteRSSFailure(method: method, options: options, url: url.absoluteString,
                                             reason: self.httpFailureResult(error), data: "",
                                             cookie: responseCookie, responseHeaders: responseHeaders)
                return
            }

            guard let response else {
                self.notifyExecuteRSSFailure(method: method, options: options, url: url.absoluteString,
                                             reason: "invalid_response", data: "",
                                             cookie: responseCookie, responseHeaders: responseHeaders)
                return
            }
            let statusCode = response.statusCode
            guard (200..<300).contains(statusCode) else {
                self.notifyExecuteRSSFailure(method: method, options: options, url: url.absoluteString,
                                             reason: String(statusCode), data: "",
                                             cookie: responseCookie, responseHeaders: responseHeaders)
                return
            }

            do {
                let items = try RSSFeedParser().parse(data)
                let eventParams: [String: String]
                if items.isEmpty {
                    eventParams = ["Reference0": "no update"]
                } else {
                    eventParams = Dictionary(uniqueKeysWithValues: items.enumerated().map { index, item in
                        ("Reference\(index)", self.sanitizeRSSWireValue(item.wireValue))
                    })
                }
                if let customEventID = options.customEventID {
                    EventBridge.shared.notifyCustom(customEventID, params: eventParams)
                } else {
                    EventBridge.shared.notify(.OnExecuteRSSComplete, params: eventParams)
                }
            } catch {
                self.notifyExecuteRSSFailure(method: method, options: options, url: url.absoluteString,
                                             reason: "parse", data: "",
                                             cookie: responseCookie, responseHeaders: responseHeaders)
            }
        })
        httpRequestRunners[taskID] = runner
        if let waitID {
            pendingHTTPWaits.insert(waitID)
            playbackQueue.append(.waitForHTTP(waitID))
        }
        runner.start()
    }

    private func sanitizeRSSWireValue(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func notifyExecuteRSSFailure(method: String,
                                         options: HTTPCommandOptions,
                                         url: String,
                                         reason: String,
                                         data: String,
                                         cookie: String,
                                         responseHeaders: String) {
        let refs = [
            "method": method,
            "asyncID": options.asyncID,
            "url": url,
            "data": data,
            "result": reason,
            "cookie": cookie,
            "responseHeaders": responseHeaders
        ]
        let params = EventReferenceTable.params(forEvent: EventID.OnExecuteRSSFailure.rawValue, refs: refs)
        if let customEventID = options.customEventID {
            EventBridge.shared.notifyCustom(customEventID + "Failure", params: params)
        } else {
            EventBridge.shared.notify(.OnExecuteRSSFailure, params: params)
        }
    }

    /// Execute update check
    func executeUpdate(target: String, options: [String]) {
        Log.debug("[GhostManager] Executing update check for: \(target)")

        DispatchQueue.global(qos: .utility).async {
            // Determine what to update
            switch target.lowercased() {
            case "self", "ghost":
                // Check for updates to this ghost
                self.checkGhostUpdate(options: options)
            case "platform", "baseware":
                // Check for updates to Ourin itself
                self.checkPlatformUpdate(options: options)
            case "other", "all":
                // `updateother` can target both ghosts and installed components.
                // Keep the legacy no-selector behavior (all ghosts), while routing
                // explicit balloon/shell/plugin/headline/language selectors to
                // their own installed target instead of silently updating ghosts.
                let parsed = UpdateCommandOptions(options)
                if !parsed.componentSelectors.isEmpty {
                    self.checkComponentUpdates(options: options, selectors: parsed.componentSelectors)
                    let hasGhostSelector = parsed.selectors.contains { $0.type == "ghost" }
                    if hasGhostSelector {
                        let ghostOptions = options.filter { rawValue in
                            let body = rawValue.hasPrefix("--") ? String(rawValue.dropFirst(2)) : rawValue
                            guard let separator = body.firstIndex(of: "=") else { return true }
                            let type = String(body[..<separator]).lowercased()
                            return !ComponentUpdateTargetDiscovery.supportedTypes.contains(type)
                        }
                        self.checkAllGhostsUpdate(options: ghostOptions)
                    }
                } else {
                    self.checkAllGhostsUpdate(options: options)
                }
            default:
                Log.info("[GhostManager] Unknown update target: \(target)")
            }
        }
    }

    /// Check for ghost updates
    func checkGhostUpdate(options: [String]) {
        let commandOptions = UpdateCommandOptions(options)
        emitUpdateBegin(targetType: "ghost", executionReason: commandOptions.reason)
        guard let updateURL = ghostConfig?.homeurl else {
            Log.info("[GhostManager] No update URL configured for ghost")
            EventBridge.shared.notify(.OnUpdateFailure, refs: [
                    "reason": "paramerror",
                    "fileList": "",
                    "targetType": "ghost",
                    "executionReason": commandOptions.reason
            ])
            self.emitUpdateResultEvents(
                target: "ghost",
                reason: "paramerror",
                fileList: "",
                explorerPath: ghostURL.path
            )
            EventBridge.shared.notifyCustom("OnUpdateCheckFailure", refs: ["reason": "missing_url"])
            return
        }

        Log.info("[GhostManager] Checking for ghost updates at homeurl: \(updateURL)")
        let installer = NarInstaller()
        installer.checkUpdateEntries(homeURLString: updateURL) { result in
            switch result {
            case .success(let entries):
                let fileList = entries.map(\.filename).joined(separator: ",")
                let reason = entries.isEmpty ? "none" : "changed"
                EventBridge.shared.notify(.OnUpdateReady, refs: [
                    "fileIndex": String(max(0, entries.count - 1)),
                    "fileList": fileList,
                    "targetType": "ghost",
                    "executionReason": commandOptions.reason
                ])
                EventBridge.shared.notify(.OnUpdateCheckComplete, refs: [
                    "reason": reason,
                    "fileList": fileList,
                    "targetType": "ghost",
                    "executionReason": commandOptions.reason
                ])

                if commandOptions.checkOnly {
                    self.emitUpdateResultEvents(
                        target: "ghost",
                        targetName: self.ghostConfig?.name ?? self.ghostURL.lastPathComponent,
                        reason: reason,
                        fileList: fileList,
                        explorerPath: self.ghostURL.path,
                        checkOnly: true
                    )
                    return
                }

                // 変更が無ければ即完了。あればダウンロード→適用してから完了イベントを出す。
                guard !entries.isEmpty else {
                    EventBridge.shared.notify(.OnUpdateComplete, refs: [
                        "reason": "none",
                        "fileList": "",
                        "targetType": "ghost",
                        "executionReason": commandOptions.reason
                    ])
                    self.emitUpdateResultEvents(target: "ghost", reason: "none", fileList: "", explorerPath: self.ghostURL.path)
                    Log.debug("[GhostManager] Ghost update: no changes")
                    return
                }
                self.emitUpdateDownloadBeginEvents(
                    base: "OnUpdate",
                    entries: entries,
                    targetType: "ghost",
                    executionReason: commandOptions.reason
                )
                installer.downloadAndApply(entries: entries, homeURLString: updateURL, targetRoot: self.ghostURL,
                                           onMD5Compare: { comparison in
                    let params = [
                        "Reference0": comparison.filename,
                        "Reference1": comparison.correctMD5,
                        "Reference2": comparison.downloadedMD5,
                        "Reference3": "ghost",
                        "Reference4": commandOptions.reason
                    ]
                    self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnMD5CompareBegin", params: params)
                    self.emitUpdatePipelineEvent(
                        base: "OnUpdate",
                        stage: comparison.matches ? "OnMD5CompareComplete" : "OnMD5CompareFailure",
                        params: params
                    )
                }, apply: !commandOptions.testOnly) { result in
                    switch result {
                    case .success(let applied):
                    let appliedList = applied.joined(separator: ",")
                    let appliedReason = applied.isEmpty ? "none" : "changed"
                    self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnDownloadComplete", params: [
                        "Reference0": updateURL,
                        "Reference1": String(applied.count)
                    ])
                    EventBridge.shared.notify(.OnUpdateComplete, refs: [
                        "reason": appliedReason,
                        "fileList": appliedList.isEmpty ? fileList : appliedList,
                        "targetType": "ghost",
                        "executionReason": commandOptions.reason
                    ])
                    self.emitUpdateResultEvents(
                        target: "ghost",
                        reason: appliedReason,
                        fileList: appliedList.isEmpty ? fileList : appliedList,
                        explorerPath: self.ghostURL.path
                    )
                    Log.debug("[GhostManager] Ghost update applied=\(applied.count)/\(entries.count)")
                    case .failure(let error):
                        let failureReason = self.normalizeUpdateFailureReason(error)
                        self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnDownloadFailure", params: [
                            "Reference0": updateURL,
                            "Reference1": failureReason
                        ])
                        EventBridge.shared.notify(.OnUpdateFailure, refs: [
                            "reason": failureReason,
                            "fileList": fileList,
                            "targetType": "ghost",
                            "executionReason": commandOptions.reason
                        ])
                        self.emitUpdateResultEvents(
                            target: "ghost",
                            reason: failureReason,
                            fileList: fileList,
                            explorerPath: self.ghostURL.path
                        )
                    }
                }
            case .failure(let error):
                Log.info("[GhostManager] Ghost update check failed: \(error)")
                let reason = self.normalizeUpdateFailureReason(error)
                EventBridge.shared.notify(.OnUpdateFailure, refs: [
                    "reason": reason,
                    "fileList": "",
                    "targetType": "ghost",
                    "executionReason": commandOptions.reason
                ])
                self.emitUpdateResultEvents(
                    target: "ghost",
                    reason: reason,
                    fileList: "",
                    explorerPath: self.ghostURL.path
                )
                EventBridge.shared.notifyCustom("OnUpdateCheckFailure", refs: ["reason": reason])
            }
        }
    }
    
    /// Check for platform (Ourin) updates
    func checkPlatformUpdate(options: [String]) {
        let commandOptions = UpdateCommandOptions(options)
        Log.info("[GhostManager] Checking for Ourin platform updates")
        emitUpdateBegin(targetType: "baseware", executionReason: commandOptions.reason)

        guard let updateURL = configuredBasewareUpdateURL(explicit: commandOptions.explicitURL) else {
            Log.info("[GhostManager] No baseware update descriptor URL is configured")
            EventBridge.shared.notify(.OnUpdateFailure, refs: [
                "reason": "paramerror",
                "fileList": "",
                "targetType": "baseware",
                "executionReason": commandOptions.reason
            ])
            EventBridge.shared.notify(.OnUpdateCheckFailure, refs: ["reason": "missing_url"])
            self.emitUpdateResultEvents(
                target: "baseware",
                reason: "paramerror",
                fileList: "",
                explorerPath: Bundle.main.bundlePath
            )
            return
        }

        NarInstaller().checkUpdateEntries(homeURLString: updateURL) { result in
            switch result {
            case .success(let entries):
                let fileList = entries.map(\.filename).joined(separator: ",")
                let reason = entries.isEmpty ? "none" : "changed"
                if !entries.isEmpty {
                    EventBridge.shared.notify(.OnUpdateReady, refs: [
                        "fileIndex": String(max(0, entries.count - 1)),
                        "fileList": fileList,
                        "targetType": "baseware",
                        "executionReason": commandOptions.reason
                    ])
                }
                EventBridge.shared.notify(.OnUpdateCheckComplete, refs: [
                    "reason": reason,
                    "fileList": fileList,
                    "targetType": "baseware",
                    "executionReason": commandOptions.reason
                ])
                if commandOptions.checkOnly {
                    self.emitUpdateResultEvents(
                        target: "baseware",
                        targetName: Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Ourin",
                        reason: reason,
                        fileList: fileList,
                        explorerPath: Bundle.main.bundlePath,
                        checkOnly: true
                    )
                    return
                }
                guard !entries.isEmpty else {
                    EventBridge.shared.notify(.OnUpdateComplete, refs: [
                        "reason": "none",
                        "fileList": "",
                        "targetType": "baseware",
                        "executionReason": commandOptions.reason
                    ])
                    self.emitUpdateResultEvents(
                        target: "baseware",
                        reason: "none",
                        fileList: "",
                        explorerPath: Bundle.main.bundlePath
                    )
                    return
                }
                self.emitUpdateDownloadBeginEvents(
                    base: "OnUpdate",
                    entries: entries,
                    targetType: "baseware",
                    executionReason: commandOptions.reason
                )
                let coordinator = BasewareUpdateCoordinator()
                coordinator.prepare(entries: entries, homeURLString: updateURL, onMD5Compare: { comparison in
                    let params = [
                        "Reference0": comparison.filename,
                        "Reference1": comparison.correctMD5,
                        "Reference2": comparison.downloadedMD5,
                        "Reference3": "baseware",
                        "Reference4": commandOptions.reason
                    ]
                    self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnMD5CompareBegin", params: params)
                    self.emitUpdatePipelineEvent(
                        base: "OnUpdate",
                        stage: comparison.matches ? "OnMD5CompareComplete" : "OnMD5CompareFailure",
                        params: params
                    )
                }) { result in
                    switch result {
                    case .success(let request):
                        if commandOptions.testOnly {
                            BasewareUpdateCoordinator.discard(request)
                            self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnDownloadComplete", params: [
                                "Reference0": updateURL,
                                "Reference1": String(entries.count)
                            ])
                            EventBridge.shared.notify(.OnUpdateComplete, refs: [
                                "reason": "changed",
                                "fileList": fileList,
                                "targetType": "baseware",
                                "executionReason": commandOptions.reason
                            ])
                            self.emitUpdateResultEvents(
                                target: "baseware",
                                reason: "changed",
                                fileList: fileList,
                                explorerPath: Bundle.main.bundlePath
                            )
                            return
                        }
                        let appDelegate: AppDelegate? = Thread.isMainThread
                            ? NSApp.delegate as? AppDelegate
                            : DispatchQueue.main.sync { NSApp.delegate as? AppDelegate }
                        guard let appDelegate else {
                            BasewareUpdateCoordinator.discard(request)
                            let failureReason = "baseware_shutdown_unavailable"
                            self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnDownloadFailure", params: [
                                "Reference0": updateURL,
                                "Reference1": failureReason
                            ])
                            EventBridge.shared.notify(.OnUpdateFailure, refs: [
                                "reason": failureReason,
                                "fileList": fileList,
                                "targetType": "baseware",
                                "executionReason": commandOptions.reason
                            ])
                            self.emitUpdateResultEvents(
                                target: "baseware",
                                reason: failureReason,
                                fileList: fileList,
                                explorerPath: Bundle.main.bundlePath
                            )
                            return
                        }
                        do {
                            try BasewareUpdateHelper.launch(request)
                        } catch {
                            BasewareUpdateCoordinator.discard(request)
                            let failureReason = self.normalizeUpdateFailureReason(error)
                            self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnDownloadFailure", params: [
                                "Reference0": updateURL,
                                "Reference1": failureReason
                            ])
                            EventBridge.shared.notify(.OnUpdateFailure, refs: [
                                "reason": failureReason,
                                "fileList": fileList,
                                "targetType": "baseware",
                                "executionReason": commandOptions.reason
                            ])
                            self.emitUpdateResultEvents(
                                target: "baseware",
                                reason: failureReason,
                                fileList: fileList,
                                explorerPath: Bundle.main.bundlePath
                            )
                            return
                        }
                        self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnDownloadComplete", params: [
                            "Reference0": updateURL,
                            "Reference1": String(entries.count)
                        ])
                        EventBridge.shared.notify(.OnUpdateComplete, refs: [
                            "reason": "changed",
                            "fileList": fileList,
                            "targetType": "baseware",
                            "executionReason": commandOptions.reason
                        ])
                        self.emitUpdateResultEvents(
                            target: "baseware",
                            reason: "changed",
                            fileList: fileList,
                            explorerPath: Bundle.main.bundlePath
                        )
                        appDelegate.beginBasewareUpdateShutdown(version: request.version)

                    case .failure(let error):
                        let failureReason = self.normalizeUpdateFailureReason(error)
                        self.emitUpdatePipelineEvent(base: "OnUpdate", stage: "OnDownloadFailure", params: [
                            "Reference0": updateURL,
                            "Reference1": failureReason
                        ])
                        EventBridge.shared.notify(.OnUpdateFailure, refs: [
                            "reason": failureReason,
                            "fileList": fileList,
                            "targetType": "baseware",
                            "executionReason": commandOptions.reason
                        ])
                        self.emitUpdateResultEvents(
                            target: "baseware",
                            reason: failureReason,
                            fileList: fileList,
                            explorerPath: Bundle.main.bundlePath
                        )
                    }
                }

            case .failure(let error):
                let reason = self.normalizeUpdateFailureReason(error)
                EventBridge.shared.notify(.OnUpdateFailure, refs: [
                    "reason": reason,
                    "fileList": "",
                    "targetType": "baseware",
                    "executionReason": commandOptions.reason
                ])
                EventBridge.shared.notify(.OnUpdateCheckFailure, refs: ["reason": reason])
                self.emitUpdateResultEvents(
                    target: "baseware",
                    reason: reason,
                    fileList: "",
                    explorerPath: Bundle.main.bundlePath
                )
            }
        }
    }

    private func configuredBasewareUpdateURL(explicit: String?) -> String? {
        let candidates = [
            explicit,
            UserDefaults.standard.string(forKey: "OurinBasewareUpdateURL"),
            Bundle.main.infoDictionary?["OurinBasewareUpdateURL"] as? String,
            ResourceBridge.shared.get("update.url")
        ]
        return candidates.compactMap { value in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return nil }
            return trimmed
        }.first
    }
    
    /// `updateother` で指定された balloon/shell/plugin/headline/language を更新する。
    ///
    /// 対象ごとに更新記述子を確認し、同じ対象のルートへ増分ファイルを適用する。
    /// ゴースト全体更新の経路とは分離し、誤って全ゴーストへフォールバックしない。
    private func checkComponentUpdates(options: [String], selectors: [UpdateCommandOptions.Selector]) {
        let commandOptions = UpdateCommandOptions(options)
        let checkOnly = commandOptions.checkOnly
        let requested = selectors.map { "\($0.type)=\($0.name)" }.joined(separator: ",")

        func emitSelectionFailure(reason: String) {
            EventBridge.shared.notify(.OnUpdateOtherFailure, refs: [
                "reason": reason,
                "fileList": requested,
                "targetType": "component",
                "executionReason": commandOptions.reason
            ])
            EventBridge.shared.notify(.OnUpdateCheckFailure, refs: [
                "reason": reason,
                "executionReason": commandOptions.reason
            ])
            EventBridge.shared.notify(.OnUpdateCheckComplete, refs: [
                "reason": reason,
                "fileList": requested,
                "targetType": "component",
                "executionReason": commandOptions.reason
            ])
            self.emitUpdateResultEvents(
                target: "component",
                reason: reason,
                fileList: requested,
                explorerPath: self.ghostURL.path,
                checkOnly: checkOnly
            )
        }

        let types = Set(selectors.map(\.type))
        let discovered = ComponentUpdateTargetDiscovery.discover(types: types)
        let targets = discovered.filter { target in
            selectors.contains { selector in
                selector.type == target.type && target.matches(name: selector.name)
            }
        }
        guard !targets.isEmpty else {
            Log.info("[GhostManager] updateother component target not found: \(requested)")
            emitSelectionFailure(reason: "target_not_found")
            return
        }

        struct BatchResult {
            let target: ComponentUpdateTarget
            let reason: String
            let fileList: String
            let failedFile: String?
        }

        func emitBatchResultEvents(_ results: [BatchResult]) {
            guard !results.isEmpty else { return }
            let separator = String(UnicodeScalar(1))
            var basicRefs: [String: String] = [:]
            var extendedRefs: [String: String] = [:]
            for (index, result) in results.enumerated() {
                let success = result.reason == "none" || result.reason == "changed"
                let value: String
                if success {
                    value = String(result.fileList.isEmpty ? 0 : result.fileList.split(separator: ",").count)
                } else {
                    value = result.reason
                }
                var basic = [result.target.type, success ? "OK" : "NG", value]
                var extended = [result.target.name, result.target.type, success ? "OK" : "NG", value]
                if let failedFile = result.failedFile, !failedFile.isEmpty {
                    basic.append(failedFile)
                    extended.append(failedFile)
                }
                basicRefs["Reference\(index)"] = basic.joined(separator: separator)
                extendedRefs["Reference\(index)"] = extended.joined(separator: separator)
            }
            let basicEvent: EventID = checkOnly ? .OnUpdateCheckResult : .OnUpdateResult
            let extendedEvent: EventID = checkOnly ? .OnUpdateCheckResultEx : .OnUpdateResultEx
            EventBridge.shared.notify(basicEvent, params: basicRefs)
            EventBridge.shared.notify(extendedEvent, params: extendedRefs)
            EventBridge.shared.notify(.OnUpdateResultExplorer, params: basicRefs)
        }

        func process(index: Int, results: [BatchResult]) {
            guard index < targets.count else {
                let failed = results.filter { $0.reason != "none" && $0.reason != "changed" }
                let changed = results.contains { $0.reason == "changed" }
                let aggregateReason = failed.first?.reason ?? (changed ? "changed" : "none")
                let aggregateFiles = results.map { $0.target.name }.joined(separator: ",")
                EventBridge.shared.notify(.OnUpdateCheckComplete, refs: [
                    "reason": aggregateReason,
                    "fileList": aggregateFiles,
                    "targetType": "component",
                    "executionReason": commandOptions.reason
                ])
                emitBatchResultEvents(results)
                return
            }

            let target = targets[index]
            let next: (BatchResult) -> Void = { result in
                process(index: index + 1, results: results + [result])
            }

            EventBridge.shared.notify(.OnUpdateOtherBegin, refs: [
                "ghostName": target.name,
                "path": target.path.path,
                "targetType": target.type,
                "executionReason": commandOptions.reason
            ])

            guard let updateURL = commandOptions.explicitURL ?? target.homeURL,
                  let parsedURL = URL(string: updateURL),
                  parsedURL.scheme != nil else {
                let reason = "missing_url"
                EventBridge.shared.notify(.OnUpdateOtherFailure, refs: [
                    "reason": reason,
                    "fileList": "",
                    "targetType": target.type,
                    "executionReason": commandOptions.reason
                ])
                EventBridge.shared.notify(.OnUpdateCheckFailure, refs: [
                    "reason": reason,
                    "executionReason": commandOptions.reason
                ])
                next(BatchResult(target: target, reason: reason, fileList: "", failedFile: nil))
                return
            }

            NarInstaller().checkUpdateEntries(homeURLString: updateURL) { result in
                switch result {
                case .success(let entries):
                    let fileList = entries.map(\.filename).joined(separator: ",")
                    let reason = entries.isEmpty ? "none" : "changed"
                    if !entries.isEmpty {
                        EventBridge.shared.notify(.OnUpdateOtherReady, refs: [
                            "fileIndex": String(max(0, entries.count - 1)),
                            "fileList": fileList,
                            "targetType": target.type,
                            "executionReason": commandOptions.reason
                        ])
                    }
                    EventBridge.shared.notify(.OnUpdateCheckComplete, refs: [
                        "reason": reason,
                        "fileList": fileList,
                        "targetType": target.type,
                        "executionReason": commandOptions.reason
                    ])
                    if entries.isEmpty || checkOnly {
                        EventBridge.shared.notify(.OnUpdateOtherComplete, refs: [
                            "reason": reason,
                            "fileList": fileList,
                            "targetType": target.type,
                            "executionReason": commandOptions.reason
                        ])
                        next(BatchResult(target: target, reason: reason, fileList: fileList, failedFile: nil))
                        return
                    }

                    self.emitUpdateDownloadBeginEvents(
                        base: "OnUpdateOther",
                        entries: entries,
                        targetType: target.type,
                        executionReason: commandOptions.reason
                    )
                    NarInstaller().downloadAndApply(
                        entries: entries,
                        homeURLString: updateURL,
                        targetRoot: target.path,
                        onMD5Compare: { comparison in
                            let params = [
                                "Reference0": comparison.filename,
                                "Reference1": comparison.correctMD5,
                                "Reference2": comparison.downloadedMD5,
                                "Reference3": target.type,
                                "Reference4": commandOptions.reason
                            ]
                            self.emitUpdatePipelineEvent(base: "OnUpdateOther", stage: "OnMD5CompareBegin", params: params)
                            self.emitUpdatePipelineEvent(
                                base: "OnUpdateOther",
                                stage: comparison.matches ? "OnMD5CompareComplete" : "OnMD5CompareFailure",
                                params: params
                            )
                        },
                        apply: !commandOptions.testOnly,
                        completion: { applyResult in
                            switch applyResult {
                            case .success(let applied):
                                let appliedList = applied.joined(separator: ",")
                                let appliedReason = applied.isEmpty ? "none" : "changed"
                                EventBridge.shared.notify(.OnUpdateOtherComplete, refs: [
                                    "reason": appliedReason,
                                    "fileList": appliedList.isEmpty ? fileList : appliedList,
                                    "targetType": target.type,
                                    "executionReason": commandOptions.reason
                                ])
                                next(BatchResult(
                                    target: target,
                                    reason: appliedReason,
                                    fileList: appliedList.isEmpty ? fileList : appliedList,
                                    failedFile: nil
                                ))
                            case .failure(let error):
                                let failureReason = self.normalizeUpdateFailureReason(error)
                                EventBridge.shared.notify(.OnUpdateOtherFailure, refs: [
                                    "reason": failureReason,
                                    "fileList": fileList,
                                    "targetType": target.type,
                                    "executionReason": commandOptions.reason
                                ])
                                next(BatchResult(
                                    target: target,
                                    reason: failureReason,
                                    fileList: fileList,
                                    failedFile: nil
                                ))
                            }
                        }
                    )

                case .failure(let error):
                    let failureReason = self.normalizeUpdateFailureReason(error)
                    EventBridge.shared.notify(.OnUpdateOtherFailure, refs: [
                        "reason": failureReason,
                        "fileList": "",
                        "targetType": target.type,
                        "executionReason": commandOptions.reason
                    ])
                    EventBridge.shared.notify(.OnUpdateCheckFailure, refs: [
                        "reason": failureReason,
                        "executionReason": commandOptions.reason
                    ])
                    next(BatchResult(target: target, reason: failureReason, fileList: "", failedFile: nil))
                }
            }
        }

        process(index: 0, results: [])
    }

    /// Check for updates to all ghosts
    func checkAllGhostsUpdate(options: [String]) {
        let commandOptions = UpdateCommandOptions(options)
        let checkOnly = commandOptions.checkOnly
        let allItems = NarRegistry.shared.installedItems(ofType: "ghost")

        func emitSelectionFailure(reason: String, fileList: String) {
            EventBridge.shared.notify(.OnUpdateOtherFailure, refs: [
                "reason": reason,
                "fileList": fileList,
                "targetType": "ghost",
                "executionReason": commandOptions.reason
            ])
            EventBridge.shared.notify(.OnUpdateCheckFailure, refs: [
                "reason": reason,
                "executionReason": commandOptions.reason
            ])
            EventBridge.shared.notify(.OnUpdateCheckComplete, refs: [
                "reason": reason,
                "fileList": fileList,
                "targetType": "ghost",
                "executionReason": commandOptions.reason
            ])
            self.emitUpdateResultEvents(
                target: "ghost",
                reason: reason,
                fileList: fileList,
                explorerPath: self.ghostURL.path,
                checkOnly: checkOnly
            )
        }

        guard commandOptions.unsupportedSelectors.isEmpty else {
            let requested = commandOptions.unsupportedSelectors
                .map { "\($0.type)=\($0.name)" }
                .joined(separator: ",")
            Log.info("[GhostManager] Unsupported updateother target: \(requested)")
            emitSelectionFailure(reason: "unsupported_target", fileList: requested)
            return
        }

        let requestedNames = commandOptions.selectors
            .filter { $0.type == "ghost" }
            .map(\.name)
        let items: [NarPackageItem]
        if requestedNames.isEmpty {
            items = allItems
        } else {
            items = allItems.filter { item in
                requestedNames.contains {
                    item.name.caseInsensitiveCompare($0) == .orderedSame
                }
            }
            guard !items.isEmpty else {
                let requested = requestedNames.joined(separator: ",")
                Log.info("[GhostManager] updateother target not found: \(requested)")
                emitSelectionFailure(reason: "target_not_found", fileList: requested)
                return
            }
        }

        Log.info("[GhostManager] Checking for updates to \(items.count) selected ghost(s)")
        guard !items.isEmpty else {
            EventBridge.shared.notify(.OnUpdateCheckComplete, refs: [
                "reason": "none",
                "fileList": "",
                "targetType": "ghost",
                "executionReason": commandOptions.reason
            ])
            self.emitUpdateResultEvents(
                target: "ghost",
                reason: "none",
                fileList: "",
                explorerPath: ghostURL.path,
                checkOnly: checkOnly
            )
            return
        }

        struct BatchResult {
            let name: String
            let reason: String
            let fileList: String
            let path: String
            let failedFile: String?
        }

        func emitBatchResultEvents(_ results: [BatchResult]) {
            guard !results.isEmpty else { return }
            let separator = String(UnicodeScalar(1))
            var basicRefs: [String: String] = [:]
            var extendedRefs: [String: String] = [:]
            for (index, result) in results.enumerated() {
                let success = result.reason == "none" || result.reason == "changed"
                let value: String
                if success {
                    let count = result.fileList.isEmpty ? 0 : result.fileList.split(separator: ",").count
                    value = String(count)
                } else {
                    value = result.reason
                }
                var basic = ["ghost", success ? "OK" : "NG", value]
                var extended = [result.name, "ghost", success ? "OK" : "NG", value]
                if let failedFile = result.failedFile, !failedFile.isEmpty {
                    basic.append(failedFile)
                    extended.append(failedFile)
                }
                basicRefs["Reference\(index)"] = basic.joined(separator: separator)
                extendedRefs["Reference\(index)"] = extended.joined(separator: separator)
            }
            let basicEvent: EventID = commandOptions.checkOnly
                ? .OnUpdateCheckResult
                : .OnUpdateResult
            let extendedEvent: EventID = commandOptions.checkOnly
                ? .OnUpdateCheckResultEx
                : .OnUpdateResultEx
            EventBridge.shared.notify(basicEvent, params: basicRefs)
            EventBridge.shared.notify(extendedEvent, params: extendedRefs)
            EventBridge.shared.notify(.OnUpdateResultExplorer, params: basicRefs)
        }

        func process(index: Int, results: [BatchResult]) {
            guard index < items.count else {
                let changed = results.filter { $0.reason == "changed" }
                let failed = results.filter { $0.reason != "changed" && $0.reason != "none" }
                let aggregateReason = failed.isEmpty ? (changed.isEmpty ? "none" : "changed") : failed[0].reason
                let aggregateFiles = results.map(\.name).joined(separator: ",")
                EventBridge.shared.notify(.OnUpdateCheckComplete, refs: [
                    "reason": aggregateReason,
                    "fileList": aggregateFiles,
                    "targetType": "ghost",
                    "executionReason": commandOptions.reason
                ])
                emitBatchResultEvents(results)
                return
            }

            let item = items[index]
            let name = item.name
            let path = item.path.path
            let ghostRoot = item.path.appendingPathComponent("ghost/master", isDirectory: true)
            let next: (BatchResult) -> Void = { result in
                process(index: index + 1, results: results + [result])
            }

            EventBridge.shared.notify(.OnUpdateOtherBegin, refs: [
                "ghostName": name,
                "path": path,
                "targetType": "ghost",
                "executionReason": commandOptions.reason
            ])
            guard let config = GhostConfiguration.load(from: ghostRoot),
                  let updateURL = config.homeurl?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !updateURL.isEmpty,
                  URL(string: updateURL) != nil else {
                let reason = "missing_url"
                EventBridge.shared.notify(.OnUpdateOtherFailure, params: [
                    "Reference0": reason,
                    "Reference1": "",
                    "Reference3": "ghost",
                    "Reference4": commandOptions.reason
                ])
                EventBridge.shared.notify(.OnUpdateCheckFailure, refs: [
                    "reason": reason,
                    "executionReason": commandOptions.reason
                ])
                next(BatchResult(name: name, reason: reason, fileList: "", path: path, failedFile: nil))
                return
            }

            let installer = NarInstaller()
            installer.checkUpdateEntries(homeURLString: updateURL) { result in
                switch result {
                case .success(let entries):
                    let fileList = entries.map(\.filename).joined(separator: ",")
                    let reason = entries.isEmpty ? "none" : "changed"
                    if !entries.isEmpty {
                        EventBridge.shared.notify(.OnUpdateOtherReady, params: [
                            "Reference0": String(max(0, entries.count - 1)),
                            "Reference1": fileList,
                            "Reference3": "ghost",
                            "Reference4": commandOptions.reason
                        ])
                    }
                    EventBridge.shared.notify(.OnUpdateCheckComplete, refs: [
                        "reason": reason,
                        "fileList": fileList,
                        "targetType": "ghost",
                        "executionReason": commandOptions.reason
                    ])
                    if entries.isEmpty || commandOptions.checkOnly {
                        EventBridge.shared.notify(.OnUpdateOtherComplete, params: [
                            "Reference0": reason,
                            "Reference1": fileList,
                            "Reference3": "ghost",
                            "Reference4": commandOptions.reason
                        ])
                        next(BatchResult(name: name, reason: reason, fileList: fileList, path: path, failedFile: nil))
                        return
                    }

                    self.emitUpdateDownloadBeginEvents(
                        base: "OnUpdateOther",
                        entries: entries,
                        targetType: "ghost",
                        executionReason: commandOptions.reason
                    )
                    installer.downloadAndApply(entries: entries, homeURLString: updateURL, targetRoot: item.path,
                                               onMD5Compare: { comparison in
                        let beginParams = [
                            "Reference0": comparison.filename,
                            "Reference1": comparison.correctMD5,
                            "Reference2": comparison.downloadedMD5,
                            "Reference3": "ghost",
                            "Reference4": commandOptions.reason
                        ]
                        self.emitUpdatePipelineEvent(
                            base: "OnUpdateOther",
                            stage: "OnMD5CompareBegin",
                            params: beginParams
                        )
                        let resultParams = [
                            "Reference1": comparison.correctMD5,
                            "Reference2": comparison.downloadedMD5,
                            "Reference3": "ghost",
                            "Reference4": commandOptions.reason
                        ]
                        self.emitUpdatePipelineEvent(
                            base: "OnUpdateOther",
                            stage: comparison.matches ? "OnMD5CompareComplete" : "OnMD5CompareFailure",
                            params: resultParams
                        )
                    }, apply: !commandOptions.testOnly) { applyResult in
                        switch applyResult {
                        case .success(let applied):
                            let appliedList = applied.joined(separator: ",")
                            EventBridge.shared.notify(.OnUpdateOtherComplete, params: [
                                "Reference0": applied.isEmpty ? "none" : "changed",
                                "Reference1": appliedList.isEmpty ? fileList : appliedList,
                                "Reference3": "ghost",
                                "Reference4": commandOptions.reason
                            ])
                            next(BatchResult(
                                name: name,
                                reason: applied.isEmpty ? "none" : "changed",
                                fileList: appliedList.isEmpty ? fileList : appliedList,
                                path: path,
                                failedFile: nil
                            ))
                        case .failure(let error):
                            let failureReason = self.normalizeUpdateFailureReason(error)
                            self.emitUpdatePipelineEvent(base: "OnUpdateOther", stage: "OnDownloadFailure", params: [
                                "Reference0": name,
                                "Reference1": failureReason
                            ])
                            EventBridge.shared.notify(.OnUpdateOtherFailure, params: [
                                "Reference0": failureReason,
                                "Reference1": fileList,
                                "Reference3": "ghost",
                                "Reference4": commandOptions.reason
                            ])
                            next(BatchResult(name: name, reason: failureReason, fileList: fileList, path: path, failedFile: nil))
                        }
                    }

                case .failure(let error):
                    let failureReason = self.normalizeUpdateFailureReason(error)
                    EventBridge.shared.notify(.OnUpdateOtherFailure, params: [
                        "Reference0": failureReason,
                        "Reference1": "",
                        "Reference3": "ghost",
                        "Reference4": commandOptions.reason
                    ])
                    EventBridge.shared.notify(.OnUpdateCheckFailure, refs: [
                        "reason": failureReason,
                        "executionReason": commandOptions.reason
                    ])
                    next(BatchResult(name: name, reason: failureReason, fileList: "", path: path, failedFile: nil))
                }
            }
        }

        process(index: 0, results: [])
    }

    private func emitUpdateBegin(targetType: String, executionReason: String) {
        EventBridge.shared.notify(.OnUpdateBegin, refs: [
            "ghostName": ghostConfig?.name ?? ghostURL.lastPathComponent,
            "path": ghostURL.path,
            "targetType": targetType,
            "executionReason": executionReason
        ])
    }

    /// ネットワーク更新イベントの正式なネストIDを解決する。
    ///
    /// `OnDownloadComplete` / `OnDownloadFailure` は Ourin の互換拡張として残し、
    /// UKADOC が定義する4つのネストイベントだけを正式IDへ接続する。
    static func updatePipelineEventName(base: String, stage: String) -> String {
        switch (base, stage) {
        case ("OnUpdate", "OnDownloadBegin"):
            return EventID.OnUpdateOnDownloadBegin.rawValue
        case ("OnUpdate", "OnMD5CompareBegin"):
            return EventID.OnUpdateOnMD5CompareBegin.rawValue
        case ("OnUpdate", "OnMD5CompareComplete"):
            return EventID.OnUpdateOnMD5CompareComplete.rawValue
        case ("OnUpdate", "OnMD5CompareFailure"):
            return EventID.OnUpdateOnMD5CompareFailure.rawValue
        case ("OnUpdateOther", "OnDownloadBegin"):
            return EventID.OnUpdateOtherOnDownloadBegin.rawValue
        case ("OnUpdateOther", "OnMD5CompareBegin"):
            return EventID.OnUpdateOtherOnMD5CompareBegin.rawValue
        case ("OnUpdateOther", "OnMD5CompareComplete"):
            return EventID.OnUpdateOtherOnMD5CompareComplete.rawValue
        case ("OnUpdateOther", "OnMD5CompareFailure"):
            return EventID.OnUpdateOtherOnMD5CompareFailure.rawValue
        default:
            return "\(base).\(stage)"
        }
    }

    private func emitUpdatePipelineEvent(base: String, stage: String, params: [String: String]) {
        EventBridge.shared.notifyCustom(
            Self.updatePipelineEventName(base: base, stage: stage),
            params: params
        )
    }

    /// 実際にダウンロードを開始するファイルごとに OnDownloadBegin を通知する。
    private func emitUpdateDownloadBeginEvents(
        base: String,
        entries: [UpdateDescriptorEntry],
        targetType: String,
        executionReason: String
    ) {
        let lastIndex = String(max(0, entries.count - 1))
        for (index, entry) in entries.enumerated() {
            emitUpdatePipelineEvent(base: base, stage: "OnDownloadBegin", params: [
                "Reference0": entry.filename,
                "Reference1": String(index),
                "Reference2": lastIndex,
                "Reference3": targetType,
                "Reference4": executionReason
            ])
        }
    }

    private func emitUpdateResultEvents(
        target: String,
        targetName: String? = nil,
        reason: String,
        fileList: String,
        explorerPath: String,
        checkOnly: Bool = false,
        failedFile: String? = nil
    ) {
        let success = reason == "none" || reason == "changed"
        let resultValue: String
        if success {
            let count = fileList.isEmpty ? 0 : fileList.split(separator: ",").count
            resultValue = count == 0 ? "0" : String(count)
        } else {
            resultValue = reason
        }
        let separator = String(UnicodeScalar(1))
        var result = [target, success ? "OK" : "NG", resultValue]
        if let failedFile, !failedFile.isEmpty { result.append(failedFile) }
        let resultValueBasic = result.joined(separator: separator)

        let defaultTargetName: String
        if target == "ghost" {
            defaultTargetName = ghostConfig?.name ?? ghostURL.lastPathComponent
        } else if target == "baseware" {
            defaultTargetName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Ourin"
        } else {
            defaultTargetName = target
        }
        var resultEx = [targetName ?? defaultTargetName, target, success ? "OK" : "NG", resultValue]
        if let failedFile, !failedFile.isEmpty { resultEx.append(failedFile) }
        let resultValueEx = resultEx.joined(separator: separator)

        let basicEvent: EventID = checkOnly ? .OnUpdateCheckResult : .OnUpdateResult
        let extendedEvent: EventID = checkOnly ? .OnUpdateCheckResultEx : .OnUpdateResultEx
        EventBridge.shared.notify(basicEvent, params: ["Reference0": resultValueBasic])
        EventBridge.shared.notify(extendedEvent, params: ["Reference0": resultValueEx])
        // Explorer execution has no separate Ex event in the current EventID set;
        // its basic record remains the same three/four-field OnUpdateResult record.
        EventBridge.shared.notify(.OnUpdateResultExplorer, params: ["Reference0": resultValueBasic])
    }

    private func normalizeUpdateFailureReason(_ error: Error) -> String {
        if let narError = error as? NarInstaller.Error {
            switch narError {
            case .updateMD5Mismatch:
                return "md5 miss"
            case .basewareArchiveUnsupported:
                return "baseware_archive_unsupported"
            case .updateDescriptorInvalid:
                return "paramerror"
            default:
                break
            }
        }
        if let coordinatorError = error as? BasewareUpdateCoordinator.Error {
            switch coordinatorError {
            case .invalidTarget:
                return "baseware_target_invalid"
            case .archiveEntry:
                return "baseware_archive_unsupported"
            case .stagingDirectoryCreationFailed, .appCopyFailed, .markerFailed:
                return "baseware_staging_failed"
            }
        }
        if let helperError = error as? BasewareUpdateHelper.Error {
            switch helperError {
            case .invalidRequest, .helperLaunchFailed:
                return "baseware_helper_unavailable"
            case .parentDidNotExit:
                return "baseware_shutdown_timeout"
            case .replacementFailed, .relaunchFailed:
                return "baseware_replace_failed"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "timeout"
            case .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
                // 404 は HTTP 応答コードであり、DNS/接続失敗を表さない。
                // ネットワーク層で応答を受け取れていない場合は、その事実を保つ。
                return "network"
            default:
                break
            }
        }

        let lower = error.localizedDescription.lowercased()
        if lower.contains("timed out") {
            return "timeout"
        }
        if lower.contains("404") {
            return "404"
        }
        if lower.isEmpty {
            return "paramerror"
        }
        return error.localizedDescription
    }
    
    /// ゴーストを終了する。通常のゴースト切替ではウィンドウだけを閉じ、
    /// `vanishbymyself` ではインストール済みゴーストをゴミ箱へ移動してから
    /// ランタイムも確実に解放する。
    func executeVanish(uninstall: Bool = false, nextGhostName: String? = nil, query: Bool = false) {
        let operation = {
            let currentInfo = self.currentGhostEventInfo
            let currentName = currentInfo.ghostName

            // 消滅イベントは UKADOC 上 GET。OnVanishSelecting/Cancel の返答は
            // 現在のゴーストで再生し、OnVanishSelected の返答だけは後続の
            // OnVanished/OnOtherGhostVanished Reference1 に引き渡す。
            _ = EventBridge.shared.requestScript(.OnVanishSelecting, to: self)

            if query {
                let alert = NSAlert()
                alert.messageText = "ゴーストの消滅"
                alert.informativeText = "「\(currentName)」を消滅させますか？\nこの操作は取り消せません。"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "消滅")
                alert.addButton(withTitle: "キャンセル")
                guard alert.runModal() == .alertFirstButtonReturn else {
                    _ = EventBridge.shared.requestScript(.OnVanishCancel, to: self)
                    return
                }
            }

            guard uninstall else {
                self.closeVanishWindowsOnly(currentName: currentName)
                return
            }

            let vanishSelectedScript = EventBridge.shared.requestScript(
                .OnVanishSelected,
                to: self,
                playResponse: false
            ) ?? ""
            let lastScript = self.choiceSourceScript
            let complete = { [weak self] in
                guard let self else { return }
                self.finishVanish(
                    currentInfo: currentInfo,
                    currentName: currentName,
                    nextGhostName: nextGhostName,
                    lastScript: lastScript,
                    vanishSelectedScript: vanishSelectedScript
                )
            }
            guard !vanishSelectedScript.isEmpty else {
                complete()
                return
            }
            self.beginVanishSelectedPlayback(
                sourceScript: vanishSelectedScript,
                completion: complete
            )
        }

        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }

    /// OnVanishSelected の応答が最後まで再生された後に、実際の消滅処理を行う。
    /// 再生中のダブルクリックで OnVanishButtonHold が成立した場合は、このメソッドの
    /// 完了クロージャ自体が破棄されるため、ゴミ箱移動へ進まない。
    private func finishVanish(
        currentInfo: GhostEventInfo,
        currentName: String,
        nextGhostName: String?,
        lastScript: String,
        vanishSelectedScript: String
    ) {
        EventBridge.shared.notify(.OnVanishing, params: [:])

        let targetItem = vanishTargetItem(preferredName: nextGhostName)
        do {
            guard FileManager.default.fileExists(atPath: ghostURL.path) else {
                throw NSError(domain: "OurinVanish", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "ghost directory does not exist"
                ])
            }
            try FileManager.default.trashItem(at: ghostURL, resultingItemURL: nil)
        } catch {
            Log.info("[GhostManager] Failed to vanish ghost \(currentName): \(error)")
            EventBridge.shared.notifyCustom("OnVanishFailure", refs: [
                "ghostName": currentName,
                "reason": error.localizedDescription
            ])
            return
        }

        // OnFirstBoot の Reference0（vanish された回数）用に記録する。
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: "OurinVanishCount") + 1, forKey: "OurinVanishCount")
        // 次に起動するゴーストを初回扱い（OnFirstBoot）にする。
        defaults.set(0, forKey: "OurinBootCount")

        // 同時起動中の他ゴーストへは、消滅元を除外した GET を送る。
        // R1/R7 を欠落させないよう、最後のスクリプトと消滅元シェルも渡す。
        let targetShellName = targetItem.map {
            ghostEventInfo(named: $0.name).shellName
        } ?? ""
        let otherClosedParams = EventReferenceTable.params(
            forEvent: EventID.OnOtherGhostClosed.rawValue,
            refs: [
                "ghostName": currentInfo.mainName,
                "lastScript": lastScript,
                "closedGhostName": currentInfo.ghostName,
                "shellName": currentInfo.shellName
            ]
        )
        _ = EventBridge.shared.request(
            .OnOtherGhostClosed,
            params: otherClosedParams,
            excluding: [self]
        )

        let otherVanishedParams = EventReferenceTable.params(
            forEvent: EventID.OnOtherGhostVanished.rawValue,
            refs: [
                "ghostName": currentInfo.mainName,
                "vanishSelectedScript": vanishSelectedScript,
                "vanishedGhostName": currentInfo.ghostName,
                "shellName": targetShellName
            ]
        )
        _ = EventBridge.shared.request(
            .OnOtherGhostVanished,
            params: otherVanishedParams,
            excluding: [self]
        )

        let appDelegate = NSApp.delegate as? AppDelegate
        let isPrimary = appDelegate?.ghostManager === self
        if isPrimary {
            appDelegate?.ghostManager = nil
        }

        if let appDelegate {
            if isPrimary {
                _ = shutdown()
                if let targetItem {
                    let vanishedBootRequest = GhostBootRequest(
                        eventID: .OnVanished,
                        references: [
                            currentInfo.mainName,
                            vanishSelectedScript,
                            currentInfo.ghostName,
                            "", "", "", "", ""
                        ]
                    )
                    appDelegate.runGhost(at: targetItem.path, bootRequest: vanishedBootRequest)
                }
            } else {
                appDelegate.terminateAdditionalGhost(self)
            }
        } else {
            _ = shutdown()
        }
        Log.debug("[GhostManager] Ghost vanished successfully: \(currentName)")
    }

    /// OnVanishSelected の応答を再生キューへ投入し、完了後の削除処理を保留する。
    func beginVanishSelectedPlayback(sourceScript: String, completion: @escaping () -> Void) {
        let context = ScriptTranslationContext(eventID: EventID.OnVanishSelected.rawValue)
        let displayScript = translateForDisplay(sourceScript, context: context)
        vanishSelectedSourceScript = sourceScript
        vanishSelectedDisplayScript = displayScript
        vanishSelectedCompletion = completion
        vanishLastClickAt = nil
        vanishLastClickScope = nil

        guard !displayScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completeVanishSelectedPlayback()
            return
        }
        runTranslatedScript(displayScript)
        // 数値応答などで runTranslatedScript が再生を拒否した場合も、消滅処理を
        // 保留したままにしない。
        if !isPlaying, playbackQueue.isEmpty {
            completeVanishSelectedPlayback()
        }
    }

    /// 再生キュー終端から呼ばれる OnVanishSelected 完了出口。
    func completeVanishSelectedPlayback() {
        guard let completion = vanishSelectedCompletion else { return }
        vanishSelectedSourceScript = nil
        vanishSelectedDisplayScript = nil
        vanishSelectedCompletion = nil
        vanishLastClickAt = nil
        vanishLastClickScope = nil
        completion()
    }

    /// 通常のゴースト切替で使う終了処理。ランタイムやインストールデータは保持する。
    private func closeVanishWindowsOnly(currentName: String) {
        Log.info("[GhostManager] Closing ghost windows for switch: \(currentName)")
        for window in characterWindows.values { window.close() }
        for window in balloonWindows.values { window.close() }
        characterWindows.removeAll()
        balloonWindows.removeAll()
        playbackQueue.removeAll()
        isPlaying = false
        vanishSelectedSourceScript = nil
        vanishSelectedDisplayScript = nil
        vanishSelectedCompletion = nil
        vanishLastClickAt = nil
        vanishLastClickScope = nil
    }

    /// 消滅後の切替先を、明示指定→現在位置からの順序選択→先頭の順に解決する。
    private func vanishTargetItem(preferredName: String?) -> NarPackageItem? {
        let currentName = ghostConfig?.name ?? ghostURL.lastPathComponent
        let items = NarRegistry.shared.installedItems(ofType: "ghost").filter {
            $0.path.standardizedFileURL != ghostURL.standardizedFileURL &&
                $0.name.caseInsensitiveCompare(currentName) != .orderedSame
        }

        if let preferredName,
           let preferred = items.first(where: {
               $0.name.caseInsensitiveCompare(preferredName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
           }) {
            return preferred
        }

        let allItems = NarRegistry.shared.installedItems(ofType: "ghost")
        if let sequentialName = NarRegistry.sequentialGhostName(items: allItems, currentName: currentName),
           let sequential = items.first(where: { $0.name.caseInsensitiveCompare(sequentialName) == .orderedSame }) {
            return sequential
        }
        return items.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }.first
    }

    func executeExtractArchive(params: [String]) {
        let options = ArchiveCommandOptions(params)
        guard params.count >= 2 else {
            dispatchArchiveCompatibilityEvent(operation: "extract", success: false, error: "invalid parameter")
            dispatchArchiveEvent(
                defaultEvent: .OnExtractArchiveComplete,
                defaultFailureEvent: .OnExtractArchiveFailure,
                requestedEventID: options.eventID,
                success: false,
                refs: ["eventID": options.eventID ?? "", "error": "invalid parameter"]
            )
            return
        }

        let archive = resolvedPath(params[0])
        let destination = resolvedPath(params[1])
        let compressedSize = ArchiveStatistics.fileSize(at: archive)
        EventBridge.shared.notifyCustom("OnExtractArchiveBegin", refs: [
            "archivePath": archive.path,
            "destPath": destination.path
        ], to: self, ignoreResponseScript: true)

        let processPath: String
        let processArguments: [String]
        if let password = options.password {
            processPath = "/usr/bin/unzip"
            processArguments = ["-q", "-o", "-P", password, archive.path, "-d", destination.path]
        } else {
            processPath = "/usr/bin/ditto"
            processArguments = ["-x", "-k", archive.path, destination.path]
        }

        runProcess(path: processPath, arguments: processArguments) { [weak self] output, ok in
            guard let self else { return }
            if ok {
                let stats = ArchiveStatistics.fileTree(at: destination)
                let refs = [
                    "eventID": options.eventID ?? "",
                    "fileCount": String(stats.fileCount),
                    "compressedSize": String(compressedSize),
                    "uncompressedSize": String(stats.byteCount)
                ]
                self.dispatchArchiveCompatibilityEvent(operation: "extract", success: true, error: nil, refs: refs)
                self.dispatchArchiveEvent(
                    defaultEvent: .OnExtractArchiveComplete,
                    defaultFailureEvent: .OnExtractArchiveFailure,
                    requestedEventID: options.eventID,
                    success: true,
                    refs: refs
                )
            } else {
                let error = self.archiveFailureCode(output: output, source: archive, destination: destination)
                self.dispatchArchiveCompatibilityEvent(operation: "extract", success: false, error: error)
                self.dispatchArchiveEvent(
                    defaultEvent: .OnExtractArchiveComplete,
                    defaultFailureEvent: .OnExtractArchiveFailure,
                    requestedEventID: options.eventID,
                    success: false,
                    refs: ["eventID": options.eventID ?? "", "error": error]
                )
            }
        }
    }

    func executeCompressArchive(params: [String]) {
        let options = ArchiveCommandOptions(params)
        guard params.count >= 2 else {
            dispatchArchiveCompatibilityEvent(operation: "compress", success: false, error: "invalid parameter")
            dispatchArchiveEvent(
                defaultEvent: .OnCompressArchiveComplete,
                defaultFailureEvent: .OnCompressArchiveFailure,
                requestedEventID: options.eventID,
                success: false,
                refs: ["eventID": options.eventID ?? "", "error": "invalid parameter"]
            )
            return
        }

        let source = resolvedPath(params[0])
        let output = resolvedPath(params[1])
        let sourceStats = ArchiveStatistics.fileTree(at: source)
        EventBridge.shared.notifyCustom("OnCompressArchiveBegin", refs: [
            "source": source.path,
            "outputPath": output.path
        ], to: self, ignoreResponseScript: true)

        let processPath: String
        let processArguments: [String]
        let currentDirectoryURL: URL?
        if let password = options.password {
            processPath = "/usr/bin/zip"
            processArguments = ["-q", "-r", "-P", password, output.path, source.lastPathComponent]
            currentDirectoryURL = source.deletingLastPathComponent()
        } else {
            processPath = "/usr/bin/ditto"
            processArguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", source.path, output.path]
            currentDirectoryURL = nil
        }

        runProcess(
            path: processPath,
            arguments: processArguments,
            currentDirectoryURL: currentDirectoryURL
        ) { [weak self] result, ok in
            guard let self else { return }
            if ok {
                let refs = [
                    "eventID": options.eventID ?? "",
                    "fileCount": String(sourceStats.fileCount),
                    "compressedSize": String(ArchiveStatistics.fileSize(at: output)),
                    "uncompressedSize": String(sourceStats.byteCount)
                ]
                self.dispatchArchiveCompatibilityEvent(operation: "compress", success: true, error: nil, refs: refs)
                self.dispatchArchiveEvent(
                    defaultEvent: .OnCompressArchiveComplete,
                    defaultFailureEvent: .OnCompressArchiveFailure,
                    requestedEventID: options.eventID,
                    success: true,
                    refs: refs
                )
            } else {
                let error = self.archiveFailureCode(output: result, source: source, destination: output)
                self.dispatchArchiveCompatibilityEvent(operation: "compress", success: false, error: error)
                self.dispatchArchiveEvent(
                    defaultEvent: .OnCompressArchiveComplete,
                    defaultFailureEvent: .OnCompressArchiveFailure,
                    requestedEventID: options.eventID,
                    success: false,
                    refs: ["eventID": options.eventID ?? "", "error": error]
                )
            }
        }
    }

    private func dispatchArchiveCompatibilityEvent(
        operation: String,
        success: Bool,
        error: String?,
        refs: [String: String] = [:]
    ) {
        if success {
            EventBridge.shared.notify(
                .OnArchiveComplete,
                refs: refs,
                to: self,
                ignoreResponseScript: true
            )
        } else {
            EventBridge.shared.notify(
                .OnArchiveFailure,
                refs: ["operation": operation, "reason": error ?? "open failed"],
                to: self,
                ignoreResponseScript: true
            )
        }
    }

    private func dispatchArchiveEvent(
        defaultEvent: EventID,
        defaultFailureEvent: EventID,
        requestedEventID: String?,
        success: Bool,
        refs: [String: String]
    ) {
        let params = EventReferenceTable.params(
            forEvent: (success ? defaultEvent : defaultFailureEvent).rawValue,
            refs: refs
        )
        if let requestedEventID, requestedEventID.hasPrefix("On") {
            let eventName = success ? requestedEventID : "\(requestedEventID)Failure"
            _ = EventBridge.shared.requestCustom(eventName, params: params, to: self)
        } else {
            let eventID = success ? defaultEvent : defaultFailureEvent
            _ = EventBridge.shared.request(eventID, params: params, to: self)
        }
    }

    private func archiveFailureCode(output: String, source: URL, destination: URL) -> String {
        let fileManager = FileManager.default
        let output = output.lowercased()
        if !fileManager.fileExists(atPath: source.path) {
            return "file not found"
        }
        let destinationParent = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: destinationParent.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            return "directory not found"
        }
        if output.contains("password") {
            return "password required"
        }
        if output.contains("crc") {
            return "crc"
        }
        if output.contains("corrupt") {
            return "corrupted"
        }
        if output.contains("permission") {
            return "open failed"
        }
        return "open failed"
    }

    /// 現在表示中のサーフェスを、ベース・SERIKOオーバーレイ・着せ替えパーツまで
    /// 含めて1枚へ合成する。zeroOrigin=true の場合は負座標を切り捨て、false では
    /// 負座標ぶんキャンバスを左上へ拡張する。
    private func dumpSurfaceImage(scope: Int, surfaceID: Int, zeroOrigin: Bool) -> NSImage? {
        guard let vm = characterViewModels[scope],
              vm.currentSurfaceID == surfaceID,
              let baseImage = vm.image else {
            return loadImage(surfaceId: surfaceID, scope: scope)
        }

        let baseEffects = vm.activeEffects.filter { $0.surfaceID == nil }
        let effectiveBase = baseEffects.isEmpty
            ? baseImage
            : (SurfaceVisualEffectRenderer.applying(image: baseImage, effects: baseEffects, filters: []) ?? baseImage)
        var layers: [SurfaceOverlay] = [SurfaceOverlay(
            id: "dump-base-\(scope)-\(surfaceID)",
            image: effectiveBase,
            offset: .zero,
            alpha: 1,
            zOrder: -10_000,
            insertionOrder: -10_000,
            blendMode: .normal,
            surfaceID: surfaceID,
            animationID: nil
        )]

        let targetedEffects = vm.activeEffects.filter { $0.surfaceID != nil }
        for overlay in SurfaceOverlay.sortedForDisplay(vm.overlays) {
            var copy = overlay
            let effects = targetedEffects.filter { $0.surfaceID == overlay.surfaceID }
            if !effects.isEmpty,
               let processed = SurfaceVisualEffectRenderer.applying(image: overlay.image, effects: effects, filters: []) {
                copy.image = processed
            }
            layers.append(copy)
        }
        for (index, part) in vm.dressupParts.enumerated() where part.isEnabled {
            layers.append(SurfaceOverlay(
                id: "dump-dressup-\(index)-\(part.category)-\(part.partName)",
                image: part.image,
                offset: part.frame.origin,
                alpha: 1,
                zOrder: 1_000 + part.zOrder,
                insertionOrder: index,
                blendMode: .normal,
                surfaceID: nil,
                animationID: nil
            ))
        }

        let minX = layers.map(\.offset.x).min() ?? 0
        let minY = layers.map(\.offset.y).min() ?? 0
        let shift = zeroOrigin
            ? CGPoint.zero
            : CGPoint(x: max(0, -minX), y: max(0, -minY))
        let shifted = layers.map { layer -> SurfaceOverlay in
            var copy = layer
            copy.offset = CGPoint(x: layer.offset.x + shift.x, y: layer.offset.y + shift.y)
            return copy
        }
        guard let composited = SurfaceBlendRenderer.composite(base: nil, overlays: shifted) else { return nil }
        guard !vm.activeFilters.isEmpty else { return composited }
        return SurfaceVisualEffectRenderer.applying(image: composited, effects: [], filters: vm.activeFilters) ?? composited
    }

    func executeDumpSurface(params: [String]) {
        guard !params.isEmpty else {
            let output = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ourin_surface_\(currentScope).png")
            writeDumpSurfaceImage(
                dumpSurfaceImage(
                    scope: currentScope,
                    surfaceID: characterViewModels[currentScope]?.currentSurfaceID ?? 0,
                    zeroOrigin: false
                ),
                to: output,
                eventID: nil,
                zeroOrigin: false
            )
            return
        }

        // 旧形式 \\![execute,dumpsurface,file.png] は単一ファイル出力として維持する。
        let firstPath = resolvedPath(params[0])
        if params.count == 1, firstPath.pathExtension.lowercased() == "png" {
            writeDumpSurfaceImage(
                dumpSurfaceImage(
                    scope: currentScope,
                    surfaceID: characterViewModels[currentScope]?.currentSurfaceID ?? 0,
                    zeroOrigin: false
                ),
                to: firstPath,
                eventID: nil,
                zeroOrigin: false
            )
            return
        }

        // SSP形式: directory, scope, surface-list, prefix, eventID, zero-origin。
        let outputDirectory = firstPath
        let scope = Int(params.count > 1 ? params[1] : "") ?? currentScope
        let surfaceSpec = params.count > 2 ? params[2] : "__system_surface_all__"
        let prefixValue = params.count > 3 ? params[3] : ""
        let prefix = prefixValue.isEmpty ? "surface" : prefixValue
        let eventID = params.count > 4 ? params[4].trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let zeroOriginValue = params.count > 5 ? params[5].lowercased() : ""
        let zeroOrigin = zeroOriginValue == "1" || zeroOriginValue == "true"
        let surfaceIDs = dumpSurfaceIDs(for: surfaceSpec, scope: scope)

        guard !surfaceIDs.isEmpty else {
            emitDumpSurfaceFailure(eventID: eventID, reason: "surface_not_found")
            return
        }

        do {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            emitDumpSurfaceFailure(eventID: eventID, reason: error.localizedDescription)
            return
        }

        var written = 0
        for surfaceID in surfaceIDs {
            let image = dumpSurfaceImage(scope: scope, surfaceID: surfaceID, zeroOrigin: zeroOrigin)
            let output = outputDirectory.appendingPathComponent("\(prefix)\(surfaceID).png")
            if writeDumpSurfaceImage(image, to: output, eventID: nil, zeroOrigin: zeroOrigin) {
                written += 1
            }
        }

        if written == surfaceIDs.count {
            if let eventID, !eventID.isEmpty {
                _ = EventBridge.shared.requestCustom(eventID, params: ["Reference0": String(written)])
            }
        } else {
            emitDumpSurfaceFailure(eventID: eventID, reason: "encode_failed")
        }
    }

    private func dumpSurfaceIDs(for specification: String, scope: Int) -> [Int] {
        let normalized = specification.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "__system_surface_all__" || normalized == "__system_surface_defined__" {
            var ids = Set(parsedSurfaceDefs.keys)
            if let table = surfaceTable {
                ids.formUnion(table.definedSurfaceIDs)
            }
            if normalized == "__system_surface_all__", let shellURL = loadShellPath(),
               let entries = try? FileManager.default.contentsOfDirectory(at: shellURL, includingPropertiesForKeys: nil) {
                let regex = try? NSRegularExpression(pattern: #"^surface(?:1)?(\d+)(?:@\d+x)?\.png$"#, options: .caseInsensitive)
                for entry in entries {
                    let name = entry.lastPathComponent
                    guard let regex,
                          let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                          let range = Range(match.range(at: 1), in: name),
                          let id = Int(name[range]) else { continue }
                    ids.insert(id)
                }
            }
            return ids.sorted()
        }

        var ids = Set<Int>()
        for token in specification.split(separator: ",") {
            let value = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
            if let rangeSeparator = value.firstIndex(of: "-"),
               let start = Int(value[..<rangeSeparator]),
               let end = Int(value[value.index(after: rangeSeparator)...]),
               start <= end {
                ids.formUnion(start...end)
            } else if let id = Int(value) {
                ids.insert(id)
            } else if let alias = surfaceNameAliases[value.lowercased()] {
                ids.insert(alias)
            }
        }
        return ids.sorted()
    }

    @discardableResult
    private func writeDumpSurfaceImage(_ image: NSImage?, to output: URL, eventID: String?, zeroOrigin: Bool) -> Bool {
        guard let image,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            emitDumpSurfaceFailure(eventID: eventID, reason: "missing_surface_or_encode_failed")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: output)
            return true
        } catch {
            emitDumpSurfaceFailure(eventID: eventID, reason: error.localizedDescription)
            return false
        }
    }

    private func emitDumpSurfaceFailure(eventID: String?, reason: String) {
        if let eventID, !eventID.isEmpty {
            _ = EventBridge.shared.requestCustom(eventID, params: [
                "Reference0": "0",
                "Reference1": reason
            ])
        } else {
            EventBridge.shared.notifyCustom("OnDumpSurfaceFailure", refs: ["reason": reason])
        }
    }

    /// キャラクターウィンドウへドロップされたURLを、標準のURLドロップ
    /// 生命周期へ接続する。OnURLDrop は Ourin 拡張として先に許可し、
    /// 応答が無い場合だけ UKADOC の OnURLQuery→ダウンロードへ進む。
    func handleURLDropEvent(_ event: ShioriEvent) {
        let rawURL = event.params["Reference0"] ?? event.params["url"] ?? ""
        let scopeID = Int(event.params["Reference1"] ?? event.params["scopeID"] ?? "") ?? 0
        let allowInsecureHTTP = URLDropPolicy.allowsInsecureHTTP()
        let security = ShioriSecurityContext.external(origin: "drag-drop")

        guard let url = URLDropPolicy.remoteURL(
            from: rawURL,
            allowInsecureHTTP: allowInsecureHTTP,
            resolveHost: false
        ) else {
            // URL の構文不正・許可外スキーム・HTTP の明示許可漏れは、まだ
            // URL の受信を試みていないため OnURLDropFailure の対象ではない。
            // 失敗イベントは OnURLDropping 後の受信／保存／設置失敗に限定する。
            Log.info("[GhostManager] rejected URL drop before download: \(rawURL)")
            return
        }

        guard activeURLDropTransferID == nil else {
            Log.info("[GhostManager] URL drop ignored while another URL is downloading")
            return
        }

        if let response = EventBridge.shared.requestScript(
            .OnURLDrop,
            params: event.params,
            to: self,
            security: security
        ), !Self.shouldIgnoreNumericEventResponse(response, eventID: EventID.OnURLDrop.rawValue) {
            return
        }

        let queryParams = EventReferenceTable.params(
            forEvent: EventID.OnURLQuery.rawValue,
            refs: URLDropPolicy.queryReferences(for: url, scopeID: scopeID)
        )
        if let response = EventBridge.shared.requestScript(
            .OnURLQuery,
            params: queryParams,
            to: self,
            security: security
        ), !Self.shouldIgnoreNumericEventResponse(response, eventID: EventID.OnURLQuery.rawValue) {
            return
        }

        switch URLDropPolicy.plannedAction(for: url) {
        case "nar":
            beginURLDropDownload(from: url, scopeID: scopeID, security: security)
        case "feed", "homeurl":
            // UKADOC: feed/homeurl はURLドロップ専用イベントを発火せず、
            // OnURLQuery後の execute,install,url と同じ処理へ渡す。
            executeInstall(params: ["url", url.absoluteString, URLDropPolicy.plannedAction(for: url)])
        default:
            Log.debug("[GhostManager] URL drop has no supported automatic action: \(url.absoluteString)")
        }
    }

    private func beginURLDropDownload(
        from url: URL,
        scopeID: Int,
        security: ShioriSecurityContext
    ) {
        let transferID = UUID()
        activeURLDropTransferID = transferID

        // DNS 解決は UI イベントのメインスレッドから外す。検査に失敗した URL は
        // OnURLDropping より前に止めるため、OnURLDropFailure は発火しない。
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard URLDropPolicy.isPublicRemoteHost(url.host ?? "") else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeURLDropTransferID == transferID else { return }
                    self.activeURLDropTransferID = nil
                    Log.info("[GhostManager] URL drop host rejected before download: \(url.absoluteString)")
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeURLDropTransferID == transferID else { return }
                self.startURLDropDownload(
                    transferID: transferID,
                    from: url,
                    scopeID: scopeID,
                    security: security
                )
            }
        }
    }

    private func startURLDropDownload(
        transferID: UUID,
        from url: URL,
        scopeID: Int,
        security: ShioriSecurityContext
    ) {
        let droppingParams = EventReferenceTable.params(
            forEvent: EventID.OnURLDropping.rawValue,
            refs: ["url": url.absoluteString, "scopeID": String(scopeID)]
        )
        _ = EventBridge.shared.requestScript(
            .OnURLDropping,
            params: droppingParams,
            to: self,
            security: security
        )

        let delegate = URLDropDownloadDelegate(
            allowInsecureHTTP: URLDropPolicy.allowsInsecureHTTP(),
            maximumBytes: URLDropPolicy.maxDownloadBytes
        ) { [weak self] localURL, response, error in
            guard self != nil else {
                if let localURL {
                    try? FileManager.default.removeItem(at: localURL)
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.activeURLDropTransferID == transferID else {
                    if let localURL {
                        try? FileManager.default.removeItem(at: localURL)
                    }
                    return
                }
                self.finishURLDropDownload(
                    transferID: transferID,
                    localURL: localURL,
                    response: response,
                    sourceURL: url,
                    scopeID: scopeID,
                    error: error,
                    security: security
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
        let task = session.downloadTask(with: url)
        activeURLDropTransferID = transferID
        activeURLDropTask = task
        activeURLDropSession = session
        activeURLDropDelegate = delegate
        task.resume()
    }

    /// `\![execute,install,url,...]` 用のNARダウンロードを、URLドロップと同じ
    /// サイズ・リダイレクト・一時ファイル管理で実行する。
    private func startExecuteInstallNarDownload(from url: URL) {
        guard activeURLDropTransferID == nil else {
            EventBridge.shared.notifyCustom("OnInstallFailure", refs: ["reason": "artificial"])
            return
        }

        let transferID = UUID()
        activeURLDropTransferID = transferID
        let delegate = URLDropDownloadDelegate(
            allowInsecureHTTP: URLDropPolicy.allowsInsecureHTTP(),
            maximumBytes: URLDropPolicy.maxDownloadBytes
        ) { [weak self] localURL, response, error in
            guard self != nil else {
                if let localURL {
                    try? FileManager.default.removeItem(at: localURL)
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.activeURLDropTransferID == transferID else {
                    if let localURL {
                        try? FileManager.default.removeItem(at: localURL)
                    }
                    return
                }
                self.finishExecuteInstallNarDownload(
                    transferID: transferID,
                    localURL: localURL,
                    response: response,
                    sourceURL: url,
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
        let task = session.downloadTask(with: url)
        activeURLDropTask = task
        activeURLDropSession = session
        activeURLDropDelegate = delegate
        task.resume()
    }

    private func finishExecuteInstallNarDownload(
        transferID: UUID,
        localURL: URL?,
        response: URLResponse?,
        sourceURL: URL,
        error: Error?
    ) {
        guard activeURLDropTransferID == transferID else {
            if let localURL {
                try? FileManager.default.removeItem(at: localURL)
            }
            return
        }
        let session = activeURLDropSession
        activeURLDropTransferID = nil
        activeURLDropTask = nil
        activeURLDropSession = nil
        activeURLDropDelegate = nil
        session?.finishTasksAndInvalidate()

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
            archiveURL = try normalizedDownloadedArchiveURL(
                localURL: localURL,
                response: response,
                sourceURL: sourceURL
            )
            _ = installNarFile(archiveURL ?? localURL)
        } catch {
            EventBridge.shared.notifyCustom("OnInstallFailure", refs: [
                "reason": URLDropFailureReason.forInstallation(error: error)
            ])
        }
    }

    private func preflightExecuteInstallURL(
        _ url: URL,
        completion: @escaping () -> Void
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard self != nil else { return }
            guard URLDropPolicy.isPublicRemoteHost(url.host ?? "") else {
                DispatchQueue.main.async {
                    EventBridge.shared.notifyCustom("OnInstallFailure", refs: ["reason": "fileio"])
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }
                completion()
            }
        }
    }

    /// ゴースト終了時に URLSession を止め、完了コールバック側へ失敗イベントを残さない。
    /// delegate が既に一時ファイルを確保していた場合は、transferID 不一致時のコールバックで消去する。
    func cancelActiveURLDropDownload() {
        activeURLDropTask?.cancel()
        activeURLDropSession?.invalidateAndCancel()
        activeURLDropTransferID = nil
        activeURLDropTask = nil
        activeURLDropSession = nil
        activeURLDropDelegate = nil
    }

    private func finishURLDropDownload(
        transferID: UUID,
        localURL: URL?,
        response: URLResponse?,
        sourceURL: URL,
        scopeID: Int,
        error: Error?,
        security: ShioriSecurityContext
    ) {
        guard activeURLDropTransferID == transferID else {
            if let localURL {
                try? FileManager.default.removeItem(at: localURL)
            }
            return
        }
        let session = activeURLDropSession
        activeURLDropTransferID = nil
        activeURLDropTask = nil
        activeURLDropSession = nil
        activeURLDropDelegate = nil
        session?.finishTasksAndInvalidate()

        var archiveURL: URL?
        defer {
            if let archiveURL {
                try? FileManager.default.removeItem(at: archiveURL)
            }
            if let localURL, localURL != archiveURL {
                try? FileManager.default.removeItem(at: localURL)
            }
        }

        if error != nil {
            emitURLDropFailure(
                localPath: localURL?.path ?? "",
                reason: URLDropFailureReason.forDownload(error: error),
                url: sourceURL.absoluteString,
                scopeID: scopeID,
                security: security
            )
            return
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            emitURLDropFailure(
                localPath: localURL?.path ?? "",
                reason: URLDropFailureReason.httpStatus(httpResponse.statusCode),
                url: sourceURL.absoluteString,
                scopeID: scopeID,
                security: security
            )
            return
        }

        guard let localURL else {
            emitURLDropFailure(
                localPath: "",
                reason: "fileio",
                url: sourceURL.absoluteString,
                scopeID: scopeID,
                security: security
            )
            return
        }

        do {
            archiveURL = try normalizedDownloadedArchiveURL(
                localURL: localURL,
                response: response,
                sourceURL: sourceURL
            )

            let droppedParams = EventReferenceTable.params(
                forEvent: EventID.OnURLDropped.rawValue,
                refs: [
                    "filePath": archiveURL?.path ?? localURL.path,
                    "url": sourceURL.absoluteString,
                    "scopeID": String(scopeID)
                ]
            )
            _ = EventBridge.shared.requestScript(
                .OnURLDropped,
                params: droppedParams,
                to: self,
                security: security
            )

            switch installNarFile(archiveURL ?? localURL) {
            case .installed:
                break
            case .refused:
                emitURLDropFailure(
                    localPath: archiveURL?.path ?? localURL.path,
                    reason: "artificial",
                    url: sourceURL.absoluteString,
                    scopeID: scopeID,
                    security: security
                )
            case .failed(let installError):
                emitURLDropFailure(
                    localPath: archiveURL?.path ?? localURL.path,
                    reason: URLDropFailureReason.forInstallation(error: installError),
                    url: sourceURL.absoluteString,
                    scopeID: scopeID,
                    security: security
                )
            }
        } catch {
            emitURLDropFailure(
                localPath: archiveURL?.path ?? localURL.path,
                reason: URLDropFailureReason.forInstallation(error: error),
                url: sourceURL.absoluteString,
                scopeID: scopeID,
                security: security
            )
        }
    }

    private func emitURLDropFailure(
        localPath: String,
        reason: String,
        url: String,
        scopeID: Int,
        security: ShioriSecurityContext
    ) {
        let params = EventReferenceTable.params(
            forEvent: EventID.OnURLDropFailure.rawValue,
            refs: [
                "filePath": localPath,
                "reason": reason,
                "url": url,
                "scopeID": String(scopeID)
            ]
        )
        _ = EventBridge.shared.requestScript(
            .OnURLDropFailure,
            params: params,
            to: self,
            security: security
        )
    }

    func executeInstall(params: [String]) {
        guard let first = params.first else {
            EventBridge.shared.notifyCustom("OnInstallFailure", refs: ["reason": "missing_target"])
            return
        }
        if first.lowercased() == "url", params.count >= 2 {
            let rawURL = params[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URLDropPolicy.remoteURL(
                from: rawURL,
                allowInsecureHTTP: URLDropPolicy.allowsInsecureHTTP(),
                resolveHost: false
            ) else {
                EventBridge.shared.notifyCustom("OnInstallFailure", refs: ["reason": "invalid_url"])
                return
            }

            let action = params.count >= 3
                ? params[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                : URLDropPolicy.plannedAction(for: url)
            guard ["feed", "nar", "homeurl"].contains(action) else {
                EventBridge.shared.notifyCustom("OnInstallFailure", refs: ["reason": "unsupported"])
                return
            }

            preflightExecuteInstallURL(url) { [weak self] in
                guard let self else { return }
                switch action {
                case "feed":
                    // RSSインストールはOnURL*ではなく、RSS取得イベントへ接続する。
                    self.executeRSS(subcommand: "rss-get", params: [url.absoluteString])
                case "homeurl":
                    // 現在のゴーストに更新先を適用し、通常の更新イベント列を実行する。
                    self.resourceManager.homeurl = url.absoluteString
                    self.ghostConfig?.homeurl = url.absoluteString
                    self.checkGhostUpdate(options: ["web-homeurl"])
                case "nar":
                    self.startExecuteInstallNarDownload(from: url)
                default:
                    break
                }
            }
            return
        }

        let pathArg = first.lowercased() == "path" && params.count >= 2 ? params[1] : first
        installNarFile(resolvedPath(pathArg))
    }

    func executeCreateNar() {
        let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(ghostURL.lastPathComponent).nar")
        EventBridge.shared.notify(.OnNarCreating, refs: ["name": output.path])
        runProcess(path: "/usr/bin/ditto", arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", ghostURL.path, output.path]) { result, ok in
            let payload: [String: String] = [
                "Reference0": output.path,
                "Reference1": result
            ]
            EventBridge.shared.notifyCustom(ok ? "OnCreateNarComplete" : "OnCreateNarFailure", params: payload)
            if ok {
                EventBridge.shared.notify(.OnNarCreated, params: payload)
            }
        }
    }

    func executeCreateUpdateData() {
        let updatePath = ghostURL.appendingPathComponent("updates2.dau")
        EventBridge.shared.notify(.OnUpdatedataCreating, refs: ["filePath": updatePath.path])
        let lines = [
            "; generated by Ourin",
            "version=\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")",
            "url=\(resourceManager.homeurl ?? ghostConfig?.homeurl ?? "")"
        ].joined(separator: "\n")
        do {
            try lines.data(using: .utf8)?.write(to: updatePath)
            EventBridge.shared.notifyCustom("OnCreateUpdateDataComplete", refs: ["filePath": updatePath.path])
            EventBridge.shared.notify(.OnUpdatedataCreated, refs: ["path": updatePath.path])
        } catch {
            EventBridge.shared.notifyCustom("OnCreateUpdateDataFailure", refs: ["reason": error.localizedDescription])
        }
    }

    func executeEmptyRecycleBin() {
        let trash = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true)
        let before = recycleBinStats(at: trash)
        var success = true
        do {
            let items = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
            for item in items {
                do {
                    try FileManager.default.removeItem(at: item)
                } catch {
                    success = false
                    Log.info("[GhostManager] Failed to remove recycle-bin item \(item.path): \(error.localizedDescription)")
                }
            }
            let after = recycleBinStats(at: trash)
            let currentName = ghostConfig?.sakuraName ?? ghostConfig?.name ?? ghostURL.lastPathComponent
            let refs = [
                "count": String(after.count),
                "size": String(after.size),
                "countDelta": String(after.count - before.count),
                "sizeDelta": String(after.size - before.size),
                "success": success && after.count == 0 ? "1" : "0",
                "ghostName": currentName
            ]
            let params = EventReferenceTable.params(forEvent: EventID.OnRecycleBinEmpty.rawValue, refs: refs)
            EventBridge.shared.notifyCustom(EventID.OnRecycleBinEmpty.rawValue, params: params, to: self)
            EventBridge.shared.notifyCustom(
                EventID.OnRecycleBinEmptyFromOther.rawValue,
                params: EventReferenceTable.params(forEvent: EventID.OnRecycleBinEmptyFromOther.rawValue, refs: refs),
                excluding: self,
                ignoreResponseScript: false
            )
            RecycleBinObserver.shared.refreshNow()
        } catch {
            let currentName = ghostConfig?.sakuraName ?? ghostConfig?.name ?? ghostURL.lastPathComponent
            let refs = [
                "count": String(before.count),
                "size": String(before.size),
                "countDelta": "0",
                "sizeDelta": "0",
                "success": "0",
                "ghostName": currentName
            ]
            EventBridge.shared.notifyCustom(
                EventID.OnRecycleBinEmpty.rawValue,
                params: EventReferenceTable.params(forEvent: EventID.OnRecycleBinEmpty.rawValue, refs: refs),
                to: self
            )
            RecycleBinObserver.shared.refreshNow()
            Log.info("[GhostManager] Failed to enumerate recycle bin: \(error.localizedDescription)")
        }
    }

    private func recycleBinStats(at directory: URL) -> (count: Int, size: Int64) {
        let snapshot = RecycleBinObserver.snapshot(at: [directory])
        return (snapshot.count, snapshot.size)
    }

    func executePing(params: [String]) {
        let parsed = parseCommandArguments(params)
        let host = parsed.options["host"] ?? parsed.positionals.first ?? "localhost"
        let eventID = parsed.options["event"] ?? ""
        let count = max(1, Int(parsed.options["count"] ?? "3") ?? 3)

        var arguments = ["-c", String(count)]
        if let ttl = parsed.options["ttl"], Int(ttl) != nil { arguments += ["-m", ttl] }
        if let size = parsed.options["size"], Int(size) != nil { arguments += ["-s", size] }
        if let timeout = parsed.options["timeout"], Int(timeout) != nil { arguments += ["-W", timeout] }
        if parsed.options["df"]?.lowercased() == "true" || parsed.options["df"] == "1" {
            arguments.append("-D")
        }
        if let data = parsed.options["data"], !data.isEmpty {
            let pattern = data.utf8.map { String(format: "%02x", $0) }.joined()
            if !pattern.isEmpty { arguments += ["-p", pattern] }
        }
        arguments.append(host)

        emitPingEvent(eventID: eventID, eventName: "OnPingProgress", host: host, count: count, success: 0, failure: 0, output: "")
        runProcess(path: "/sbin/ping", arguments: arguments) { [weak self] output, ok in
            guard let self else { return }
            let successCount = self.pingSuccessCount(output: output, requested: count, processSucceeded: ok)
            let failureCount = max(0, count - successCount)
            self.emitPingEvent(
                eventID: eventID,
                eventName: ok ? "OnPingComplete" : "OnPingFailure",
                host: host,
                count: count,
                success: successCount,
                failure: failureCount,
                output: output
            )
            self.emitPingEvent(
                eventID: eventID,
                eventName: "OnPingProgress",
                host: host,
                count: count,
                success: successCount,
                failure: failureCount,
                output: output
            )
        }
    }

    func executeNslookup(params: [String]) {
        let parsed = parseCommandArguments(params)
        let host = parsed.options["host"] ?? parsed.positionals.first ?? "localhost"
        let eventID = parsed.options["event"] ?? ""
        let lookupType = isIPAddress(host) ? "reverse" : "lookup"
        runProcess(path: "/usr/bin/nslookup", arguments: [host]) { [weak self] output, ok in
            guard let self else { return }
            let result = self.nslookupResult(output: output, reverse: lookupType == "reverse")
            self.emitNslookupEvent(
                eventID: eventID,
                eventName: ok ? "OnNSLookupComplete" : "OnNSLookupFailure",
                host: host,
                lookupType: lookupType,
                result: result,
                output: output
            )
        }
    }

    private func emitPingEvent(
        eventID: String,
        eventName: String,
        host: String,
        count: Int,
        success: Int,
        failure: Int,
        output: String
    ) {
        let refs: [String: String] = [
            "Reference0": eventID,
            "Reference1": "\(host)\u{01}\(count)\u{01}\(success)\u{01}\(failure)",
            "Reference2": "\(output.isEmpty ? "" : (success > 0 ? "OK" : output))\u{01}\(host)"
        ]
        _ = EventBridge.shared.requestCustom(
            eventID.lowercased().hasPrefix("on") ? eventID : eventName,
            params: refs,
            to: self
        )
    }

    private func emitNslookupEvent(
        eventID: String,
        eventName: String,
        host: String,
        lookupType: String,
        result: String,
        output: String
    ) {
        let refs: [String: String] = [
            "Reference0": eventID,
            "Reference1": host,
            "Reference2": lookupType,
            "Reference3": result.isEmpty ? output : result
        ]
        _ = EventBridge.shared.requestCustom(
            eventID.lowercased().hasPrefix("on") ? eventID : eventName,
            params: refs,
            to: self
        )
    }

    private func pingSuccessCount(output: String, requested: Int, processSucceeded: Bool) -> Int {
        guard processSucceeded else { return 0 }
        let pattern = #"(\d+(?:\.\d+)?)% packet loss"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
           let lossRange = Range(match.range(at: 1), in: output),
           let loss = Double(output[lossRange]) {
            return max(0, min(requested, Int((Double(requested) * (100.0 - loss) / 100.0).rounded())))
        }
        return requested
    }

    private func isIPAddress(_ host: String) -> Bool {
        IPv4Address(host) != nil || IPv6Address(host) != nil
    }

    private func nslookupResult(output: String, reverse: Bool) -> String {
        let lines = output.split(whereSeparator: { $0.isNewline }).map(String.init)
        if reverse {
            return lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("name =") })?
                .split(separator: "=", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        }
        return lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("Address:") else { return nil }
            return trimmed.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) }
        }.joined(separator: "\u{01}")
    }

    private func applyRequestOptions(_ parsed: (positionals: [String], options: [String: String], flags: Set<String>), to request: inout URLRequest) {
        if let timeoutStr = parsed.options["timeout"], let timeout = TimeInterval(timeoutStr), timeout > 0 {
            request.timeoutInterval = timeout
        }

        if let headerLine = parsed.options["header"], let separator = headerLine.firstIndex(of: ":") {
            let key = String(headerLine[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(headerLine[headerLine.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        if let headers = parsed.options["headers"] {
            for pair in headers.split(separator: "|") {
                let token = String(pair)
                guard let separator = token.firstIndex(of: ":") else { continue }
                let key = String(token[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(token[token.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
        }
    }

    func executeCreateShortcut(params: [String]) {
        guard params.count >= 2 else {
            EventBridge.shared.notifyCustom("OnCreateShortcutFailure", refs: ["reason": "missing_args"])
            return
        }
        let target = resolvedPath(params[0])
        let link = resolvedPath(params[1])
        do {
            try? FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            EventBridge.shared.notifyCustom("OnCreateShortcutComplete", refs: ["linkPath": link.path])
        } catch {
            EventBridge.shared.notifyCustom("OnCreateShortcutFailure", refs: ["reason": error.localizedDescription])
        }
    }

    func executeReloadSurface() {
        let current = characterViewModels[currentScope]?.currentSurfaceID ?? 0
        updateSurface(id: current)
        EventBridge.shared.notifyCustom("OnSurfaceReloaded", refs: ["surfaceID": String(current)])
    }

    func executeReload(target: String, params: [String]) {
        switch target.lowercased() {
        case "descript":
            let parsed = parseCommandArguments(params)
            let descriptorTarget = (parsed.positionals.first ?? parsed.options["target"] ?? "ghost").lowercased()
            let ghostRoot = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)

            if descriptorTarget == "ghost" || descriptorTarget == "all" {
                if let config = GhostConfiguration.load(from: ghostRoot) {
                    ghostConfig = config
                    applyGhostConfiguration(config, ghostRoot: ghostRoot)
                }
            }

            if descriptorTarget == "shell" || descriptorTarget == "all" {
                executeReloadSurface()
            }

            if descriptorTarget == "balloon" || descriptorTarget == "all" {
                let baseBalloonDir = ghostURL.appendingPathComponent("balloon", isDirectory: true)
                let preferred = parsed.options["name"] ?? parsed.options["balloon"] ?? ""
                let balloonDir = preferred.isEmpty ? baseBalloonDir : baseBalloonDir.appendingPathComponent(preferred, isDirectory: true)
                let descriptPath = balloonDir.appendingPathComponent("descript.txt").path
                if let config = BalloonConfig.load(from: descriptPath) {
                    balloonConfig = config
                    balloonImageLoader = BalloonImageLoader(balloonPath: balloonDir.path)
                }
            }
            EventBridge.shared.notifyCustom("OnDescriptReloaded", refs: ["target": descriptorTarget, "params": params.joined(separator: ",")])
        case "shell", "balloon", "ghost", "aigraph":
            executeReloadSurface()
        case "shiori":
            executeLoad(target: target)
        case "makoto":
            reloadMakotoTranslators()
        default:
            break
        }
    }

    func executeUnload(target: String) {
        let lowered = target.lowercased()
        if lowered == "makoto" {
            unloadMakotoTranslators()
            NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
        } else if lowered == "shiori" {
            shioriRuntime?.unload()
            shioriRuntime = nil
            yayaAdapter = nil
            if let token = eventToken {
                EventBridge.shared.unregister(token)
                eventToken = nil
            }
            EventBridge.shared.notifyCustom("OnShioriUnloaded", refs: ["name": lowered])
            NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
        }
    }

    func executeLoad(target: String) {
        let lowered = target.lowercased()
        if lowered == "makoto" {
            reloadMakotoTranslators()
            return
        }
        guard lowered == "shiori" else { return }
        guard shioriRuntime == nil else { return }
        let ghostRoot = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
        let moduleName = ShioriRuntimeFactory.moduleName(for: ghostConfig)
        guard let runtime = createLoadedShioriRuntime(moduleName: moduleName, ghostRoot: ghostRoot) else {
            EventBridge.shared.notifyCustom("OnShioriLoadFailure", refs: ["reason": lowered])
            return
        }
        shioriRuntime = runtime
        yayaAdapter = runtime as? YayaAdapter
        if let oldToken = eventToken {
            EventBridge.shared.unregister(oldToken)
        }
        eventToken = EventBridge.shared.register(runtime: runtime, ghostManager: self)
        EventBridge.shared.notifyCustom(
            "OnShioriLoaded",
            refs: ["name": moduleName, "kind": runtime.kind.rawValue]
        )
        NotificationCenter.default.post(name: .fmoNeedsRefresh, object: nil)
    }

    static func parseScalarLiteral(_ raw: String?) -> UInt32? {
        guard var token = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return nil }
        let radix: Int
        if token.hasPrefix("0x") || token.hasPrefix("0X") {
            token = String(token.dropFirst(2))
            radix = 16
        } else {
            // UKADOC: 0x-prefixed values are hexadecimal; otherwise values are decimal.
            radix = 10
        }
        return UInt32(token, radix: radix)
    }

    func decodeScalarLiteral(_ raw: String?) -> UnicodeScalar? {
        guard let value = Self.parseScalarLiteral(raw) else { return nil }
        return UnicodeScalar(value)
    }

    private func normalizedDownloadedArchiveURL(
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

    /// NAR を実インストールし、インストールイベントを同じ経路で発火する。
    /// D&D／ファイル関連付けと `\![open,install,...]` の挙動を一致させるため、
    /// 呼び出し側は直接 NarInstaller を呼ばず、このメソッドを通す。
    @discardableResult
    func installNarFile(_ narURL: URL) -> NarInstallDispatchOutcome {
        EventBridge.shared.notifyCustom("OnInstallBegin", params: [:])
        var eventTarget: GhostManager?
        do {
            let installer = NarInstaller()
            let manifest = try installer.inspectManifest(fromNar: narURL)
            let installPreview = installPreview(for: manifest)

            // shell/supplement の accept は「現在のゴーストに渡してよいか」の判定値。
            // 別の起動中ゴーストが対象なら、以降のイベントをそのゴーストだけへ reroute する。
            if let accept = manifest.accept?.trimmingCharacters(in: .whitespacesAndNewlines),
               !accept.isEmpty,
               ["shell", "supplement"].contains(manifest.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
               !acceptsInstall(accept) {
                if let runningTarget = EventBridge.shared.runningGhost(named: accept, excluding: self) {
                    eventTarget = runningTarget
                    _ = EventBridge.shared.notifyCustom("OnInstallReroute", refs: [
                        "accept": accept,
                        "identifier": installPreview.identifier,
                        "name": installPreview.name
                    ], to: runningTarget)
                } else {
                    _ = EventBridge.shared.notifyCustom("OnInstallRefuse", refs: [
                        "accept": accept,
                        "identifier": installPreview.identifier,
                        "name": installPreview.name
                    ], to: self)
                    return .refused
                }
            }

            let result = try installer.installWithResult(fromNar: narURL)
            emitInstallCompletionEvents(result, recipient: eventTarget)
            return .installed(result)
        } catch {
            let refs = ["reason": installFailureReason(error)]
            if let eventTarget {
                _ = EventBridge.shared.notifyCustom("OnInstallFailure", refs: refs, to: eventTarget)
            } else {
                EventBridge.shared.notifyCustom("OnInstallFailure", refs: refs)
            }
            return .failed(error)
        }
    }

    private func acceptsInstall(_ acceptedName: String) -> Bool {
        let normalized = acceptedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        var names = [ghostConfig?.name ?? "", ghostURL.lastPathComponent]
        names.append(contentsOf: ghostConfig?.installAccept ?? [])
        return names.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
        }
    }

    private func installPreview(for manifest: InstallManifest) -> (identifier: String, name: String) {
        let type = manifest.type.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasBundledBalloon = ["ghost", "shell"].contains(type.lowercased())
            && manifest.balloonDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let identifier = NarInstaller.installIdentifier(type: type, hasBundledBalloon: hasBundledBalloon)
        let name = manifest.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (identifier, name?.isEmpty == false ? name! : manifest.directory)
    }

    /// NAR の実設置結果を UKADOC の OnInstall 系 Reference へ変換する。
    /// 単一対象は後方互換の OnInstallComplete、複数対象は Ex を使う。
    func emitInstallCompletionEvents(_ result: NarInstallResult, recipient: GhostManager? = nil) {
        guard let main = result.objects.first else { return }

        func notify(_ eventName: String, refs: [String: String]) {
            if let recipient {
                _ = EventBridge.shared.notifyCustom(eventName, refs: refs, to: recipient)
            } else {
                EventBridge.shared.notifyCustom(eventName, refs: refs)
            }
        }

        // `%lastghostname` / `%lastobjectname` は install.txt の name を基準に更新する。
        if main.identifier == "ghost" {
            EnvironmentExpander.lastInstalledGhostName = main.name
        }
        EnvironmentExpander.lastInstalledObjectName = main.name

        let attachedBalloon = result.objects.count == 2
            && (main.identifier == "ghost" || main.identifier == "shell")
            && result.objects[1].identifier == "balloon"

        if result.objects.count == 1 {
            notify("OnInstallComplete", refs: [
                "identifier": main.identifier,
                "name": main.name
            ])
            return
        }

        if attachedBalloon {
            let combinedIdentifier = "\(main.identifier) with balloon"
            notify("OnInstallComplete", refs: [
                "identifier": combinedIdentifier,
                "name": main.name,
                "name2": result.objects[1].name
            ])
            return
        }

        let separator = String(UnicodeScalar(1))
        notify("OnInstallCompleteEx", refs: [
            "identifiers": result.objects.map(\.identifier).joined(separator: separator),
            "names": result.objects.map(\.name).joined(separator: separator),
            "paths": result.objects.map(\.path).joined(separator: separator)
        ])
    }

    func installFailureReason(_ error: Error) -> String {
        guard let narError = error as? NarInstaller.Error else { return "unsupported" }
        switch narError {
        case .notZip, .unsupportedType:
            return "unsupported"
        case .unzipFailed:
            return "extraction"
        case .installTxtNotFound, .installTxtDecodeFailed, .installTxtMissingKey:
            return "invalid type"
        case .zipSlipDetected, .invalidDeletePath, .deleteInstructionDecodeFailed, .attachedComponentSourceNotFound:
            return "invalid type"
        case .directoryConflict:
            return "unsupported"
        case .updateDescriptorNotFound, .updateDescriptorDecodeFailed, .updateDescriptorInvalid,
             .updateDownloadFailed, .updateMD5Mismatch, .basewareArchiveUnsupported:
            return "unsupported"
        }
    }

    private func runProcess(
        path: String,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        completion: @escaping (String, Bool) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                process.waitUntilExit()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8) ?? ""
                completion(text, process.terminationStatus == 0)
            } catch {
                completion(error.localizedDescription, false)
            }
        }
    }

    private func resolvedPath(_ rawPath: String) -> URL {
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath)
        }
        return ghostURL.appendingPathComponent(rawPath)
    }

    func postSystemMessage(title: String, body: String, level: String) {
        let finalTitle = title.isEmpty ? NSLocalizedString("System Message", comment: "system message title") : title
        let content = UNMutableNotificationContent()
        content.title = finalTitle
        content.body = body
        content.userInfo = [
            "ourinSystemMessage": "1",
            "level": level
        ]
        let request = UNNotificationRequest(identifier: "ourin.system.\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.info("[GhostManager] Failed to post system message: \(error.localizedDescription)")
            }
        }
        EventBridge.shared.notifyCustom("OnSystemMessage", refs: [
            "title": finalTitle,
            "body": body,
            "level": level
        ])
    }

    func setClipboardText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        EventBridge.shared.notifyCustom("OnClipboardWrite", refs: ["text": text])
    }

    func getClipboardText() -> String {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string) ?? ""
    }

    func clearClipboard() {
        NSPasteboard.general.clearContents()
        EventBridge.shared.notifyCustom("OnClipboardClear", params: [:])
    }

    // MARK: - Change / Open Command Helpers

    func parseCommandArguments(_ args: [String]) -> (positionals: [String], options: [String: String], flags: Set<String>) {
        var positionals: [String] = []
        var options: [String: String] = [:]
        var flags: Set<String> = []

        for arg in args {
            let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("--") {
                let body = String(trimmed.dropFirst(2))
                if let eq = body.firstIndex(of: "=") {
                    let key = String(body[..<eq]).lowercased()
                    let value = String(body[body.index(after: eq)...])
                    options[key] = value
                } else {
                    flags.insert(body.lowercased())
                }
            } else {
                positionals.append(trimmed)
            }
        }

        return (positionals, options, flags)
    }

    func switchGhost(named target: String, options: [String]) {
        let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let parsed = parseCommandArguments(options)
        let raiseEvent = parsed.options["option"]?.lowercased() == "raise-event" || parsed.flags.contains("option=raise-event")

        let resolvedName: String?
        switch normalized.lowercased() {
        case "sequential":
            resolvedName = NarRegistry.sequentialGhostName(
                items: NarRegistry.shared.installedItems(ofType: "ghost"),
                currentName: ghostConfig?.name ?? ghostURL.lastPathComponent
            )
            guard resolvedName != nil else {
                Log.debug("[GhostManager] Sequential ghost switch ignored: no next ghost")
                return
            }
        case "random":
            resolvedName = nil
        default:
            resolvedName = normalized
        }

        let eventTargetName = resolvedName ?? normalized
        let sourceInfo = currentGhostEventInfo
        guard eventTargetName.caseInsensitiveCompare(sourceInfo.ghostName) != .orderedSame,
              eventTargetName.caseInsensitiveCompare(sourceInfo.mainName) != .orderedSame else {
            Log.debug("[GhostManager] Ghost switch ignored: target is already active")
            return
        }
        let targetInfo = ghostEventInfo(named: eventTargetName)
        let changingParams: [String: String] = [
            "nextGhostName": targetInfo.mainName,
            "changeMode": "manual",
            "nextGhostNameSSP": targetInfo.ghostName,
            "nextGhostPath": targetInfo.path
        ]
        let changeRequest = GhostBootRequest(
            eventID: .OnGhostChanged,
            references: [
                sourceInfo.mainName,
                "",
                sourceInfo.ghostName,
                sourceInfo.path,
                "", "", "", ""
            ]
        )
        var changeScript = ""
        if raiseEvent {
            // UKADOC: Reference0=切替先の本体側名前, Reference1=manual/automatic, Reference2=切替先ゴースト名[SSP], Reference3=切替先パス[SSP]
            // OnGhostChanging は返答スクリプトを切替前に再生する GET イベント。
            changeScript = EventBridge.shared.requestScript(
                .OnGhostChanging,
                params: EventReferenceTable.params(forEvent: EventID.OnGhostChanging.rawValue, refs: changingParams),
                to: self
            ) ?? ""
        }

        bootOtherGhost(name: eventTargetName, bootRequest: changeRequest) { [weak self] target, result in
            guard let self, result.succeeded else { return }
            let nextInfo = target.currentGhostEventInfo
            let otherParams = EventReferenceTable.params(
                forEvent: EventID.OnOtherGhostChanged.rawValue,
                refs: [
                    "prevGhostName": sourceInfo.mainName,
                    "nextGhostName": nextInfo.mainName,
                    "prevChangeScript": changeScript,
                    "nextChangeScript": result.script,
                    "prevGhostNameSSP": sourceInfo.ghostName,
                    "nextGhostNameSSP": nextInfo.ghostName,
                    "prevShellName": sourceInfo.shellName,
                    "nextShellName": nextInfo.shellName
                ]
            )
            EventBridge.shared.request(
                .OnOtherGhostChanged,
                params: otherParams,
                excluding: [self, target]
            )
            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  appDelegate.completeGhostSwitch(from: self, to: target) else {
                self.shutdown()
                return
            }
        }
    }

    func callGhost(named target: String, options: [String]) {
        let normalized = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let parsed = parseCommandArguments(options)
        let raiseEvent = parsed.options["option"]?.lowercased() == "raise-event" || parsed.flags.contains("option=raise-event")

        let sourceInfo = currentGhostEventInfo
        let targetName: String
        switch normalized.lowercased() {
        case "random":
            let candidates = NarRegistry.shared.installedGhosts().filter { $0 != sourceInfo.ghostName }
            guard let randomName = candidates.randomElement() else { return }
            targetName = randomName
        default:
            targetName = normalized
        }
        let targetInfo = ghostEventInfo(named: targetName)

        if raiseEvent {
            EventBridge.shared.request(
                .OnGhostCalling,
                params: EventReferenceTable.params(
                    forEvent: EventID.OnGhostCalling.rawValue,
                    refs: [
                        "nextGhostName": targetInfo.mainName,
                        "changeMode": "manual",
                        "nextGhostNameSSP": targetInfo.ghostName,
                        "nextGhostPath": targetInfo.path
                    ]
                ),
                to: self
            )
        }

        let callRequest = GhostBootRequest(
            eventID: .OnGhostCalled,
            references: [
                sourceInfo.mainName,
                "",
                sourceInfo.ghostName,
                sourceInfo.path,
                "", "", "", ""
            ]
        )
        bootOtherGhost(name: targetName, bootRequest: callRequest) { [weak self] target, result in
            guard let self, result.succeeded else { return }
            let calledInfo = target.currentGhostEventInfo
            let completeParams = EventReferenceTable.params(
                forEvent: EventID.OnGhostCallComplete.rawValue,
                refs: [
                    "calledGhostMainName": calledInfo.mainName,
                    "calledBootScript": result.script,
                    "calledGhostNameSSP": calledInfo.ghostName,
                    "calledShellName": calledInfo.shellName
                ]
            )
            _ = EventBridge.shared.request(
                .OnGhostCallComplete,
                params: completeParams,
                to: self
            )
        }
    }

    // MARK: - Dialog Commands

    struct InputDialogOptions {
        let noClose: Bool
        let noClear: Bool
        let limit: Int?
        let balloonID: String?
        let references: [String]

        init(rawArguments: [String]) {
            var optionValues: [String: [String]] = [:]
            for raw in rawArguments {
                guard raw.hasPrefix("--") else { continue }
                let body = String(raw.dropFirst(2))
                let separator = body.firstIndex(of: "=")
                let key = String(body[..<(separator ?? body.endIndex)]).lowercased()
                let value = separator.map { String(body[body.index(after: $0)...]) } ?? ""
                optionValues[key, default: []].append(value)
            }

            let modes = optionValues["option", default: []]
                .flatMap { $0.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "="))
                        .lowercased()
                } }
            noClose = modes.contains("noclose")
            noClear = modes.contains("noclear")
            limit = optionValues["limit"]?.last.flatMap(Int.init).map { max(0, $0) }
            balloonID = optionValues["balloon"]?.last.flatMap { $0.isEmpty ? nil : $0 }
            references = optionValues["reference", default: []]
        }

        static let none = InputDialogOptions(rawArguments: [])

        func limited(_ value: String) -> String {
            guard let limit else { return value }
            return String(value.prefix(limit))
        }
    }

    func inputDialogOptions(from rawArguments: [String]) -> InputDialogOptions {
        InputDialogOptions(rawArguments: rawArguments)
    }

    private func beginInputDialog(_ alert: NSAlert, id: String) {
        activeInputAlert = alert
        activeInputDialogID = id
        inputDialogCloseRequested = false
    }

    private func endInputDialog() {
        activeInputAlert = nil
        activeInputDialogID = nil
        inputDialogCloseRequested = false
    }

    @discardableResult
    func closeInputDialog(id: String) -> Bool {
        guard let alert = activeInputAlert,
              let activeID = activeInputDialogID,
              id == "__SYSTEM_ALL_INPUT__" || activeID.caseInsensitiveCompare(id) == .orderedSame else {
            return false
        }
        inputDialogCloseRequested = true
        alert.window.close()
        NSApp.abortModal()
        return true
    }

    private func consumeInputDialogCloseRequest() -> Bool {
        let requested = inputDialogCloseRequested
        inputDialogCloseRequested = false
        return requested
    }

    private func beginCommunicateDialog(_ alert: NSAlert) {
        activeCommunicateAlert = alert
        communicateDialogCloseRequested = false
    }

    private func endCommunicateDialog() {
        activeCommunicateAlert = nil
        communicateDialogCloseRequested = false
    }

    func closeCommunicateBoxDialog() {
        guard let alert = activeCommunicateAlert else { return }
        communicateDialogCloseRequested = true
        alert.window.close()
        NSApp.abortModal()
    }

    func handleGhostTermsConsent() {
        let ghostName = ghostConfig?.name ?? ghostURL.lastPathComponent
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("利用規約", comment: "ghost terms title")
        alert.informativeText = NSLocalizedString("このゴーストの利用規約を確認しますか？", comment: "ghost terms message")
        alert.addButton(withTitle: NSLocalizedString("同意して開く", comment: "accept terms"))
        alert.addButton(withTitle: NSLocalizedString("拒否", comment: "decline terms"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            EventBridge.shared.notify(.OnGhostTermsAccept, refs: ["ghostName": ghostName])
            openFilePath("terms.txt")
        } else {
            EventBridge.shared.notify(.OnGhostTermsDecline, refs: ["ghostName": ghostName])
        }
    }

    func showInputBoxDialog(id: String, timeoutMs: Int?, initialText: String, options: InputDialogOptions = .none) {
        _ = requestDialogEvent(eventID: "OnInputbox.autocomplete", references: [id, initialText])
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Input", comment: "input dialog title")
        alert.informativeText = NSLocalizedString("Please enter text.", comment: "input dialog message")
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = initialText
        if let balloonID = options.balloonID, let index = Int(balloonID),
           let image = balloonImageLoader?.loadSurface(index: index, type: "c") {
            alert.icon = image
        }
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        beginInputDialog(alert, id: id)
        defer { endInputDialog() }

        let limitObserver: NSObjectProtocol?
        if options.limit != nil {
            limitObserver = NotificationCenter.default.addObserver(
                forName: NSControl.textDidChangeNotification,
                object: textField,
                queue: .main
            ) { [weak textField] _ in
                guard let textField, let limit = options.limit else { return }
                if textField.stringValue.count > limit {
                    textField.stringValue = String(textField.stringValue.prefix(limit))
                }
            }
        } else {
            limitObserver = nil
        }
        defer {
            if let limitObserver { NotificationCenter.default.removeObserver(limitObserver) }
        }

        while true {
            var timedOut = false
            let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
            let response = alert.runModal()
            timer?.invalidate()

            if consumeInputDialogCloseRequest() { break }

            if response == .alertFirstButtonReturn {
                let value = options.limited(textField.stringValue)
                emitUserInput(id: id, value: value, options: options)
                guard options.noClose else { break }
                if !options.noClear { textField.stringValue = "" }
            } else {
                emitUserInputCancel(id: id, timedOut: timedOut, options: options)
                break
            }
        }
    }

    func showPasswordInputDialog(id: String, timeoutMs: Int?, initialText: String, options: InputDialogOptions = .none) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Password Input", comment: "password input title")
        alert.informativeText = NSLocalizedString("Please enter password.", comment: "password input message")
        alert.alertStyle = .informational

        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = initialText
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        beginInputDialog(alert, id: id)
        defer { endInputDialog() }

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if consumeInputDialogCloseRequest() { return }

        if response == .alertFirstButtonReturn {
            emitUserInput(id: id, value: options.limited(textField.stringValue), options: options)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut, options: options)
        }
    }

    func showDateInputDialog(id: String, timeoutMs: Int?, year: Int?, month: Int?, day: Int?, options: InputDialogOptions = .none) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Date Input", comment: "date input title")
        alert.alertStyle = .informational

        let now = Date()
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
        comps.year = year ?? comps.year
        comps.month = month ?? comps.month
        comps.day = day ?? comps.day
        let date = Calendar.current.date(from: comps) ?? now

        let datePicker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.dateValue = date
        alert.accessoryView = datePicker
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        beginInputDialog(alert, id: id)
        defer { endInputDialog() }

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if consumeInputDialogCloseRequest() { return }

        if response == .alertFirstButtonReturn {
            let selectedComps = Calendar.current.dateComponents([.year, .month, .day], from: datePicker.dateValue)
            let value = "\(selectedComps.year ?? 0),\(selectedComps.month ?? 0),\(selectedComps.day ?? 0)"
            emitUserInput(id: id, value: value, options: options)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut, options: options)
        }
    }

    func showSliderInputDialog(id: String, timeoutMs: Int?, initial: Double?, min: Double?, max: Double?, options: InputDialogOptions = .none) {
        let minValue = min ?? 0
        let maxValue = max ?? 100
        let startValue = initial ?? minValue

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Slider Input", comment: "slider input title")
        alert.alertStyle = .informational

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 56))
        let slider = NSSlider(value: startValue, minValue: minValue, maxValue: maxValue, target: nil, action: nil)
        slider.frame = NSRect(x: 0, y: 24, width: 320, height: 24)
        let valueLabel = NSTextField(labelWithString: String(format: "%.2f", startValue))
        valueLabel.frame = NSRect(x: 0, y: 0, width: 320, height: 20)
        slider.target = valueLabel
        slider.action = #selector(NSTextField.takeDoubleValueFrom(_:))
        container.addSubview(slider)
        container.addSubview(valueLabel)
        alert.accessoryView = container

        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        beginInputDialog(alert, id: id)
        defer { endInputDialog() }

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if consumeInputDialogCloseRequest() { return }

        if response == .alertFirstButtonReturn {
            emitUserInput(
                id: id,
                value: String(slider.doubleValue),
                supplemental: "\(minValue),\(maxValue)",
                options: options
            )
        } else {
            emitUserInputCancel(
                id: id,
                timedOut: timedOut,
                supplemental: "\(minValue),\(maxValue)",
                options: options
            )
        }
    }

    func showTimeInputDialog(id: String, timeoutMs: Int?, hour: Int?, minute: Int?, second: Int?, options: InputDialogOptions = .none) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Time Input", comment: "time input title")
        alert.alertStyle = .informational

        let now = Date()
        var comps = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        comps.hour = hour ?? comps.hour
        comps.minute = minute ?? comps.minute
        comps.second = second ?? comps.second
        let date = Calendar.current.date(from: comps) ?? now

        let timePicker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        timePicker.datePickerStyle = .textFieldAndStepper
        timePicker.datePickerElements = [.hourMinuteSecond]
        timePicker.dateValue = date
        alert.accessoryView = timePicker
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        beginInputDialog(alert, id: id)
        defer { endInputDialog() }

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if consumeInputDialogCloseRequest() { return }

        if response == .alertFirstButtonReturn {
            let selectedComps = Calendar.current.dateComponents([.hour, .minute, .second], from: timePicker.dateValue)
            let value = "\(selectedComps.hour ?? 0),\(selectedComps.minute ?? 0),\(selectedComps.second ?? 0)"
            emitUserInput(id: id, value: value, options: options)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut, options: options)
        }
    }

    func showIPInputDialog(id: String, timeoutMs: Int?, initialText: String, options: InputDialogOptions = .none) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("IP Input", comment: "ip input title")
        alert.informativeText = NSLocalizedString("Please enter IP address.", comment: "ip input message")
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = initialText
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
        beginInputDialog(alert, id: id)
        defer { endInputDialog() }

        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if consumeInputDialogCloseRequest() { return }

        if response == .alertFirstButtonReturn {
            emitUserInput(id: id, value: options.limited(textField.stringValue), options: options)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut, options: options)
        }
    }

    func showChoiceInputDialog(id: String, timeoutMs: Int?, choices: [String], options: InputDialogOptions = .none) {
        let sanitized = choices.filter { !$0.isEmpty }
        guard !sanitized.isEmpty else {
            emitUserInputCancel(id: id, timedOut: false, options: options)
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Choice Input", comment: "choice input title")
        alert.alertStyle = .informational
        for item in sanitized {
            alert.addButton(withTitle: item)
        }
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        var timedOut = false
        beginInputDialog(alert, id: id)
        defer { endInputDialog() }
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if consumeInputDialogCloseRequest() { return }

        let buttonIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if buttonIndex >= 0 && buttonIndex < sanitized.count {
            emitUserInput(id: id, value: sanitized[buttonIndex], options: options)
        } else {
            emitUserInputCancel(id: id, timedOut: timedOut, options: options)
        }
    }

    func showSystemDialog(type: String, parameters: [String]) {
        let parsed = parseCommandArguments(parameters)
        let eventID = parsed.options["id"] ?? ""

        switch type {
        case "open", "folder":
            let panel = NSOpenPanel()
            panel.canChooseFiles = (type == "open")
            panel.canChooseDirectories = (type == "folder")
            panel.allowsMultipleSelection = false
            if let title = parsed.options["title"] { panel.title = title }
            if let path = parsed.options["dir"] { panel.directoryURL = URL(fileURLWithPath: path) }
            if panel.runModal() == .OK, let url = panel.url {
                emitSystemDialog(type: type, eventID: eventID, value: url.path)
            } else {
                emitSystemDialogCancel(type: type, eventID: eventID)
            }
        case "save":
            let panel = NSSavePanel()
            if let title = parsed.options["title"] { panel.title = title }
            if let path = parsed.options["dir"] { panel.directoryURL = URL(fileURLWithPath: path) }
            if let name = parsed.options["name"] { panel.nameFieldStringValue = name }
            if panel.runModal() == .OK, let url = panel.url {
                emitSystemDialog(type: type, eventID: eventID, value: url.path)
            } else {
                emitSystemDialogCancel(type: type, eventID: eventID)
            }
        case "color":
            let panel = NSColorPanel.shared
            if let colorSpec = parsed.options["color"] {
                let rgb = colorSpec.split(separator: " ").compactMap { Double($0) }
                if rgb.count == 3 {
                    panel.color = NSColor(red: rgb[0] / 255.0, green: rgb[1] / 255.0, blue: rgb[2] / 255.0, alpha: 1.0)
                }
            }
            panel.makeKeyAndOrderFront(nil)
            let rgb = panel.color.usingColorSpace(.deviceRGB) ?? panel.color
            let value = "\(Int(rgb.redComponent * 255)),\(Int(rgb.greenComponent * 255)),\(Int(rgb.blueComponent * 255))"
            emitSystemDialog(type: type, eventID: eventID, value: value)
        default:
            Log.info("[GhostManager] Unsupported system dialog type: \(type)")
        }
    }

    func showTeachBoxDialog() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showTeachBoxDialog() }
            return
        }
        if let existing = utilityWindows["teachbox"] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 170),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("Teach", comment: "teachbox title")
        window.isReleasedWhenClosed = false
        window.delegate = self

        let message = NSTextField(
            labelWithString: NSLocalizedString("Enter text to teach.", comment: "teachbox message")
        )
        let textField = NSTextField(string: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = NSLocalizedString("Text", comment: "teachbox input placeholder")

        let okButton = NSButton(
            title: NSLocalizedString("OK", comment: "OK"),
            target: self,
            action: #selector(acceptTeachBox(_:))
        )
        okButton.keyEquivalent = "\r"
        let cancelButton = NSButton(
            title: NSLocalizedString("Cancel", comment: "Cancel"),
            target: self,
            action: #selector(cancelTeachBox(_:))
        )
        cancelButton.keyEquivalent = "\u{1b}"

        let buttons = NSStackView(views: [okButton, cancelButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.alignment = .centerY

        let stack = NSStackView(views: [message, textField, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = NSView()
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20),
            textField.widthAnchor.constraint(equalToConstant: 380),
            textField.heightAnchor.constraint(equalToConstant: 24)
        ])

        teachBoxTextField = textField
        utilityWindows["teachbox"] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // UKADOC: opening TeachBox raises OnTeachStart immediately.
        _ = requestDialogEvent(eventID: "OnTeachStart", references: [])
    }

    func closeTeachBoxDialog() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.closeTeachBoxDialog() }
            return
        }
        guard let window = utilityWindows["teachbox"] else { return }
        teachBoxProgrammaticClose = true
        utilityWindows.removeValue(forKey: "teachbox")
        teachBoxTextField = nil
        window.close()
        teachBoxProgrammaticClose = false
    }

    @objc func acceptTeachBox(_ sender: Any?) {
        guard let window = utilityWindows["teachbox"] else { return }
        let value = teachBoxTextField?.stringValue ?? ""
        teachBoxProgrammaticClose = true
        utilityWindows.removeValue(forKey: "teachbox")
        teachBoxTextField = nil
        window.close()
        teachBoxProgrammaticClose = false
        _ = requestDialogEvent(eventID: "OnTeach", references: [value])
    }

    @objc func cancelTeachBox(_ sender: Any?) {
        guard let window = utilityWindows["teachbox"] else { return }
        teachBoxProgrammaticClose = true
        utilityWindows.removeValue(forKey: "teachbox")
        teachBoxTextField = nil
        window.close()
        teachBoxProgrammaticClose = false
        _ = requestDialogEvent(eventID: "OnTeachInputCancel", references: ["", "cancel"])
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              utilityWindows["teachbox"] === window else { return }
        utilityWindows.removeValue(forKey: "teachbox")
        teachBoxTextField = nil
        guard !teachBoxProgrammaticClose else { return }
        // User closed the title-bar window: report cancel, but never for a
        // script-issued close, which UKADOC explicitly excludes.
        _ = requestDialogEvent(eventID: "OnTeachInputCancel", references: ["", "cancel"])
    }

    func showCommunicateBoxDialog(timeoutMs: Int?, initialText: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Communicate", comment: "communicatebox title")
        alert.informativeText = NSLocalizedString("Enter text to communicate.", comment: "communicatebox message")
        alert.alertStyle = .informational

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        textField.stringValue = initialText
        alert.accessoryView = textField
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))

        beginCommunicateDialog(alert)
        defer { endCommunicateDialog() }
        var timedOut = false
        let timer = scheduleModalTimeout(timeoutMs: timeoutMs) { timedOut = true }
        let response = alert.runModal()
        timer?.invalidate()

        if communicateDialogCloseRequested { return }

        if response == .alertFirstButtonReturn {
            _ = requestDialogEvent(eventID: "OnCommunicate", references: ["user", textField.stringValue])
        } else {
            emitCommunicateInputCancel(timedOut: timedOut)
        }
    }

    func emitUserInput(
        id: String,
        value: String,
        supplemental: String = "",
        options: InputDialogOptions = .none
    ) {
        let normalizedValue = options.limited(value)
        if id.lowercased().hasPrefix("on") {
            _ = requestDialogEvent(eventID: id, references: [normalizedValue, supplemental] + options.references)
        } else {
            _ = requestDialogEvent(
                eventID: "OnUserInput",
                references: [id, normalizedValue, supplemental] + options.references
            )
        }
    }

    func emitUserInputCancel(
        id: String,
        timedOut: Bool,
        supplemental: String = "",
        options: InputDialogOptions = .none
    ) {
        let handled = requestDialogEvent(
            eventID: "OnUserInputCancel",
            references: [id, timedOut ? "timeout" : "close", supplemental] + options.references
        )
        if timedOut && !handled {
            _ = requestDialogEvent(eventID: "OnUserInput", references: [id, "timeout", supplemental] + options.references)
        }
    }

    func emitSystemDialog(type: String, eventID: String, value: String) {
        let refs = [type, eventID, value]
        if eventID.lowercased().hasPrefix("on") {
            _ = requestDialogEvent(eventID: eventID, references: refs)
        } else {
            _ = requestDialogEvent(eventID: "OnSystemDialog", references: refs)
        }
    }

    func emitSystemDialogCancel(type: String, eventID: String) {
        let refs = [type, eventID]
        if eventID.lowercased().hasPrefix("on") {
            _ = requestDialogEvent(eventID: eventID, references: refs)
        } else {
            _ = requestDialogEvent(eventID: "OnSystemDialogCancel", references: refs)
        }
    }

    func emitCommunicateInputCancel(timedOut: Bool) {
        let handled = requestDialogEvent(
            eventID: "OnCommunicateInputCancel",
            references: ["", timedOut ? "timeout" : "cancel"]
        )
        if timedOut && !handled {
            _ = requestDialogEvent(eventID: "OnCommunicate", references: ["timeout"])
        }
    }

    func enterSelectMode(params: [String]) {
        selectModeActive = true
        selectModeScope = currentScope
        let requestedMode = params.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        selectModeName = requestedMode?.isEmpty == false ? requestedMode! : "rect"
        InputMonitor.shared.beginSelectionMode(scope: selectModeScope, mode: selectModeName)
        EventBridge.shared.notify(.OnSelectModeBegin, refs: [
            "scopeID": String(selectModeScope),
            "mode": selectModeName
        ])
    }

    func leaveSelectMode(params _: [String]) {
        guard selectModeActive else {
            EventBridge.shared.notify(.OnSelectModeCancel, refs: [
                "scopeID": String(currentScope),
                "mode": "rect"
            ])
            return
        }
        selectModeActive = false
        let scope = selectModeScope
        let mode = selectModeName
        let rect = InputMonitor.shared.endSelectionMode()
        guard let rect, rect.width > 0, rect.height > 0 else {
            EventBridge.shared.notify(.OnSelectModeCancel, refs: [
                "scopeID": String(scope),
                "mode": mode
            ])
            return
        }
        let selection = "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.maxX)),\(Int(rect.maxY))"
        EventBridge.shared.notify(.OnSelectModeComplete, refs: [
            "scopeID": String(scope),
            "mode": mode,
            "selectionRect": selection
        ])
    }

    func enterCollisionMode() {
        collisionModeActive = true
    }

    func leaveCollisionMode() {
        collisionModeActive = false
    }

    func enterPassiveMode() {
        passiveModeActive = true
        EventBridge.shared.notifyCustom("OnPassiveModeBegin", params: [:])
    }

    func leavePassiveMode() {
        passiveModeActive = false
        EventBridge.shared.notifyCustom("OnPassiveModeEnd", params: [:])
    }

    func enterInductionMode(params: [String]) {
        inductionModeActive = true
        var payload: [String: String] = [:]
        for (index, value) in params.enumerated() {
            payload["Reference\(index)"] = value
        }
        EventBridge.shared.notifyCustom("OnInductionModeBegin", params: payload)
    }

    func leaveInductionMode() {
        inductionModeActive = false
        EventBridge.shared.notifyCustom("OnInductionModeEnd", params: [:])
    }

    func enterNoUserBreakMode() {
        noUserBreakModeActive = true
        EventBridge.shared.notifyCustom("OnNoUserBreakModeBegin", params: [:])
    }

    func leaveNoUserBreakMode() {
        noUserBreakModeActive = false
        EventBridge.shared.notifyCustom("OnNoUserBreakModeEnd", params: [:])
    }

    /// Force the balloon for one scope to display its online marker.
    /// The state intentionally persists until the matching leave command or
    /// ghost shutdown, as required by the Sakura Script specification.
    func enterOnlineMode(scope: Int) {
        DispatchQueue.main.async {
            let vm = self.getBalloonVM(for: scope)
            vm.onlineModeActive = true
            vm.onlineMarkerIndex = 0
            self.startOnlineMarkerAnimation(for: scope)
        }
    }

    /// Stop the forced online marker for one scope.
    func leaveOnlineMode(scope: Int) {
        DispatchQueue.main.async {
            self.onlineMarkerTimers[scope]?.invalidate()
            self.onlineMarkerTimers.removeValue(forKey: scope)
            let vm = self.getBalloonVM(for: scope)
            vm.onlineModeActive = false
            vm.onlineMarkerIndex = 0
        }
    }

    private func startOnlineMarkerAnimation(for scope: Int) {
        onlineMarkerTimers[scope]?.invalidate()
        onlineMarkerTimers.removeValue(forKey: scope)

        guard balloonViewModels[scope] != nil,
              let loader = balloonImageLoader,
              let config = balloonConfig,
              loader.loadOnlineMarker(index: 0, filenamePrefix: config.onlineMarkerFilename) != nil else {
            return
        }

        let interval = max(0.05, config.onlineMarkerInterval)
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self,
                  let vm = self.balloonViewModels[scope],
                  vm.onlineModeActive,
                  let loader = self.balloonImageLoader,
                  let config = self.balloonConfig else { return }

            let next = vm.onlineMarkerIndex + 1
            if loader.loadOnlineMarker(index: next, filenamePrefix: config.onlineMarkerFilename) != nil {
                vm.onlineMarkerIndex = next
            } else {
                vm.onlineMarkerIndex = 0
            }
        }
        onlineMarkerTimers[scope] = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func setBalloonMarker(_ marker: String) {
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            vm.balloonMarkerText = marker
        }
    }

    func setBalloonNumber(fileName: String = "", current: String = "", maximum: String = "") {
        DispatchQueue.main.async {
            guard let vm = self.balloonViewModels[self.currentScope] else { return }
            vm.balloonNumberFileName = fileName
            vm.balloonNumberCurrent = current
            vm.balloonNumberMaximum = maximum
            vm.balloonNumberVisible = !fileName.isEmpty || !current.isEmpty || !maximum.isEmpty
        }
    }

    func setSerikoTalk(mode: String) {
        let enabled = mode.lowercased() == "1" || mode.lowercased() == "true" || mode.lowercased() == "on"
        serikoTalkEnabledForScript = enabled
        EventBridge.shared.notifyCustom("OnSerikoTalkChanged", refs: ["enabled": enabled ? "1" : "0"])
    }

    func openDeveloperTool(_ tool: String) {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.showDevTools()
            NotificationCenter.default.post(name: .devToolsReload, object: tool)
        }
    }

    @discardableResult
    func requestDialogEvent(eventID: String, references: [String]) -> Bool {
        guard !eventID.isEmpty else { return false }
        if let response = shioriRuntime?.request(method: "GET", id: eventID, refs: references, timeout: 4.0),
           response.ok,
           let script = response.value,
           !script.isEmpty {
            runNotifyScript(
                script,
                translationContext: .init(eventID: eventID, references: references)
            )
            return true
        } else {
            var params: [String: String] = [:]
            for (index, value) in references.enumerated() {
                params["Reference\(index)"] = value
            }
            // Dialog events are generated by this ghost's UI. Do not broadcast a
            // fallback response to every running ghost when the local runtime is
            // unavailable or does not implement the event.
            EventBridge.shared.notifyCustom(eventID, params: params, to: self, ignoreResponseScript: true)
            return false
        }
    }

    private func scheduleModalTimeout(timeoutMs: Int?, onTimeout: @escaping () -> Void) -> Timer? {
        guard let timeoutMs, timeoutMs > 0 else { return nil }
        let timeoutSec = TimeInterval(timeoutMs) / 1000.0
        return Timer.scheduledTimer(withTimeInterval: timeoutSec, repeats: false) { _ in
            onTimeout()
            NSApp.abortModal()
        }
    }
    
}

private extension String {
    func matches(for pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let nsrange = NSRange(startIndex..., in: self)
        return regex.matches(in: self, options: [], range: nsrange).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: self) else {
                return nil
            }
            return String(self[range])
        }
    }
}
