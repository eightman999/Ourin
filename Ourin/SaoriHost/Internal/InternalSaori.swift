import Foundation

// SAORI over DirectSSTP と内蔵モジュール（UKADOC 2.9.13〜）。
// https://ssp.shillest.net/ukadoc/manual/spec_saori_ex.html
//
// `internal_` で始まる名前のモジュールをベースウェア自身が実装する。DLL としては読み込めず、
// Direct SSTP（Ourin では XPC）と、SHIORI（YAYA の FUNCTIONEX、里々）からの呼び出しだけを受け付ける。

/// 失敗。`description` は応答の ErrorDescription ヘッダに入る固定の英語の文字列。
struct InternalSaoriError: Error, Equatable {
    var status: Int
    var description: String

    static func badRequest(_ description: String) -> InternalSaoriError { .init(status: 400, description: description) }
    static func failed(_ description: String) -> InternalSaoriError { .init(status: 500, description: description) }

    static let invalidParameter = badRequest("invalid parameter")
    static let unknownModule = badRequest("unknown module")
    static let unknownFunction = badRequest("unknown function")
    static let ghostRequired = badRequest("ghost required")
    static let directSSTPOnly = badRequest("direct sstp only")
    static let invalidEncoding = badRequest("invalid encoding")
    static let outOfRange = badRequest("out of range")
    static let tooLarge = badRequest("too large")
    static let unsupportedAlgorithm = badRequest("unsupported algorithm")
    static let notText = failed("not text")
    static let internalError = failed("internal error")
}

/// 関数の結果。`result` が空で `values` も無ければ 204。
struct InternalSaoriResult: Equatable {
    var result: String
    var values: [String] = []

    init(_ result: String, values: [String] = []) {
        self.result = result
        self.values = values
    }
}

/// 呼び出し元のゴーストに依存する情報。`ghostRoot` が nil なら「ゴーストなし」。
struct InternalSaoriContext {
    /// ゴーストの基準フォルダ（ghost/master）。相対パスの基準にする。
    var ghostRoot: URL?
    /// `--async` の結果をゴーストへイベントで届ける。ゴーストが終了していれば何もしない。
    var deliverEvent: ((String, [String: String]) -> Void)?

    static let none = InternalSaoriContext(ghostRoot: nil, deliverEvent: nil)

    var hasGhost: Bool { ghostRoot != nil }
}

/// 位置引数と、その後ろのオプション（`--名前=値`）に分けた呼び出し。
struct InternalSaoriCall {
    var positionals: [String]
    /// 小文字にした名前 → 値。同じ名前は後のものが有効。
    var options: [String: String]

    func option(_ name: String) -> String? { options[name] }
}

struct InternalSaoriFunction {
    var name: String
    /// 位置引数の数（必須の数, 全体の数）。省略できる位置引数を飛ばすときは空の引数を置く。
    var required: Int
    var total: Int
    /// 受け付けるオプション名（小文字）。`async` はどの関数でも受け付ける。
    var options: Set<String> = []
    var handler: (InternalSaoriCall, InternalSaoriContext) throws -> InternalSaoriResult

    init(_ name: String, positionals: Int, options: Set<String> = [],
         handler: @escaping (InternalSaoriCall, InternalSaoriContext) throws -> InternalSaoriResult) {
        self.init(name, required: positionals, total: positionals, options: options, handler: handler)
    }

    init(_ name: String, required: Int, total: Int, options: Set<String> = [],
         handler: @escaping (InternalSaoriCall, InternalSaoriContext) throws -> InternalSaoriResult) {
        self.name = name
        self.required = required
        self.total = total
        self.options = options
        self.handler = handler
    }
}

protocol InternalSaoriModule {
    /// 正規の名前（小文字。`internal_` で始まる）。
    var name: String { get }
    var functions: [InternalSaoriFunction] { get }
}

final class InternalSaoriRegistry {
    /// 標準のモジュール一式。
    static let shared = InternalSaoriRegistry(modules: InternalSaoriRegistry.standardModules())

    private var modules: [String: InternalSaoriModule] = [:]
    private let lock = NSLock()

