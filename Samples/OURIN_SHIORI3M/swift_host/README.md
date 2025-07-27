# OurinShioriHost（SwiftPM）
**SHIORI/3.0M** バンドルをロードして `GET SHIORI/3.0` を投げる最小ホスト。

## ビルド/実行
```bash
cd samples/swift_host
swift build -c release
# 実行（引数に .bundle のパス）
.build/release/ourin-shiori-host ../c_shiori/build/OurinSampleSHIORI.bundle
```
