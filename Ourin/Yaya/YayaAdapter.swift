import Foundation

/// Codable request sent to yaya_core helper.
struct YayaRequest: Codable {
    let cmd: String
    let ghost_root: String?
    let dic: [String]?
    /// Structured dic entries with per-file encoding: [["path":..,"encoding":..], ...].
    /// Takes precedence over `dic` when present (transition compatibility).
    let dic_entries: [[String: String]]?
    let encoding: String?
    let env: [String:String]?
    let method: String?
    let id: String?
    let headers: [String:String]?
    let ref: [String]?

    // Convenience initializer that keeps existing call sites simple.
    init(cmd: String, ghost_root: String? = nil, dic: [String]? = nil, dic_entries: [[String: String]]? = nil,
         encoding: String? = nil, env: [String:String]? = nil, method: String? = nil,
         id: String? = nil, headers: [String:String]? = nil, ref: [String]? = nil) {
        self.cmd = cmd; self.ghost_root = ghost_root; self.dic = dic; self.dic_entries = dic_entries
        self.encoding = encoding; self.env = env; self.method = method; self.id = id
        self.headers = headers; self.ref = ref
    }
}

/// Codable response returned from yaya_core helper.
struct YayaResponse: Codable {
    let ok: Bool
    let status: Int
    let headers: [String:String]?
    let value: String?
    let error: String?
    let loaded_dics: [String]?  // List of successfully loaded dictionary files
}

/// Adapter that communicates with YAYA core via JSON line IPC.
final class YayaAdapter {
    private var proc = Process()
    private var inPipe = Pipe()
    private var outPipe = Pipe()
    private var errPipe = Pipe()
    private let ioQueue = DispatchQueue(label: "yaya.adapter.io")

    /// Resource manager for handling SHIORI resource GET requests
    public var resourceManager: ResourceManager?
    private let saoriManager = SaoriManager()

    /// FMO スナップショット供給クロージャ（READFMO 用）。
    /// AppDelegate が起動時に設定する。`id.key\x01value\r\n` 形式の文字列を返すこと。
    public static var fmoSnapshotProvider: (() -> String)?

