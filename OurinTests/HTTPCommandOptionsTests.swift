import Foundation
import Testing

@testable import Ourin

struct HTTPCommandOptionsTests {
    @Test
    func parsesSyncCustomEventsAndRequestFlags() {
        let root = URL(fileURLWithPath: "/tmp/ourin-http-options-root", isDirectory: true)
        let options = GhostManager.HTTPCommandOptions(
            arguments: [
                "--sync=OnExample",
                "--param-charset=Shift_JIS",
                "--no-cache",
                "--streaming",
                "--timeout=999",
                "--param=name=value"
            ],
            parameterRoot: root
        )

        #expect(options.asyncID == "OnExample")
        #expect(options.customEventID == "OnExample")
        #expect(options.waitForCompletion)
        #expect(options.parameterEncoding == .shiftJIS)
        #expect(options.noCache)
        #expect(options.streaming)
        #expect(options.timeout == 300)
        #expect(options.parameters == ["name=value"])
    }

    @Test
    func resolvesParameterInputFileOnlyInsideGhostMaster() throws {
        let root = URL(fileURLWithPath: "/tmp/ourin-http-options-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("payload.bin")
        let payload = Data([0x00, 0x01, 0xff, 0x7f])
        try payload.write(to: input)

        let valid = GhostManager.HTTPCommandOptions(
            arguments: ["--param-input-file=payload.bin"],
            parameterRoot: root
        )
        #expect(valid.parameterInputData == payload)
        #expect(valid.parameterInputFileError == nil)

        let outside = GhostManager.HTTPCommandOptions(
            arguments: ["--param-input-file=../payload.bin"],
            parameterRoot: root
        )
        #expect(outside.parameterInputData == nil)
        #expect(outside.parameterInputFileError == "path_outside_ghost")
    }
}
