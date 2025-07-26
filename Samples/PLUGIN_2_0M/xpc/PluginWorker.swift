import Foundation

@objc public protocol PluginWorker {
    func roundTrip(_ request: Data, withReply reply: @escaping (Data) -> Void)
}
