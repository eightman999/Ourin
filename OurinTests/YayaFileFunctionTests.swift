import Foundation
import Testing
@testable import Ourin

/// yaya_core のファイル関数を YAYA 本体に合わせる（#179）。
struct YayaFileFunctionTests {
    private static func locateYayaCore() -> URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "yaya_core") { return url }
        return nil
    }

    /// load と要求を 1 回ずつ送り、最後の応答の値を返す。stderr は読まずに捨てる。
    private static func request(_ id: String, ghost: URL, exe: URL) -> String? {
        let requests: [[String: Any]] = [
            ["cmd": "load", "ghost_root": ghost.path, "encoding": "UTF-8", "dic_entries": [["path": "t.dic"]]],
            ["cmd": "request", "method": "GET", "id": id, "ref": [], "headers": ["Charset": "UTF-8"]],
        ]
        let input = requests.compactMap { try? JSONSerialization.data(withJSONObject: $0) }
            .compactMap { String(data: $0, encoding: .utf8) }.joined(separator: "\n") + "\n"
        let proc = Process()
        proc.executableURL = exe
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return nil }
        inPipe.fileHandleForWriting.write(Data(input.utf8))
        inPipe.fileHandleForWriting.closeFile()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        var last: String?
        for line in String(data: data, encoding: .utf8)?.split(separator: "\n") ?? [] {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["host_op"] == nil else { continue }
            if let value = obj["value"] as? String { last = value }
        }
        return last
    }

    @Test
    func backslashPathsAndDirectoryDestinationsWorkLikeYaya() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found")
            return
        }
        let fm = FileManager.default
        let ghost = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: ghost.appendingPathComponent("src"), withIntermediateDirectories: true)
        try fm.createDirectory(at: ghost.appendingPathComponent("dest"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: ghost) }
        try "data".write(to: ghost.appendingPathComponent("src/data.txt"), atomically: true, encoding: .utf8)
        try "move".write(to: ghost.appendingPathComponent("src/move.txt"), atomically: true, encoding: .utf8)
        try "other".write(to: ghost.appendingPathComponent("src/other.txt"), atomically: true, encoding: .utf8)
        try "kept".write(to: ghost.appendingPathComponent("dest/exists.txt"), atomically: true, encoding: .utf8)

        // Taromati2 の FULLNAMEFCOPY と同じく、`\` 区切りで、コピー先にフォルダを渡す。
        let dic = """
        Probe {
            _a = FCOPY('src\\data.txt', 'dest')
            _b = FMOVE('.\\src\\move.txt', 'dest\\')
            _c = FCOPY('src\\data.txt', 'dest\\renamed.txt')
            _d = FMOVE('src\\other.txt', 'dest\\exists.txt')
            _e = FCOPY('..\\src\\data.txt', 'dest')
            _f = FCOPY('src\\data.txt', '\\top.txt')
            TOSTR(_a) + TOSTR(_b) + TOSTR(_c) + TOSTR(_d) + TOSTR(_e) + TOSTR(_f)
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)

        // コピー・移動・ファイル名指定のコピーは成功。既存の移動先と `..` は失敗。
        // `\\` で始まるパスもゴーストの中の相対パスとして扱う（絶対パスにしない）。
        #expect(Self.request("Probe", ghost: ghost, exe: exe) == "111001")
        func contents(_ path: String) -> String? {
            try? String(contentsOf: ghost.appendingPathComponent(path), encoding: .utf8)
        }
        #expect(contents("dest/data.txt") == "data")
        #expect(contents("dest/move.txt") == "move")
        #expect(!fm.fileExists(atPath: ghost.appendingPathComponent("src/move.txt").path))
        #expect(contents("dest/renamed.txt") == "data")
        #expect(contents("dest/exists.txt") == "kept")
        #expect(contents("src/other.txt") == "other")
        #expect(contents("top.txt") == "data")
        // `\` を名前に含むファイルは作らない。
        let names = try fm.contentsOfDirectory(atPath: ghost.path)
        #expect(!names.contains { $0.contains("\\") }, "\(names)")
    }

    /// SPLITPATH は YAYA 本体の Windows 版（_wsplitpath）と同じ 4 要素を返す。
    /// Taromati2 の SPLITPATH.roughly は名前と拡張子をつないでファイル名に戻す。
    @Test
    func splitPathReturnsDriveDirectoryNameAndExtensionLikeYaya() throws {
        guard let exe = Self.locateYayaCore() else {
            print("[skip] yaya_core not found")
            return
        }
        let fm = FileManager.default
        let ghost = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: ghost, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: ghost) }
        let dic = """
        Join {
            _argv[0][0] + '|' + _argv[0][1] + '|' + _argv[0][2] + '|' + _argv[0][3]
        }
        Probe {
            Join(SPLITPATH('C:\\dir\\sub\\name.ext')) + '#' + Join(SPLITPATH('./profile\\debeso.db.base')) + '#' + Join(SPLITPATH('noext'))
        }
        """
        try dic.write(to: ghost.appendingPathComponent("t.dic"), atomically: true, encoding: .utf8)
        #expect(Self.request("Probe", ghost: ghost, exe: exe)
            == "C:|\\dir\\sub\\|name|.ext#|./profile\\|debeso.db|.base#||noext|")
    }

    @Test
    func ghostBootPreparesTheProfileFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let ghostRoot = root.appendingPathComponent("ghost/master", isDirectory: true)
        try fm.createDirectory(at: ghostRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        GhostManager.prepareProfileDirectory(ghostRoot: ghostRoot)
        var isDirectory: ObjCBool = false
        #expect(fm.fileExists(atPath: ghostRoot.appendingPathComponent("profile").path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        // ゴーストのフォルダが無ければ何も作らない。
        let missing = root.appendingPathComponent("missing/ghost/master", isDirectory: true)
        GhostManager.prepareProfileDirectory(ghostRoot: missing)
        #expect(!fm.fileExists(atPath: missing.path))
    }
    @Test
    func saveFileStaysBesideOriginalModuleWhenBasepathChanges() throws {
        let package = URL(fileURLWithPath: "/tmp/ourin-save-path-test")
        let context = ShioriRuntimeLoadContext(
            ghostURL: package,
            ghostRoot: package.appendingPathComponent("ghost/master"),
            moduleName: "shiori\\aya.dll"
        )
        #expect(YayaAdapter.saveFilePath(for: context) == package.appendingPathComponent("ghost/master/shiori/aya_variable.cfg").resolvingSymlinksInPath().path)
        let outside = ShioriRuntimeLoadContext(
            ghostURL: package, ghostRoot: package, moduleName: "../../../escape.dll"
        )
        #expect(YayaAdapter.saveFilePath(for: outside) == nil)
        let request = YayaRequest(cmd: "load", saveFile: YayaAdapter.saveFilePath(for: context))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        #expect(json?["save_file"] as? String == YayaAdapter.saveFilePath(for: context))
    }

}
