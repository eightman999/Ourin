# XPC Skeleton（任意）
SHIORI 実行を別プロセス化する場合の最小 IF:
```swift
@objc public protocol OurinShioriXPC {
    func execute(_ request: Data, withReply reply: @escaping (Data)->Void)
}
```
- XPC サービスに `exportedInterface` として登録し、Host は `NSXPCConnection` で接続します。
