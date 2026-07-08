import Testing
import Foundation
@testable import Ourin

struct NarInstallTests {
    @Test
    func parseInstallTxt() throws {
        let raw = "type,ghost\ndirectory,foo"
        let manifest = try InstallTxtParser.parse(raw)
        #expect(manifest.type == "ghost")
        #expect(manifest.directory == "foo")
    }

    /// `type,saori` の設置先解決（UKADOC 未規定のため Ourin 定義:
    /// accept あり → 対象ゴーストの ghost/master/<dir>、なし → 共有 saori/<dir>）
    @Test
    func saoriInstallTargetResolution() throws {
        let shared = try OurinPaths.installTarget(forType: "saori", directory: "mciaudior")
        #expect(shared.path.hasSuffix("/saori/mciaudior"))

        let ghostLocal = try OurinPaths.installTarget(forType: "saori", directory: "mciaudior", accept: "emily4")
        #expect(ghostLocal.path.hasSuffix("/ghost/emily4/ghost/master/mciaudior"))
    }

    @Test
    func installUtf8Nar() throws {
        let nar = try makeSampleNar(encoding: .utf8, dirName: "sample1_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }
        let installer = NarInstaller()
        let target = try installer.install(fromNar: nar)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test
    func installSjisNar() throws {
        let sjisEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.shiftJIS.rawValue)))
        let nar = try makeSampleNar(encoding: sjisEnc, dirName: "sample_sjis_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }
        let installer = NarInstaller()
        let target = try installer.install(fromNar: nar)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test
    func updateDescriptorParsesRelativeAndAbsoluteEntries() throws {
        let text = """
        ; comment
        patch1.nar,2026-01-01
        https://example.com/ghost/patch2.nar\u{0001}meta
        """
        let base = URL(string: "https://example.com/ghost/")!
        let urls = UpdateDescriptorParser.parse(text, baseURL: base)
        #expect(urls.contains(URL(string: "https://example.com/ghost/patch1.nar")!))
        #expect(urls.contains(URL(string: "https://example.com/ghost/patch2.nar")!))
    }

    @Test
    func deleteTxtRemovesLegacyFiles() throws {
        let nar = try makeSampleNar(encoding: .utf8, dirName: "sample_delete_\(UUID().uuidString)", withDeleteInstruction: true)
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }
        let installer = NarInstaller()
        let target = try installer.install(fromNar: nar)
        #expect(!FileManager.default.fileExists(atPath: target.appendingPathComponent("legacy.txt").path))
    }

    // MARK: - 複合 install.txt（付属コンポーネント同時インストール）

    /// type=ghost に balloon/headline/plugin/calendar.skin を同梱した install.txt が構造化パースされること。
    /// UKADOC: https://ssp.shillest.net/ukadoc/manual/descript_install.html (*.directory)
    @Test
    func parseComplexInstallTxtWithAttachedComponents() throws {
        let raw = """
        charset,UTF-8
        type,ghost
        directory,MyGhost
        balloon.directory,MyBalloon
        balloon.source.directory,balloon
        headline.directory,MyHeadline
        plugin.directory,MyPlugin
        calendar.skin.directory,MyCalSkin
        """
        let manifest = try InstallTxtParser.parse(raw)
        #expect(manifest.type == "ghost")
        #expect(manifest.directory == "MyGhost")
        // 後方互換: balloonDirectory / balloonSourceDirectory も維持されること
        #expect(manifest.balloonDirectory == "MyBalloon")
        #expect(manifest.balloonSourceDirectory == "balloon")
        // 構造化リスト: 4 コンポーネント
        #expect(manifest.attachedComponents.count == 4)
        let types = manifest.attachedComponents.map(\.type)
        #expect(types.contains("balloon"))
        #expect(types.contains("headline"))
        #expect(types.contains("plugin"))
        #expect(types.contains("calendar.skin"))
        // balloon には source.directory が反映されていること
        let balloon = manifest.attachedComponents.first { $0.type == "balloon" }
        #expect(balloon?.directory == "MyBalloon")
        #expect(balloon?.sourceDirectory == "balloon")
        #expect(balloon?.kindToken == "balloon")
        // source.directory 未指定のコンポーネントは nil（= directory と同義）
        let headline = manifest.attachedComponents.first { $0.type == "headline" }
        #expect(headline?.directory == "MyHeadline")
        #expect(headline?.sourceDirectory == nil)
        // calendar.skin の kindToken はドットを保持したまま
        let calSkin = manifest.attachedComponents.first { $0.type == "calendar.skin" }
        #expect(calSkin?.kindToken == "calendar.skin")
        #expect(calSkin?.directory == "MyCalSkin")
    }

