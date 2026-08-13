import Foundation
import Testing

struct YayaSaoriResponseParsingTests {
    @Test
    func requestlibParsesCaseInsensitiveRawResultAndValueHeaders() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executable = repositoryRoot.appendingPathComponent("yaya_core/build/yaya_core")
        try #require(FileManager.default.isExecutableFile(atPath: executable.path))

        let ghostRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Ourin-YayaSaoriRaw-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: ghostRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: ghostRoot) }
        try """
        RawSaori {
            _result = REQUESTLIB('demo', 'ignored')
            _values = valueex()
            _result + ':' + _values[0]
        }
        """.write(to: ghostRoot.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        try process.run()
        defer {
            errors.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }

        func send(_ object: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: object)
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data([0x0A]))
        }

        func readLine(timeout: TimeInterval = 5) -> [String: Any]? {
            let handle = output.fileHandleForReading
            let semaphore = DispatchSemaphore(value: 0)
            var data = Data()
            var reachedEOF = false
            DispatchQueue.global(qos: .userInitiated).async {
                while true {
                    let byte = handle.readData(ofLength: 1)
                    if byte.isEmpty {
                        reachedEOF = true
                        break
                    }
                    if byte == Data([0x0A]) { break }
                    data.append(byte)
                }
                semaphore.signal()
            }
            guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
            guard !reachedEOF else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }

        try send([
            "cmd": "load",
            "ghost_root": ghostRoot.path,
            "encoding": "UTF-8",
            "dic_entries": [["path": "t.dic", "encoding": "UTF-8"]]
        ])
        let loaded = try #require(readLine())
        #expect(loaded["ok"] as? Bool == true)

        try send([
            "cmd": "request",
            "method": "GET",
            "id": "RawSaori",
            "headers": ["Charset": "UTF-8"],
            "ref": []
        ])
        let hostRequest = try #require(readLine())
        #expect(hostRequest["host_op"] as? String == "plugin")
        let hostParams = try #require(hostRequest["params"] as? [String: Any])
        #expect(hostParams["operation"] as? String == "saori_request")
        try send([
            "ok": true,
            "response": "SAORI/1.0 200 OK\r\nresult: raw-result\r\nvalue0: extra\r\n\r\n"
        ])

        let response = try #require(readLine())
        #expect(response["ok"] as? Bool == true)
        #expect(response["value"] as? String == "raw-result:extra")
    }
}
