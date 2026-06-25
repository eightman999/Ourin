import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

@objc public protocol OurinShioriXPC {
    func execute(_ request: Data, bundlePath: String, withReply reply: @escaping (Data?, String?) -> Void)
}

public enum ShioriLoaderError: Error, CustomStringConvertible {
    case openFailed(String)
    case missingRequiredSymbol(String)
    case xpcUnavailable(String)
    case requestTimeout
    case requestFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let detail):
            return "Failed to open SHIORI module: \(detail)"
        case .missingRequiredSymbol(let name):
            return "Required SHIORI symbol missing: \(name)"
        case .xpcUnavailable(let detail):
            return "SHIORI XPC backend unavailable: \(detail)"
        case .requestTimeout:
            return "SHIORI XPC request timed out."
        case .requestFailed(let detail):
            return "SHIORI request failed: \(detail)"
        }
    }
}

// MARK: - Backend Protocol
/// Common interface for different SHIORI backends.
protocol ShioriBackend {
    func request(_ text: String) -> String?
    func unload()
}

// MARK: - YAYA Backend
/// Backend for YAYA ghosts, communicating with a helper process.
final class YayaBackend: ShioriBackend {
    private let yayaAdapter: YayaAdapter

    init?(ghostURL: URL, descript: [String:String]) {
        let ghostMasterURL = ghostURL.appendingPathComponent("ghost/master")
        let yayaTxtURL = ghostMasterURL.appendingPathComponent("yaya.txt")

        // yaya.txtはUTF-8 BOM付きの可能性があるため、BOMを許容するString.init(contentsOf:)を使用する
        guard let yayaTxtContents = try? String(contentsOf: yayaTxtURL) else {
            //NSLog("[Ourin.YayaBackend] Failed to read yaya.txt")
            return nil
        }

        // Recursively parse config files to collect all dic entries (+ charset 指定)
        var collector = DicCollector()
        collectDicEntries(content: yayaTxtContents, baseURL: ghostMasterURL, sourceName: "yaya.txt",
                          collector: &collector, visited: [])

        NSLog("[YayaBackend] Collected \(collector.entries.count) dic entries from yaya.txt and includes (charset: \(collector.globalCharset ?? "auto"))")

        if collector.entries.isEmpty {
            //NSLog("[Ourin.YayaBackend] No dic files found in yaya.txt")
            return nil
        }

        guard let adapter = YayaAdapter() else {
            NSLog("[YayaBackend] Failed to initialize YayaAdapter (is yaya_core missing?)")
            return nil
        }

        let ok = adapter.load(ghostRoot: ghostMasterURL, dicEntries: collector.entries,
                              encoding: collector.globalCharset ?? "auto")
        if !ok {
            //NSLog("[Ourin.YayaBackend] YayaAdapter.load failed")
            return nil
        }

        self.yayaAdapter = adapter
        //NSLog("[Ourin.YayaBackend] YAYA backend initialized successfully for \(ghostURL.lastPathComponent)")
    }

    func request(_ text: String) -> String? {
        guard let parsed = YayaBackend.parseRequest(text) else {
            return "SHIORI/3.0 400 Bad Request\r\n\r\n"
        }

        guard let yayaResponse = yayaAdapter.request(method: parsed.method, id: parsed.id, headers: parsed.headers, refs: parsed.refs, timeout: 5.0) else {
            return "\(parsed.protocolVersion) 500 Internal Server Error\r\n\r\n"
        }

        return YayaBackend.buildResponse(
            from: yayaResponse,
            requestVersion: parsed.protocolVersion,
            requestMethod: parsed.originalMethod
        )
    }

    func unload() {
        yayaAdapter.unload()
    }
}

// MARK: - YAYA Config Parsing Helpers

/// Structured dictionary load entry produced by the YAYA config parser.
/// Carries enough metadata to honor per-dic encoding and to report provenance.
struct DicEntry: Equatable {
    /// Path relative to ghost/master (as written in the config file).
    let path: String
    /// Per-dic encoding hint (e.g. "UTF-8", "Shift_JIS"). nil = inherit global charset.
    var encoding: String?
    /// Config file this entry originated from (for diagnostics).
    let sourceConfig: String
    /// 1-based line number within sourceConfig.
    let sourceLine: Int

    /// Identity for duplicate suppression (first-occurrence wins).
    static func == (lhs: DicEntry, rhs: DicEntry) -> Bool {
        // Compare normalized relative path only; same file from two configs is a duplicate.
        lhs.path.caseInsensitiveCompare(rhs.path) == .orderedSame
    }
    func hash(into hasher: inout Hasher) { hasher.combine(path.lowercased()) }
}

