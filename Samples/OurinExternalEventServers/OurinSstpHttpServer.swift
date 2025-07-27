// OurinSstpHttpServer.swift
import Foundation
import Network

public final class OurinSstpHttpServer {
    private var listener: NWListener?
    public var onRequest: ((String) -> String)? // input: raw SSTP, output: raw SSTP response

    public init() {}

    public func start(host: String = "127.0.0.1", port: UInt16 = 9810) throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
        listener?.stateUpdateHandler = { state in
            print("[SSTP-HTTP] listener: \(state)")
        }
        listener?.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.start(queue: .global())
            self.handle(conn: conn)
        }
        listener?.start(queue: .main)
        print("[SSTP-HTTP] Listening on \(host):\(port)")
    }

    public func stop() { listener?.cancel(); listener = nil }

    private func handle(conn: NWConnection) {
        var buffer = Data()
        func readMore() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                if let d = data { buffer.append(d) }
                if isComplete || error != nil {
                    conn.cancel(); return
                }
                // look for header end
                if let headerEnd = buffer.range(of: Data([13,10,13,10])) {
                    let header = buffer.subdata(in: 0..<headerEnd.upperBound)
                    let headersText = String(data: header, encoding: .utf8) ?? ""
                    // Find Content-Length (case-insensitive)
                    var contentLength = 0
                    for rawLine in headersText.split(separator: "\n") {
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        if line.lowercased().hasPrefix("content-length:") {
                            let v = line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
                            contentLength = Int(v) ?? 0
                        }
                    }
                    let bodyStart = headerEnd.upperBound
                    if buffer.count - bodyStart >= contentLength {
                        let body = buffer.subdata(in: bodyStart..<bodyStart+contentLength)
                        if let sstp = Self.decode(body) {
                            let respSstp = self.onRequest?(sstp) ?? "SSTP/1.1 204 No Content\r\n\r\n"
                            let lines = [
                                "HTTP/1.1 200 OK\r",
                                "Content-Type: text/plain; charset=UTF-8\r",
                                "Content-Length: \(respSstp.utf8.count)\r",
                                "\r",
                                respSstp
                            ]
                            let http = lines.joined()
                            conn.send(content: http.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                            return
                        }
                    }
                }
                readMore()
            }
        }
        readMore()
    }

    private static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .shiftJIS)
    }
}
