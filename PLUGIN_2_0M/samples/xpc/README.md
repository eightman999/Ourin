# xpc

PLUGIN/2.0M を **XPC サービス**で隔離実行するための骨組み。

- `PluginWorker.xpc` が `request(Data) -> Data` のラウンドトリップを提供
- ホストは `.plugin` をロードせず、XPC サービスに **ワイヤ文字列（UTF-8）**の往復を委譲
- 例外やクラッシュは XPC 側に閉じ込められる

> これは骨組みであり、Xcode の「XPC Service」テンプレートを使ったターゲット追加が必要です。
