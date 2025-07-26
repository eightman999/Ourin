import Foundation

final class PluginWorkerImpl: NSObject, PluginWorker {
    func roundTrip(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        // ここで .plugin を別プロセスでロードしてもよいし、
        // あるいはネイティブ実装を直接呼んでもよい。
        // デモとして "200 OK" を固定応答。
        let resp = """
        PLUGIN/2.0M 200 OK
        Charset: UTF-8

        """.data(using: .utf8)!
        reply(resp)
    }
}

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    let impl = PluginWorkerImpl()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: PluginWorker.self)
        newConnection.exportedObject = impl
        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
