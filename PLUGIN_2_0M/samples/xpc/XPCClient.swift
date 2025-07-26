import Foundation

public final class XPCClient {
    private let connection: NSXPCConnection
    private let remote: PluginWorker

    public init(serviceName: String) {
        connection = NSXPCConnection(serviceName: serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: PluginWorker.self)
        connection.resume()
        remote = connection.remoteObjectProxyWithErrorHandler { err in
            NSLog("XPC error: %@", err.localizedDescription)
        } as! PluginWorker
    }

    public func send(text: String, completion: @escaping (String) -> Void) {
        remote.roundTrip(Data(text.utf8)) { data in
            completion(String(decoding: data, as: UTF8.self))
        }
    }
}