/// Mutable collector state shared across recursive config parsing.
final class DicCollector {
    var entries: [DicEntry] = []
    var globalCharset: String? = nil
    /// Already-visited absolute config paths (include cycle prevention).
    private var visited: Set<String> = []

    func wasVisited(_ absolutePath: String) -> Bool { visited.contains(absolutePath) }
    func markVisited(_ absolutePath: String) { visited.insert(absolutePath) }

    /// Add an entry unless an identical relative path was already added (first-occurrence wins).
    @discardableResult
    func addEntry(path: String, encoding: String?, source: String, line: Int) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let candidate = DicEntry(path: trimmed, encoding: encoding, sourceConfig: source, sourceLine: line)
        if entries.contains(where: { $0 == candidate }) {
            NSLog("[YayaBackend] Skipping duplicate dic entry: \(trimmed)")
            return false
        }
        entries.append(candidate)
        return true
    }
}

/// Resolve a YAYA config file encoding token (e.g. "UTF-8", "Shift_JIS", "sjis") to a
/// canonical name understood by yaya_core. Returns nil for empty/auto.
private func canonicalCharset(_ raw: String) -> String? {
    let t = raw.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return nil }
    let lower = t.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "")
    switch lower {
    case "utf8": return "UTF-8"
    case "shiftjis", "sjis", "cp932", "windows31j", "ms932", "ms_kanji": return "CP932"
    case "auto", "default": return nil
    default: return t
    }
}

/// Recursively parse YAYA config files (yaya.txt, system_config.txt, etc.) to collect dic entries
/// @param content The content of the config file
/// @param baseURL The base directory (ghost/master)
/// @param dicFiles In-out array to collect dic file paths
/// @param visited Set of already-visited file paths to prevent infinite recursion
func parseYayaConfigFile(content: String, baseURL: URL, dicFiles: inout [String], visited: Set<String>) {
    var collector = DicCollector()
    collectDicEntries(content: content, baseURL: baseURL, sourceName: "yaya.txt", collector: &collector, visited: visited)
    dicFiles.append(contentsOf: collector.entries.map { $0.path })
}

/// charset 指定（"charset,Shift_JIS" 等）も収集するバージョン。
/// 収集した charset は yaya_core の辞書デコードのヒントとして渡す。
func parseYayaConfigFile(content: String, baseURL: URL, dicFiles: inout [String], charset: inout String?, visited: Set<String>) {
    var collector = DicCollector()
    collectDicEntries(content: content, baseURL: baseURL, sourceName: "yaya.txt", collector: &collector, visited: visited)
    dicFiles.append(contentsOf: collector.entries.map { $0.path })
    if charset == nil { charset = collector.globalCharset }
}

