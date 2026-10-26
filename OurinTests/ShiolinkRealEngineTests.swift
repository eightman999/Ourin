import Foundation
import Testing
@testable import Ourin

/// Opt-in integration tests. Dependencies are installed outside the repository;
/// ordinary tests never install packages or require network access.
struct ShiolinkRealEngineTests {
    private static let npmRoot = ProcessInfo.processInfo.environment["OURIN_SHIOLINK_NPM_ROOT"]
    private static let gemRoot = ProcessInfo.processInfo.environment["OURIN_SHIOLINK_GEM_ROOT"]

    private func exercise(executable: String, arguments: [String], source: String, name: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Ourin-RealShiolink-\(UUID().uuidString)")
        let master = root.appendingPathComponent("ghost/master")
        try FileManager.default.createDirectory(at: master, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try source.write(to: master.appendingPathComponent(name), atomically: true, encoding: .utf8)
        let args = String(data: try JSONEncoder().encode(arguments), encoding: .utf8)!
        try "[SHIOLINK]\nexecutable=\(executable)\narguments=\(args)\ncharmode=UTF-8\n"
            .write(to: master.appendingPathComponent("SHIOLINK.ourin.ini"), atomically: true, encoding: .utf8)
        let context = ShioriRuntimeLoadContext(ghostURL: root, ghostRoot: master, moduleName: "SHIOLINK.dll")
        let runtime = try #require(ShioriRuntimeFactory.makeRuntime(for: context.moduleName))
        defer { runtime.unload() }
        for expected in ["1", "2"] {
            #expect(runtime.load(context: context))
            #expect(runtime.request(method: "GET", id: "OnBoot", timeout: 5)?.value == "桜鈴 🌸 \(expected)")
            #expect(runtime.request(method: "GET", id: "OnMouseDoubleClick", refs: ["日本語"], timeout: 5)?.value == "日本語")
            #expect(runtime.request(method: "NOTIFY", id: "OnTest", timeout: 5)?.status == 204)
            runtime.unload()
            #expect(!runtime.isLoaded)
        }
    }

    @Test(.enabled(if: npmRoot != nil, "Set OURIN_SHIOLINK_NPM_ROOT to a prefix with sanajk and shiolinkjs"))
    func sanaJKBootTalkSaveAndReload() throws {
        let prefix = try #require(Self.npmRoot)
        let rootLiteral = String(data: try JSONEncoder().encode(prefix + "/node_modules"), encoding: .utf8)!
        let source = """
        const modules = \(rootLiteral);
        const fs = require('fs');
        const builder = new (require(modules + '/sanajk').SanaShioriBuilder)().useDefaults();
        let count = fs.existsSync('count.txt') ? Number(fs.readFileSync('count.txt', 'utf8')) : 0;
        builder.state.events.OnBoot = () => `桜鈴 🌸 ${++count}`;
        builder.state.events.OnMouseDoubleClick = ctx => ctx.request.headers.Reference(0);
        const engine = builder.build();
        const unload = engine.unload.bind(engine);
        engine.unload = async () => { fs.writeFileSync('count.txt', String(count)); await unload(); process.exit(0); };
        require(modules + '/shiolinkjs').runShiori(engine);
        """
        try exercise(executable: ProcessInfo.processInfo.environment["OURIN_SHIOLINK_NODE"] ?? "/opt/homebrew/bin/node",
                     arguments: ["./main.js"], source: source, name: "main.js")
    }

    @Test(.enabled(if: gemRoot != nil, "Set OURIN_SHIOLINK_GEM_ROOT to a gem install prefix with sana and shiolink"))
    func sanaBootTalkSaveAndReload() throws {
        let prefix = try #require(Self.gemRoot)
        let rootLiteral = String(data: try JSONEncoder().encode(prefix), encoding: .utf8)!
        let source = """
        ENV['GEM_HOME'] = \(rootLiteral)
        ENV['GEM_PATH'] = \(rootLiteral)
        require 'rubygems'
        Gem.clear_paths
        require 'sana'
        require 'shiolink'
        $stdout.sync = true
        $stdin.set_encoding('UTF-8')
        class Events
        def _load(path); $count = File.exist?('count.txt') ? File.read('count.txt').to_i : 0; end
        def _unload; File.write('count.txt', $count.to_s); exit; end
        def version(r); '0.0.1'; end
        def OnBoot(r); $count += 1; "桜鈴 🌸 #{$count}"; end
        def OnMouseDoubleClick(r); r.Reference0; end
        def OnTest(r); nil; end
        end
        engine = Sana.new(Events.new)
        Shiolink.new(engine.method(:load), engine.method(:unload), engine.method(:request)).start
        """
        try exercise(executable: ProcessInfo.processInfo.environment["OURIN_SHIOLINK_RUBY"] ?? "/opt/homebrew/bin/ruby",
                     arguments: ["./main.rb"], source: source, name: "main.rb")
    }
}
