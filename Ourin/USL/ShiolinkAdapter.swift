import Foundation
import Darwin

/// SHIOLINK.INI's commandline/charmode plus a shell-free Ourin executable/arguments form.
struct ShiolinkConfiguration {
    let executable: URL
    let arguments: [String]
    let directory: URL
    let charset: String

    enum Failure: Error { case missing, invalid, unsupportedCharset, executableMissing }

    static func load(context: ShioriRuntimeLoadContext) throws -> Self {
        let module = context.moduleName.replacingOccurrences(of: "\\", with: "/")
        guard !module.hasPrefix("/"), !module.split(separator: "/").contains("..") else { throw Failure.invalid }
        let directory = context.ghostRoot.appendingPathComponent(module).deletingLastPathComponent()
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var config: URL?
        for name in ["SHIOLINK.ourin.ini", "SHIOLINK.INI"] {
            let matches = entries.filter { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
            guard matches.count <= 1 else { throw Failure.invalid }
            if let match = matches.first { config = match; break }
        }
        guard let config else { throw Failure.missing }
        let handle = try FileHandle(forReadingFrom: config)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 65537) ?? Data()
        guard data.count <= 65536, let text = EncodingAdapter.decodeTextDefinition(data) else { throw Failure.invalid }
        var values: [String: String] = [:]
        var inSection = true
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                inSection = line.lowercased() == "[shiolink]"
                continue
            }
            guard inSection, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            guard values[key] == nil else { throw Failure.invalid }
            values[key] = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        }
        let charset = values["charmode"] ?? "UTF-8"
        // Framing uses ASCII CRLF. UTF-16/32 and unknown encodings cannot use this transport.
        guard let encoding = EncodingAdapter.knownEncoding(for: charset),
              encoding == .utf8 || encoding == .shiftJIS else { throw Failure.unsupportedCharset }
        let executableName: String
        let arguments: [String]
        if let name = values["executable"] {
            guard values["commandline"] == nil, !name.isEmpty,
                  let args = (values["arguments"] ?? "[]").data(using: .utf8),
                  let parsed = try? JSONDecoder().decode([String].self, from: args) else { throw Failure.invalid }
            executableName = name
            arguments = parsed
        } else {
            guard values["arguments"] == nil, let command = values["commandline"] else { throw Failure.invalid }
            let tokens = try tokenize(command)
            guard let first = tokens.first, !first.isEmpty else { throw Failure.invalid }
            executableName = first
            arguments = Array(tokens.dropFirst())
        }
        guard !executableName.contains("\\"), !executableName.contains(":"),
              !["exe", "com", "bat", "cmd", "ps1"].contains(URL(fileURLWithPath: executableName).pathExtension.lowercased()),
              !([executableName] + arguments).contains(where: { $0.contains("\0") || $0.contains("\r") || $0.contains("\n") }) else { throw Failure.invalid }
        let candidates: [URL]
        if executableName.hasPrefix("/") { candidates = [URL(fileURLWithPath: executableName)] }
        else if executableName.contains("/") { candidates = [directory.appendingPathComponent(executableName)] }
        else {
            candidates = [directory.appendingPathComponent(executableName)] +
                ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].map { URL(fileURLWithPath: $0).appendingPathComponent(executableName) }
        }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw Failure.executableMissing }
        return Self(executable: executable, arguments: arguments, directory: directory, charset: EncodingAdapter.charsetName(for: encoding))
    }

    /// Quotes group arguments; shell substitutions/operators are never evaluated.
    static func tokenize(_ command: String) throws -> [String] {
        var result: [String] = [], token = ""
        var quote: Character?, started = false
        for character in command {
            if let active = quote {
                if character == active { quote = nil } else { token.append(character) }
                started = true
            } else if character == "\"" || character == "'" {
                quote = character; started = true
            } else if character.isWhitespace {
                if started { result.append(token); token = ""; started = false }
            } else {
                guard !"|;&<>`$".contains(character) else { throw Failure.invalid }
                token.append(character); started = true
            }
        }
        guard quote == nil else { throw Failure.invalid }
        if started { result.append(token) }
        return result
    }
}