/// Primary structured parser. Produces `DicEntry` list and a global dic charset.
/// Supports: `charset`/`charset.*` directives, `dic, path[, enc]`, `dicdir, dir`, `include, file`,
/// `_loading_order.txt`, duplicate suppression (first-occurrence), and include cycle prevention.
func collectDicEntries(content: String, baseURL: URL, sourceName: String,
                       collector: inout DicCollector, visited: Set<String>) {
    let lines = content.components(separatedBy: .newlines)

    for (idx, rawLine) in lines.enumerated() {
        let lineNumber = idx + 1
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespaces)

        // Skip comments and empty lines
        if trimmedLine.isEmpty || trimmedLine.hasPrefix("//") {
            continue
        }

        // Remove inline comments
        let lineWithoutComment: String
        if let commentIndex = trimmedLine.range(of: "//") {
            lineWithoutComment = String(trimmedLine[..<commentIndex.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else {
            lineWithoutComment = trimmedLine
        }
        guard !lineWithoutComment.isEmpty else { continue }

        let lower = lineWithoutComment.lowercased()

        // Parse charset directives: "charset, X" and "charset.<scope>, X"
        // Relevant scope for dictionaries is "dic" (e.g. charset.dic, UTF-8).
        if lower.hasPrefix("charset") {
            // Split off the value after the first comma
            guard let commaRange = lineWithoutComment.range(of: ",") else { continue }
            let keyPart = String(lineWithoutComment[..<commaRange.lowerBound]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(lineWithoutComment[commaRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            // keyPart is "charset" or "charset.dic" / "charset.output" / ...
            if keyPart == "charset" || keyPart == "charset.dic" {
                if collector.globalCharset == nil, let canon = canonicalCharset(value) {
                    collector.globalCharset = canon
                }
            }
            // Other charset scopes (output/file/save/extension) are noted but not needed for loading.
            continue
        }

        // Parse "dic, filename" or "dic, path/filename, encoding"
        if lower.hasPrefix("dic,") {
            let remainder = String(lineWithoutComment.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            let parts = remainder.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let dicPath = parts.first, !dicPath.isEmpty else { continue }
            // parts[1], if present, is the per-dic encoding
            var perDicEnc: String? = nil
            if parts.count >= 2 {
                perDicEnc = canonicalCharset(parts[1])
            }
            NSLog("[YayaBackend] Adding dic file: \(dicPath)\(perDicEnc.map { " (\($0))" } ?? "")")
            collector.addEntry(path: dicPath, encoding: perDicEnc, source: sourceName, line: lineNumber)
            continue
        }

        // Parse "dicdir, path" — load a directory of .dic files in declared order.
        if lower.hasPrefix("dicdir,") {
            let dirRel = String(lineWithoutComment.dropFirst("dicdir,".count)).trimmingCharacters(in: .whitespaces)
            let dirURL = baseURL.appendingPathComponent(dirRel)
            NSLog("[YayaBackend] Processing dicdir: \(dirRel)")
            let dirEntries = expandDicDir(dirURL: dirURL, baseURL: baseURL, globalCharset: collector.globalCharset,
                                          source: sourceName, line: lineNumber)
            for e in dirEntries {
                collector.addEntry(path: e.path, encoding: e.encoding, source: sourceName, line: lineNumber)
            }
            continue
        }

        // Parse "include, filename"
        if lower.hasPrefix("include,") {
            let includePath = String(lineWithoutComment.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            let includeURL = baseURL.appendingPathComponent(includePath)
            let absolutePath = includeURL.path

            NSLog("[YayaBackend] Processing include: \(includePath)")

            // Prevent infinite recursion
            if collector.wasVisited(absolutePath) || visited.contains(absolutePath) {
                NSLog("[YayaBackend] Skipping already visited: \(includePath)")
                continue
            }
            collector.markVisited(absolutePath)

            // Try to read the included file (try UTF-8 first, then Shift-JIS)
            if let includeContent = (try? String(contentsOf: includeURL, encoding: .utf8)) ?? (try? String(contentsOf: includeURL, encoding: .shiftJIS)) {
                NSLog("[YayaBackend] Successfully read include file: \(includePath)")
                var nested = visited
                nested.insert(absolutePath)
                collectDicEntries(content: includeContent, baseURL: baseURL, sourceName: includePath,
                                  collector: &collector, visited: nested)
            } else {
                NSLog("[YayaBackend] Failed to read include file: \(includePath)")
            }
            continue
        }

        // Unknown directives (ignoreiolog, log, etc.) are intentionally skipped.
    }
}

/// Expand a `dicdir` directory into ordered dic entries.
/// If `_loading_order.txt` exists, honor its enable/disable + ordering; otherwise load `.dic`
/// files in deterministic lexical order. Paths are returned relative to baseURL (ghost/master).
private func expandDicDir(dirURL: URL, baseURL: URL, globalCharset: String?, source: String, line: Int) -> [DicEntry] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: dirURL.path) else {
        NSLog("[YayaBackend] dicdir not found: \(dirURL.path)")
        return []
    }

    let loadingOrderURL = dirURL.appendingPathComponent("_loading_order.txt")

    // Helper: build a DicEntry relative to baseURL from a filename inside dirURL.
    func entry(forFile filename: String, encoding: String?) -> DicEntry {
        // Path relative to baseURL (ghost/master). dicdir entries are typically subpaths.
        let fileRelToBase: String
        if dirURL.path == baseURL.path {
            fileRelToBase = filename
        } else {
            // Compute relative path dirRel/filename
            let baseStd = baseURL.standardizedFileURL.path
            let dirStd = dirURL.standardizedFileURL.path
            if dirStd.hasPrefix(baseStd) {
                let rel = String(dirStd.dropFirst(baseStd.count))
                let cleaned = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
                fileRelToBase = cleaned.isEmpty ? filename : "\(cleaned)/\(filename)"
            } else {
                fileRelToBase = filename
            }
        }
        return DicEntry(path: fileRelToBase, encoding: encoding ?? globalCharset, sourceConfig: source, sourceLine: line)
    }

    // 1) Honor _loading_order.txt if present.
    //    The real yaya-dic format uses the SAME directives as yaya.txt:
    //      dic, filename, encoding     -> load (error if missing)
    //      dicif, filename, encoding   -> load if exists (skip silently if missing)
    //    Bare filenames are also tolerated as a convenience.
    if let orderContent = (try? String(contentsOf: loadingOrderURL, encoding: .utf8)) ?? (try? String(contentsOf: loadingOrderURL, encoding: .shiftJIS)) {
        NSLog("[YayaBackend] dicdir: using _loading_order.txt in \(dirURL.lastPathComponent)")
        var result: [DicEntry] = []
        for rawLine in orderContent.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("//") { continue }
            // Strip inline comments
            var entryToken = trimmed
            if let c = trimmed.range(of: "//") { entryToken = String(trimmed[..<c.lowerBound]).trimmingCharacters(in: .whitespaces) }
            guard !entryToken.isEmpty else { continue }

            let lower = entryToken.lowercased()
            // Parse "dic, filename[, encoding]" and "dicif, filename[, encoding]"
            if lower.hasPrefix("dic,") || lower.hasPrefix("dicif,") {
                let isDicif = lower.hasPrefix("dicif,")
                let prefixLen = isDicif ? "dicif,".count : "dic,".count
                let remainder = String(entryToken.dropFirst(prefixLen)).trimmingCharacters(in: .whitespaces)
                let parts = remainder.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let filename = parts.first, !filename.isEmpty else { continue }
                let enc: String? = (parts.count >= 2) ? canonicalCharset(parts[1]) : nil
                // dicif: skip silently if the file does not exist
                if isDicif {
                    let fileURL = dirURL.appendingPathComponent(filename)
                    if !fm.fileExists(atPath: fileURL.path) {
                        NSLog("[YayaBackend] dicif: skipping missing \(filename) in \(dirURL.lastPathComponent)")
                        continue
                    }
                }
                result.append(entry(forFile: filename, encoding: enc))
                continue
            }

            // Tolerate legacy "flag,filepath" / bare "filepath" forms.
            let parts = entryToken.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let first = parts.first, !first.isEmpty else { continue }
            if parts.count >= 2, let flag = Int(first) {
                // 0,filepath (disabled) -> skip; 1,filepath (enabled) -> load
                if flag == 0 { continue }
                result.append(entry(forFile: parts[1], encoding: nil))
            } else {
                result.append(entry(forFile: first, encoding: nil))
            }
        }
        if !result.isEmpty { return result }
        // Fall through to lexical enumeration if order file was empty.
    }

    // 2) Lexical fallback: enumerate .dic files in the directory (shallow).
    NSLog("[YayaBackend] dicdir: no usable _loading_order.txt, loading .dic files lexically from \(dirURL.lastPathComponent)")
    guard let contents = try? fm.contentsOfDirectory(atPath: dirURL.path) else { return [] }
    let dicFiles = contents.filter { $0.lowercased().hasSuffix(".dic") }.sorted()
    return dicFiles.map { entry(forFile: $0, encoding: nil) }
}

// MARK: - YayaBackend Helpers
extension YayaBackend {
    struct ParsedRequest {
        let method: String
        let originalMethod: String
        let protocolVersion: String
        let id: String
        let headers: [String: String]
        let refs: [String]
    }

    static func parseDescript(url: URL) -> [String: String] {
        guard let contents = (try? String(contentsOf: url, encoding: .shiftJIS)) ?? (try? String(contentsOf: url, encoding: .utf8)) else {
            return [:]
        }
        var dict: [String: String] = [:]
        let lines = contents.components(separatedBy: .newlines)
        for line in lines {
            if line.starts(with: "//") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            if let separatorIndex = line.firstIndex(of: ",") {
                let key = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[separatorIndex...]).dropFirst().trimmingCharacters(in: .whitespaces)
                dict[key] = value
            }
        }
        return dict
    }

    static func parseRequest(_ text: String) -> ParsedRequest? {
        let lines = text.components(separatedBy: "\r\n")
        guard lines.count >= 2, let firstLine = lines.first else { return nil }
        let parts = firstLine.components(separatedBy: .whitespaces)
        guard parts.count >= 2 else { return nil }
        let originalMethod = parts[0].uppercased()
        let protocolVersion = parts[1].uppercased()
        var headers: [String: String] = [:]
        var lowercasedHeaders: [String: String] = [:]
        var refs: [String] = []
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let separatorIndex = line.firstIndex(of: ":") {
                let key = String(line[..<separatorIndex])
                let value = String(line[separatorIndex...]).dropFirst().trimmingCharacters(in: .whitespaces)
                headers[key] = value
                lowercasedHeaders[key.lowercased()] = value
            }
        }

        let id = lowercasedHeaders["id"]
            ?? lowercasedHeaders["event"]
            ?? (originalMethod == "TEACH" ? "OnTeach" : nil)
        guard let resolvedID = id, !resolvedID.isEmpty else { return nil }

        var i = 0
        while let ref = headers["Reference\(i)"] ?? lowercasedHeaders["reference\(i)"] {
            refs.append(ref)
            i += 1
        }

        if originalMethod == "TEACH", refs.isEmpty, let sentence = lowercasedHeaders["sentence"], !sentence.isEmpty {
            refs.append(sentence)
        }

        let method: String
        if originalMethod == "TEACH" {
            method = "NOTIFY"
        } else {
            method = originalMethod
        }
        return ParsedRequest(
            method: method,
            originalMethod: originalMethod,
            protocolVersion: protocolVersion.hasPrefix("SHIORI/2.") ? protocolVersion : "SHIORI/3.0",
            id: resolvedID,
            headers: headers,
            refs: refs
        )
    }

    static func buildResponse(from yayaResponse: YayaResponse, requestVersion: String, requestMethod: String) -> String {
        var status = yayaResponse.status
        // SHIORI/2.x TEACH legacy mapping: a "no content" (204) response to a TEACH
        // request is reported as 312 (input not trusted). Its reason phrase must be
        // "No Content (Not Trusted)", distinct from a genuine 311/312 OnTeach value.
        var teachMappedTo312 = false
        if requestVersion.hasPrefix("SHIORI/2."), requestMethod == "TEACH", status == 204 {
            status = 312
            teachMappedTo312 = true
        }
        var statusText = "OK"
        if teachMappedTo312 {
            statusText = "No Content (Not Trusted)"
        } else {
            switch status {
            case 204: statusText = "No Content"
            case 311: statusText = "Not Enough"
            case 312: statusText = "Not Trusted"
            case 400: statusText = "Bad Request"
            case 500: statusText = "Internal Server Error"
            default: break
            }
        }
        var responseString = "\(requestVersion) \(status) \(statusText)\r\n"
        if let headers = yayaResponse.headers {
            for (key, value) in headers {
                responseString += "\(key): \(value)\r\n"
            }
        }
        if let value = yayaResponse.value {
            responseString += "Value: \(value)\r\n"
        }
        responseString += "\r\n"
        return responseString
    }
}

// MARK: - XPC Backend
/// Backend that executes SHIORI requests in an external XPC service.
final class XpcBackend: ShioriBackend {
    private let connection: NSXPCConnection
    private let moduleURL: URL
    private let timeout: TimeInterval

    init(serviceName: String, moduleURL: URL, timeout: TimeInterval = 5.0) throws {
        guard !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShioriLoaderError.xpcUnavailable("Empty service name")
        }
        self.connection = NSXPCConnection(machServiceName: serviceName, options: [])
        self.connection.remoteObjectInterface = NSXPCInterface(with: OurinShioriXPC.self)
        self.connection.resume()
        self.moduleURL = moduleURL
        self.timeout = timeout
    }

    func request(_ text: String) -> String? {
        let reqCharset = EncodingAdapter.detectCharset(in: Data(text.utf8))
        let requestData = EncodingAdapter.encode(text, charset: reqCharset)
        let sem = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: String?
        var connectionError: Error?

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            connectionError = error
            sem.signal()
        }) as? OurinShioriXPC else {
            NSLog("[XpcBackend] Failed to create remote proxy")
            return nil
        }

        proxy.execute(requestData, bundlePath: moduleURL.path) { data, errorText in
            responseData = data
            responseError = errorText
            sem.signal()
        }

        if sem.wait(timeout: .now() + timeout) == .timedOut {
            NSLog("[XpcBackend] Request timeout")
            return nil
        }

        if let connectionError {
            NSLog("[XpcBackend] Connection error: \(connectionError.localizedDescription)")
            return nil
        }
        if let responseError {
            NSLog("[XpcBackend] Remote error: \(responseError)")
            return nil
        }
        guard let responseData else {
            return nil
        }
        let respCharset = EncodingAdapter.detectCharset(in: responseData)
        return EncodingAdapter.decode(responseData, charset: respCharset)
            ?? String(data: responseData, encoding: .utf8)
    }

    func unload() {
        connection.invalidate()
    }
}