    /// 同種の付属コンポーネントを複数指定（balloon0, balloon1）した場合のパース。
    /// UKADOC: 「複数の同じ種類のものをインストールしたい時は、\*部分を balloon0,balloon1,...のように」
    @Test
    func parseMultipleBalloonsAttachedComponents() throws {
        let raw = """
        type,ghost
        directory,MyGhost
        balloon0.directory,FirstBalloon
        balloon0.source.directory,src_balloon_0
        balloon1.directory,SecondBalloon
        """
        let manifest = try InstallTxtParser.parse(raw)
        let balloons = manifest.attachedComponents.filter { $0.type == "balloon" }
        #expect(balloons.count == 2)
        let byDir = Dictionary(uniqueKeysWithValues: balloons.map { ($0.directory, $0) })
        #expect(byDir["FirstBalloon"]?.sourceDirectory == "src_balloon_0")
        #expect(byDir["FirstBalloon"]?.kindToken == "balloon0")
        #expect(byDir["SecondBalloon"]?.sourceDirectory == nil)
        #expect(byDir["SecondBalloon"]?.kindToken == "balloon1")
        // balloon0/balloon1 は従来の balloonDirectory（数字なし "balloon" のみ）には反映されない
        #expect(manifest.balloonDirectory == nil)
    }

    /// `*.refresh` / `*.refreshundeletemask` のパース。
    @Test
    func parseAttachedComponentRefreshAndMask() throws {
        let raw = """
        type,ghost
        directory,MyGhost
        headline.directory,MyHeadline
        headline.refresh,1
        headline.refreshundeletemask,savedata:*.sav:userconfig.txt
        """
        let manifest = try InstallTxtParser.parse(raw)
        #expect(manifest.attachedComponents.count == 1)
        let headline = manifest.attachedComponents.first
        #expect(headline?.type == "headline")
        #expect(headline?.refresh == true)
        #expect(headline?.refreshUndeleteMask == ["savedata", "*.sav", "userconfig.txt"])
    }

    /// type=ghost に同梱された headline と plugin が、所定位置（headline/<name>, plugin/<name>）へ展開されること。
    @Test
    func installNarWithAttachedHeadlineAndPlugin() throws {
        let uid = UUID().uuidString
        let ghostName = "ghost_\(uid)"
        let headlineName = "headline_\(uid)"
        let pluginName = "plugin_\(uid)"
        let installTxt = """
        charset,UTF-8
        type,ghost
        directory,\(ghostName)
        headline.directory,\(headlineName)
        plugin.directory,\(pluginName)
        """
        let nar = try makeComplexNar(
            installTxt: installTxt,
            attachedDirs: [
                (headlineName, "descript.txt", "type,headline"),
                (pluginName, "descript.txt", "type,plugin"),
            ]
        )
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }

