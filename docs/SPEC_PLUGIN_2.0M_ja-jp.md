# PLUGIN/2.0M — macOS ネイティブ差分仕様（Draft）
**Status:** Draft  
**Updated:** 2026-06-26  
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

### 5.1 Ourin 互換パッケージディレクトリ

SSP 由来の Windows plugin を macOS native plugin へ移植する場合、Ourin では `.plugin` bundle 単体だけでなく、元 plugin ディレクトリに近い **パッケージディレクトリ** を標準形として扱う。

```text
SomePlugin_mac/
  install.txt
  descript.txt
  message.japanese.txt
  message.english.txt
  SomePlugin.plugin/
    Contents/
      Info.plist
      MacOS/SomePlugin
      Resources/descript.txt   # fallback 用。通常はルート descript.txt を優先
```

- `install.txt` は Ourin が当該ディレクトリを `type,plugin` の plugin パッケージとして解釈するために読む。
- `descript.txt` は plugin の互換メタデータとして読む。パッケージルートの `descript.txt` が存在する場合、bundle 内 `Resources/descript.txt` より優先する。
- `message.*.txt` は言語別表示文字列として読む。native `.plugin` は、表示文言を可能な限りこのファイルへ委譲する。
- `.plugin` bundle は実行本体であり、DLL の `load` / `loadu` / `request` / `unload` / `unloadu` 互換処理に集中する。
- 既存配布物の `ReadMe.txt` 等を同梱する場合は、実行時入力ではなく参照資料として扱う。

### 5.2 macOS 独自制約と互換ビュー

Ourin は Windows DLL/PE plugin のバイナリ実行互換を提供しない。既存の `*.dll` / `*.exe` 資産は
`descript.txt`、`install.txt`、`message.*.txt` 等のメタデータを読む対象であり、Mach-O の
`.plugin` / `.bundle` へ移植されていない限り `request` の送信対象にはしない。

この差異を UI・プロパティ・テストで一貫して扱うため、ホストは `PluginCompatibilityEntry` を互換ビューとして公開する。

| フィールド | 意味 |
|---|---|
| `path` / `compatibilityPath` | `descript.txt` の `filename` から得る互換パス。`pluginlist.index(n).path` はこれを返す。legacy DLL では元 DLL パスになる。 |
| `executablePath` | 実際にロード可能な macOS `.plugin` / `.bundle` のパス。legacy metadata-only では `compatibilityPath` と同じ値を返す。 |
| `packagePath` | `install.txt` 付き plugin パッケージディレクトリ。存在しない場合は空または nil。 |
| `native` | macOS native bundle としてロード可能なら `1`、metadata-only なら `0`。 |
| `executionState` | `native` または `metadataOnly`。 |
| `canDispatchRequests` | PLUGIN `GET` / `NOTIFY` を送れる場合のみ true。Windows DLL metadata-only は false。 |
| `filename` / `charset` / `message.*` | SSP 由来の表示・互換メタデータ。実行可否とは独立して保持する。 |

PLUGIN request の `Target` 解決では、native としてロード済みの plugin に限り、`id` / `name` /
`compatibilityPath` / `executablePath` / `packagePath` を照合対象にできる。metadata-only plugin は
`pluginlist.*` や開発ツールの一覧には現れるが、イベントディスパッチ対象にはならない。

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
  ホストは応答を複製するだけで `plugin_free()` を自動では呼ばない（静的バッファを返す実装と両立させるため）。
- **load の引数**：ホストは `malloc` 確保・NUL 終端・**末尾 `/` 付き**のディレクトリを `load(ptr, len)` 形式で渡す。
  所有権はモジュールへ移るので `free()` してよい。`int load(const char*)` の実装もそのまま受け取れる。戻り値 0 はロード失敗として記録し、実行対象から除外する。メタデータは一覧に残すが request / unload は呼び出さない。
- **Windows DLL 互換 ABI（任意）**：DLL のソースを変えずに移植する場合、Windows と同じ
  ```c
  int   load(void *h, long len);      // h は free する
  void *request(void *h, long *len);  // h は free する。*len は入力長→出力長。戻り値は malloc 確保（ホストが free）
  ```
  を使える。`.plugin` / `.bundle` は Info.plist に `OurinModuleABI` = `ukagaka` を宣言する。
  bundle にしない単体 `.dylib` はこの規約を既定とする。HEADLINE の `execute` も同じ扱い。
