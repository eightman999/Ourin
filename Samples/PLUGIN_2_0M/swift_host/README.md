# swift_host

`.plugin` をロードし、`request` にワイヤ文字列を投げる最小ホスト。

## 使い方

```swift
let url = URL(fileURLWithPath: "/path/to/MyPlugin.plugin")
let plugin = try Plugin(url: url)
let req = "GET PLUGIN/2.0M\r\nID: version\r\nCharset: UTF-8\r\n\r\n"
let resp = plugin.send(req)
print(resp)
```

> 同一プロセス内では **ホストとプラグインのアーキテクチャが一致**している必要があります（Universal 2 配布推奨）。
