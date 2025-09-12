import Foundation

/// Codable request sent to yaya_core helper.
struct YayaRequest: Codable {
    let cmd: String
    let ghost_root: String?
    let dic: [String]?
    let encoding: String?
    let env: [String:String]?
    let method: String?
    let id: String?
    let headers: [String:String]?
    let ref: [String]?
}

/// Codable response returned from yaya_core helper.
struct YayaResponse: Codable {
    let ok: Bool
    let status: Int
    let headers: [String:String]?
    let value: String?
    let error: String?
}

/// Adapter that communicates with YAYA core via JSON line IPC.
/// Adapter that communicates with YAYA core via JSON line IPC.
final class YayaAdapter {
    private var proc = Process()
    private var inPipe = Pipe()
    private var outPipe = Pipe()

    /// Create adapter. The helper executable is searched in the app bundle by default.
    init?() {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "yaya_core") else {
            NSLog("[YayaAdapter] Could not locate yaya_core executable in bundle")
            return nil
        }
        proc.executableURL = url
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        do {
            try proc.run()
            NSLog("[YayaAdapter] Launched yaya_core at \(url.path)")
        } catch {
            NSLog("[YayaAdapter] Failed to launch yaya_core at \(url.path): \(error)")
            return nil
        }
    }

    /// Send encodable object as one JSON line.
    private func send<T: Encodable>(_ obj: T) throws {
        let data = try JSONEncoder().encode(obj)
        inPipe.fileHandleForWriting.write(data)
        inPipe.fileHandleForWriting.write(Data([0x0a]))
    }

    /// Read a single line from helper.
    private func readLine() throws -> Data? {
        var buf = Data()
        let h = outPipe.fileHandleForReading
        while true {
            let d = h.readData(ofLength: 1)
            if d.isEmpty { break }
            if d == Data([0x0a]) { break }
            buf.append(d)
        }
        return buf.isEmpty ? nil : buf
    }

    /// Send request and decode response.
    private func exchange(_ req: YayaRequest) throws -> YayaResponse? {
        try send(req)
        guard let line = try readLine() else { return nil }
        return try JSONDecoder().decode(YayaResponse.self, from: line)
    }

    /// Load dictionaries for a ghost and perform capability handshake.
    func load(ghostRoot: URL, dics: [String], encoding: String = "utf-8") -> Bool {
        let req = YayaRequest(cmd: "load", ghost_root: ghostRoot.path, dic: dics, encoding: encoding, env: ["LANG":"ja_JP.UTF-8"], method: nil, id: nil, headers: ["Charset":"UTF-8"], ref: nil)
        guard (try? exchange(req)?.ok) == true else { return false }
        _ = capability()
        return true
    }

    /// Send SHIORI request.
    func request(method: String, id: String, headers: [String:String] = [:], refs: [String] = []) -> YayaResponse? {
        let req = YayaRequest(cmd: "request", ghost_root: nil, dic: nil, encoding: nil, env: nil, method: method, id: id, headers: headers, ref: refs)
        return try? exchange(req)
    }

    /// Query adapter capability using SHIORI GET.
    @discardableResult
    func capability() -> YayaResponse? {
        request(method: "GET", id: "capability")
    }

    /// Unload current dictionaries and terminate helper.
    func unload() {
        let req = YayaRequest(cmd: "unload", ghost_root: nil, dic: nil, encoding: nil, env: nil, method: nil, id: nil, headers: nil, ref: nil)
        _ = try? exchange(req)
        proc.terminate()
    }
}

/// Build GET request headers following SHIORI/3.0M rules.
func buildGET(id: String, refs: [String]) -> Data {
    var headers = ["ID": id, "Charset": "UTF-8", "Sender": "Ourin"]
    for (i, r) in refs.enumerated() { headers["Reference\(i)"] = r }
    let ordered = headers.keys.sorted().map { "\($0): \(headers[$0]!)\r\n" }.joined()
    return Data((ordered + "\r\n").utf8)
}
