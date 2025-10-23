
# HEADLINE/2.0M — macOS ネイティブ差分仕様（Draft）
**Status:** Draft  
**Updated:** 2025-07-26  
**Audience:** ベースウェア（Ourin/桜鈴）実装者・モジュール作者  
**Scope:** UKADOC **HEADLINE/2.0** を母体に、**macOS ネイティブ**（.plugin/.bundle）で安全に運用するための差分を規定します。  
**非目標:** Windows DLL のバイナリ互換（語彙・挙動の互換のみ対象）。

---

## 目次
- [1. 目的と設計方針](#1-目的と設計方針)
- [2. 用語](#2-用語)
- [3. 適用範囲と互換性](#3-適用範囲と互換性)
- [4. OS/CPU と配布](#4-oscpu-と配布)
- [5. 実体とエクスポート（.plugin/.bundle）](#5-実体とエクスポートpluginbundle)
- [6. ワイヤ（HEADLINE/2.0 との差分）](#6-ワイヤheadline20-との差分)
- [7. Path の表現（macOS 最適化）](#7-path-の表現macos-最適化)
- [8. 設定ファイル（descript.txt）差分](#8-設定ファイルdescripttxt差分)
- [9. エラー応答の指針](#9-エラー応答の指針)
- [10. セキュリティ/安定性（XPC隔離は推奨）](#10-セキュリティ安定性xpc隔離は推奨)
- [11. 例（Version / Headline 取得）](#11-例version--headline-取得)
- [12. 最小実装（C）](#12-最小実装c)
- [13. 適合チェックリスト](#13-適合チェックリスト)
- [14. 参照（Normative / Informative）](#14-参照normative--informative)

---

## 1. 目的と設計方針
- **HEADLINE/2.0 の語彙・挙動を維持**しつつ、**macOS の Loadable Bundle（.plugin/.bundle）**に対応。  
- **文字コードは UTF‑8 を既定**とし、互換のため **Shift_JIS / Windows‑31J** 等のラベルを **同一系として受理**します。  
- **バイナリ互換は対象外**。Windows 固有の API（HGLOBAL 等）は用いず、**生バイト列 + 長さ**の呼び出し規約に読み替えます。

## 2. 用語
- **2.0M**: 本仕様の Mac 差分版識別子。  
- **ホスト**: Ourin（桜鈴）など、HEADLINE モジュールを実行するベースウェア。  
- **モジュール**: HEADLINE の実装本体（.plugin/.bundle で配布）。  
- **ワイヤ**: `GET Version HEADLINE/2.x` / `GET Headline HEADLINE/2.x` を先頭行とするテキストの往復。

## 3. 適用範囲と互換性
- **語彙互換**：`GET Version` / `GET Headline`、`Charset`、`Option`、`Path`、`Headline`、`RequestCharset` など **HEADLINE/2.0 と同一のヘッダ/意味**を踏襲します。  
- **既定文字コード**：2.0M では未指定時 **UTF‑8**。`Shift_JIS` / `Windows‑31J` などは **同一系（CP932 相当）**として受理します。  
- **呼び出し回数**：`GET Headline` は **旧ファイル→新ファイル**の **2 回**呼び出され得ます（順不同）。モジュールは順に依存しないこと。

## 4. OS/CPU と配布
- **最小 OS:** **macOS 10.15（Catalina）以降**。  
- **配布形態:** **Universal 2**（`arm64 + x86_64`）を推奨必須。  
- **実体:** **Bundle（.plugin/.bundle）** とし、CFBundle/Bundle API でロードします。

## 5. 実体とエクスポート（.plugin/.bundle）
- **必須エクスポート（C ABI）**
  ```c
  // HEADLINE/2.0 の “execute” を踏襲
  const unsigned char* execute(const unsigned char* req, size_t len, size_t* out_len);

  // 任意：メモリ解放フック（ホストが即時コピーする設計を推奨）
  void headline_free(void* p);

  // 任意：ライフサイクル（UTF‑8 パス受領を推奨）
  int  loadu(const char* plugin_dir_utf8); // 成功0
  void unload(void);
  ```
- **ロード/解決**：ホストは `CFBundleGetFunctionPointerForName` で `execute` を取得。返却バッファは **UTF‑8** を推奨。

## 6. ワイヤ（HEADLINE/2.0 との差分）
- **版表記**：`HEADLINE/2.0M`（構文は 2.0 と同形）。  
- **CRLF/空行終端**：2.0 と同じ。ゼロ終端は前提にしない。  
- **`Option: url`**：2.0 と同じく有効。`Headline:` 値は **本文 + 0x01 + URL**（複数行可）。  
- **`RequestCharset`**：モジュールからホストへ **次回の希望文字コード**を提示可。

## 7. Path の表現（macOS 最適化）
- **推奨**：`Path:` は **POSIX 絶対パス（UTF‑8）** または **`file://` URL（RFC 8089 準拠）**。  
- **互換**：Windows 風パス `C:\...` を受け取った場合、**ホスト側で POSIX/`file://` に正規化**してからモジュールに渡します。  
- **実装ヒント**：Foundation の `URL(fileURLWithPath:)` / `standardizedFileURL` を利用。

## 8. 設定ファイル（descript.txt）差分
- **基本**は HEADLINE/2.0 の規定に従います（`name`/`dllname`/`url`/`openurl` 等）。  
- **2.0M 追加**：`dllname` の代替として **`filename` に .plugin/.bundle** を指定可能（両立時は `filename` を優先）。  
- **文字コード**：`charset` は UTF‑8 推奨（旧互換で Shift_JIS も可）。  
- **注意**：行頭が `\` / `%` の文字列は**破棄対象**のため、利用時は**エスケープ**が必要。

## 9. エラー応答の指針
- **400 Bad Request**：CRLF/空行終端の欠落、必須ヘッダ不足。  
- **415 Unsupported Charset**：不明なラベル。  
- **500 Module Error**：モジュール内例外。

## 10. セキュリティ/安定性（XPC隔離は推奨）
- 解析負荷が高いモジュールは **NSXPCConnection** を用いて **別プロセス**化（`request(Data)->Data` 相当の橋渡し）。  
- クラッシュ隔離・権限最小化に寄与。

## 11. 例（Version / Headline 取得）

### 11.1 Version 照会
**Request**
```
GET Version HEADLINE/2.0M
Charset: UTF-8
Sender: Ourin
```

**Response**
```
HEADLINE/2.0M 200 OK
Charset: UTF-8
Value: HeadlineModule 1.1
```

### 11.2 Headline 取得（`Option: url`）
**Request**
```
GET Headline HEADLINE/2.0M
Charset: UTF-8
Option: url
Path: file:///Users/you/Library/Application%20Support/Ourin/cache/news.html
```

**Response**
```
HEADLINE/2.0M 200 OK
Charset: UTF-8
Headline: ほげ1\x01https://example.com/1
Headline: ほげ2\x01https://example.com/2
Headline: ほげ3\x01https://example.com/3
```

> 注: `GET Headline` は **旧/新ファイルに対して 2 回**呼ばれ得ます。順序に依存しない実装としてください。

## 12. 最小実装（C）
```c
#include <stdlib.h>
#include <string.h>
static unsigned char* dupmsg(const char* s, size_t* out){ size_t n=strlen(s); unsigned char* p=malloc(n); memcpy(p,s,n); *out=n; return p; }

const unsigned char* execute(const unsigned char* req, size_t len, size_t* out_len) {
  (void)len; (void)req;
  // 超簡易: Versionリクエストだけ200で返すデモ（実用では解析必須）
  const char* ok =
    "HEADLINE/2.0M 200 OK\r\n"
    "Charset: UTF-8\r\n"
    "Value: HeadlineModule 1.0\r\n"
    "\r\n";
  return dupmsg(ok, out_len);
}
void headline_free(void* p){ free(p); }
int loadu(const char* plugin_dir_utf8){ (void)plugin_dir_utf8; return 0; }
void unload(void){}
```

## 13. 適合チェックリスト
- [ ] 先頭行に `HEADLINE/2.0M` を用い、**CRLF/空行終端**で往復できる。  
- [ ] **UTF‑8 既定**、`Shift_JIS`/`Windows‑31J` を受理。  
- [ ] `Option: url` 時の `Headline: 本文\x01URL` を処理。  
- [ ] `Path:` に **POSIX/`file://`** を受理（Windows 風はホストで正規化）。  
- [ ] 実体は **.plugin/.bundle**、`execute` を C ABI で公開。

## 14. 参照（Normative / Informative）
- UKADOC: **HEADLINE/2.0**（語彙・`Option: url`・0x01区切り・2回呼び出しの注意）  
- UKADOC: **Headline 設定（descript.txt）**（必須項目・文字コード・`\`/`%` エスケープ）  
- UKADOC: **DLL共通仕様**（Windows 固有メモリ規約の参考—2.0M では置換）  
- Apple: **CFBundleGetFunctionPointerForName**（関数名でポインタ解決）  
- Apple: **Universal 2**（`arm64`/`x86_64`）  
- Apple: **32‑bit 非対応（10.15+）**  
- RFC 8089: **file URL**  
