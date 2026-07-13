
# SHIORI/3.0M — macOS ネイティブ差分仕様（Draft）
**Status:** Draft  
**Updated:** 2025-07-27  
**Audience:** ベースウェア Ourin（桜鈴）実装者・SHIORI作者  
**Scope:** UKADOC **SHIORI/3.0** の語彙・挙動互換を維持しつつ、Windows DLL 依存（GlobalAlloc等）を **macOS の Bundle（.bundle/.plugin）＋C ABI** に置換する。  
**非目標:** Windows DLL のバイナリ互換（語彙・挙動のみ互換）。

---

## 目次
- [1. 目的と方針](#1-目的と方針)
- [2. 用語](#2-用語)
- [3. 互換（変えないもの）](#3-互換変えないもの)
- [4. macOS 差分（置き換えるもの）](#4-macos-差分置き換えるもの)
- [5. 文字コードポリシー](#5-文字コードポリシー)
- [6. リクエスト/レスポンス（ワイヤ規定）](#6-リクエストレスポンスワイヤ規定)
- [7. 2.x（2.0/2.5）互換の扱い](#7-2x205互換の扱い)
- [8. 例（OnBoot/OnCommunicate）](#8-例onbootoncommunicate)
- [9. 最小実装（C ABI と雛形）](#9-最小実装c-abi-と雛形)
- [10. Ourin ホスト実装メモ](#10-ourin-ホスト実装メモ)
- [11. 適合チェックリスト](#11-適合チェックリスト)
- [12. 参照（Normative/Informative）](#12-参照normativeinformative)

---

## 1. 目的と方針
- **SHIORI/3.0 の語彙・挙動**（`GET/NOTIFY`、`ID`、`Reference*`、`Charset`、`SecurityLevel/Origin` 等）を**そのまま準用**する。  
- 実体（Windows の DLL 規約）は **macOS の Bundle + C ABI** に**読み替え**る。**XPC 分離**は任意の推奨事項とする。

## 2. 用語
- **3.0M**: 本仕様の macOS 差分版識別。  
- **ホスト**: Ourin などのベースウェア。  
- **モジュール**: SHIORI 実装本体（`.bundle`/`.plugin`）。  
- **ワイヤ**: CRLF 改行＋空行終端の SHIORI メッセージ（3.0 の構文）。

## 3. 互換（変えないもの）
- **メソッド**：`GET`（値を返す前提）、`NOTIFY`（返さない前提）。  
- **ワイヤ構文**：CRLF 改行、**空行で終端**、ヘッダの並び（`Charset` は先頭近くに）。  
- **主要ヘッダ**：`ID`、`Reference0..N`、`Sender`、`SenderType`、`SecurityLevel`、`SecurityOrigin`、`BaseID`、`Status` ほか。  
- **レスポンス**：`SHIORI/3.0 200/204/...` と `Value`（場合により `ValueNotify` など拡張）。

## 4. macOS 差分（置き換えるもの）
### 4.1 実体（DLL → Bundle）とエクスポート
- 配布：`.bundle`（または `.plugin`）。**Universal 2**（`arm64`/`x86_64`）推奨。  
- エクスポート（**C ABI**）:
  ```c
  bool shiori_load(const char* dir_utf8);
  void shiori_unload(void);
  bool shiori_request(const unsigned char* req, size_t req_len,
                      unsigned char** res, size_t* res_len);
  void shiori_free(unsigned char* p);
  ```
- **ロード/解決**：CFBundle から **関数名**で解決（`CFBundleGetFunctionPointerForName`）。  
- **メモリ管理**：戻り値は **呼び出し側（ホスト）が shiori_free する**。グローバルアロケータの混在は不可。

### 4.2 実行コンテナ（任意）
- 最小は **同一プロセス内ロード**。  
- 解析や安定性重視の場合、**XPC サービス**へ分離し `Data -> Data` で橋渡し。

## 5. 文字コードポリシー
- **既定は UTF‑8**。  
- 互換として `Shift_JIS / Windows‑31J / CP932 / SJIS` ラベルは **同一系**として受理（CP932 相当）。  
- レスポンスの `Charset` はリクエストに揃えることを推奨。

## 6. リクエスト/レスポンス（ワイヤ規定）
- **先頭行**：`GET SHIORI/3.0` または `NOTIFY SHIORI/3.0`。  
- **終端**：CRLF + CRLF。**ゼロ終端は前提にしない**。  
- **例（最小）**：
  ```
  GET SHIORI/3.0
  Charset: UTF-8
  ID: OnBoot

  ```
  **Response**
  ```
  SHIORI/3.0 200 OK
  Charset: UTF-8
  Value: \h\s0Hello from 3.0M

  ```

## 7. 2.x（2.0/2.5）互換の扱い
- **語彙・挙動互換のみ**を提供。**バイナリ互換は提供しない**。  
- **SHIORI Resource**（2.5 由来）は 3.0 以降、**通常の Event とほぼ同等**に整理。戻り値は**短いテキスト**として扱う。  
- 2.x 的な問い合わせは、可能な限り **3.0 の `ID`/`Reference*` へ写像**する。

## 8. 例（OnBoot/OnCommunicate）
**OnBoot（起動）**
```
GET SHIORI/3.0
Charset: UTF-8
Sender: Ourin
ID: OnBoot

```
**OnCommunicate（対話）**
```
GET SHIORI/3.0
Charset: UTF-8
Sender: Ourin
ID: OnCommunicate
Reference0: こんにちは

```

## 9. 最小実装（C ABI と雛形）
**ヘッダ**
```c
// shiori.h (3.0M)
#pragma once
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif
bool shiori_load(const char* dir_utf8);
void shiori_unload(void);
bool shiori_request(const unsigned char* req, size_t req_len,
                    unsigned char** res, size_t* res_len);
void shiori_free(unsigned char* p);
#ifdef __cplusplus
} // extern "C"
#endif
```

**実装（超最小）**
```c
// shiori.c (3.0M minimal)
#include "shiori.h"
#include <string.h>
#include <stdlib.h>

bool shiori_load(const char* dir_utf8){ (void)dir_utf8; return true; }
void shiori_unload(void){}

static unsigned char* duputf8(const char* s, size_t* out){
  size_t n = strlen(s);
  unsigned char* p = (unsigned char*)malloc(n);
  if(!p) return NULL; memcpy(p, s, n); *out = n; return p;
}

bool shiori_request(const unsigned char* req, size_t len,
                    unsigned char** res, size_t* res_len){
  (void)len;
  const char *ok =
    "SHIORI/3.0 200 OK\r\n"
    "Charset: UTF-8\r\n"
    "Value: \\h\\s0Hello from 3.0M\r\n"
    "\r\n";
  *res = duputf8(ok, res_len);
  return *res != NULL;
}

void shiori_free(unsigned char* p){ free(p); }
```

## 10. Ourin ホスト実装メモ
- `CFBundle` でロードし、`shiori_load`→`shiori_request`→`shiori_unload`（終了時）を呼ぶ。  
- **XPC 分離**する場合は、`request(Data)->Data` の固定 IF で橋渡し。  
- **macOS 10.15+ / 64bit 専用**、**Universal 2** 配布を基本とする。

## 10.1 BridgeToSHIORI — イベントパイプライン実装

`BridgeToSHIORI.swift` はホスト内部のイベントを SHIORI/3.0 ワイヤへ変換し、ネイティブ SHIORI バンドルまたは稼働中ゴースト（YAYA 等）へ橋渡しするブリッジ層である。

### メソッドの選択

| 呼び出し元 | メソッド | ワイヤ先頭行 |
|---|---|---|
| `sendGet` / `sendGetCustom` | `GET` | `GET SHIORI/3.0` |
| `sendNotify` / `sendNotifyCustom` | `NOTIFY` | `NOTIFY SHIORI/3.0` |

- NOTIFY は GET に強制変換されない。`EventBridge.sendNotify` は必ず `method: "NOTIFY"` を渡し、`BridgeToSHIORI.handle` もその値をそのまま `ShioriHost.request` へ転送する（`BridgeToSHIORI.swift:250` の `let verb = method.uppercased() == "NOTIFY" ? "NOTIFY" : "GET"` 参照）。
- 時刻系イベント（`OnSecondChange` 等）は `cantalk` フラグに応じて GET/NOTIFY を動的に切り替える（`EventBridge.swift:443–451`）。

### handle と handleResponse の使い分け

`BridgeToSHIORI` は 2 つの公開メソッドを持つ。

- **`handle(event:references:headers:method:) -> String`**  
  応答の `Value`（スクリプト文字列）のみを返す。`GhostManager` / `ResourceBridge` / `WebHandler` のように、結果を直接スクリプト値として扱う呼び出し向け。

- **`handleResponse(event:references:headers:method:) -> String`**  
  完全な SHIORI/3.0 ワイヤ応答文字列を返す（`SHIORI/3.0 200 OK\r\n...`）。  
  `SSTPDispatcher.mapShioriResponse` が `ReferenceN` / `Value` / `ValueNotify` / `Status` 等の全ヘッダを解釈できるよう、SSTP ディスパッチャ経路でのみ使用する。

### 稼働中ゴーストへの橋渡し（liveGhostResolver）

ネイティブ SHIORI バンドル（`SHIORI_BUNDLE_PATH` 環境変数）が未設定の場合、`handle` / `handleResponse` は `liveGhostResolver` クロージャを呼び出す。  
このクロージャは AppDelegate が起動時に設定し、実際にロードされた YAYA ゴースト等へリクエストを転送する。  
宛先ゴーストが存在しない、または応答できない場合は `nil` を返す（`handle` は空文字列を返す）。

優先順位: **登録済み Resource 値（テスト用）→ ネイティブ SHIORI バンドル → liveGhostResolver（稼働中ゴースト）**

### Resource イベントの正規化

イベント名が `Resource` のとき、`references[0]` をリソース名として扱う。  
内部では通常の SHIORI `GET` として送出され（`ID: Resource` / `Reference0: <name>`）、返値は短いテキスト値として扱う（UKADOC SHIORI/2.5 由来の Resource に相当する 3.0 写像）。

### ReceiverGhostName による宛先ルーティング

SSTP フレームに `ReceiverGhostName` ヘッダが含まれる場合、`liveGhostResolver` はそのゴースト名に一致するセッションへのみリクエストを送る。ヘッダがない場合はプライマリゴーストへ送る。

### ワイヤ直列化における改行サニタイズ

稼働中ゴーストからの構造化応答を `handleResponse` がワイヤ文字列へ直列化する際、各ヘッダ値・Value から CR/LF を除去する。  
SakuraScript の改行は `\n` トークンで表現するため、生の改行を除去しても表示上の影響はない。

## 11. 実装状況（Implementation Status）

**更新日:** 2026-07-13

### 11.1 Ourin ホスト側の実装

- [x] **CFBundle によるロード**: `ShioriLoader.swift` にて実装済み
- [x] **YAYA バックエンド**: `YayaBackend` および `YayaAdapter.swift` にて YAYA ゴーストのサポート実装済み
- [x] **文字コード対応**: UTF-8 既定、Shift_JIS/CP932 受理機能を実装済み
- [x] **リクエスト/レスポンス処理**: CRLF + 空行終端の基本的なワイヤプロトコル処理を実装済み
- [x] **Bundle/Plugin 形式の SHIORI**: `BundleBackend` がC ABIを直接ロード
- [x] **XPC 分離実行**: 同梱`OurinShioriXPCService`で接続単位にNative SHIORIを隔離
- [x] **shiori_free メモリ管理**: `BundleBackend` / `DylibBackend` で応答解放を実装
- [x] **共通ランタイム接続**: `descript.txt` の `shiori` に従いYAYA/里々/Nativeを選択
- [x] **里々バックエンド**: 固定版SATORIを`satori_core` helperとしてUniversal 2で同梱
- [x] **表示前トランスレータ**: `OnTranslate`とghost/shell MAKOTOを仕様順で実行
- [x] **ゴーストキャッシュ**: `shiori.cache`に従うbounded runtime cacheとSuspend/Restore
- [x] **外部SAORI**: ゴーストローカル探索とWindows名からmacOS native moduleへの代替

### 11.2 実装済みの機能

1. **YAYA ゴースト対応**
   - `yaya.txt` の解析とロード
   - `dic` ファイルの再帰的読み込み
   - リクエスト/レスポンス処理
   - `OnBoot`, `OnCommunicate` 等の基本イベント

2. **文字エンコーディング**
   - UTF-8 既定での処理
   - Shift_JIS/CP932 の自動検出と変換

3. **イベントシステム**
   - システムイベントの監視と SHIORI への転送
   - `EventBridge` によるイベント配信

### 11.3 制限事項

1. **配布ゴースト回帰**
   - 里々と外部SAORIは実エンジンfixtureで自動試験済み。第三者配布の里々ゴーストによる実機確認は未実施。

2. **Windowsバイナリ**
   - Windows DLL自体は実行しない。同名のmacOS native `.dylib/.so`が検索パスにある場合のみ代替する。

## 12. 適合チェックリスト
- [x] `GET/NOTIFY SHIORI/3.0`、CRLF＋空行終端で往復できる（YAYA バックエンドで実装）  
- [x] `Charset` 未指定は UTF‑8、SJIS系ラベルは CP932 として受理  
- [x] `Value`/`ValueNotify` 等の拡張を必要に応じて実装（基本実装済み）  
- [x] 実体は `.bundle/.plugin`＋ **C ABI** でロード可能
- [x] **shiori_free** による戻り値解放
- [x] 同梱XPC ServiceによるNative SHIORIの既定隔離
- [x] `OnTranslate` → ghost MAKOTO → shell MAKOTOの表示前変換
- [x] `shiori.cache`による切替時runtime保持と明示破棄
- [x] SATORI外部SAORIのmacOS native代替探索

## 13. 参照（Normative/Informative）
- SHIORI/3.0（UKADOC）  
- SHIORI Event リスト／メモ  
- DLL 共通仕様（Windows の GlobalAlloc 規約の根拠。3.0M では置換）  
- Apple: CFBundle（関数名でポインタ解決）/ NSXPCConnection（分離実行）  
- macOS 10.15 以降 32bit 非対応