- **配置と解決**：`plugin/<name>/descript.txt` の `filename`（例 `Foo.dll`）から、同じディレクトリの
  `Foo.dylib` / `libFoo.dylib` / `Foo.plugin` / `Foo.bundle` / `Foo.so` を大小文字を区別せずに探す。
  `install.txt` は不要。Windows PE（`MZ`）の `.dll` 自体は実行対象にしない。HEADLINE（`headline/<name>/`）・SAORI も同じ規則で解決する。

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

### 9.1 `install.txt` / `message.*.txt` の扱い

Ourin 互換パッケージディレクトリでは、`.plugin` bundle 内だけでなく、パッケージルートの SSP 互換 txt を読む。

- `install.txt`
  - `type,plugin` を検出した場合、そのディレクトリを plugin パッケージとして登録する。
  - `directory` は設置名・更新時の識別名として扱う。
  - `charset` は UTF-8 / Shift_JIS / CP932 系を受理する。
- `message.<language>.txt`
  - `message.japanese.txt`、`message.english.txt` などを言語別辞書として読む。
  - `menu.title`、`menu.<command>`、`message.end` 等のキーは Ourin 側の表示・メニュー構築で利用できる。
  - plugin 実装内に固定文言を埋め込むより、可能な限り `message.*.txt` を優先する。

方針として、今後作る移植 `.plugin` は **`descript.txt` および DLL エントリポイント互換に留める**。`install.txt` に基づく登録、`message.*.txt` に基づく表示言語選択、その他パッケージメタデータの解釈は Ourin ホスト側の責務とする。

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

**更新日:** 2025-10-22

### 12.1 Ourin ホスト側の実装

- [x] **プラグイン検出とロード**: `PluginRegistry.swift` にて実装済み
- [x] **CFBundle ロード**: `.plugin` および `.bundle` ファイルのロード機能を実装済み
- [x] **descript.txt 解析**: プラグインメタデータの読み取りを実装済み
- [x] **install.txt パッケージ検出**: `type,plugin` ディレクトリ配下の native `.plugin` 読み込みを実装済み
- [x] **message.*.txt 解析**: パッケージルートの言語別メッセージ辞書を読み取り、plugin メタデータへ保持
- [x] **互換ビュー**: `PluginCompatibilityEntry` で `path` / `executablePath` / `packagePath` / 実行可否を明示
- [x] **legacy DLL metadata-only**: Windows DLL 資産をロードせず、一覧・プロパティ互換情報として登録
- [x] **文字コード対応**: UTF-8 既定、Shift_JIS/CP932 の自動検出を実装済み
- [x] **PLUGIN/2.0M プロトコル**: `PluginProtocol.swift` にて完全実装済み
- [x] **イベントディスパッチ**: `PluginRegistry.swift` にて PLUGIN/2.0M 互換のイベントディスパッチを実装済み
- [x] **XPC 隔離**: 実装済み (2026-06-15)。`PluginXpcBackend.swift`(`OurinPluginXPC`/`PluginXpcClient`) を新設し、`OURIN_PLUGIN_ISOLATION_MODE=xpc` または `OURIN_PLUGIN_XPC_SERVICE` 指定時に `PluginEventDispatcher` が別プロセスのワーカーへ透過転送する（既定はインプロセス）。

### 12.2 実装済みの機能

1. **プラグイン検出**
   - App バンドル内の `Contents/PlugIns/` からの検出
   - `~/Library/Application Support/Ourin/PlugIns/` からの検出
   - `/Users/<user>/Documents/Ourin/plugin` 配下の `install.txt` 付き plugin パッケージディレクトリからの検出
   - `.plugin` および `.bundle` 拡張子のサポート

2. **プラグインメタデータ**
   - `descript.txt` の解析（name, id, filename, secondchange.interval など）
   - `install.txt` の解析（type, directory, charset など）
   - `message.*.txt` の解析（言語別 menu/message キー）
   - UTF-8 および Shift_JIS のエンコーディング自動検出

3. **ライフサイクル管理**
   - `load()`/`loadu()` 関数の呼び出し
   - `unload()` 関数の呼び出し
   - プラグインの一括アンロード

