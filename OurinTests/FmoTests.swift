import Testing
@testable import Ourin

struct FmoTests {
    // MARK: - buildSnapshot format

    @Test func buildSnapshotProducesSSPRecordFormat() {
        let record = FmoGhostRecord(
            name: "Emily4",
            keroname: "Teddy",
            path: "/path/to/ghost",
            shell: "master",
            balloon: "default",
            sakuraSurface: 0,
            keroSurface: 10
        )
        let snapshot = FmoManager.buildSnapshot(records: [record])

        #expect(snapshot.contains("0.name\u{01}Emily4\r\n"))
        #expect(snapshot.contains("0.keroname\u{01}Teddy\r\n"))
        #expect(snapshot.contains("0.path\u{01}/path/to/ghost\r\n"))
        #expect(snapshot.contains("0.shell\u{01}master\r\n"))
        #expect(snapshot.contains("0.balloon\u{01}default\r\n"))
        #expect(snapshot.contains("0.sakura.surface\u{01}0\r\n"))
        #expect(snapshot.contains("0.kero.surface\u{01}10\r\n"))
        #expect(snapshot.contains("0.hwnd\u{01}0\r\n"))
    }

    @Test func buildSnapshotUsesCRLF() {
        let record = FmoGhostRecord(name: "Test", keroname: "", path: "/tmp", shell: "master", balloon: "", sakuraSurface: 0, keroSurface: 10)
        let snapshot = FmoManager.buildSnapshot(records: [record])

        // Every line ends with \r\n
        let lines = snapshot.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.count == 8)

        // No bare \n without preceding \r
        let withoutCRLF = snapshot.replacingOccurrences(of: "\r\n", with: "")
        #expect(!withoutCRLF.contains("\n"))
        #expect(!withoutCRLF.contains("\r"))
    }

    @Test func buildSnapshotUsesSOHSeparator() {
        let record = FmoGhostRecord(name: "Ghost", keroname: "", path: "/p", shell: "s", balloon: "b", sakuraSurface: 5, keroSurface: 15)
        let snapshot = FmoManager.buildSnapshot(records: [record])

        // Each record line has exactly one \x01 separator
        let lines = snapshot.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        for line in lines {
            let sohCount = line.filter { $0 == "\u{01}" }.count
            #expect(sohCount == 1, "Line should have exactly one SOH: \(line)")
        }
    }

    @Test func buildSnapshotDoesNotUseKeyEqualsValueFormat() {
        let record = FmoGhostRecord(name: "Test", keroname: "", path: "/tmp", shell: "master", balloon: "", sakuraSurface: 0, keroSurface: 10)
        let snapshot = FmoManager.buildSnapshot(records: [record])

        // Should not contain the old key=value;... format
        #expect(!snapshot.contains("baseware.name="))
        #expect(!snapshot.contains("ghost."))
        #expect(!snapshot.contains("fmo.shared"))

        // Values should be separated by SOH, not =
        let lines = snapshot.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        for line in lines {
            let parts = line.components(separatedBy: "\u{01}")
            #expect(parts.count == 2, "Line should be key\\x01value: \(line)")
            // The key part should not contain =
            #expect(!parts[0].contains("="), "Key should not contain '=': \(parts[0])")
        }
    }

    @Test func buildSnapshotMultipleGhosts() {
        let records = [
            FmoGhostRecord(name: "Ghost0", keroname: "K0", path: "/p0", shell: "s0", balloon: "b0", sakuraSurface: 0, keroSurface: 10),
            FmoGhostRecord(name: "Ghost1", keroname: "K1", path: "/p1", shell: "s1", balloon: "b1", sakuraSurface: 2, keroSurface: 12)
        ]
        let snapshot = FmoManager.buildSnapshot(records: records)

        #expect(snapshot.contains("0.name\u{01}Ghost0\r\n"))
        #expect(snapshot.contains("1.name\u{01}Ghost1\r\n"))
        #expect(snapshot.contains("0.sakura.surface\u{01}0\r\n"))
        #expect(snapshot.contains("1.sakura.surface\u{01}2\r\n"))
    }

    @Test func buildSnapshotEmptyRecordsReturnsEmptyString() {
        let snapshot = FmoManager.buildSnapshot(records: [])
        #expect(snapshot.isEmpty)
    }

    @Test func hwndIsDummyZero() {
        let record = FmoGhostRecord(name: "Test", keroname: "", path: "/tmp", shell: "master", balloon: "", sakuraSurface: 0, keroSurface: 10)
        let snapshot = FmoManager.buildSnapshot(records: [record])
        #expect(snapshot.contains("0.hwnd\u{01}0\r\n"))
    }

    @Test func recordFieldOrder() {
        let record = FmoGhostRecord(name: "N", keroname: "K", path: "/P", shell: "S", balloon: "B", sakuraSurface: 1, keroSurface: 2)
        let snapshot = FmoManager.buildSnapshot(records: [record])
        let lines = snapshot.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        #expect(lines.count == 8)
        #expect(lines[0].hasPrefix("0.name\u{01}"))
        #expect(lines[1].hasPrefix("0.keroname\u{01}"))
        #expect(lines[2].hasPrefix("0.path\u{01}"))
        #expect(lines[3].hasPrefix("0.shell\u{01}"))
        #expect(lines[4].hasPrefix("0.balloon\u{01}"))
        #expect(lines[5].hasPrefix("0.sakura.surface\u{01}"))
        #expect(lines[6].hasPrefix("0.kero.surface\u{01}"))
        #expect(lines[7].hasPrefix("0.hwnd\u{01}"))
    }
}
