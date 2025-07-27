import Foundation

@objc public protocol OurinShioriXPC {
    func execute(_ request: Data, withReply reply: @escaping (Data)->Void)
}