    /// 非同期呼び出しを動かすキュー。同時に動かすのは CPU の数ほど（2〜4）まで。
    private static let asyncQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "jp.ourin.internal-saori"
        queue.maxConcurrentOperationCount = max(2, min(4, ProcessInfo.processInfo.activeProcessorCount))
        queue.qualityOfService = .utility
        return queue
    }()

    init(modules: [InternalSaoriModule]) {
        for module in modules { register(module) }
    }

    func register(_ module: InternalSaoriModule) {
        lock.lock(); defer { lock.unlock() }
        modules[module.name.lowercased()] = module
    }

    /// `internal_` で始まる名前か（大文字小文字は区別しない）。互換モジュールは含まない。
    static func isInternalName(_ name: String) -> Bool {
        name.lowercased().hasPrefix("internal_")
    }

    func module(named name: String) -> InternalSaoriModule? {
        lock.lock(); defer { lock.unlock() }
        return modules[name.lowercased()]
    }

    var moduleNames: [String] {
        lock.lock(); defer { lock.unlock() }
        return modules.values.map(\.name).sorted()
    }

    // MARK: - 要求の処理

    /// SAORI/1.0 の要求文字列を処理して、応答の文字列を返す。
    func handle(requestText: String, context: InternalSaoriContext = .none) -> String {
        let request: SaoriRequest
        do {
            request = try SaoriProtocol.parseRequest(requestText)
        } catch {
            return SaoriProtocol.buildResponse(Self.errorResponse(.invalidParameter, charset: "UTF-8"))
        }
        return SaoriProtocol.buildResponse(handle(request: request, context: context))
    }

    func handle(request: SaoriRequest, context: InternalSaoriContext = .none) -> SaoriResponse {
        let charset = request.headerValue("Charset") ?? "UTF-8"
        guard let moduleName = request.headerValue("Module")?.trimmingCharacters(in: .whitespaces), !moduleName.isEmpty else {
            return Self.errorResponse(.invalidParameter, charset: charset)
        }
        guard let module = module(named: moduleName) else {
            return Self.errorResponse(.unknownModule, charset: charset)
        }

        // 機能の判定。使えれば 200 OK。
        if request.method.uppercased() == "GET", request.target?.lowercased() == "version" {
            return Self.successResponse(InternalSaoriResult("Ourin Internal"), charset: charset)
        }
        guard request.method.uppercased() == "EXECUTE" else {
            return Self.errorResponse(.invalidParameter, charset: charset)
        }

        var arguments: [String] = []
        while let value = request.headerValue("Argument\(arguments.count)") { arguments.append(value) }
        guard let functionName = arguments.first, !functionName.isEmpty else {
            return Self.errorResponse(.invalidParameter, charset: charset)
        }
        guard let function = module.functions.first(where: { $0.name.lowercased() == functionName.lowercased() }) else {
            return Self.errorResponse(.unknownFunction, charset: charset)
        }

        let call: InternalSaoriCall
        do {
            call = try Self.parse(arguments: Array(arguments.dropFirst()), for: function)
        } catch let error as InternalSaoriError {
            return Self.errorResponse(error, charset: charset)
        } catch {
            return Self.errorResponse(.internalError, charset: charset)
        }

        if let asyncID = call.option("async") {
            return startAsync(id: asyncID, module: module, function: function, call: call, context: context, charset: charset)
        }
        do {
            return Self.successResponse(try function.handler(call, context), charset: charset)
        } catch let error as InternalSaoriError {
            return Self.errorResponse(error, charset: charset)
        } catch {
            return Self.errorResponse(.internalError, charset: charset)
        }
    }

    /// 引数を位置引数とオプションに分ける。
    /// 位置引数の位置にある値は `--` で始まっていてもデータとして読む。オプションは位置引数より後ろにだけ書ける。
    static func parse(arguments: [String], for function: InternalSaoriFunction) throws -> InternalSaoriCall {
        guard arguments.count >= function.required else { throw InternalSaoriError.invalidParameter }
        let positionalCount = min(function.total, arguments.count)
        let positionals = Array(arguments.prefix(positionalCount))
        var options: [String: String] = [:]
        let allowed = function.options.union(["async"])
        for argument in arguments.dropFirst(positionalCount) {
            // 位置引数より後ろにある `--` で始まらない値は不正。
            guard argument.hasPrefix("--") else { throw InternalSaoriError.invalidParameter }
            let body = argument.dropFirst(2)
            let eq = body.firstIndex(of: "=")
            let name = String(body[..<(eq ?? body.endIndex)]).lowercased()
            let value = eq.map { String(body[body.index(after: $0)...]) } ?? ""
            guard allowed.contains(name) else { throw InternalSaoriError.invalidParameter }
            options[name] = value
        }
        return InternalSaoriCall(positionals: positionals, options: options)
    }

    // MARK: - 非同期

    private func startAsync(id: String, module: InternalSaoriModule, function: InternalSaoriFunction,
                            call: InternalSaoriCall, context: InternalSaoriContext, charset: String) -> SaoriResponse {
        // ゴーストなしの呼び出しでは使えない。識別子が空なら不正。
        guard context.hasGhost, context.deliverEvent != nil else {
            return Self.errorResponse(.ghostRequired, charset: charset)
        }
        guard !id.isEmpty else { return Self.errorResponse(.invalidParameter, charset: charset) }

        let moduleName = module.name
        let functionName = function.name
        Self.asyncQueue.addOperation {
            let outcome: Result<InternalSaoriResult, InternalSaoriError>
            do {
                outcome = .success(try function.handler(call, context))
            } catch let error as InternalSaoriError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.internalError)
            }
            let event = Self.asyncEvent(id: id, module: moduleName, function: functionName, outcome: outcome)
            // 結果が届く前にゴーストが終了していたら、届けない（deliverEvent 側で確かめる）。
            context.deliverEvent?(event.name, event.references)
        }
        // 受け付けたらすぐ 204。結果はあとでイベントで届く。
        return SaoriResponse(version: "SAORI/1.0", statusCode: 204, statusMessage: "No Content",
                             headers: ["Charset": charset], body: nil)
    }

    /// 非同期の結果を届けるイベント。識別子が On で始まれば成功時はその名前、失敗時は ID+Failure。
    /// そうでなければ OnInternalSaoriComplete / OnInternalSaoriFailure。
    static func asyncEvent(id: String, module: String, function: String,
                           outcome: Result<InternalSaoriResult, InternalSaoriError>) -> (name: String, references: [String: String]) {
        let custom = id.hasPrefix("On")
        switch outcome {
        case .success(let result):
            var references = [
                "Reference0": id, "Reference1": result.result, "Reference2": module, "Reference3": function
            ]
            for (index, value) in result.values.enumerated() { references["Reference\(4 + index)"] = value }
            return (custom ? id : "OnInternalSaoriComplete", references)
        case .failure(let error):
            return (custom ? id + "Failure" : "OnInternalSaoriFailure", [
                "Reference0": id, "Reference1": error.description, "Reference2": module, "Reference3": function
            ])
        }
    }

    // MARK: - 応答

    static func successResponse(_ result: InternalSaoriResult, charset: String) -> SaoriResponse {
        var headers: [String: String] = ["Charset": charset]
        if result.result.isEmpty && result.values.isEmpty {
            return SaoriResponse(version: "SAORI/1.0", statusCode: 204, statusMessage: "No Content", headers: headers, body: nil)
        }
        headers["Result"] = result.result
        for (index, value) in result.values.enumerated() { headers["Value\(index)"] = value }
        return SaoriResponse(version: "SAORI/1.0", statusCode: 200, statusMessage: "OK", headers: headers, body: nil)
    }

    static func errorResponse(_ error: InternalSaoriError, charset: String) -> SaoriResponse {
        SaoriResponse(
            version: "SAORI/1.0",
            statusCode: error.status,
            statusMessage: error.status == 400 ? "Bad Request" : "Internal Server Error",
            headers: ["Charset": charset, "ErrorDescription": error.description],
            body: nil
        )
    }
}

