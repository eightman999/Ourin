import Foundation
import Darwin

/// Rishu/Proxy 1.1 connects back to an ephemeral IPv4 loopback listener using --port.
/// This uses the upstream TCP transport without modifying the ghost's Perl files.
final class RishuProxyAdapter: GhostShioriRuntime {
    let kind: ShioriRuntimeKind = .rishu
    var resourceManager: ResourceManager?
    private let lock = NSLock()
    private var loaded = false
    var isLoaded: Bool { lock.lock(); defer { lock.unlock() }; return loaded }
    private var child: Process?
    private var spawnedPID: pid_t?
    var lastProcessIdentifier: pid_t? { lock.lock(); defer { lock.unlock() }; return spawnedPID }
    private(set) var lastError: String?
    private var socketFD: Int32 = -1
    private var listenerFD: Int32 = -1
    private var pending = Data()
    private let maximumFrame = 1_048_576
    private let loadTimeout: TimeInterval
    private let perlExecutable: URL
    private let validPerlPath: Bool
    private var communication = ShioriCommunicationOptions()

    init(perlExecutable: URL? = nil, loadTimeout: TimeInterval = 5) {
        let configured = ProcessInfo.processInfo.environment["OURIN_RISHU_PERL_EXECUTABLE"]
        self.validPerlPath = perlExecutable != nil || configured == nil || configured!.hasPrefix("/")
        self.perlExecutable = perlExecutable ?? configured.map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: "/usr/bin/perl")
        self.loadTimeout = loadTimeout
    }

    static func remoteScript(in directory: URL) -> URL? {
        let matches = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.caseInsensitiveCompare("rishu_remote.pl") == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }

    func load(context: ShioriRuntimeLoadContext) -> Bool {
        lock.lock(); defer { lock.unlock() }
        stop(graceful: true)
        spawnedPID = nil; lastError = nil
        let module = context.moduleName.replacingOccurrences(of: "\\", with: "/")
        guard !module.hasPrefix("/"), !module.split(separator: "/").contains("..") else { return fail("Invalid module path") }
        let directory = context.ghostRoot.appendingPathComponent(module).deletingLastPathComponent()
        guard validPerlPath, let script = Self.remoteScript(in: directory),
              FileManager.default.isExecutableFile(atPath: perlExecutable.path),
              !directory.path.contains("\r"), !directory.path.contains("\n"),
              let loadData = "PROXY LOAD RISHU/1.1\r\nDirectory: \(directory.path)/\r\n\r\n".data(using: .shiftJIS) else {
            return fail("rishu_remote.pl, executable Perl, and a Shift_JIS-compatible directory are required")
        }
        communication = context.communication
        let deadline = now + bounded(loadTimeout)
        guard let port = listenOnLoopback() else { return fail("Cannot create Rishu loopback listener") }
        let process = Process()
        process.executableURL = perlExecutable
        process.arguments = [script.path, "--port", String(port)]
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return fail("Cannot launch Perl: \(error.localizedDescription)") }
        child = process; spawnedPID = process.processIdentifier
        guard ready(listenerFD, events: Int16(POLLIN), deadline: deadline) else { return fail("Rishu did not connect before the deadline") }
        socketFD = accept(listenerFD, nil, nil)
        close(listenerFD); listenerFD = -1
        guard socketFD >= 0, configureSocket(socketFD),
              write(loadData, deadline: deadline), let response = readFrame(deadline: deadline),
              successfulWrapper(response) else { return fail("Rishu LOAD failed or timed out") }
        loaded = true
        return true
    }

    func request(method: String, id: String, headers: [String: String], refs: [String], timeout: TimeInterval) -> ShioriRuntimeResponse? {
        lock.lock(); defer { lock.unlock() }
        guard loaded else { return nil }
        let charset = communication.forceEncoding ?? communication.encoding ?? "Shift_JIS"
        guard let encoding = EncodingAdapter.knownEncoding(for: charset), encoding == .shiftJIS || encoding == .utf8 else {
            _ = fail("Unsupported Rishu SHIORI charset"); return nil
        }
        let wire = ShioriWireCodec.makeRequest(method: method, id: id, headers: headers, refs: refs,
                                              protocolVersion: communication.version ?? "SHIORI/3.0", charset: charset)
        let packet = "PROXY REQUEST RISHU/1.1\r\nCommand: " + wire
        guard let data = communication.escapeUnknown ? EncodingAdapter.encode(packet, charset: charset, escapeUnknown: true) : packet.data(using: encoding) else {
            _ = fail("Rishu request cannot be encoded"); return nil
        }
        let deadline = now + bounded(timeout)
        guard write(data, deadline: deadline), let wrapped = readFrame(deadline: deadline), successfulWrapper(wrapped),
              let original = Self.originalResponse(in: wrapped),
              let text = EncodingAdapter.decode(original, charset: communication.forceEncoding ?? EncodingAdapter.detectCharset(in: original, default: charset)),
              let response = ShioriWireCodec.parseResponse(communication.escapeUnknown ? EncodingAdapter.restoreEscapedUnicode(in: text) : text) else {
            _ = fail("Rishu response timed out, exceeded the limit, or was malformed"); return nil
        }
        return response
    }

    /// Original-Response begins the embedded SHIORI status line, followed by its headers.
    static func originalResponse(in frame: Data) -> Data? {
        let marker = Data("Original-Response: ".utf8)
        var offset = frame.startIndex
        while offset < frame.endIndex, let lineEnd = frame[offset...].range(of: Data([13, 10])) {
            let line = frame[offset..<lineEnd.lowerBound]
            if line.count >= marker.count,
               String(data: line.prefix(marker.count), encoding: .ascii)?.lowercased() == "original-response: " {
                return Data(frame[(offset + marker.count)...])
            }
            if line.isEmpty { return nil }
            offset = lineEnd.upperBound
        }
        return nil
    }

    private func successfulWrapper(_ data: Data) -> Bool {
        guard let end = data.range(of: Data([13, 10])),
              let first = String(data: data[..<end.lowerBound], encoding: .ascii) else { return false }
        let parts = first.split(separator: " ")
        guard parts.count >= 2, parts[0] == "RISHU/1.1", let status = Int(parts[1]) else { return false }
        return (200..<300).contains(status)
    }

    private func listenOnLoopback() -> UInt16? {
        listenerFD = socket(AF_INET, SOCK_STREAM, 0)
        guard listenerFD >= 0, configureSocket(listenerFD) else { return nil }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listenerFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0, listen(listenerFD, 1) == 0 else { return nil }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let found = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listenerFD, $0, &length) }
        }
        return found == 0 ? UInt16(bigEndian: address.sin_port) : nil
    }

    private func configureSocket(_ fd: Int32) -> Bool {
        var yes: Int32 = 1
        return fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 &&
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private func bounded(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite ? min(max(seconds, 0.001), 60) : 5
    }
    private func ready(_ fd: Int32, events: Int16, deadline: TimeInterval) -> Bool {
        while now < deadline {
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(100, max(1, (deadline - now) * 1000))))
            if result > 0 { return descriptor.revents & events != 0 }
            if result < 0 && errno != EINTR { return false }
            if child != nil && child?.isRunning != true { return false }
        }
        return false
    }

    private func write(_ data: Data, deadline: TimeInterval) -> Bool {
        guard socketFD >= 0, data.count <= maximumFrame else { return false }
        return data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return true }
            var offset = 0
            while offset < bytes.count {
                guard ready(socketFD, events: Int16(POLLOUT), deadline: deadline) else { return false }
                let count = Darwin.write(socketFD, base.advanced(by: offset), bytes.count - offset)
                if count > 0 { offset += count }
                else if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                else { return false }
            }
            return true
        }
    }

    private func readFrame(deadline: TimeInterval) -> Data? {
        while now < deadline {
            if let end = pending.range(of: Data([13, 10, 13, 10])) {
                let headerSize = pending.distance(from: pending.startIndex, to: end.upperBound)
                guard let header = String(data: pending.prefix(headerSize), encoding: .isoLatin1) else { return nil }
                var contentLength: Int?
                for line in header.components(separatedBy: "\r\n") {
                    let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 && parts[0].lowercased() == "content-length" {
                        let value = parts[1].trimmingCharacters(in: .whitespaces)
                        guard contentLength == nil, !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
                              let length = Int(value), length <= maximumFrame - headerSize else { return nil }
                        contentLength = length
                    }
                }
                let total = headerSize + (contentLength ?? 0)
                if pending.count >= total {
                    let result = Data(pending.prefix(total))
                    pending = Data(pending.dropFirst(total))
                    return result
                }
            }
            guard pending.count < maximumFrame, ready(socketFD, events: Int16(POLLIN), deadline: deadline) else { return nil }
            var bytes = [UInt8](repeating: 0, count: min(8192, maximumFrame - pending.count))
            let count = Darwin.read(socketFD, &bytes, bytes.count)
            if count > 0 { pending.append(contentsOf: bytes.prefix(count)) }
            else if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            else { return nil }
        }
        return nil
    }

    @discardableResult
    private func fail(_ message: String) -> Bool {
        lastError = message
        NSLog("[RishuProxyAdapter] %@", message)
        stop(graceful: false)
        return false
    }
    func unload() { lock.lock(); defer { lock.unlock() }; stop(graceful: true) }
    private func stop(graceful: Bool) {
        loaded = false
        if graceful && socketFD >= 0 && child?.isRunning == true {
            let deadline = now + 0.5
            if write(Data("PROXY UNLOAD RISHU/1.1\r\n\r\n".utf8), deadline: deadline) { _ = readFrame(deadline: deadline) }
            _ = write(Data("PROXY EXIT RISHU/1.1\r\n\r\n".utf8), deadline: deadline)
        }
        if socketFD >= 0 { close(socketFD); socketFD = -1 }
        if listenerFD >= 0 { close(listenerFD); listenerFD = -1 }
        if let child, child.isRunning {
            let deadline = now + (graceful ? 0.3 : 0)
            while child.isRunning && now < deadline { usleep(5_000) }
            if child.isRunning {
                child.terminate()
                let terminated = now + 0.2
                while child.isRunning && now < terminated { usleep(5_000) }
            }
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
        child = nil; pending.removeAll(keepingCapacity: false)
    }
    deinit { stop(graceful: true) }
}