// MARK: - Bundle Backend
/// Backend for SHIORI modules loaded from .bundle/.plugin files (macOS native)
final class BundleBackend: ShioriBackend {
    private let bundle: CFBundle
    private var loadFn: ShioriLoad?
    private var requestFn: ShioriRequest?
    private var unloadFn: ShioriUnload?
    private var freeFn: ShioriFree?
    
    /// Path of loaded module
    public let moduleURL: URL
    
    init(url: URL) throws {
        guard let b = CFBundleCreate(kCFAllocatorDefault, url as CFURL) else {
            throw NSError(domain: "USL.BundleBackend", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CFBundle from \(url.path)"])
        }
        guard CFBundleLoadExecutable(b) else {
            let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError, userInfo: [NSLocalizedDescriptionKey: "Failed to load bundle executable from \(url.path)"])
            throw error
        }
        
        self.bundle = b
        self.moduleURL = url
        
        func loadSymbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let sym = CFBundleGetFunctionPointerForName(b, name as CFString) else { return nil }
            return unsafeBitCast(sym, to: type)
        }
        
        loadFn = loadSymbol("shiori_load", as: ShioriLoad.self)
        requestFn = loadSymbol("shiori_request", as: ShioriRequest.self)
        unloadFn = loadSymbol("shiori_unload", as: ShioriUnload.self)
        freeFn = loadSymbol("shiori_free", as: ShioriFree.self)