4. **PLUGIN/2.0M プロトコル処理** (`PluginProtocol.swift`)
   - **PluginRequest/PluginResponse 構造体**: リクエストとレスポンスの型定義
   - **PluginProtocolParser**: CRLF 区切りのワイヤテキストをパース
     - `parseRequest()`: GET/NOTIFY リクエストのパース
     - `parseResponse()`: ステータスコードとヘッダーを含むレスポンスのパース
   - **PluginProtocolBuilder**: 構造化データをワイヤテキストに変換
     - `buildRequest()`: リクエストを CRLF 区切り形式に変換
     - `buildResponse()`: レスポンスを CRLF 区切り形式に変換
   - **Plugin 構造体の拡張メソッド**:
     - `sendRequest()`: 構造化リクエストを送信してレスポンスをパース
     - `get()`: GET リクエストの便利メソッド
     - `notify()`: NOTIFY リクエストの便利メソッド
     - `version()`: プラグインバージョン取得

5. **イベントディスパッチシステム** (`PluginRegistry.swift`)
   - **汎用ディスパッチ**:
     - `dispatchGet()`: 全プラグインに GET イベントを送信し、スクリプトを含むレスポンスを収集
     - `dispatchNotify()`: 全プラグインに NOTIFY イベントを送信
     - `getAllVersions()`: 全プラグインのバージョン情報を取得
   - **具体的なイベント実装**:
     - `dispatchOnMenuExec()`: メニュー選択イベント (GET)
     - `dispatchOnSecondChange()`: 秒変更イベント (NOTIFY 強制)
     - `dispatchOnMinuteChange()`: 分変更イベント (NOTIFY 強制)
     - `dispatchOnOtherGhostTalk()`: 他ゴースト発話イベント (NOTIFY)
     - `dispatchOnGhostChanging()` / `dispatchOnGhostChanged()` / `dispatchOnShellChanging()` / `dispatchOnShellChanged()`:
       **定義のみ・未配線**（2026-07-05 監査で確認: `PluginRegistry.swift` にメソッドは存在するが呼び出し元が無い。
       これらは PLUGIN/2.0M の17種の標準通知イベントには含まれない予備実装であり、
       ゴースト/シェル切替の SHIORI 通知は `EventBridge` 経由で別途行われる）

### 12.3 未実装の機能

1. ~~**XPC プロセス分離**~~ → 実装済み (2026-06-15)。`PluginXpcClient` 経由で別プロセスワーカーへ透過転送（env で有効化）。

2. **追加のイベントタイプ**
   - 全ての PLUGIN/2.0 イベントタイプの実装（基本的なイベントは実装済み、追加イベントは必要に応じて実装可能）

### 12.4 実装ファイル

- `Ourin/PluginHost/Plugin.swift`: プラグインバンドルのラッパーと基本的な通信機能
- `Ourin/PluginHost/PluginRegistry.swift`: プラグイン検出、管理、イベントディスパッチ
- `Ourin/PluginHost/PluginProtocol.swift`: PLUGIN/2.0M プロトコルの型定義、パーサー、ビルダー

## 13. 適合チェックリスト
- [x] 要求行は SSP 本体と同じ `GET PLUGIN/2.0` / `NOTIFY PLUGIN/2.0`（2026-10-26 変更。要求行を完全一致で判定するプラグインがあるため `2.0M` を付けない）。応答の版表記は問わない
- [x] 送信文字コードは descript.txt の `charset`、未指定なら Shift_JIS。`version` 応答の `Charset` で以後を切り替え、ヘッダが無ければ Shift_JIS（ukadoc plugin-event）
- [x] CRLF/空行終端などの 2.0 仕様に従う（実装済み - `PluginProtocolParser/Builder`）
- [x] 実体は **.plugin/.bundle**（CFBundle）で Universal 2 を配布（対応済み）
- [x] 最小 OS は **10.15+**（対応済み）

## 14. 既知の差分（Windows 前提語彙）
- `HWND` 相当（OnGhostBoot 等の Reference0）は各キャラクターウィンドウの `CGWindowID` を **バイト値 1 区切り**で渡す（未構築は `0`）。
- Windows DLL/PE plugin の機械語は実行しない（配布 DLL の大半は 32bit x86 で、Apple silicon の Rosetta でも動かない）。
  本体 DLL が汎用エンジン（`yaya.dll` / `aya.dll` / `kagari.dll`）なら、探索時に DLL の隣へ `<DLL名>.plugin` を生成し、
  Ourin 内蔵エンジンで同梱辞書を動かす（§19）。独自コードの DLL は metadata-only のまま、macOS 向けに作り直した
  `.dylib` / `.plugin` を置けば読み込む。
