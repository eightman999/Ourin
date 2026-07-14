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
        #expect(lines.count == 14)

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

    @Test func compatibilityViewParsesSnapshot() throws {
        var record = FmoGhostRecord(name: "Ghost", keroname: "Kero", path: "/ghost", shell: "master", balloon: "default", sakuraSurface: 5, keroSurface: 15)
        record.hwnd = 1001
        record.kerohwnd = 1002
        record.hwndList = "1001,1002"

        let view = FmoManager.buildCompatibilityView(records: [record])

        let entry = try #require(view.entry(id: 0))
        #expect(entry["name"] == "Ghost")
        #expect(entry["keroname"] == "Kero")
        #expect(entry["path"] == "/ghost")
        #expect(entry["sakura.surface"] == "5")
        #expect(entry["kero.surface"] == "15")
        #expect(entry["hwnd"] == "1001")
        #expect(view.value(id: 0, key: "hwndlist") == "1001,1002")
    }

    @Test func compatibilityViewIgnoresMalformedLinesAndSortsByID() throws {
        let snapshot = [
            "2.name\u{01}Third",
            ".name\u{01}Broken",
            "1.name\u{01}Second",
            "0.\u{01}NoField",
            "missing-separator",
            "0.name\u{01}First"
        ].joined(separator: "\r\n") + "\r\n"

        let view = FmoCompatibilityView.parse(snapshot)

        #expect(view.entries.map(\.id) == ["0", "1", "2"])
        #expect(view.value(id: 0, key: "name") == "First")
        #expect(view.value(id: 1, key: "name") == "Second")
        #expect(view.value(id: 2, key: "name") == "Third")
        #expect(view.value(id: 0, key: "") == nil)
    }

    @Test func buildSnapshotEmptyRecordsReturnsEmptyString() {
        let snapshot = FmoManager.buildSnapshot(records: [])
        #expect(snapshot.isEmpty)
    }

    @Test func hwndReflectsRecord() {
        var record = FmoGhostRecord(name: "Test", keroname: "", path: "/tmp", shell: "master", balloon: "", sakuraSurface: 0, keroSurface: 10)
        record.hwnd = 42
        record.kerohwnd = 43
        record.hwndList = "42,43"
        let snapshot = FmoManager.buildSnapshot(records: [record])
        // hwnd はダミー0ではなくレコード固有の安定・一意な値を出力する
        #expect(snapshot.contains("0.hwnd\u{01}42\r\n"))
        #expect(snapshot.contains("0.kerohwnd\u{01}43\r\n"))
        #expect(snapshot.contains("0.hwndlist\u{01}42,43\r\n"))
        #expect(snapshot.contains("0.modulestate\u{01}\r\n"))
        #expect(!snapshot.contains("module.state"))
    }

    @Test func recordFieldOrder() {
        let record = FmoGhostRecord(name: "N", keroname: "K", path: "/P", shell: "S", balloon: "B", sakuraSurface: 1, keroSurface: 2)
        let snapshot = FmoManager.buildSnapshot(records: [record])
        let lines = snapshot.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        #expect(lines.count == 14)
        #expect(lines[0].hasPrefix("0.name\u{01}"))
        #expect(lines[1].hasPrefix("0.keroname\u{01}"))
        #expect(lines[2].hasPrefix("0.fullname\u{01}"))
        #expect(lines[3].hasPrefix("0.ghostname\u{01}"))
        #expect(lines[4].hasPrefix("0.path\u{01}"))
        #expect(lines[5].hasPrefix("0.ghostpath\u{01}"))
        #expect(lines[6].hasPrefix("0.sakura.surface\u{01}"))
        #expect(lines[7].hasPrefix("0.kero.surface\u{01}"))
        #expect(lines[8].hasPrefix("0.hwnd\u{01}"))
        #expect(lines[9].hasPrefix("0.kerohwnd\u{01}"))
        #expect(lines[10].hasPrefix("0.hwndlist\u{01}"))
        #expect(lines[11].hasPrefix("0.modulestate\u{01}"))
        #expect(lines[12].hasPrefix("0.shell\u{01}"))
        #expect(lines[13].hasPrefix("0.balloon\u{01}"))
    }

    @Test func uniqueRecordIDPrefixesEveryLine() throws {
        let id = "0123456789abcdef0123456789abcdef"
        var record = FmoGhostRecord(name: "Owned", keroname: "", path: "/owned")
        record.id = id
        record.moduleState = FmoModuleState(
            shiori: .running,
            ghostMakoto: .running,
            shellMakoto: nil,
            compatible: nil
        ).value

        let snapshot = FmoManager.buildSnapshot(records: [record])
        let lines = snapshot.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(lines.allSatisfy { $0.hasPrefix("\(id).") })
        #expect(snapshot.contains("\(id).modulestate\u{01}shiori:running,makoto-ghost:running\r\n"))

        let entry = try #require(FmoCompatibilityView.parse(snapshot).entry(id: id))
        #expect(entry["modulestate"] == "shiori:running,makoto-ghost:running")
    }

    @Test func moduleStateUsesUkadocNamesAndHealthValues() {
        let state = FmoModuleState(
            shiori: .critical,
            ghostMakoto: .running,
            shellMakoto: .critical,
            compatible: nil
        )
        #expect(state.value == "shiori:critical,makoto-ghost:running,makoto-shell:critical")
    }
}