        guard requestFn != nil else {
            throw ShioriLoaderError.missingRequiredSymbol("shiori_request")
        }
        guard freeFn != nil else {
            throw ShioriLoaderError.missingRequiredSymbol("shiori_free")
        }
        
        NSLog("[BundleBackend] Loaded bundle: \(url.lastPathComponent)")
        NSLog("[BundleBackend] Found symbols: load=\(loadFn != nil), request=\(requestFn != nil), unload=\(unloadFn != nil), free=\(freeFn != nil)")
        
        if let l = loadFn {
            let dirPath = url.deletingLastPathComponent().path
            let dirCString = (dirPath as NSString).utf8String
            _ = l(dirCString)
            NSLog("[BundleBackend] Called shiori_load with path: \(dirPath)")
        }
    }
    
    deinit {
        unload()
    }
    
    func request(_ text: String) -> String? {
        guard let req = requestFn else {
            NSLog("[BundleBackend] shiori_request not available")
            return nil
        }
        
        // 要求は Charset ヘッダ（既定 UTF-8）に従ってエンコードする
        let reqCharset = EncodingAdapter.detectCharset(in: Data(text.utf8))
        let bytes = Array(EncodingAdapter.encode(text, charset: reqCharset))
        var outPtr: UnsafeMutablePointer<UInt8>? = nil
        var outLen: Int = 0

        let ok = bytes.withUnsafeBytes {
            req($0.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count, &outPtr, &outLen)
        }

        guard ok, let p = outPtr else {
            NSLog("[BundleBackend] shiori_request failed")
            return nil
        }

        let data = Data(bytes: p, count: outLen)
        freeFn?(p)
        // 応答は応答ヘッダの Charset に従ってデコードする（既定 UTF-8）
        let respCharset = EncodingAdapter.detectCharset(in: data)
        return EncodingAdapter.decode(data, charset: respCharset) ?? String(data: data, encoding: .utf8)
    }
    
    func unload() {
        if let u = unloadFn {
            u()
            NSLog("[BundleBackend] Called shiori_unload")
        }
        loadFn = nil
        requestFn = nil
        unloadFn = nil
        freeFn = nil
    }
}

