import AppKit
import Foundation

// 互換モジュール（UKADOC「SAORI over DirectSSTP」の互換モジュール。SSP 2.9.13〜）。
// https://ssp.shillest.net/ukadoc/manual/spec_saori_ex.html#compat
//
// よく使われていた SAORI DLL（houchi・clipcopy・textcopy・saori_ip・saori_cpuid・mciaudio・cpuusage・httpc・
// string・hanayu）をベースウェアが内蔵し、ゴーストがその DLL を load したら DLL を読まずに差し替える（ファイル名で判定）。
// Direct SSTP からも、DLL 名から .dll を除いた名前（Module: string など）で呼べる。引数と戻り値は原作の SAORI のまま。
// macOS では Windows の DLL を読めないので、これらのゴーストを動かすにはこの差し替えが要る。

/// 互換モジュールの応答。原作に合わせて、モジュールごとに 200 / 204 / 400 / 500 を返す。
struct CompatSaoriResult: Equatable {
    var status: Int
    var result: String?
    var values: [String] = []
    /// 400 / 500 のときの ErrorDescription。
    var error: String?

    static let noContent = CompatSaoriResult(status: 204)
    static let badRequest = CompatSaoriResult(status: 400, error: "bad request")
    static let ghostRequired = CompatSaoriResult(status: 400, error: "ghost required")
    static let internalError = CompatSaoriResult(status: 500, error: "internal error")

    static func ok(_ result: String, values: [String] = []) -> CompatSaoriResult {
        CompatSaoriResult(status: 200, result: result, values: values)
    }
}

/// 呼び出し元の情報。モジュールを用意するときに決まる。
struct CompatSaoriEnvironment {
    /// ゴーストの基準フォルダ（ghost/master）。nil なら「ゴーストなし」（Direct SSTP）。
    var ghostRoot: URL?
    /// DLL を置いた場所。httpc の保存先や hanayu.txt の場所など、原作で「dll と同じ場所」だったものの基準。
    var moduleDirectory: URL?
    /// 原作が DirectSSTP で本体へ送っていたイベントを、このゴーストへ届ける（Reference0 から順）。
    var deliverEvent: ((String, [String]) -> Void)?

    static let ghostless = CompatSaoriEnvironment(ghostRoot: nil, moduleDirectory: nil, deliverEvent: nil)

    var hasGhost: Bool { ghostRoot != nil }

    /// ゴーストのフォルダ（ghost/master）を基準にしたパス。`\` 区切りも読む。絶対パスはそのまま。
    func resolve(_ path: String, base: URL? = nil) -> URL? {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasPrefix("/") { return URL(fileURLWithPath: normalized).standardizedFileURL }
        guard let root = base ?? ghostRoot else { return nil }
        return root.appendingPathComponent(normalized).standardizedFileURL
    }
}

/// 互換モジュール。ゴーストごと・読み込みごとに 1 つ作る（状態を持つものはインスタンスに持つ）。
protocol CompatSaoriModule: AnyObject {
    init(environment: CompatSaoriEnvironment)
    /// Argument0 から順の引数。`charset` は要求の Charset（漢字コードを扱う関数で使う）。
    func execute(_ arguments: [String], charset: String) -> CompatSaoriResult
    /// unload・ゴーストの終了で呼ぶ。
    func unload()
}

extension CompatSaoriModule {
    func unload() {}
}

enum CompatSaoriRegistry {
    /// 互換モジュールの名前（DLL 名から .dll を除いて小文字にしたもの）と、作り方。
    static let factories: [String: (CompatSaoriEnvironment) -> CompatSaoriModule] = [
        "houchi": { CompatHouchiModule(environment: $0) },
        "clipcopy": { CompatClipcopyModule(environment: $0) },
        "textcopy": { CompatTextcopyModule(environment: $0) },
        "saori_ip": { CompatSaoriIPModule(environment: $0) },
        "saori_cpuid": { CompatSaoriCPUIDModule(environment: $0) },
        "mciaudio": { CompatMCIAudioModule(environment: $0) },
        "cpuusage": { CompatCPUUsageModule(environment: $0) },
        "httpc": { CompatHttpcModule(environment: $0) },
        "string": { CompatStringModule(environment: $0) },
        "hanayu": { CompatHanayuModule(environment: $0) }
    ]

