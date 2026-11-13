import Foundation
import Testing

struct YayaSaoriResponseParsingTests {
    @Test
    func requestlibParsesCaseInsensitiveRawResultAndValueHeaders() throws {
        let core = try YayaCoreLineHarness(name: "Raw", dictionary: """
        RawSaori {
            _result = REQUESTLIB('demo', 'ignored')
            _values = valueex()
            _result + ':' + _values[0]
        }
        """)
        defer { core.close() }

        let loaded = try core.load()
        #expect(loaded["ok"] as? Bool == true)

        let hostRequest = try core.request(id: "RawSaori")
        #expect(hostRequest["host_op"] as? String == "plugin")
        let hostParams = try #require(hostRequest["params"] as? [String: Any])
        #expect(hostParams["operation"] as? String == "saori_request")

        let response = try core.reply(
            "SAORI/1.0 200 OK\r\nresult: raw-result\r\nvalue0: extra\r\n\r\n"
        )
        #expect(response["ok"] as? Bool == true)
        #expect(response["value"] as? String == "raw-result:extra")
    }

    @Test
    func requestlibKeepsLaterValueHeadersWhenAnEarlierIndexIsMissing() throws {
        let core = try YayaCoreLineHarness(name: "Sparse", dictionary: """
        RawSaori {
            _result = REQUESTLIB('demo', 'ignored')
            _values = valueex()
            _result + ':' + _values[0] + ':' + _values[1]
        }
        """)
        defer { core.close() }

        let loaded = try core.load()
        #expect(loaded["ok"] as? Bool == true)

        let hostRequest = try core.request(id: "RawSaori")
        #expect(hostRequest["host_op"] as? String == "plugin")

        let response = try core.reply(
            "SAORI/1.0 200 OK\r\nResult: sparse\r\nValue0: first\r\nValue2: third\r\n\r\n"
        )
        #expect(response["ok"] as? Bool == true)
        #expect(response["value"] as? String == "sparse:first:third")
    }
}

/// yaya_core と JSON line IPC で直接やり取りするテスト用ハーネス。
/// 応答が得られなかった場合に、どの段階で何を受け取ったかを失敗メッセージに残す。
final class YayaCoreLineHarness {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let ghostRoot: URL
    private let stderrLock = NSLock()
    private var stderrData = Data()

    init(name: String, dictionary: String) throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = repositoryRoot.appendingPathComponent("yaya_core/build/yaya_core")
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))

        ghostRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ourin-YayaSaori\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ghostRoot, withIntermediateDirectories: true)
        try dictionary.write(to: ghostRoot.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        process.executableURL = executable
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            self.stderrLock.lock()
            self.stderrData.append(chunk)
            self.stderrLock.unlock()
        }
        try process.run()
    }

    func close() {
        errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        try? FileManager.default.removeItem(at: ghostRoot)
    }

    func load() throws -> [String: Any] {
        try exchange("load", [
            "cmd": "load",
            "ghost_root": ghostRoot.path,
            "encoding": "UTF-8",
            "dic_entries": [["path": "t.dic", "encoding": "UTF-8"]]
        ])
    }

    func request(id: String, references: [String] = []) throws -> [String: Any] {
        try exchange("request", [
            "cmd": "request",
            "method": "GET",
            "id": id,
            "headers": ["Charset": "UTF-8"],
            "ref": references
        ])
    }

    func reply(_ saoriResponse: String) throws -> [String: Any] {
        try exchange("host reply", ["ok": true, "response": saoriResponse])
    }

    private func exchange(_ step: String, _ object: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: object)
        input.fileHandleForWriting.write(data)
        input.fileHandleForWriting.write(Data([0x0A]))

        let line = readLine(timeout: 5)
        let parsed = line.state == "line"
            ? line.data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            : nil
        return try #require(parsed, "\(step): \(line.state) stdout=\(Self.text(line.data)) stderr=\(stderrText()) running=\(process.isRunning)")
    }

    private func readLine(timeout: TimeInterval) -> (data: Data?, state: String) {
        let handle = output.fileHandleForReading
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var data = Data()
        var reachedEOF = false
        // 全体実行では他テストのブロッキング待ちで GCD のスレッドプールが埋まり、
        // global queue に積んだ読み取りが上限内に始まらないことがある。専用スレッドで読む。
        Thread {
            while true {
                let byte = handle.readData(ofLength: 1)
                lock.lock()
                defer { lock.unlock() }
                if byte.isEmpty {
                    reachedEOF = true
                    break
                }
                if byte == Data([0x0A]) { break }
                data.append(byte)
            }
            semaphore.signal()
        }.start()
        let finished = semaphore.wait(timeout: .now() + timeout) == .success
        lock.lock()
        defer { lock.unlock() }
        if !finished { return (data, "timeout") }
        if reachedEOF { return (data, "eof") }
        return (data, "line")
    }

    private func stderrText() -> String {
        stderrLock.lock()
        defer { stderrLock.unlock() }
        return Self.text(stderrData)
    }

    private static func text(_ data: Data?) -> String {
        guard let data else { return "nil" }
        let value = String(decoding: data, as: UTF8.self)
        return value.count > 2000 ? String(value.suffix(2000)) : value
    }
}
