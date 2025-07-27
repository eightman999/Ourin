// OurinSstpTcpServer.swift
import Foundation
import Network

public final class OurinSstpTcpServer {
    private var listener: NWListener?
    public var onRequest: ((String) -> String)? // input: raw SSTP, output: raw response

    public init() {}

    public func start(host: String = "127.0.0.1", port: UInt16 = 9801) throws {
        let params = NWParameters.tcp
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener?.stateUpdateHandler = { state in
            print("[SSTP-TCP] listener state: \(state)")
        }
        listener?.newConnectionHandler = { [weak self] conn in
            guard let self else { return }
            conn.stateUpdateHandler = { state in
                print("[SSTP-TCP] conn: \(state)")
            }
            conn.start(queue: .global())
            self.receive(on: conn)
        }
        listener?.start(queue: .main)
        print("[SSTP-TCP] Listening on \(host):\(port)")
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(on conn: NWConnection) {
        var buffer = Data()
        func loop() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                    if let range = buffer.range(of: Data([13,10,13,10])) { // CRLFCRLF
                        let header = buffer.subdata(in: 0..<range.lowerBound)
                        if let text = Self.decode(header) {
                            let resp = self.onRequest?(text) ?? "SSTP/1.1 204 No Content\r\n\r\n"
                            conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in
                                conn.cancel()
                            })
                            return
                        }
                    }
                }
                if isComplete || error != nil {
                    conn.cancel()
                    return
                }
                loop()
            }
        }
        loop()
    }

    private static func decode(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .shiftJIS)
    }
}
