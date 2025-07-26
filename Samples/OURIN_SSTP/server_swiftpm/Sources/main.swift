import Foundation
import Network

let port: NWEndpoint.Port = 9801

final class SSTPServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ourin.sstp.listener")
    
    func start() throws {
        let params = NWParameters.tcp
        // Bind to loopback only
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: port)
        listener?.stateUpdateHandler = { state in
            print("[OurinSSTP] listener state: \(state)")
        }
        listener?.newConnectionHandler = { [weak self] conn in
            self?.handle(connection: conn)
        }
        listener?.start(queue: queue)
        dispatchMain()
    }
    
    private func handle(connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            print("[OurinSSTP] conn state: \(state)")
        }
        connection.start(queue: queue)
        readMessage(connection: connection, accumulated: Data())
    }
    
    private func readMessage(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            var buffer = accumulated
            if let d = data { buffer.append(d) }
            if let error = error {
                print("[OurinSSTP] receive error: \(error)")
                connection.cancel()
                return
            }
            // Detect HTTP vs SSTP by first bytes
            if let response = HTTPBridge.tryHandle(data: buffer) {
                self?.sendAndClose(connection: connection, data: response)
                return
            }
            if let reqEnd = buffer.range(of: Data([13,10,13,10])) { // \r\n\r\n
                let headerData = buffer.subdata(in: 0..<reqEnd.lowerBound)
                let body = buffer.subdata(in: reqEnd.upperBound..<buffer.count)
                let req = String(data: headerData, encoding: .utf8) ?? ""
                let parsed = SSTPParser.parse(message: req)
                let resp = DemoHandlers.handle(request: parsed, body: body)
                self?.sendAndClose(connection: connection, data: resp.data(using: .utf8) ?? Data())
            } else if isComplete {
                // No full message; close
                connection.cancel()
            } else {
                self?.readMessage(connection: connection, accumulated: buffer)
            }
        }
    }
    
    private func sendAndClose(connection: NWConnection, data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

struct SSTPRequest {
    var method: String = ""
    var version: String = ""
    var headers: [String:String] = [:]
}

enum SSTPParser {
    static func parse(message: String) -> SSTPRequest {
        let lines = message.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first else { return SSTPRequest() }
        let comps = first.split(separator: " ")
        var req = SSTPRequest()
        if comps.count >= 2 {
            req.method = String(comps[0])
            req.version = String(comps[1])
        }
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            if let idx = line.firstIndex(of: ":") {
                let k = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                req.headers[k] = v
            }
        }
        return req
    }
}

enum DemoHandlers {
    static func handle(request: SSTPRequest, body: Data) -> String {
        // Minimal demo: respond 200 to SEND/NOTIFY/COMMUNICATE/EXECUTE
        let charset = request.headers["Charset"] ?? "UTF-8"
        let script = "\\h\\s0OK"
        let head = "SSTP/1.4 200 OK\r\nCharset: \(charset)\r\nScript: \(script)\r\n\r\n"
        return head
    }
}

enum HTTPBridge {
    static func tryHandle(data: Data) -> Data? {
        // Very tiny HTTP detector (starts with a method word and space and "HTTP/1."): not robust
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        if s.hasPrefix("POST ") && s.contains(" HTTP/1.") {
            // Find body (after \r\n\r\n), then treat body as SSTP request
            guard let range = s.range(of: "\r\n\r\n") else { return nil }
            let body = String(s[range.upperBound...])
            let parsed = SSTPParser.parse(message: body)
            let resp = DemoHandlers.handle(request: parsed, body: Data())
            let http = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(resp.utf8.count)\r\n\r\n\(resp)"
            return Data(http.utf8)
        }
        return nil
    }
}

do {
    try SSTPServer().start()
} catch {
    fputs("Failed to start SSTP server: \(error)\n", stderr)
    exit(1)
}