    /// Create adapter. The helper executable is searched in the app bundle by default.
    init?() {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "yaya_core") else {
            NSLog("[YayaAdapter] Could not locate yaya_core executable in bundle")
            return nil
        }
        proc.executableURL = url
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        // Monitor stderr in background, but avoid flooding logs unless verbose
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard let str = String(data: data, encoding: .utf8), !str.isEmpty else { return }
            let text = str.trimmingCharacters(in: .newlines)
            // Split by lines in case multiple messages arrive at once
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                if Log.verbose {
                    NSLog("[yaya_core stderr] \(line)")
                } else {
                    // Only surface important lines in non-verbose mode
                    if line.localizedCaseInsensitiveContains("error") ||
                       line.localizedCaseInsensitiveContains("failed") {
                        NSLog("[yaya_core stderr] \(line)")
                    }
                }
            }
        }

        do {
            try proc.run()
            NSLog("[YayaAdapter] Launched yaya_core at \(url.path)")
        } catch {
            NSLog("[YayaAdapter] Failed to launch yaya_core at \(url.path): \(error)")
            return nil
        }
    }

    /// Send encodable object as one JSON line.
    private func send<T: Encodable>(_ obj: T) throws {
        let data = try JSONEncoder().encode(obj)
        try sendJSONLine(data)
    }

    private func sendJSONObject(_ obj: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: obj)
        try sendJSONLine(data)
    }

    private func sendJSONLine(_ data: Data) throws {
        inPipe.fileHandleForWriting.write(data)
        inPipe.fileHandleForWriting.write(Data([0x0a]))
    }

    /// Read a single line from helper.
    private func readLine() throws -> Data? {
        var buf = Data()
        let h = outPipe.fileHandleForReading
        while true {
            let d = h.readData(ofLength: 1)
            if d.isEmpty { break }
            if d == Data([0x0a]) { break }
            buf.append(d)
        }
        return buf.isEmpty ? nil : buf
    }

    /// Send request and decode response.
    private func exchange(_ req: YayaRequest) throws -> YayaResponse? {
        Log.debug("[YayaAdapter] exchange() sending request: cmd=\(req.cmd), id=\(req.id ?? "nil")")
        try send(req)
        Log.debug("[YayaAdapter] exchange() request sent, waiting for response...")
        while true {
            guard let line = try readLine() else {
                NSLog("[YayaAdapter] exchange() readLine() returned nil")
                return nil
            }

            if let jsonAny = try? JSONSerialization.jsonObject(with: line),
               let jsonObj = jsonAny as? [String: Any],
               let hostOp = jsonObj["host_op"] as? String {
                try handleHostOperation(hostOp, payload: jsonObj)
                continue
            }

            Log.debug("[YayaAdapter] exchange() received \(line.count) bytes, decoding...")
            let response = try JSONDecoder().decode(YayaResponse.self, from: line)
            Log.debug("[YayaAdapter] exchange() decoded response: ok=\(response.ok)")
            if let value = response.value {
                let preview = String(value.prefix(200))
                Log.debug("[YayaAdapter] Decoded value preview: \(preview)")
            }
            return response
        }
    }

    private func handleHostOperation(_ hostOp: String, payload: [String: Any]) throws {
        switch hostOp {
        case "plugin":
            let req = payload["params"] as? [String: Any] ?? [:]
            let operation = req["operation"] as? String ?? ""
            let params = req["params"] as? [String: Any] ?? [:]
            let response = handlePluginOperation(operation, params: params)
            try sendJSONObject(response)
        case "fmo":
            // READFMO からの同期問い合わせ。現在の FMO スナップショットを返す。
            let req = payload["params"] as? [String: Any] ?? [:]
            let operation = req["operation"] as? String ?? ""
            switch operation {
            case "read":
                let snapshot = Self.fmoSnapshotProvider?() ?? ""
                try sendJSONObject(["ok": true, "snapshot": snapshot])
            default:
                try sendJSONObject(["ok": false, "error": "unsupported fmo operation: \(operation)"])
            }
        default:
            try sendJSONObject(["ok": false, "error": "unsupported host_op: \(hostOp)"])
        }
    }

    /// Try an exchange with timeout; returns nil on timeout.
    private func exchange(_ req: YayaRequest, timeout: TimeInterval) -> YayaResponse? {
        var result: YayaResponse?
        let group = DispatchGroup()
        group.enter()
        ioQueue.async {
            defer { group.leave() }
            do { result = try self.exchange(req) } catch { result = nil }
        }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            NSLog("[YayaAdapter] exchange timed out for cmd=\(req.cmd)")
            return nil
        }
        return result
    }

    /// Load dictionaries for a ghost and perform capability handshake.
    /// - Parameter encoding: yaya.txt の charset 指定（"Shift_JIS" 等）。"auto" は自動判定（UTF-8妥当→UTF-8、それ以外はCP932変換）。
    @discardableResult
    func load(ghostRoot: URL, dicEntries: [DicEntry], encoding: String = "auto") -> Bool {
        Log.debug("[YayaAdapter] load() called with ghostRoot: \(ghostRoot.path), dics: \(dicEntries.count) files")

        // First, try to load messagetxt file if available
        let messagetxtDir = ghostRoot.appendingPathComponent("messagetxt")
        if FileManager.default.fileExists(atPath: messagetxtDir.path) {
            // Try to load language-specific message file (prefer japanese.txt for now)
            let messageFileNames = ["japanese.txt", "english.txt", "simplified-chinese.txt", "traditional-chinese.txt", "classical-chinese.txt"]
            for fileName in messageFileNames {
                let messagePath = messagetxtDir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: messagePath.path) {
                    Log.debug("[YayaAdapter] Loading message file: \(fileName)")
                    // Create a manual JSON request since YayaRequest doesn't have message_path
                    do {
                        let msgDict: [String: Any] = ["cmd": "load_messages", "message_path": messagePath.path]
                        try sendJSONObject(msgDict)

                        // Read response
                        if let line = try readLine() {
                            let response = try JSONDecoder().decode(YayaResponse.self, from: line)
                            if response.ok {
                                Log.debug("[YayaAdapter] Successfully loaded message file: \(fileName)")
                            } else {
                                NSLog("[YayaAdapter] Failed to load message file: \(response.error ?? "unknown error")")
                            }
                        }
                    } catch {
                        NSLog("[YayaAdapter] Error loading message file: \(error)")
                    }
                    break // Only load first available message file
                }
            }
        }

        // Then load dictionary files. Prefer structured entries (per-dic encoding) over flat list.
        let structured: [[String: String]] = dicEntries.map { e in
            var dict: [String: String] = ["path": e.path]
            if let enc = e.encoding { dict["encoding"] = enc }
            return dict
        }
        let req = YayaRequest(cmd: "load", ghost_root: ghostRoot.path, dic: dicEntries.map { $0.path },
                              dic_entries: structured, encoding: encoding,
                              env: ["LANG":"ja_JP.UTF-8"], method: nil, id: nil,
                              headers: ["Charset":"UTF-8"], ref: nil)

        // 辞書ロードはタイムアウト付きで実行する。
        // ヘルパー側のパース不具合（無限ループ等）でロードが返らなくても、
        // GhostManager の起動バックグラウンドスレッドを永久にブロックさせない。
        // 正常時でも多数辞書のパースに時間がかかるため、余裕のある上限にする。
        let response = exchange(req, timeout: 60.0)
        guard let response = response else {
            NSLog("[YayaAdapter] load() timed out or returned no response; tearing down helper")
            forceTerminate()
            return false
        }
        Log.debug("[YayaAdapter] load() response: ok=\(response.ok), status=\(response.status), error=\(response.error ?? "nil")")
        guard response.ok else {
            NSLog("[YayaAdapter] load() failed: response.ok is false")
            return false
        }

        // Log loaded dictionary files if available
        if let loadedDics = response.loaded_dics, !loadedDics.isEmpty {
            Log.debug("[YayaAdapter] Successfully loaded \(loadedDics.count) dictionary files:")
            for (index, dicPath) in loadedDics.enumerated() {
                // Extract just the filename from the full path for cleaner output
                if let filename = dicPath.components(separatedBy: "/").last {
                    Log.debug("[YayaAdapter]   [\(index + 1)] \(filename)")
                } else {
                    Log.debug("[YayaAdapter]   [\(index + 1)] \(dicPath)")
                }
            }
        }

        _ = capability()
        NSLog("[YayaAdapter] load() succeeded")
        return true
    }

    /// ヘルパープロセスを即座に停止する（タイムアウト時の後始末用）。
    /// unload() と異なり "unload" コマンドを送らない（ハング中のヘルパーには届かないため）。
    private func forceTerminate() {
        guard proc.isRunning else { return }
        proc.terminate()
        usleep(200_000) // 0.2s
        if proc.isRunning {
            #if os(macOS)
            kill(pid_t(proc.processIdentifier), SIGKILL)
            #endif
        }
    }

    /// Send SHIORI request with timeout (default 10 seconds).
    /// Handles SHIORI Resource GET requests by querying ResourceManager first.
    func request(method: String, id: String, headers: [String:String] = [:], refs: [String] = [], timeout: TimeInterval = 10.0) -> YayaResponse? {
        // Handle SHIORI Resource GET requests
        if method.uppercased() == "GET", let rm = resourceManager {
            let resourceId = id.lowercased()

            // Known SHIORI resources that should be handled by ResourceManager
            let knownResources = [
                "username", "homeurl", "useorigin1",
                "sakura.defaultleft", "sakura.defaulttop", "sakura.defaultx", "sakura.defaulty",
                "kero.defaultleft", "kero.defaulttop", "kero.defaultx", "kero.defaulty"
            ]

            // Check if this is a char*.default* resource pattern
            let isCharResource = resourceId.hasPrefix("char") &&
                (resourceId.hasSuffix(".defaultleft") || resourceId.hasSuffix(".defaulttop") ||
                 resourceId.hasSuffix(".defaultx") || resourceId.hasSuffix(".defaulty"))

            if knownResources.contains(resourceId) || isCharResource {
                if let value = rm.get(resourceId) {
                    // Return cached resource value
                    return YayaResponse(ok: true, status: 200, headers: ["Charset": "UTF-8"], value: value, error: nil, loaded_dics: nil)
                } else {
                    // Resource not set, fall through to YAYA
                    // (YAYA might have a default value)
                }
            }
        }

        // Normal SHIORI request to YAYA
        let req = YayaRequest(cmd: "request", ghost_root: nil, dic: nil, encoding: nil, env: nil, method: method, id: id, headers: headers, ref: refs)
        return exchange(req, timeout: timeout)
    }

    /// Query adapter capability using SHIORI GET.
    @discardableResult
    func capability() -> YayaResponse? {
        request(method: "GET", id: "capability")
    }

    /// Unload current dictionaries and terminate helper.
    func unload() {
        let req = YayaRequest(cmd: "unload", ghost_root: nil, dic: nil, encoding: nil, env: nil, method: nil, id: nil, headers: nil, ref: nil)
        // Try graceful unload with a short timeout.
        _ = exchange(req, timeout: 1.0)
        if proc.isRunning {
            proc.terminate()
        }
        // Give the helper a moment to exit, then force kill if needed.
        usleep(300_000) // 0.3s
        if proc.isRunning {
            NSLog("[YayaAdapter] Forcing kill of yaya_core (pid=\(proc.processIdentifier))")
            #if os(macOS)
            let pid = proc.processIdentifier
            kill(pid_t(pid), SIGKILL)
            #endif
        }
        saoriManager.unloadAll()
    }

    /// Bridge helper for yaya_core SAORI request operations.
    func handleSaoriRequest(module: String, request: String, charset: String = "UTF-8") -> String? {
        do {
            return try saoriManager.request(moduleName: module, requestText: request, charset: charset)
        } catch {
            NSLog("[YayaAdapter] SAORI request failed: \(error)")
            return nil
        }
    }

    func handlePluginOperation(_ operation: String, params: [String: Any]) -> [String: Any] {
        switch operation {
        case "saori_load":
            guard let module = params["module"] as? String, !module.isEmpty else {
                return ["ok": false, "error": "module parameter required"]
            }
            do {
                _ = try saoriManager.loadModule(named: module)
                return ["ok": true]
            } catch {
                NSLog("[YayaAdapter] SAORI load failed: \(error)")
                return ["ok": false, "error": "\(error)"]
            }

        case "saori_unload":
            guard let module = params["module"] as? String, !module.isEmpty else {
                return ["ok": false, "error": "module parameter required"]
            }
            saoriManager.unloadModule(named: module)
            return ["ok": true]

        case "saori_request":
            guard let module = params["module"] as? String, !module.isEmpty else {
                return ["ok": false, "error": "module parameter required"]
            }
            let requestText = (params["request"] as? String) ?? ""
            let charset = (params["charset"] as? String) ?? "UTF-8"
            guard let response = handleSaoriRequest(module: module, request: requestText, charset: charset) else {
                return ["ok": false, "error": "saori request failed"]
            }
            // Parse the SAORI response so the helper can use Result/Value0.. directly
            // even when it does not parse raw text itself.
            var parsed: [String: Any] = ["ok": true, "response": response]
            if let saoriResp = try? SaoriProtocol.parseResponse(response) {
                parsed["status"] = saoriResp.statusCode
                if let result = saoriResp.headers["Result"] { parsed["result"] = result }
                var values: [String] = []
                var idx = 0
                while let v = saoriResp.headers["Value\(idx)"] { values.append(v); idx += 1 }
                if !values.isEmpty { parsed["values"] = values }
            }
            return parsed

        case "saori_execute":
            guard let module = params["module"] as? String, !module.isEmpty else {
                return ["ok": false, "error": "module parameter required"]
            }
            let charset = (params["charset"] as? String) ?? "UTF-8"
            let securityLevel = params["securityLevel"] as? String
            let securityOrigin = params["securityOrigin"] as? String
            let arguments = (params["arguments"] as? [String]) ?? []
            do {
                let response = try saoriManager.execute(
                    moduleName: module,
                    arguments: arguments,
                    charset: charset,
                    securityLevel: securityLevel,
                    securityOrigin: securityOrigin
                )
                return ["ok": true, "status": response.statusCode, "response": SaoriProtocol.buildResponse(response)]
            } catch {
                return ["ok": false, "error": "\(error)"]
            }

        default:
            return ["ok": false, "error": "unsupported operation: \(operation)"]
        }
    }
}

/// Build GET request headers following SHIORI/3.0M rules.
func buildGET(id: String, refs: [String]) -> Data {
    var headers = ["ID": id, "Charset": "UTF-8", "Sender": "Ourin"]
    for (i, r) in refs.enumerated() { headers["Reference\(i)"] = r }
    let ordered = headers.keys.sorted().map { "\($0): \(headers[$0]!)\r\n" }.joined()
    return Data((ordered + "\r\n").utf8)
}