/// SHIOLINK *L / *S / *U transport, separate from SHIORIPROXY and JSONL helpers.
/// All pipe I/O is nonblocking and bounded by a single monotonic transaction deadline.
final class ShiolinkAdapter: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .shiolink
    var resourceManager: ResourceManager?
    private let lock = NSLock()
    private var loaded = false
    var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return loaded }
    private var process: Process?
    private var spawnedProcessIdentifier: pid_t?
    /// Retained after cleanup for diagnostics; reset before each load attempt.
    /// Captured after Process.run(), so it does not depend on helper initialization.
    var lastProcessIdentifier: pid_t? {
        lock.lock(); defer { lock.unlock() }
        return spawnedProcessIdentifier
    }
    private var input: Pipe?, output: Pipe?
    private var pending = Data()
    private var configuration: ShiolinkConfiguration?
    private var communication = ShioriCommunicationOptions()
    private let maximumBytes = 1_048_576
    private let loadTimeout: TimeInterval
    private(set) var lastError: String?

    init(loadTimeout: TimeInterval = 5) { self.loadTimeout = loadTimeout }

    @discardableResult
    func load(context: ShioriRuntimeLoadContext) -> Bool {
        lock.lock(); defer { lock.unlock() }
        stop(graceful: true)
        lastError = nil
        spawnedProcessIdentifier = nil
        do {
            let config = try ShiolinkConfiguration.load(context: context)
            guard !config.directory.path.contains("\n"), !config.directory.path.contains("\r") else { throw ShiolinkConfiguration.Failure.invalid }
            let child = Process(), stdin = Pipe(), stdout = Pipe()
            child.executableURL = config.executable
            child.arguments = config.arguments
            child.currentDirectoryURL = config.directory
            child.standardInput = stdin
            child.standardOutput = stdout
            // Never accumulate stderr or let a verbose helper fill an undrained pipe.
            child.standardError = FileHandle.nullDevice
            try child.run()
            spawnedProcessIdentifier = child.processIdentifier
            process = child; input = stdin; output = stdout; configuration = config
            stdin.fileHandleForReading.closeFile()
            stdout.fileHandleForWriting.closeFile()
            for fd in [stdin.fileHandleForWriting.fileDescriptor, stdout.fileHandleForReading.fileDescriptor] {
                guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else { throw ShiolinkConfiguration.Failure.invalid }
            }
            guard fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { throw ShiolinkConfiguration.Failure.invalid }
            communication = context.communication
            let deadline = now + bounded(loadTimeout)
            guard write("*L:\(config.directory.path)/\r\n", deadline: deadline),
                  exchange(method: "GET", id: "version", headers: [:], refs: [], deadline: deadline) != nil else {
                fail("SHIOLINK initialization failed")
                return false
            }
            loaded = true
            return true
        } catch {
            fail("SHIOLINK configuration or launch failed: \(error)")
            return false
        }
    }

    func request(method: String, id: String, headers: [String: String], refs: [String], timeout: TimeInterval) -> ShioriRuntimeResponse? {
        lock.lock(); defer { lock.unlock() }
        guard loaded else { return nil }
        guard let result = exchange(method: method, id: id, headers: headers, refs: refs, deadline: now + bounded(timeout)) else {
            fail("SHIOLINK response timed out, exceeded the limit, or was malformed")
            return nil
        }
        return result
    }

    private func exchange(method: String, id: String, headers: [String: String], refs: [String], deadline: TimeInterval) -> ShioriRuntimeResponse? {
        guard let configuration, process?.isRunning == true else { return nil }
        let serial = UUID().uuidString
        guard write("*S:\(serial)\r\n", deadline: deadline),
              readLine(deadline: deadline) == Data("*S:\(serial)".utf8) else { return nil }
        let charset = communication.forceEncoding ?? communication.encoding ?? configuration.charset
        guard let encoding = EncodingAdapter.knownEncoding(for: charset), encoding == .utf8 || encoding == .shiftJIS else { return nil }
        let wire = ShioriWireCodec.makeRequest(method: method, id: id, headers: headers, refs: refs,
                                              protocolVersion: communication.version ?? "SHIORI/3.0", charset: charset)
        guard write(wire, charset: charset, deadline: deadline) else { return nil }
        var response = Data()
        while let line = readLine(deadline: deadline) {
            guard response.count + line.count + 2 <= maximumBytes else { return nil }
            response.append(line); response.append(contentsOf: [13, 10])
            if line.isEmpty {
                let responseCharset = communication.forceEncoding ?? EncodingAdapter.detectCharset(in: response, default: charset)
                guard let text = EncodingAdapter.decode(response, charset: responseCharset) else { return nil }
                return ShioriWireCodec.parseResponse(communication.escapeUnknown ? EncodingAdapter.restoreEscapedUnicode(in: text) : text)
            }
        }
        return nil
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private func bounded(_ timeout: TimeInterval) -> TimeInterval {
        timeout.isFinite ? min(max(timeout, 0.001), 60) : 5
    }

    private func ready(_ fd: Int32, events: Int16, deadline: TimeInterval) -> Bool {
        while now < deadline {
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let remaining = min(100, max(1, Int((deadline - now) * 1000)))
            let result = poll(&descriptor, 1, Int32(remaining))
            if result > 0 { return (descriptor.revents & events) != 0 }
            if result < 0 && errno != EINTR { return false }
            if process?.isRunning != true { return false }
        }
        return false
    }

    private func write(_ text: String, charset: String? = nil, deadline: TimeInterval) -> Bool {
        guard let input, let encoding = EncodingAdapter.knownEncoding(for: charset ?? configuration?.charset ?? "UTF-8"),
              let data = text.data(using: encoding), data.count <= maximumBytes else { return false }
        let fd = input.fileHandleForWriting.fileDescriptor
        return data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return true }
            var offset = 0
            while offset < buffer.count {
                guard ready(fd, events: Int16(POLLOUT), deadline: deadline) else { return false }
                let count = Darwin.write(fd, base.advanced(by: offset), buffer.count - offset)
                if count > 0 { offset += count }
                else if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
                else { return false }
            }
            return true
        }
    }

    private func readLine(deadline: TimeInterval) -> Data? {
        guard let output else { return nil }
        let fd = output.fileHandleForReading.fileDescriptor
        while now < deadline {
            if let newline = pending.firstIndex(of: 10) {
                var line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                if line.last == 13 { line.removeLast() }
                return line
            }
            guard pending.count < maximumBytes, ready(fd, events: Int16(POLLIN), deadline: deadline) else { return nil }
            var buffer = [UInt8](repeating: 0, count: min(8192, maximumBytes - pending.count))
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 { pending.append(contentsOf: buffer.prefix(count)) }
            else if count < 0 && (errno == EAGAIN || errno == EINTR) { continue }
            else { return nil }
        }
        return nil
    }

    private func fail(_ message: String) {
        lastError = message
        NSLog("[ShiolinkAdapter] %@", message)
        stop(graceful: false)
    }

    func unload() {
        lock.lock(); defer { lock.unlock() }
        stop(graceful: true)
    }

    private func stop(graceful: Bool) {
        loaded = false
        if let child = process, child.isRunning {
            if graceful { _ = write("*U:\r\n", deadline: now + 0.2) }
            let graceEnd = now + (graceful ? 0.3 : 0)
            while child.isRunning && now < graceEnd { usleep(5_000) }
            if child.isRunning {
                child.terminate()
                let terminateEnd = now + 0.2
                while child.isRunning && now < terminateEnd { usleep(5_000) }
            }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        input?.fileHandleForWriting.closeFile()
        output?.fileHandleForReading.closeFile()
        process = nil; input = nil; output = nil; configuration = nil
        pending.removeAll(keepingCapacity: false)
    }

    deinit { stop(graceful: true) }
}
