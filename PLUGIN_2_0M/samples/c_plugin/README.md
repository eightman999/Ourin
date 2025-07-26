# c_plugin

最小の PLUGIN/2.0M プラグイン（C, iconv 使用）。

- `ID: version` に `Value:` を返す
- `ID: OnMenuExec` に簡易スクリプトを返す
- `ID: OnSecondChange` は `204 No Content`
- `Charset:` が `Shift_JIS` / `Windows-31J` 等なら **CP932 -> UTF-8** に変換して処理

## ビルド（CMake）
```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

生成物: `build/MyPlugin.plugin`

> Universal 2 は `CMAKE_OSX_ARCHITECTURES="arm64;x86_64"` で指定。Xcode 生成時も同様。