// MARK: - Dylib Backend
/// Backend for traditional SHIORI ghosts loaded from .dylib files.
final class DylibBackend: ShioriBackend {
    private var handle: UnsafeMutableRawPointer?
    private var loadFn: ShioriLoad?
    private var requestFn: ShioriRequest?
    private var unloadFn: ShioriUnload?
    private var freeFn: ShioriFree?

    /// Path of loaded module
    public let moduleURL: URL

    init(url: URL) throws {
        guard let h = dlopen(url.path, RTLD_NOW) else {
            let detail = dlerror().map { String(cString: $0) } ?? "unknown"
            throw ShioriLoaderError.openFailed(detail)
        }
        handle = h
        func loadSymbol<T>(_ names: [String], as type: T.Type) -> T? {
            for name in names {
                if let sym = dlsym(h, name) {
                    return unsafeBitCast(sym, to: type)
                }
            }
            return nil
        }
        // 汎用 dylib 規約に対応: `shiori_` 接頭辞付き・無印（Windows 由来の load/unload/request）・
        // および UTF-8 パス版 `loadu` を順に解決する。`loadu` を優先（macOS のパスは UTF-8）。
        loadFn = loadSymbol(["shiori_loadu", "loadu", "shiori_load", "load"], as: ShioriLoad.self)
        requestFn = loadSymbol(["shiori_request", "request"], as: ShioriRequest.self)
        unloadFn = loadSymbol(["shiori_unloadu", "unloadu", "shiori_unload", "unload"], as: ShioriUnload.self)
        freeFn = loadSymbol(["shiori_free", "free"], as: ShioriFree.self)
        self.moduleURL = url

        guard requestFn != nil else {
            dlclose(h)
            handle = nil
            throw ShioriLoaderError.missingRequiredSymbol("shiori_request")
        }
        guard freeFn != nil else {
            dlclose(h)
            handle = nil
            throw ShioriLoaderError.missingRequiredSymbol("shiori_free")
        }

        // call load if available
        if let l = loadFn {
            _ = l(url.deletingLastPathComponent().path)
        }
    }