        // NAR の中身を検証: zip がディレクトリを正しく含めたか（NAR 作成問題の切り分け）
        let verifyDir = FileManager.default.temporaryDirectory.appendingPathComponent("verify_\(uid)", isDirectory: true)
        try FileManager.default.createDirectory(at: verifyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: verifyDir) }
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", nar.path, verifyDir.path]
        try ditto.run()
        ditto.waitUntilExit()
        let headlineVerify = verifyDir.appendingPathComponent(headlineName).appendingPathComponent("descript.txt")
        let pluginVerify = verifyDir.appendingPathComponent(pluginName).appendingPathComponent("descript.txt")
        #expect(FileManager.default.fileExists(atPath: headlineVerify.path), "NAR should contain \(headlineName)/descript.txt")
        #expect(FileManager.default.fileExists(atPath: pluginVerify.path), "NAR should contain \(pluginName)/descript.txt")

        let installer = NarInstaller()
        let target = try installer.install(fromNar: nar)
        #expect(FileManager.default.fileExists(atPath: target.path))

        let base = try OurinPaths.baseDirectory()
        let headlineFile = base.appendingPathComponent("headline/\(headlineName)/descript.txt")
        let pluginFile = base.appendingPathComponent("plugin/\(pluginName)/descript.txt")
        #expect(FileManager.default.fileExists(atPath: headlineFile.path), "headline should be installed under headline/")
        #expect(FileManager.default.fileExists(atPath: pluginFile.path), "plugin should be installed under plugin/")
    }

    /// type=ghost に同梱された calendar.skin が calendar/skin/<name> へ展開されること。
    /// ドット区切りの kindToken（calendar.skin）が OurinPaths.installTarget の calendar/skin へ正規化されることの確認。
    @Test
    func installNarWithAttachedCalendarSkin() throws {
        let uid = UUID().uuidString
        let ghostName = "ghost_\(uid)"
        let skinName = "calskin_\(uid)"
        let installTxt = """
        charset,UTF-8
        type,ghost
        directory,\(ghostName)
        calendar.skin.directory,\(skinName)
        """
        let nar = try makeComplexNar(
            installTxt: installTxt,
            attachedDirs: [
                (skinName, "descript.txt", "type,calendar.skin"),
            ]
        )
        defer { try? FileManager.default.removeItem(at: nar.deletingLastPathComponent()) }

        let installer = NarInstaller()
        _ = try installer.install(fromNar: nar)

        let base = try OurinPaths.baseDirectory()
        let skinFile = base.appendingPathComponent("calendar/skin/\(skinName)/descript.txt")
        #expect(FileManager.default.fileExists(atPath: skinFile.path), "calendar skin should be installed under calendar/skin/")
    }

    private func makeSampleNar(encoding: String.Encoding, dirName: String, withDeleteInstruction: Bool = false) throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let installText = "type,ghost\ndirectory,\(dirName)"
        let installURL = base.appendingPathComponent("install.txt")
        try installText.data(using: encoding)!.write(to: installURL)
        let readmeURL = base.appendingPathComponent("README.txt")
        try "sample".data(using: encoding)!.write(to: readmeURL)
        if withDeleteInstruction {
            let legacyURL = base.appendingPathComponent("legacy.txt")
            try "legacy".data(using: encoding)!.write(to: legacyURL)
            let deleteURL = base.appendingPathComponent("delete.txt")
            try "legacy.txt".data(using: encoding)!.write(to: deleteURL)
        }
        let nar = base.appendingPathComponent("sample.nar")
        let proc = Process()
        proc.currentDirectoryURL = base
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        var files = ["install.txt", "README.txt"]
        if withDeleteInstruction {
            files.append(contentsOf: ["legacy.txt", "delete.txt"])
        }
        proc.arguments = ["-q", nar.path] + files
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw NSError(domain: "zip", code: Int(proc.terminationStatus), userInfo: nil) }
        return nar
    }

    /// カスタム install.txt と同梱ディレクトリを含む NAR を作成する。
    /// attachedDirs: (アーカイブ内のディレクトリ名, その配下に置くファイル名, ファイル内容)
    /// 同梱ディレクトリはアーカイブルート直下に置かれる（UKADOC manual_install.html の標準構成）。
    private func makeComplexNar(
        installTxt: String,
        encoding: String.Encoding = .utf8,
        attachedDirs: [(archiveDir: String, fileName: String, content: String)] = []
    ) throws -> URL {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        let installURL = base.appendingPathComponent("install.txt")
        try installTxt.data(using: encoding)!.write(to: installURL)
        var entries: [String] = ["install.txt"]
        for ad in attachedDirs {
            let dirURL = base.appendingPathComponent(ad.archiveDir, isDirectory: true)
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            let fileURL = dirURL.appendingPathComponent(ad.fileName)
            try ad.content.data(using: encoding)!.write(to: fileURL)
            entries.append(ad.archiveDir)
        }
        let nar = base.appendingPathComponent("sample.nar")
        let proc = Process()
        proc.currentDirectoryURL = base
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        // ディレクトリを再帰的に含めるため -r を指定。
        proc.arguments = ["-rq", nar.path] + entries
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw NSError(domain: "zip", code: Int(proc.terminationStatus), userInfo: nil) }
        return nar
    }
}