    /// `saori/string.dll` や `String.DLL`・`string` のような名前から、互換モジュールの名前を取り出す。互換でなければ nil。
    static func compatName(_ module: String) -> String? {
        var base = (module.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent.lowercased()
        if base.hasSuffix(".dll") { base = String(base.dropLast(4)) }
        return factories[base] != nil ? base : nil
    }
}

/// 互換モジュールのインスタンスを持つ場所。ゴーストの SAORI の読み込み口（SaoriManager）ごとに 1 つ、
/// Direct SSTP 用（ゴーストなし）に 1 つある。DLL として load したものと Direct SSTP のものは状態を共有しない。
final class CompatSaoriHost {
    /// Direct SSTP からの呼び出し用。Ourin では Direct SSTP の呼び出し元ゴーストが分からないので「ゴーストなし」。
    static let directSSTP = CompatSaoriHost()

    private var instances: [String: CompatSaoriModule] = [:]
    private let lock = NSLock()
    private var ghostRoot: URL?
    private var deliverEvent: ((String, [String: String]) -> Void)?

    init(ghostRoot: URL? = nil, deliverEvent: ((String, [String: String]) -> Void)? = nil) {
        self.ghostRoot = ghostRoot
        self.deliverEvent = deliverEvent
    }

    /// 呼び出し元ゴーストを設定する。ゴーストが変わったら、それまでのインスタンスは捨てる。
    func configure(ghostRoot: URL?, deliverEvent: ((String, [String: String]) -> Void)?) {
        unloadAll()
        lock.lock(); defer { lock.unlock() }
        self.ghostRoot = ghostRoot
        self.deliverEvent = deliverEvent
    }

