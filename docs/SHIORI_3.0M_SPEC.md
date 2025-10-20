
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

## 11. 実装状況（Implementation Status）

**更新日:** 2025-10-20

### 11.1 Ourin ホスト側の実装

- [x] **CFBundle によるロード**: `ShioriLoader.swift` にて実装済み
- [x] **YAYA バックエンド**: `YayaBackend` および `YayaAdapter.swift` にて YAYA ゴーストのサポート実装済み
- [x] **文字コード対応**: UTF-8 既定、Shift_JIS/CP932 受理機能を実装済み
- [x] **リクエスト/レスポンス処理**: CRLF + 空行終端の基本的なワイヤプロトコル処理を実装済み
- [ ] **Bundle/Plugin 形式の SHIORI**: C ABI での直接ロードは未実装（現在は YAYA のみ対応）
- [ ] **XPC 分離実行**: 未実装（現在は同一プロセス内で実行）
- [ ] **shiori_free メモリ管理**: C ABI 未実装のため該当なし

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

### 11.3 未実装の機能

1. **C ABI での Bundle/Plugin ロード**
   - `shiori_load`, `shiori_request`, `shiori_unload`, `shiori_free` 関数の実装
   - CFBundle からの関数ポインタ解決

2. **XPC サービス分離**
   - SHIORI の別プロセス実行
   - セキュリティサンドボックス分離

3. **SHIORI/2.x 互換**
   - 2.x プロトコルのサポート

## 12. 適合チェックリスト
- [x] `GET/NOTIFY SHIORI/3.0`、CRLF＋空行終端で往復できる（YAYA バックエンドで実装）  
- [x] `Charset` 未指定は UTF‑8、SJIS系ラベルは CP932 として受理  
- [x] `Value`/`ValueNotify` 等の拡張を必要に応じて実装（基本実装済み）  
- [ ] 実体は `.bundle/.plugin`（Universal 2）＋ **C ABI**（未実装）  
- [ ] **shiori_free** による戻り値解放（未実装）

## 13. 参照（Normative/Informative）
- SHIORI/3.0（UKADOC）  
- SHIORI Event リスト／メモ  
- DLL 共通仕様（Windows の GlobalAlloc 規約の根拠。3.0M では置換）  
- Apple: CFBundle（関数名でポインタ解決）/ NSXPCConnection（分離実行）  
- macOS 10.15 以降 32bit 非対応