    deinit { unload() }

    func request(_ text: String) -> String? {
        guard let req = requestFn else { return nil }
        let reqCharset = EncodingAdapter.detectCharset(in: Data(text.utf8))
        let bytes = Array(EncodingAdapter.encode(text, charset: reqCharset))
        var outPtr: UnsafeMutablePointer<UInt8>? = nil
        var outLen: Int = 0
        let ok = bytes.withUnsafeBytes {
            req($0.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count, &outPtr, &outLen)
        }
        guard ok, let p = outPtr else { return nil }
        let data = Data(bytes: p, count: outLen)
        freeFn?(p)
        let respCharset = EncodingAdapter.detectCharset(in: data)
        return EncodingAdapter.decode(data, charset: respCharset) ?? String(data: data, encoding: .utf8)
    }

    func unload() {
        if let u = unloadFn { u() }
        if let h = handle { dlclose(h); handle = nil }
        loadFn = nil
        requestFn = nil
        unloadFn = nil
        freeFn = nil
    }
}


/// Function pointer types for SHIORI C-ABI
private typealias ShioriLoad = @convention(c) (UnsafePointer<CChar>?) -> Bool
private typealias ShioriRequest = @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?, UnsafeMutablePointer<Int>?) -> Bool
private typealias ShioriUnload = @convention(c) () -> Void
private typealias ShioriFree = @convention(c) (UnsafeMutablePointer<UInt8>?) -> Void

/// Dynamic loader for SHIORI modules following USL spec
public final class ShioriLoader {
    private let backend: ShioriBackend

    /// Path of loaded module, if available.
    public var moduleURL: URL? {
        if let dylib = backend as? DylibBackend {
            return dylib.moduleURL
        }
        if let bundle = backend as? BundleBackend {
            return bundle.moduleURL
        }
        return nil
    }

    private init(backend: ShioriBackend) {
        self.backend = backend
    }

    deinit { unload() }