    private func key(_ module: String) -> String {
        module.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    /// モジュールを用意する（DLL の load に当たる。houchi・hanayu などはここで動き出す）。
    @discardableResult
    func load(module: String) -> CompatSaoriModule? {
        guard let name = CompatSaoriRegistry.compatName(module), let factory = CompatSaoriRegistry.factories[name] else { return nil }
        lock.lock()
        if let existing = instances[key(module)] {
            lock.unlock()
            return existing
        }
        let environment = environment(for: module)
        lock.unlock()
        // モジュールの初期化（ファイルの読み込みやタイマーの開始）はロックの外で行う。
        let instance = factory(environment)
        lock.lock(); defer { lock.unlock() }
        if let existing = instances[key(module)] {
            instance.unload()
            return existing
        }
        instances[key(module)] = instance
        return instance
    }

    func unload(module: String) {
        lock.lock()
        let instance = instances.removeValue(forKey: key(module))
        lock.unlock()
        instance?.unload()
    }

    func unloadAll() {
        lock.lock()
        let all = Array(instances.values)
        instances.removeAll()
        lock.unlock()
        for instance in all { instance.unload() }
    }

    var loadedModuleKeys: [String] {
        lock.lock(); defer { lock.unlock() }
        return instances.keys.sorted()
    }

    /// DLL の置き場所。絶対パスならその親、相対パスならゴーストのフォルダからの親。Direct SSTP の名前（.dll なし）はゴーストのフォルダ。
    private func environment(for module: String) -> CompatSaoriEnvironment {
        let normalized = module.replacingOccurrences(of: "\\", with: "/")
        let parent = (normalized as NSString).deletingLastPathComponent
        var directory: URL?
        if normalized.hasPrefix("/") {
            directory = URL(fileURLWithPath: parent, isDirectory: true)
        } else if let root = ghostRoot {
            directory = parent.isEmpty ? root : root.appendingPathComponent(parent, isDirectory: true)
        }
        let deliver = deliverEvent
        return CompatSaoriEnvironment(
            ghostRoot: ghostRoot,
            moduleDirectory: directory?.standardizedFileURL,
            deliverEvent: deliver.map { send in
                { name, references in
                    var params: [String: String] = [:]
                    for (index, value) in references.enumerated() { params["Reference\(index)"] = value }
                    send(name, params)
                }
            }
        )
    }

    // MARK: - 要求の処理

    /// SAORI/1.0 の要求文字列を処理して、応答の文字列を返す。
    func handle(module: String, requestText: String, charset: String) -> String {
        guard let request = try? SaoriProtocol.parseRequest(requestText) else {
            return SaoriProtocol.buildResponse(Self.response(.badRequest, charset: charset))
        }
        return SaoriProtocol.buildResponse(handle(module: module, request: request, defaultCharset: charset))
    }

    func handle(module: String, request: SaoriRequest, defaultCharset: String = "UTF-8") -> SaoriResponse {
        let charset = request.headerValue("Charset") ?? defaultCharset
        guard let instance = load(module: module) else {
            return Self.response(CompatSaoriResult(status: 400, error: "unknown module"), charset: charset)
        }
        if request.method.uppercased() == "GET", request.target?.lowercased() == "version" {
            return Self.response(.ok("Ourin Compat"), charset: charset)
        }
        guard request.method.uppercased() == "EXECUTE" else {
            return Self.response(.badRequest, charset: charset)
        }
        var arguments: [String] = []
        while let value = request.headerValue("Argument\(arguments.count)") { arguments.append(value) }
        return Self.response(instance.execute(arguments, charset: charset), charset: charset)
    }

    static func response(_ result: CompatSaoriResult, charset: String) -> SaoriResponse {
        var headers: [String: String] = ["Charset": charset]
        if result.status == 200 {
            headers["Result"] = result.result ?? ""
            for (index, value) in result.values.enumerated() { headers["Value\(index)"] = value }
        } else if let error = result.error {
            headers["ErrorDescription"] = error
        }
        return SaoriResponse(version: "SAORI/1.0", statusCode: result.status,
                             statusMessage: SaoriProtocol.statusMessage(for: result.status), headers: headers, body: nil)
    }

    // MARK: - 共通の道具

    /// C の atoi / wcstoul のように、先頭の数字だけを読む（数字でなければ 0）。
    static func leadingInteger(_ text: String) -> Int {
        var digits = ""
        var iterator = text.trimmingCharacters(in: .whitespaces).makeIterator()
        var sign = 1
        if var first = iterator.next() {
            if first == "-" || first == "+" {
                sign = first == "-" ? -1 : 1
                guard let next = iterator.next() else { return 0 }
                first = next
            }
            var current: Character? = first
            while let character = current, character.isASCII, character.isNumber {
                digits.append(character)
                current = iterator.next()
            }
        }
        return (Int(digits.prefix(18)) ?? 0) * sign
    }
}

/// テストで差し替えるための外部とのつなぎ目（クリップボード・ネットワーク・入力の放置時間・音声の再生）。
enum CompatSaoriHooks {
    static var writeClipboard: (String) -> Bool = { text in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// URL の中身と、Content-Type の charset。取れなければ nil。
    static var fetch: (URL) -> (data: Data, charset: String?)? = { url in CompatNetwork.fetch(url) }

    /// インターネットにつながっているか。
    static var isOnline: () -> Bool = { CompatNetwork.isOnline() }

    /// 最後のユーザー入力からの秒数（システム全体）。
    static var idleSeconds: () -> Double = {
        guard let anyInput = CGEventType(rawValue: ~UInt32(0)) else { return 0 }
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        return seconds.isFinite && seconds >= 0 ? seconds : 0
    }

    static var makeAudioPlayer: (URL) -> CompatAudioPlayer? = { url in CompatSystemAudioPlayer(url: url) }

    /// hanayu のグラフの窓を開く・閉じる（テストでは窓を出さない）。
    static var presentGraph: (CompatHanayuGraph, String) -> Void = { graph, key in CompatHanayuWindows.shared.show(graph, key: key) }
    static var dismissGraph: (String) -> Bool = { key in CompatHanayuWindows.shared.close(key: key) }
}

