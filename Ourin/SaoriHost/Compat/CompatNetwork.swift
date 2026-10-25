import Foundation
import Network
import SystemConfiguration

/// 互換モジュールの HTTP 取得（同期）。原作は WinINet で http も https も取れたので、平文の http も取れるようにする。
/// （URLSession は App Transport Security で平文の http を拒むので、http は Network.framework で直に話す。）
enum CompatNetwork {
    static let timeout: TimeInterval = 30
    /// 取得する大きさの上限（8MB）。
    static let maximumBytes = 8 * 1024 * 1024

    /// URL の中身と Content-Type の charset。ステータスコードによらず本文を返す（原作どおり）。取れなければ nil。
    static func fetch(_ url: URL) -> (data: Data, charset: String?)? {
        fetch(url, redirects: 5)
    }

    private static func fetch(_ url: URL, redirects: Int) -> (data: Data, charset: String?)? {
        switch url.scheme?.lowercased() {
        case "http":
            guard let response = PlainHTTP.get(url) else { return nil }
            if (300..<400).contains(response.status), redirects > 0,
               let location = response.headers["location"], let next = URL(string: location, relativeTo: url)?.absoluteURL {
                return fetch(next, redirects: redirects - 1)
            }
            return (response.body, charset(fromContentType: response.headers["content-type"]))
        case "https":
            return fetchWithURLSession(url)
        default:
            return nil
        }
    }

    private static func fetchWithURLSession(_ url: URL) -> (data: Data, charset: String?)? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("httpc_for_saori (Ourin)", forHTTPHeaderField: "User-Agent")
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: (data: Data, charset: String?)?
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if error == nil, let data, data.count <= maximumBytes {
                outcome = (data, response?.textEncodingName)
            }
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + timeout + 5) == .timedOut {
            task.cancel()
            return nil
        }
        return outcome
    }

    static func charset(fromContentType value: String?) -> String? {
        guard let value else { return nil }
        for part in value.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2, pair[0].lowercased() == "charset" {
                return pair[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    /// インターネットにつながっているか（原作の「引数なし」）。
    static func isOnline() -> Bool {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, "www.example.com") else { return false }
        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(reachability, &flags) else { return false }
        return flags.contains(.reachable) && !flags.contains(.connectionRequired)
    }
}

/// 平文の HTTP/1.1 の GET（Connection: close）。chunked と Content-Length を読む。
enum PlainHTTP {
    struct Response {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    static func get(_ url: URL) -> Response? {
        guard let host = url.host, !host.isEmpty else { return nil }
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 80)) ?? .http
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query { path += "?" + query }
        let hostHeader = url.port.map { "\(host):\($0)" } ?? host
        let request = "GET \(path) HTTP/1.1\r\nHost: \(hostHeader)\r\nUser-Agent: httpc_for_saori (Ourin)\r\nAccept: */*\r\nConnection: close\r\n\r\n"

        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let queue = DispatchQueue(label: "jp.ourin.compat.http")
        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var received = Data()
        var finished = false

        func finish() {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            semaphore.signal()
        }

        func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let data {
                    lock.lock()
                    received.append(data)
                    let tooLarge = received.count > CompatNetwork.maximumBytes + 65_536
                    lock.unlock()
                    if tooLarge { finish(); return }
                }
                if isComplete { finish(); return }
                if error != nil { finish(); return }
                receive()
            }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: Data(request.utf8), completion: .contentProcessed { error in
                    if error != nil { finish() } else { receive() }
                })
            case .failed, .cancelled, .waiting:
                // waiting はつながらない（相手が拒んだ・経路が無い）ときで、待ち続けずに失敗にする。
                finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + CompatNetwork.timeout)
        connection.cancel()
        lock.lock()
        let bytes = received
        lock.unlock()
        // 切断がエラー扱いでも、ヘッダと本文が読めていればそれを使う（Connection: close の終わり方は相手しだい）。
        return parse(bytes)
    }

    static func parse(_ bytes: Data) -> Response? {
        guard let separator = bytes.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: bytes[bytes.startIndex..<separator.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let statusLine = lines.removeFirst().split(separator: " ")
        guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/"), let status = Int(statusLine[1]) else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var body = Data(bytes[separator.upperBound...])
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            guard let decoded = dechunk(body) else { return nil }
            body = decoded
        } else if let length = headers["content-length"].flatMap({ Int($0) }), length <= body.count {
            body = body.prefix(length)
        }
        guard body.count <= CompatNetwork.maximumBytes else { return nil }
        return Response(status: status, headers: headers, body: body)
    }

    static func dechunk(_ data: Data) -> Data? {
        var output = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while index < data.endIndex {
            guard let lineEnd = data.range(of: crlf, in: index..<data.endIndex) else { return output.isEmpty ? nil : output }
            let sizeText = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self).split(separator: ";").first ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { return nil }
            if size == 0 { return output }
            let start = lineEnd.upperBound
            guard data.distance(from: start, to: data.endIndex) >= size else { return nil }
            let end = data.index(start, offsetBy: size)
            output.append(data[start..<end])
            index = data.distance(from: end, to: data.endIndex) >= 2 ? data.index(end, offsetBy: 2) : data.endIndex
        }
        return output
    }
}
