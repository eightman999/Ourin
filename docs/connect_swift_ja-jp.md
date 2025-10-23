# yaya_core から Swift 製プラグインを扱う手順

本書では、`yaya_core`（C++ 製ヘルパー実行ファイル）から macOS ネイティブの Swift プラグイン（`.plugin` / `.bundle`）をロードし、SHIORI/PLUGIN プロトコルのやり取りを行うための手順を整理します。すべて UTF-8 を既定とし、記述は日本語で統一しています。

## 1. 全体像

1. Swift で PLUGIN/2.0M 仕様に準拠したロード可能バンドルを用意する。
2. バンドルをアプリの `Ourin.app/Contents/PlugIns/` など既定ディレクトリへ配置する。
3. `yaya_core` が CFBundle API を介してプラグインをロードし、`load` / `request` / `unload` を呼び出す。
4. PLUGIN で返されたワイヤ文字列を `yaya_core` 側でパースし、JSON IPC 応答として Swift 層へ返す。

Swift プラグインは Swift コードで実装されますが、エクスポートは C ABI で提供されるため、`yaya_core`（C++）からも透過的に呼び出すことができます。

## 2. Swift プラグインの要件

### 2.1 ターゲット設定

- Xcode で **Bundle（Mach-O Type: Bundle）** を選択し、出力拡張子を `.plugin` に設定します。
- **Architectures:** `arm64` / `x86_64`（Universal 2）を有効にすること。
- **Deployment Target:** macOS 10.15 以上。

### 2.2 エクスポート関数

Swift コードからは `@_cdecl` で C ABI の関数を公開します。

```swift
@_cdecl("load")
public func pluginLoad(_ pluginDir: UnsafePointer<CChar>) -> Int32 {
    // 初期化処理（必要ならバンドルパス解析など）
    return 0
}

@_cdecl("request")
public func pluginRequest(_ bytes: UnsafePointer<UInt8>, _ length: Int, _ outLength: UnsafeMutablePointer<Int>) -> UnsafePointer<UInt8>? {
    let data = Data(bytes: bytes, count: length)
    guard let response = handleWire(String(decoding: data, as: UTF8.self)) else {
        outLength.pointee = 0
        return nil
    }
    let utf8 = Array(response.utf8)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: utf8.count)
    _ = buffer.initialize(from: utf8, count: utf8.count)
    outLength.pointee = utf8.count
    return UnsafePointer(buffer)
}

@_cdecl("unload")
public func pluginUnload() {
    // 後始末
}
@_cdecl("plugin_free")
public func pluginFree(_ pointer: UnsafeMutablePointer<UInt8>?) {
    pointer?.deallocate()
}
```

> **メモ:** `request` から返すバッファはライフサイクル管理が重要です。コピーして返す場合は、`plugin_free` を併せて公開し `yaya_core` 側が解放できるようにします。

## 3. プラグインの配置

- `Ourin.app` バンドル配下の `Contents/PlugIns/` に配置するのが推奨です。
- プラグインバンドル内には最低限 `Contents/Info.plist` と `Contents/MacOS/<Executable>`、`Contents/Resources/descript.txt` を含めます。
- `descript.txt` の `filename` は `.plugin` を指定し、文字コードは UTF-8 を推奨します。

## 4. yaya_core 側でのロード処理

C++17 以降で CoreFoundation をリンクし、`CFBundle` API を利用します。以下は概念的なコード断片です。

```cpp
#include <CoreFoundation/CoreFoundation.h>

struct PluginHandle {
    CFBundleRef bundle;
    using LoadFn = int32_t(*)(const char*);
    using RequestFn = const unsigned char*(*)(const unsigned char*, size_t, size_t*);
    using UnloadFn = void(*)();

    LoadFn load = nullptr;
    RequestFn request = nullptr;
    UnloadFn unload = nullptr;
};

PluginHandle loadPlugin(const std::string& path) {
    PluginHandle handle{};
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, CFStringCreateWithCString(nullptr, path.c_str(), kCFStringEncodingUTF8), kCFURLPOSIXPathStyle, true);
    handle.bundle = CFBundleCreate(kCFAllocatorDefault, url);
    CFRelease(url);
    if (!handle.bundle || !CFBundleLoadExecutable(handle.bundle)) {
        throw std::runtime_error("Failed to load plugin bundle");
    }
    handle.request = reinterpret_cast<PluginHandle::RequestFn>(CFBundleGetFunctionPointerForName(handle.bundle, CFSTR("request")));
    handle.load = reinterpret_cast<PluginHandle::LoadFn>(CFBundleGetFunctionPointerForName(handle.bundle, CFSTR("load")));
    handle.unload = reinterpret_cast<PluginHandle::UnloadFn>(CFBundleGetFunctionPointerForName(handle.bundle, CFSTR("unload")));
    if (!handle.request) {
        throw std::runtime_error("request symbol missing");
    }
    return handle;
}
```

### 4.1 ライフサイクル

1. `load()` が存在する場合はバンドルディレクトリ（UTF-8 パス）を渡して初期化します。
2. `request()` でワイヤ文字列（CRLF + 空行終端）を UTF-8 バイト列として渡します。
3. `unload()` が存在する場合は終了処理で必ず呼び出します。
4. `CFBundleUnloadExecutable` と `CFRelease` でバンドルを解放します。

## 5. ワイヤ ↔ JSON 変換

- プラグインとの通信は **PLUGIN/2.0M** のワイヤ文字列です。
- `yaya_core` はこれを受け取り、SHIORI レイヤで `status` や `Value` を抽出して JSON IPC 形式にマッピングします。
- 例: Swift プラグインが `PLUGIN/2.0M 200 OK` を返した場合、`yaya_core` は `{ "ok": true, "status": 200, ... }` へ変換します。

## 6. エラー処理とデバッグ

- シンボル取得に失敗した場合は即座にアンロードし、JSON IPC でエラーを返す。
- `request()` の戻り値が `nullptr` の場合は `500` 相当のエラーとして扱う。
- Xcode の `DYLD_PRINT_LIBRARIES` や `CFBundleCopyBundleURL` でロード状況を確認できます。
- ログは JSON 形式で出力し、Swift 側・`yaya_core` 側で突き合わせます。

## 7. マルチアーキテクチャ対応

- プラグインと `yaya_core` の両方を Universal 2 でビルドし、Rosetta 実行時の不整合を避けます。
- `lipo -info MyPlugin.plugin/Contents/MacOS/MyPlugin` でアーキテクチャを確認します。

## 8. テスト戦略

1. **単体テスト:** Swift プラグイン側で `request()` の入出力を XCTest で検証。
2. **結合テスト:** `yaya_core` から実際にロードして JSON IPC 経由で応答を確認するスクリプトを整備。
3. **ロングラン:** プラグインを連続ロード/アンロードし、メモリリークが発生しないかを Instruments で監視します。

---

以上が `yaya_core` から Swift 製プラグインを安全に扱うための手順です。実装時には `SPEC_PLUGIN_2.0M.md` や `OURIN_YAYA_ADAPTER_SPEC_1.0M.md` の規定も併せて参照し、ワイヤ仕様や IPC の整合性を確認してください。