/// SAORI/1.0 の要求かどうか（Direct SSTP だけで受け付けるため、受信口で見分ける）。
enum InternalSaoriRouting {
    static func isSaoriRequest(_ text: String) -> Bool {
        guard let firstLine = text.split(whereSeparator: \.isNewline).first else { return false }
        let upper = firstLine.uppercased()
        return upper.hasPrefix("EXECUTE ") && upper.contains("SAORI/") || upper.hasPrefix("GET ") && upper.contains("SAORI/")
    }

    /// Direct SSTP で受け取った SAORI/1.0 の要求を内蔵モジュールで処理し、要求の Charset の文字コードで応答する。
    /// Direct SSTP の呼び出し元ゴーストは分からないので「ゴーストなし」として扱う。
    static func respond(to text: String) -> Data {
        let response = InternalSaoriRegistry.shared.handle(requestText: text, context: .none)
        let charset = (try? SaoriProtocol.parseRequest(text))?.headerValue("Charset") ?? "UTF-8"
        return (try? SaoriProtocol.encode(response, charset: charset)) ?? Data(response.utf8)
    }

    /// Direct SSTP 以外（TCP・HTTP など）で受け取った SAORI/1.0 の要求への応答。
    static var directSSTPOnlyResponse: String {
        SaoriProtocol.buildResponse(InternalSaoriRegistry.errorResponse(.directSSTPOnly, charset: "UTF-8"))
    }
}
