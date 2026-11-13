import XCTest
@testable import Ourin

final class YayaExecutionGateTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var ghostRoot: URL!

    override func setUpWithError() throws {
        suiteName = "YayaExecutionGateTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        ghostRoot = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: ghostRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: ghostRoot)
    }

    func testShellMetacharactersAreNotInterpreted() throws {
        let marker = ghostRoot.appendingPathComponent("ourin_exec_test")
        let gate = YayaExecutionGate(defaults: defaults)
        var confirmed: [YayaExecutionGate.Invocation] = []
        gate.confirm = { invocation, completion in confirmed.append(invocation); completion(.deny) }

        let reply = gate.handle(params: ["command": "touch \(marker.path); echo", "wait": false, "arguments": ""],
                                ghostRoot: ghostRoot)

        XCTAssertEqual(reply["ok"] as? Bool, false)
        XCTAssertEqual(reply["status"] as? Int, 403)
        XCTAssertEqual(confirmed.count, 1)
        // `;` はシェルの区切りではなく単なる引数の一部として扱われる。
        XCTAssertEqual(confirmed.first?.target,
                       .executable(URL(fileURLWithPath: "/usr/bin/touch").resolvingSymlinksInPath(), ["\(marker.path);", "echo"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testUnconfirmedExecutionIsDeniedAndNotRun() {
        let marker = ghostRoot.appendingPathComponent("ourin_exec_test")
        let gate = YayaExecutionGate(defaults: defaults)
        gate.confirm = { _, completion in completion(.deny) }

        let reply = gate.handle(params: ["command": "/usr/bin/touch", "wait": true, "arguments": marker.path],
                                ghostRoot: ghostRoot)

        XCTAssertEqual(reply["status"] as? Int, 403)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testAllowAlwaysAllowsOnlyTheSameProgramAndArguments() {
        let marker = ghostRoot.appendingPathComponent("allowed")
        let gate = YayaExecutionGate(defaults: defaults)
        let decided = expectation(description: "confirmation")
        gate.confirm = { _, completion in completion(.allowAlways); decided.fulfill() }

        _ = gate.handle(params: ["command": "/usr/bin/touch", "wait": true, "arguments": marker.path], ghostRoot: ghostRoot)
        wait(for: [decided], timeout: 2)

        var asked = false
        gate.confirm = { _, completion in asked = true; completion(.deny) }
        try? FileManager.default.removeItem(at: marker)
        let allowed = gate.handle(params: ["command": "/usr/bin/touch", "wait": true, "arguments": marker.path],
                                  ghostRoot: ghostRoot)
        XCTAssertEqual(allowed["ok"] as? Bool, true)
        XCTAssertEqual(allowed["exit_code"] as? Int, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(asked)

        let other = gate.handle(params: ["command": "/usr/bin/touch", "wait": true,
                                         "arguments": ghostRoot.appendingPathComponent("other").path],
                                ghostRoot: ghostRoot)
        XCTAssertEqual(other["status"] as? Int, 403)
        XCTAssertTrue(asked)
    }

    func testTokenizeKeepsQuotedArgumentsWithoutExpansion() {
        XCTAssertEqual(YayaExecutionGate.tokenize(#"a "b c" $(id) ;rm"#), ["a", "b c", "$(id)", ";rm"])
        XCTAssertEqual(YayaExecutionGate.tokenize(#""""#), [""])
    }

    func testURLsAreOpenedWithoutShell() throws {
        let target = try YayaExecutionGate.resolve(command: "https://example.com/?q=a;b", arguments: "", ghostRoot: ghostRoot)
        XCTAssertEqual(target, .open(URL(string: "https://example.com/?q=a;b")!))
        XCTAssertThrowsError(try YayaExecutionGate.resolve(command: "", arguments: "", ghostRoot: ghostRoot))
        XCTAssertThrowsError(try YayaExecutionGate.resolve(command: "no-such-program-ourin", arguments: "", ghostRoot: ghostRoot))
    }

    func testMissingGhostRootIsDenied() {
        let gate = YayaExecutionGate(defaults: defaults)
        let reply = gate.handle(params: ["command": "/usr/bin/true"], ghostRoot: nil)
        XCTAssertEqual(reply["status"] as? Int, 403)
    }
}
