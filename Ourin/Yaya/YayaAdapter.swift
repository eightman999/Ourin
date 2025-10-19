import Foundation

/// Codable request sent to yaya_core helper.
struct YayaRequest: Codable {
    let cmd: String
    let ghost_root: String?
    let dic: [String]?
    let encoding: String?
    let env: [String:String]?
    let method: String?
    let id: String?
    let headers: [String:String]?
    let ref: [String]?
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
        guard let line = try readLine() else {
            NSLog("[YayaAdapter] exchange() readLine() returned nil")
            return nil
        }
        Log.debug("[YayaAdapter] exchange() received \(line.count) bytes, decoding...")

        // Debug: Show raw JSON string before decoding
        if let jsonStr = String(data: line, encoding: .utf8) {
            let preview = String(jsonStr.prefix(300))
            Log.debug("[YayaAdapter] Raw JSON preview: \(preview)")
            // Count backslashes in JSON
            let backslashCount = jsonStr.filter { $0 == "\\" }.count
            Log.debug("[YayaAdapter] Backslash count in JSON: \(backslashCount)")
        }

        let response = try JSONDecoder().decode(YayaResponse.self, from: line)
        Log.debug("[YayaAdapter] exchange() decoded response: ok=\(response.ok)")

        // Debug: Show decoded value with backslash count
        if let value = response.value {
            let preview = String(value.prefix(200))
            Log.debug("[YayaAdapter] Decoded value preview: \(preview)")
            let backslashCount = value.filter { $0 == "\\" }.count
            Log.debug("[YayaAdapter] Backslash count in decoded value: \(backslashCount)")
        }
        return response
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
    func load(ghostRoot: URL, dics: [String], encoding: String = "utf-8") -> Bool {
        Log.debug("[YayaAdapter] load() called with ghostRoot: \(ghostRoot.path), dics: \(dics.count) files")

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
                        let msgData = try JSONSerialization.data(withJSONObject: msgDict)
                        inPipe.fileHandleForWriting.write(msgData)
                        inPipe.fileHandleForWriting.write(Data([0x0a]))

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

        // Then load dictionary files
        let req = YayaRequest(cmd: "load", ghost_root: ghostRoot.path, dic: dics, encoding: encoding, env: ["LANG":"ja_JP.UTF-8"], method: nil, id: nil, headers: ["Charset":"UTF-8"], ref: nil)

        do {
            let response = try exchange(req)
            Log.debug("[YayaAdapter] load() response: ok=\(response?.ok ?? false), status=\(response?.status ?? -1), error=\(response?.error ?? "nil")")
            guard response?.ok == true else {
                NSLog("[YayaAdapter] load() failed: response.ok is false or nil")
                return false
            }

            // Log loaded dictionary files if available
            if let loadedDics = response?.loaded_dics, !loadedDics.isEmpty {
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
        } catch {
            NSLog("[YayaAdapter] load() exchange threw error: \(error)")
            return false
        }

        _ = capability()
        NSLog("[YayaAdapter] load() succeeded")
        return true
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
    }
}

/// Build GET request headers following SHIORI/3.0M rules.
func buildGET(id: String, refs: [String]) -> Data {
    var headers = ["ID": id, "Charset": "UTF-8", "Sender": "Ourin"]
    for (i, r) in refs.enumerated() { headers["Reference\(i)"] = r }
    let ordered = headers.keys.sorted().map { "\($0): \(headers[$0]!)\r\n" }.joined()
    return Data((ordered + "\r\n").utf8)
}