- パスは POSIX パスで公開する。`path` は SSP 互換上の元モジュール位置、`executablePath` は macOS native 実体、
  `packagePath` は package directory を指す。

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

## 19. SSP 実互換と DLL → .plugin 変換（2026-10-26）

### 19.1 根拠
- ukadoc: `list/plugin-event`、`descript/plugin`、`spec/plugin`。
- SSP 本体のシンボルマップ（Taromati2 同梱 `ssp/ssp.map` の `sp_plugin.obj`）に残る文字列リテラル:
  `GET PLUGIN/2.0\r\n`、`NOTIFY PLUGIN/2.0\r\n`、`Language: `、`othersurfacechange`、`otherghosttalk`、`secondchangeinterval`、
  横流し対象の `OnChoiceSelect(Ex)` / `OnAnchorSelect(Ex)` / `OnChoiceDoubleClick` / `OnAnchorDoubleClick`。
- GitHub 上の実プラグイン約 25 件（yaya_plugin2.dic 系、ambergon、apxxxxxxe、nikolat、ukatech/csaori 等）のソース。

### 19.2 ホスト送信の規則
| 項目 | 規則 |
|---|---|
| 要求行 | `GET PLUGIN/2.0` / `NOTIFY PLUGIN/2.0` |
| Sender | ホスト発は `Ourin`。ゴーストの `\![raiseplugin]` / `\![notifyplugin]`、ゴーストのメニューからの `OnMenuExec`、プラグインが出したトレイバルーンのクリックはゴースト名（descript の name） |
| Language | `Japanese` / `English` / `Chinese-Simplified` / `Chinese-Traditional` / `Hangeoul`（OS の優先言語から） |
| 文字コード | descript `charset` → 未指定は Shift_JIS。`version` 応答の Charset（無ければ Shift_JIS）で以後を決める。要求は送信直前に組み立てるので、version 直後のイベントにも反映される |
| secondchangeinterval | 未指定は 1 秒、0 で送らない |
| installedplugin | Reference ごとに 1 プラグイン、`名前 0x01 ID` |
| *pathlist | 格納フォルダ（`ghost/`・`balloon/`・`headline/`・`plugin/`）の絶対パス、末尾 `/` 付き |
| OnGhostBoot 等 | Ref0 = CGWindowID の 0x01 区切り、Ref3 = Owned SSTP と同じセッション ID、Ref4 = ゴーストフォルダ（末尾 `/`） |
| 選択肢・アンカー横流し | そのスクリプトを返したプラグインだけへ送る（応答元が不明な旧経路は全プラグイン） |
| othersurfacechange | descript で有効なら、他ゴーストのサーフェス変更を `OnOtherSurfaceChange`（SHIORI と同じ Reference）で送る |
| descript 値 | 先頭が `\` / `%` の値は破棄、`\\` / `\%` は文字へ戻す |

### 19.3 DLL → .plugin 変換
- `PluginRegistry` は `plugin/<name>/` を走査するとき `DLLPluginConverter.convert` を呼ぶ。
- DLL は PE ヘッダ（CPU 種別、エクスポート、インポート DLL）だけを読み、実行しない。
- `filename` が `yaya.dll` / `aya.dll` / `aya5.dll` / `kagari.dll`（または本体にエンジン名が残る DLL）で、`load` / `request` をエクスポートしていれば、
  DLL の隣に `<DLL名>.plugin/Contents/Info.plist` を作る。キー: `OurinPluginEngine`（`yaya` / `kagari`）、`OurinOriginalModule`、
  `OurinOriginalMachine`、`OurinOriginalExports`、`OurinOriginalImports`、`OurinConverterVersion`。実行体は持たない。
- 読み込み時、`OurinPluginEngine` 付きの `.plugin` は `PluginEngineHost` が処理する。
  - YAYA: yaya_core を別プロセスで起動し、`<DLL名>.txt`（yaya.dll → yaya.txt）の辞書を読み、辞書の `load` に DLL のフォルダ（末尾 `/`）を渡す。
    要求文は新しい IPC コマンド `raw_request` で辞書の `request` へそのまま渡し、応答はその Charset で書き戻す。
  - KAGARI: 同梱の `libkagari.dylib` を `NativeShioriModule` でプラグインのフォルダを指定して開く。
- 元の DLL・descript.txt・辞書は変更しない。変換結果は `PluginRegistry.conversionReports` とログに残る。
- 変換しないもの: 独自コードの DLL（`main.dll`、`ghost_speaker.dll`、csaori 系など）、`akari.dll`（内蔵エンジン無し）。
  理由とインポート DLL を記録する。ソースがあれば macOS 向けに `.dylib` / `.plugin` を作って置けば、既存の名前解決で読み込まれる。

### 19.4 Windows 固有機能の扱い（現状）
| Windows 側 | macOS 側 |
|---|---|
| HWND（Reference0） | CGWindowID（0x01 区切り） |
| `C:\...\` パス | POSIX パス、フォルダは末尾 `/` |
| Direct SSTP（WM_COPYDATA） | ローカル SSTP（TCP 9801 / XPC）。移植モジュールはこちらへ送る |
| FMO（共有メモリ "Sakura"） | Ourin の FMO（POSIX 共有メモリ）と YAYA の READFMO |
| 32bit x86 DLL | 実行不可。汎用エンジン DLL は内蔵エンジンへ、独自コードは再ビルド |

### 19.5 汎用 SAORI と Windows 前提の小物
- `proxy_ex.dll`: 内蔵実装（`BuiltinSaori` / `ProxyExSaori`）。`foo.exe` は DLL のフォルダ基準で macOS 版の `foo`（拡張子なし）・`foo.command`・`foo.sh` に読み替えて起動し、標準出力を Result で返す。`/delim`・`/charset`・`hwnd` も本家（ukatech/csaori impl_saori/proxy_ex）どおり。見つからなければ 400。
- `\![open,browser,file:///…\a.html]`: file URL の `\` を `/` に直して開く。
- `\![set,trayballoon,…]` をプラグインのスクリプトが出した場合、クリック（`OnTrayBalloonClick`）とタイムアウトはそのプラグインへ返す。

### 19.6 yaya_core の互換修正（YAYA 製プラグインの実物で判明）
- 行末 `/` による行継続を文字列の外でも受け付ける（CharameLNetwork）。
- FOPEN / FREAD / FWRITE / FWRITE2 / FCLOSE / FSEEK / FTELL / FREADBIN / FWRITEBIN / FREADENCODE / FWRITEDECODE を本家 YAYA と同じ「ファイル名で識別」に変更。FOPEN は 1 / 2 / 0、FREAD は EOF で -1、FWRITE は改行付き。モード名 `read` / `write` / `append` を正しく解釈する（従来は `write` の `r` を読み込み指定と誤認していた）。`\` 区切りのパスを受け付ける。
- FENUM(dir[, delimiter]) を本家どおり「フォルダは先頭 `\`、delimiter 区切りの文字列」に変更。
- GETVARLIST(prefix) の先頭一致絞り込み、GETSETTING('coreinfo.path' 等)。

### 19.7 実プラグインでの確認（2026-10-26）
yaya_core を直接起動し、Ourin と同じ PLUGIN/2.0 要求を流した結果（Ourin 本体での表示確認は未実施）。

| プラグイン | 読込 | version | OnMenuExec |
|---|---|---|---|
| BalloonSelector | OK | BalloonSelector/2.4 | メニュー Script |
| Wallet of Unyu | OK | WalletOfUnyu/1.2 | 所持金表示 + Event |
| Inventory | OK | origin/1.0 | 所持品一覧 |
| DBdiary | OK | origin/1.0 | 204（ゴースト側から呼ぶ型） |
| stampcollection | OK | StampCollection/1.4.1 | スタンプ帳 |
| CharameLNetwork | OK | CharameLNetwork/0.5 | HTML 生成 + open,browser |
| Spectre / recentghosts / daumaker / RadioMidnight / GhostWardrobe | OK | 各版 | メニュー Script（GhostWardrobe は proxy_ex 経由の hashing を使う） |

未対応: Win32 API 直叩き（EnumWindows、レジストリ、COM、名前付きパイプ等）は、
該当 DLL を macOS 向けに作り直さない限り動かない。

