import Foundation
import Testing
@testable import Ourin

struct SatoriStderrLifecycleTests {
    @Test func eofCancelsReadabilityMonitoring() async throws {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        defer { reader.readabilityHandler = nil; try? reader.close() }
        SatoriAdapter.monitorStandardError(reader)
        try #require(reader.readabilityHandler != nil)
        try pipe.fileHandleForWriting.close()
        #expect(await waitUntil { reader.readabilityHandler == nil })
    }

    @Test func malformedStderrStillDrainsAndCancelsAtEof() async throws {
        let pipe = Pipe()
        let reader = pipe.fileHandleForReading
        defer { reader.readabilityHandler = nil; try? reader.close() }
        SatoriAdapter.monitorStandardError(reader)
        try pipe.fileHandleForWriting.write(contentsOf: Data([0xff, 0xfe, 0x80]))
        try pipe.fileHandleForWriting.write(contentsOf: Data("diagnostic\n".utf8))
        try pipe.fileHandleForWriting.close()
        #expect(await waitUntil { reader.readabilityHandler == nil })
    }

    @Test func repeatedRealHelperExitsLeaveNoMonitoredHandles() async throws {
        var readers: [FileHandle] = []
        defer {
            for reader in readers { reader.readabilityHandler = nil; try? reader.close() }
        }
        for _ in 0..<12 {
            let errors = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
            process.standardOutput = FileHandle.nullDevice
            process.standardError = errors
            let reader = errors.fileHandleForReading
            readers.append(reader)
            SatoriAdapter.monitorStandardError(reader)
            try process.run()
            // The parent must release its own write end to observe child EOF.
            try errors.fileHandleForWriting.close()
            #expect(await waitUntil { !process.isRunning && reader.readabilityHandler == nil })
        }
        #expect(readers.allSatisfy { $0.readabilityHandler == nil })
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while ProcessInfo.processInfo.systemUptime < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return predicate()
    }
}
