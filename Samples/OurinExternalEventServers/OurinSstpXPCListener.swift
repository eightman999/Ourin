// OurinSstpXPCListener.swift
import Foundation

public final class OurinSstpXPCListener: NSObject, NSXPCListenerDelegate, OurinSstpXPCProtocol {
    private let listener: NSXPCListener
    public var onRequest: ((String) -> String)? // raw SSTP -> raw SSTP response

    public init(machServiceName: String = "jp.ourin.sstp") {
        self.listener = NSXPCListener(machServiceName: machServiceName)
        super.init()
        self.listener.delegate = self
    }

    public func start() {
        listener.resume()
        print("[SSTP-XPC] Listening (mach service)")
    }

    // MARK: - NSXPCListenerDelegate
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: OurinSstpXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.resume()
        return true
    }

    // MARK: - OurinSstpXPCProtocol
    public func deliverSSTP(_ request: Data, with reply: @escaping (Data) -> Void) {
        let str = String(data: request, encoding: .utf8)
            ?? String(data: request, encoding: .shiftJIS)
            ?? ""
        let resp = onRequest?(str) ?? "SSTP/1.1 204 No Content\r\n\r\n"
        reply(Data(resp.utf8))
    }
}
