import Foundation
import Testing
@testable import Ourin

struct BasewareUpdateTests {
    @Test
    func helperRequestRoundTripsThroughCommandLineArguments() {
        let request = BasewareUpdateRequest(
            parentPID: 1234,
            targetAppURL: URL(fileURLWithPath: "/tmp/Ourin.app", isDirectory: true),
            stagedAppURL: URL(fileURLWithPath: "/tmp/.OurinUpdate/Ourin.app", isDirectory: true),
            markerURL: URL(fileURLWithPath: "/tmp/marker.json"),
            version: "1.2.3 beta"
        )

        let parsed = BasewareUpdateRequest(commandLine: ["Ourin"] + request.helperArguments)
        #expect(parsed == request)
    }

    @Test
    func markerMovesFromPendingToApplied() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-baseware-marker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let request = BasewareUpdateRequest(
            parentPID: 1234,
            targetAppURL: root.appendingPathComponent("Ourin.app", isDirectory: true),
            stagedAppURL: root.appendingPathComponent("staged/Ourin.app", isDirectory: true),
            markerURL: root.appendingPathComponent("marker.json"),
            version: "2.0.0"
        )
        try BasewareUpdateMarker.writePending(request)
        #expect(BasewareUpdateMarker.appliedVersion(at: request.markerURL) == nil)

        try BasewareUpdateMarker.markApplied(at: request.markerURL)
        #expect(BasewareUpdateMarker.appliedVersion(at: request.markerURL) == "2.0.0")
    }

    @Test
    func helperReplacesStagedAppAndLeavesAppliedMarker() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourin-baseware-replace-\(UUID().uuidString)", isDirectory: true)
        let target = root.appendingPathComponent("Ourin.app", isDirectory: true)
        let staged = root.appendingPathComponent("stage/Ourin.app", isDirectory: true)
        let targetFile = target.appendingPathComponent("Contents/Resources/version.txt")
        let stagedFile = staged.appendingPathComponent("Contents/Resources/version.txt")
        try FileManager.default.createDirectory(at: targetFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: targetFile)
        try Data("new".utf8).write(to: stagedFile)
        defer { try? FileManager.default.removeItem(at: root) }

        let request = BasewareUpdateRequest(
            parentPID: 1234,
            targetAppURL: target,
            stagedAppURL: staged,
            markerURL: root.appendingPathComponent("marker.json"),
            version: "3.0.0"
        )
        try BasewareUpdateMarker.writePending(request)
        try BasewareUpdateHelper.replace(request, relaunch: false)

        #expect(String(data: try Data(contentsOf: targetFile), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: staged.path))
        #expect(BasewareUpdateMarker.appliedVersion(at: request.markerURL) == "3.0.0")
    }
}
