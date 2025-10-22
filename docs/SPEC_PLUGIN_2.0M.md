# PLUGIN/2.0M — macOS ネイティブ差分仕様（Draft）
**Status:** Draft  
**Updated:** 2025-07-26  
**Audience:** ベースウェア実装者 / プラグイン作者  
**Scope:** UKADOC **PLUGIN/2.0** を母体に、macOS ネイティブで運用するための差分を規定  
**非目標:** PLUGIN/1.0 DLL のバイナリ互換（※語彙・挙動の互換のみ対象）

---

## 目次
- [1. 目的と設計方針](#1-目的と設計方針)
- [2. 用語](#2-用語)
- [3. 適用範囲と互換性](#3-適用範囲と互換性)
- [4. OS / CPU 要件](#4-os--cpu-要件)
- [5. 実体（バンドル形式）](#5-実体バンドル形式)
- [6. ワイヤプロトコル（2.0 との差分）](#6-ワイヤプロトコル20-との差分)
- [7. API（エクスポート関数・メモリ管理）](#7-apiエクスポート関数メモリ管理)
- [8. イベント分岐（実装指針）](#8-イベント分岐実装指針)
- [9. 設定ファイル（descript.txt）差分](#9-設定ファイルdescripttxt差分)
- [10. セキュリティ/安定性：XPC隔離（推奨）](#10-セキュリティ安定性xpc隔離推奨)
- [11. 例](#11-例)
- [12. 適合チェックリスト](#12-適合チェックリスト)
- [13. 既知の差分（Windows 前提語彙）](#13-既知の差分windows-前提語彙)
- [14. 付録A：DLL → .plugin ポーティング手順（最短）](#14-付録adll--plugin-ポーティング手順最短)
- [15. 付録B：ビルドレシピ（Xcode/CMake）](#15-付録bビルドレシピxcodecmake)
- [16. 付録C：最小ホストローダ（Swift）](#16-付録c最小ホストローダswift)
- [17. 参照（Normative / Informative）](#17-参照normative--informative)

---

## 1. 目的と設計方針
- **PLUGIN/2.0** の語彙・プロトコル（`GET/NOTIFY PLUGIN/2.x`・CRLF区切り・`ID/Reference*`・`Script/ScriptOption`・`Target` など）を維持しつつ、**macOS のネイティブ実体（Bundle/.plugin）**で安全に拡張できるよう差分規定する。  
- 文字コードは **UTF‑8 を既定**に改め、**JIS 系（Shift_JIS / Windows‑31J）互換**は受理する方針。  
- **1.0 互換は挙動互換**（語彙・振る舞い）に限り、**バイナリ互換は対象外**。

## 2. 用語
- **2.0M**: 本仕様の版識別子（Mac 差分）。  
- **ホスト**: ベースウェア本体（プラグインをロードする側）。  
- **プラグイン**: .plugin/.bundle で配布される拡張。  
- **ワイヤ**: `GET/NOTIFY PLUGIN/2.x` のヘッダ文法と往復。

## 3. 適用範囲と互換性
- **PLUGIN/2.0 とワイヤ互換**：行構造（CRLF 区切り/空行終端）、`ID`/`Reference*`/`Script`/`ScriptOption`/`Target` の意味論を維持する。  
- **NOTIFY 強制イベント**では、返したスクリプトは無視される——2.0 と同一解釈。

## 4. OS / CPU 要件
- **最小 OS:** **macOS 10.15（Catalina）以降**（= 32bit 非対応世代）。  
- **配布形態:** **Universal 2**（`arm64 + x86_64`）を推奨必須。  
- **Rosetta 2:** Apple silicon 上で **x86_64 ホストを Rosetta**で動かす場合、**読み込むプラグインも x86_64**で一致させる。

## 5. 実体（バンドル形式）
- Windows の **DLL** に相当する実体は、macOS では **Loadable Bundle（`.plugin` / `.bundle`）** とする。ロードは **CFBundle/Bundle** API を用いる。  
- バンドル構造（典型）：
  ```text
  MyPlugin.plugin/
    Contents/
      Info.plist
      MacOS/MyPlugin      # 実行ファイル（Mach-O, Universal 2）
      Resources/descript.txt
  ```
  App バンドル配下の **`Contents/PlugIns/`** に配置するのが通例。

## 6. ワイヤプロトコル（2.0 との差分）
- **版表記:** 先頭行のプロトコル名は `PLUGIN/2.0M` を用いる（構文は 2.0 と同形）。  
- **Charset 既定:** 2.0M では **UTF‑8** を未指定時の既定とする。互換のため `Shift_JIS` / `Windows‑31J` 等のラベルを受理する（実体は CP932 相当として扱ってよい）。  
- **改行・終端:** 2.0 と同じく **CRLF**、**空行でヘッダ終端**。値中の改行等は URL エンコードを推奨（2.0 の慣行に従う）。

## 7. API（エクスポート関数・メモリ管理）
- **必須エクスポート（C ABI）**
  ```c
  int  load (const char* plugin_dir_utf8);
  int  loadu(const char* plugin_dir_utf8);   // UTF-8 パス受領
  void unload(void);
  const unsigned char* request(const unsigned char* buf, size_t len, size_t* out_len);
  /* optional */ void plugin_free(void* p);
  ```
  ※ 2.0 の関数構成を C ABI に読み替える（HGLOBAL 等の WinAPI 前提は撤廃）。
- **メモリ管理**：既定は **呼び出し側（ホスト）でコピー/破棄**。必要なら `plugin_free()` を任意提供。

## 8. イベント分岐（実装指針）
- リクエストは **ID ヘッダ**と任意個の **ReferenceN** で表現される（2.0 と同様）。ID ごとに処理を分岐する。  
- 代表例：
  - `ID: version` … `Value:` ヘッダで自プラグインのバージョンを返す。必要なら `Charset:` をここで宣言。  
  - `ID: OnMenuExec`（GET） … メニュー選択に応じた `Script:` を返す。  
  - `ID: OnSecondChange`（NOTIFY 強制） … スクリプトは返しても処理系で無視され得るため、`204 No Content` か `200 OK` のみ返す実装を推奨。  
- `Sender`/`Target` の意味は 2.0 と同一（Sender は起点、Target は返信先）。

## 9. 設定ファイル（descript.txt）差分
- **必須:** `name` / `id` / `filename`（2.0 踏襲）。  
- **文字コード:** 「旧環境配慮なら Shift_JIS、そうでなければ UTF‑8 推奨」。  
- **2.0M 追加許容:** `filename` に **`.plugin` / `.bundle`** を指定可。

## 10. セキュリティ/安定性：XPC隔離（推奨）
- 不安定/高負荷プラグインは **XPC サービス**として別プロセスに分離し、ホスト↔プラグイン間は**テキスト（ワイヤ文字列）のまま透過転送**する。  
- 型安全にしたい場合は、`request(Data) -> Data` 相当のメソッドを持つ **NSXPCConnection** ベースのインターフェースを定義する。  
- XPC 隔離は**規格必須ではない**が、クラッシュ隔離・権限最小化の観点から強く推奨。

## 11. 例

### 11.1 version 問合せ（GET）
```
GET PLUGIN/2.0M
ID: version
Charset: UTF-8
Sender: Host
```

```
PLUGIN/2.0M 200 OK
Charset: UTF-8
Value: SamplePlugin 1.0.0
```

### 11.2 NOTIFY 強制イベント（OnSecondChange）
```
NOTIFY PLUGIN/2.0M
ID: OnSecondChange
Charset: UTF-8
```
（スクリプトを返しても処理系で無視され得る。`204 No Content` または `200 OK` のみ推奨）

## 12. 実装状況（Implementation Status）

**更新日:** 2025-10-20

### 12.1 Ourin ホスト側の実装

- [x] **プラグイン検出とロード**: `PluginRegistry.swift` にて実装済み
- [x] **CFBundle ロード**: `.plugin` および `.bundle` ファイルのロード機能を実装済み
- [x] **descript.txt 解析**: プラグインメタデータの読み取りを実装済み
- [x] **文字コード対応**: UTF-8 既定、Shift_JIS/CP932 の自動検出を実装済み
- [ ] **PLUGIN/2.0M プロトコル**: ワイヤプロトコルの完全実装は未完了
- [ ] **イベントディスパッチ**: `PluginEventDispatcher.swift` にて基本構造は実装済みだが、完全な PLUGIN/2.0M 互換は未達成
- [ ] **XPC 隔離**: 未実装（現在は同一プロセス内で実行）

### 12.2 実装済みの機能

1. **プラグイン検出**
   - App バンドル内の `Contents/PlugIns/` からの検出
   - `~/Library/Application Support/Ourin/PlugIns/` からの検出
   - `.plugin` および `.bundle` 拡張子のサポート

2. **プラグインメタデータ**
   - `descript.txt` の解析（name, id, filename, secondchange.interval など）
   - UTF-8 および Shift_JIS のエンコーディング自動検出

3. **ライフサイクル管理**
   - `load()`/`loadu()` 関数の呼び出し
   - `unload()` 関数の呼び出し
   - プラグインの一括アンロード

### 12.3 未実装の機能

1. **完全な PLUGIN/2.0M プロトコル**
   - `request()` 関数の呼び出しとワイヤプロトコル処理
   - `ID`/`Reference*`/`Script`/`ScriptOption`/`Target` の完全な実装
   - NOTIFY 強制イベントの処理

2. **XPC プロセス分離**
   - プラグインの別プロセス実行
   - セキュリティサンドボックス分離

3. **高度なイベント処理**
   - 全ての PLUGIN/2.0 イベントタイプの完全サポート

## 13. 適合チェックリスト
- [ ] `PLUGIN/2.0M` 行で 2.0 と同構文のワイヤを話せる（未実装）  
- [x] 既定 `Charset` は **UTF‑8**、`Shift_JIS`/`Windows‑31J` を受理（実装済み）  
- [ ] CRLF/空行終端などの 2.0 仕様に従う（未実装）  
- [x] 実体は **.plugin/.bundle**（CFBundle）で Universal 2 を配布（対応済み）  
- [x] 最小 OS は **10.15+**（対応済み）

## 14. 既知の差分（Windows 前提語彙）
- `HWND` 相当のフィールドは macOS では **未使用/0** とする（必要なら将来の UI 連携拡張で定義）。

## 15. 付録A：DLL → .plugin ポーティング手順（最短）
1) **ターゲットを Bundle（Mach‑O: bundle）** に切替（Xcode）。**Universal 2** を有効化。  
2) **エクスポート関数**は `request/load(u)/unload` を **C ABI** で再掲（`__declspec` は不要）。  
3) **文字コード**は **UTF‑8 既定**、`Shift_JIS`/`Windows‑31J` ラベルは **CP932 同等**として受理。  
4) **配置**は `MyPlugin.plugin/Contents/{MacOS,Resources}`。App 側は `Contents/PlugIns/` からロード。  
5) **Rosetta 注意**：x86_64 のみの配布ならホストも x86_64 で実行（Apple silicon では Rosetta）。

## 16. 付録B：ビルドレシピ（Xcode/CMake）
- **Xcode（推奨）**
  - Target: *Bundle*（Mach‑O Type: *Bundle*）  
  - Architectures: **Standard**（`arm64`/`x86_64`）＝ Universal 2  
  - Deployment Target: `macOS 10.15` 以上  
  - 出力: `MyPlugin.plugin`（自動で `Contents/` 構造を生成）
- **CMake**
  ```cmake
  set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
  add_library(MyPlugin MODULE plugin.c)
  set_target_properties(MyPlugin PROPERTIES BUNDLE TRUE BUNDLE_EXTENSION "plugin" OUTPUT_NAME "MyPlugin")
  ```

## 17. 付録C：最小ホストローダ（Swift）
> macOS の **Bundle** API で `.plugin` をロードし、`request` 関数にワイヤ文字列（CRLF/空行終端）を渡す最小例。

```swift
import Foundation

typealias ReqFn = @convention(c) (UnsafePointer<UInt8>, Int, UnsafeMutablePointer<Int>) -> UnsafePointer<UInt8>?
typealias LoadFn = @convention(c) (UnsafePointer<CChar>) -> Int32
typealias UnloadFn = @convention(c) () -> Void

struct Plugin {
    let bundle: Bundle
    let request: ReqFn
    let load: LoadFn?
    let unload: UnloadFn?

    init(url: URL) throws {
        guard let bundle = Bundle(url: url) else { throw NSError(domain: "Plugin", code: -1) }
        self.bundle = bundle
        // Force load the bundle image
        _ = bundle.principalClass
        func sym<T>(_ name: String) -> T? {
            let fp = CFBundleGetFunctionPointerForName(bundle._cfBundle, name as CFString)
            guard fp != nil else { return nil }
            return unsafeBitCast(fp, to: Optional<T>.self)
        }
        guard let req: ReqFn = sym("request") else { throw NSError(domain:"Plugin", code:-2) }
        self.request = req
        self.load = sym("load")
        self.unload = sym("unload")
    }

    func send(_ text: String) -> String {
        var outLen: Int = 0
        var bytes = Array(text.utf8)
        let respPtr = bytes.withUnsafeMutableBytes { raw -> UnsafePointer<UInt8>? in
            return request(raw.bindMemory(to: UInt8.self).baseAddress!, bytes.count, &outLen)
        }
        guard let p = respPtr else { return "" }
        let buf = UnsafeBufferPointer(start: p, count: outLen)
        return String(decoding: buf, as: UTF8.self)
    }
}

private extension Bundle { var _cfBundle: CFBundle { CFBundleGetBundleWithIdentifier(self.bundleIdentifier! as CFString)! } }
```

## 18. 参照（Normative / Informative）
- UKADOC: PLUGIN/2.0（リクエスト/レスポンス、CRLF、ID/Reference/Script/Target 等）  
- UKADOC: Plugin 設定（descript.txt）  
- Apple: CFBundle / Bundle（バンドル実体・ロード）  
- Apple: Building a universal macOS binary（Universal 2）  
- Apple: 32‑bit 非対応（macOS 10.15+）  
- Apple: XPC / XPC Service（プロセス分離）  
- WHATWG/MDN: Encoding labels（Shift_JIS / Windows‑31J 等の同義ラベル集合）

> 注: 本文中の例・定数は説明用。実装では例外処理・境界チェック・SJIS→UTF‑8 変換のエラー処理等を追加すること。
