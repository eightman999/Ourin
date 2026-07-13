import Foundation

/// satori_core helperへ送るJSON Lines要求。
/// YAYAと同じSHIORI境界を採用し、ベースウェア側の配送経路を共用する。
private struct SatoriRequest: Codable {
    let cmd: String
    let ghost_root: String?
    let dic: [String]?
    let method: String?
    let id: String?
    let headers: [String: String]?
    let ref: [String]?
    let protocol_version: String?
    let escape_unknown: Bool?

    init(cmd: String, ghostRoot: String? = nil, dic: [String]? = nil,
         method: String? = nil, id: String? = nil,
         headers: [String: String]? = nil, refs: [String]? = nil,
         protocolVersion: String? = nil, escapeUnknown: Bool? = nil) {
        self.cmd = cmd
        self.ghost_root = ghostRoot
        self.dic = dic
        self.method = method
        self.id = id
        self.headers = headers
        self.ref = refs
        self.protocol_version = protocolVersion
        self.escape_unknown = escapeUnknown
    }
}

/// 里々ランタイムとのJSON Lines IPCアダプタ。
///
/// 辞書の解釈は `satori_core` に閉じ込め、Swift側はSHIORI要求と応答だけを扱う。
/// これにより、将来の里々エンジン更新でGhostManagerやSSTP経路を変更せずに済む。
final class SatoriAdapter: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .satori
    private(set) var isLoaded = false
    var resourceManager: ResourceManager?

    private var process = Process()
    private var inputPipe = Pipe()
    private var outputPipe = Pipe()
    private var errorPipe = Pipe()
    private let ioQueue = DispatchQueue(label: "satori.adapter.io")
    private let recoveryLock = NSLock()
    private let executableURL: URL
    private var lastLoadContext: ShioriRuntimeLoadContext?
    private var communication = ShioriCommunicationOptions()

    convenience init?() {
        guard let executable = Bundle.main.url(forAuxiliaryExecutable: "satori_core") else {
            NSLog("[SatoriAdapter] Could not locate satori_core executable in bundle")
            return nil
        }
        self.init(executableURL: executable)
    }

    init?(executableURL: URL) {
        self.executableURL = executableURL
        guard launchHelper() else { return nil }
    }

    @discardableResult
    private func launchHelper() -> Bool {
        process = Process()
        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()
        process.executableURL = executableURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            if Log.verbose {
                NSLog("[satori_core stderr] %@", text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        do {
            try process.run()
            return true
        } catch {
            NSLog("[SatoriAdapter] Failed to launch satori_core: %@", error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func load(ghostRoot: URL, dicEntries: [String], communication: ShioriCommunicationOptions = .init()) -> Bool {
        isLoaded = false
        guard process.isRunning else { return false }
        let request = SatoriRequest(
            cmd: "load",
            ghostRoot: ghostRoot.path,
            dic: dicEntries,
            protocolVersion: communication.version ?? "SHIORI/3.0",
            escapeUnknown: communication.escapeUnknown
        )
        isLoaded = exchange(request, timeout: 10)?.ok == true
        if isLoaded {
            self.communication = communication
        }
        return isLoaded
    }

    @discardableResult
    func load(context: ShioriRuntimeLoadContext) -> Bool {
        let loaded = load(
            ghostRoot: context.ghostRoot,
            dicEntries: context.dictionaryEntries.map { $0.path },
            communication: context.communication
        )
        if loaded {
            lastLoadContext = context
        }
        return loaded
    }

    func request(method: String, id: String, headers: [String: String], refs: [String], timeout: TimeInterval) -> ShioriRuntimeResponse? {
        guard recoverIfNeeded() else { return nil }
        let request = SatoriRequest(cmd: "request", method: method, id: id, headers: headers, refs: refs)
        guard let response = exchange(request, timeout: timeout) else { return nil }
        guard communication.escapeUnknown else { return response }
        return ShioriRuntimeResponse(
            ok: response.ok,
            status: response.status,
            headers: response.headers?.mapValues(EncodingAdapter.restoreEscapedUnicode),
            value: response.value.map(EncodingAdapter.restoreEscapedUnicode),
            error: response.error.map(EncodingAdapter.restoreEscapedUnicode),
            loaded_dics: response.loaded_dics
        )
    }

    func unload() {
        lastLoadContext = nil
        isLoaded = false
        if process.isRunning {
            _ = exchange(SatoriRequest(cmd: "unload"), timeout: 3)
        }
        if process.isRunning {
            process.terminate()
            for _ in 0..<30 where process.isRunning {
                usleep(10_000)
            }
            if process.isRunning {
                #if os(macOS)
                kill(pid_t(process.processIdentifier), SIGKILL)
                #endif
            }
        }
        inputPipe.fileHandleForWriting.closeFile()
        outputPipe.fileHandleForReading.closeFile()
        errorPipe.fileHandleForReading.closeFile()
    }

    deinit {
        unload()
        errorPipe.fileHandleForReading.readabilityHandler = nil
    }

    private func send(_ request: SatoriRequest) throws {
        let data = try JSONEncoder().encode(request)
        inputPipe.fileHandleForWriting.write(data)
        inputPipe.fileHandleForWriting.write(Data([0x0a]))
    }

    private func readLine() throws -> Data? {
        var data = Data()
        while true {
            let byte = outputPipe.fileHandleForReading.readData(ofLength: 1)
            if byte.isEmpty { return data.isEmpty ? nil : data }
            if byte == Data([0x0a]) { return data }
            data.append(byte)
        }
    }

    private func exchange(_ request: SatoriRequest, timeout: TimeInterval) -> ShioriRuntimeResponse? {
        let group = DispatchGroup()
        var result: ShioriRuntimeResponse?
        group.enter()
        ioQueue.async {
            defer { group.leave() }
            do {
                try self.send(request)
                guard let line = try self.readLine() else { return }
                result = try JSONDecoder().decode(ShioriRuntimeResponse.self, from: line)
            } catch {
                NSLog("[SatoriAdapter] IPC failed: %@", error.localizedDescription)
            }
        }
        guard group.wait(timeout: .now() + timeout) == .success else {
            NSLog("[SatoriAdapter] IPC timed out for %@ %@", request.method ?? request.cmd, request.id ?? "")
            forceTerminate()
            return nil
        }
        if result == nil {
            forceTerminate()
        }
        return result
    }

    private func forceTerminate() {
        isLoaded = false
        guard process.isRunning else { return }
        process.terminate()
        usleep(200_000)
        if process.isRunning {
            #if os(macOS)
            kill(pid_t(process.processIdentifier), SIGKILL)
            #endif
        }
    }

    private func waitForIOQueueToDrain(timeout: TimeInterval = 2.0) -> Bool {
        let group = DispatchGroup()
        group.enter()
        ioQueue.async { group.leave() }
        return group.wait(timeout: .now() + timeout) == .success
    }

    private func recoverIfNeeded() -> Bool {
        if isLoaded, process.isRunning { return true }
        recoveryLock.lock()
        defer { recoveryLock.unlock() }
        if isLoaded, process.isRunning { return true }
        guard let context = lastLoadContext else { return false }
        guard waitForIOQueueToDrain() else {
            NSLog("[SatoriAdapter] Timed-out I/O generation did not drain; recovery aborted")
            return false
        }
        guard launchHelper() else { return false }
        let restored = load(
            ghostRoot: context.ghostRoot,
            dicEntries: context.dictionaryEntries.map { $0.path },
            communication: context.communication
        )
        if !restored {
            forceTerminate()
        }
        return restored
    }
}