    /// Initialize SHIORI backend from an explicit module path.
    public convenience init?(moduleURL: URL, xpcServiceName: String? = ShioriLoader.resolvedXpcServiceName()) {
        do {
            let backend = try ShioriLoader.makeBackend(moduleURL: moduleURL, xpcServiceName: xpcServiceName)
            self.init(backend: backend)
        } catch {
            NSLog("[ShioriLoader] Failed to initialize backend for \(moduleURL.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Attempt to load module by name searching typical USL paths
    public convenience init?(module name: String, base: URL) {
        let shioriName = (name as NSString).lastPathComponent.lowercased()
        let backend: ShioriBackend
        
        if shioriName == "yaya.dll" {
            // It's YAYA. Instantiate YayaBackend.
            // The descript dictionary will be loaded inside YayaBackend's initializer.
            // For now, we pass an empty dictionary as a placeholder.
            guard let yaya = YayaBackend(ghostURL: base, descript: [:]) else {
                return nil
            }
            backend = yaya
        } else {
            // Search for the module file
            let paths = ShioriLoader.searchPaths(base: base)
            guard let url = ShioriLoader.find(name: name, in: paths) else {
                // Module not found
                return nil
            }
            do {
                backend = try ShioriLoader.makeBackend(moduleURL: url, xpcServiceName: ShioriLoader.resolvedXpcServiceName())
            } catch {
                NSLog("[ShioriLoader] Failed to create backend for \(url.lastPathComponent): \(error)")
                return nil
            }
        }

        self.init(backend: backend)
    }

    /// Send SHIORI request and return raw response string
    public func request(_ text: String) -> String? {
        return backend.request(text)
    }

    /// Unload module if loaded
    public func unload() {
        backend.unload()
    }
}

// MARK: - Search path & name normalization helpers
extension ShioriLoader {
    public static func resolvedXpcServiceName(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let explicit = environment["SHIORI_XPC_SERVICE_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        if let explicit = environment["OURIN_SHIORI_XPC_SERVICE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        let mode = environment["OURIN_SHIORI_ISOLATION_MODE"]?.lowercased()
        if mode == "xpc" {
            return "jp.ourin.shiori"
        }
        return nil
    }

    private static func makeBackend(moduleURL: URL, xpcServiceName: String?) throws -> ShioriBackend {
        if let xpcServiceName {
            do {
                NSLog("[ShioriLoader] Trying XPC backend (\(xpcServiceName)) for \(moduleURL.lastPathComponent)")
                return try XpcBackend(serviceName: xpcServiceName, moduleURL: moduleURL)
            } catch {
                NSLog("[ShioriLoader] XPC backend unavailable, falling back to native loader: \(error)")
            }
        }
        let ext = moduleURL.pathExtension.lowercased()
        if ext == "bundle" || ext == "plugin" {
            return try BundleBackend(url: moduleURL)
        }
        return try DylibBackend(url: moduleURL)
    }

    /// Default search paths defined by USL spec
    static func searchPaths(base: URL) -> [URL] {
        var arr: [URL] = []
        arr.append(base.appendingPathComponent("ghost/master"))
        arr.append(base.appendingPathComponent("ghost/master/modules"))
        if let bundle = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent() {
            arr.append(bundle.appendingPathComponent("Frameworks"))
        }
        return arr
    }

    /// Try to locate module in given search paths
    static func find(name: String, in paths: [URL]) -> URL? {
        let variants = normalizedNames(for: name)
        let fm = FileManager.default
        for dir in paths {
            for v in variants {
                let url = dir.appendingPathComponent(v)
                if fm.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    /// Generate possible file names according to USL name normalization
    static func normalizedNames(for name: String) -> [String] {
        let base = (name as NSString).lastPathComponent
        var stem = base
        var list: [String] = [base]
        if base.hasSuffix(".dll") {
            stem = String(base.dropLast(4))
        } else if let dot = base.lastIndex(of: ".") {
            stem = String(base[..<dot])
        }
        list.append("\(stem).dylib")
        list.append("lib\(stem).dylib")
        list.append("\(stem).bundle")
        list.append("\(stem).plugin")
        list.append("\(stem).so")
        list.append("lib\(stem).so")
        return Array(NSOrderedSet(array: list)) as! [String]
    }
}

// MARK: - SHIORI XPC Service Host
public protocol ShioriRequesting {
    func request(_ text: String) -> String?
    func unload()
}

extension ShioriLoader: ShioriRequesting {}

/// Listener-side service implementation for `OurinShioriXPC`.
public final class ShioriXPCServiceHost: NSObject, NSXPCListenerDelegate, OurinShioriXPC {
    private let listener: NSXPCListener
    private let loaderFactory: (URL) -> ShioriRequesting?
    private let lock = NSLock()
    private var loaders: [String: ShioriRequesting] = [:]

    public init(
        listener: NSXPCListener = .service(),
        loaderFactory: @escaping (URL) -> ShioriRequesting? = { url in
            ShioriLoader(moduleURL: url, xpcServiceName: nil)
        }
    ) {
        self.listener = listener
        self.loaderFactory = loaderFactory
        super.init()
        self.listener.delegate = self
    }

    public func resume() {
        listener.resume()
    }

    public func invalidateAllLoaders() {
        lock.lock()
        let current = loaders.values
        loaders.removeAll()
        lock.unlock()
        current.forEach { $0.unload() }
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: OurinShioriXPC.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    public func execute(_ request: Data, bundlePath: String, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let requestText = String(data: request, encoding: .utf8), !requestText.isEmpty else {
            reply(nil, "Invalid SHIORI request payload")
            return
        }

        let trimmedPath = bundlePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            reply(nil, "Empty SHIORI module path")
            return
        }

        let moduleURL = URL(fileURLWithPath: trimmedPath)
        guard FileManager.default.fileExists(atPath: moduleURL.path) else {
            reply(nil, "SHIORI module not found: \(moduleURL.path)")
            return
        }

        guard let loader = resolveLoader(moduleURL: moduleURL) else {
            reply(nil, "Failed to load SHIORI module: \(moduleURL.lastPathComponent)")
            return
        }

        guard let response = loader.request(requestText) else {
            reply(nil, "SHIORI request failed.")
            return
        }
        reply(Data(response.utf8), nil)
    }

    private func resolveLoader(moduleURL: URL) -> ShioriRequesting? {
        let key = moduleURL.standardizedFileURL.path

        lock.lock()
        if let cached = loaders[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let created = loaderFactory(moduleURL) else {
            return nil
        }

        lock.lock()
        if let existing = loaders[key] {
            lock.unlock()
            created.unload()
            return existing
        }
        loaders[key] = created
        lock.unlock()
        return created
    }
}
