# SHIORI External Events — **3.0M‑Mac 仕様書（UKADOC準拠）**
**Status:** Draft / Ourin (macOS 10.15+ / Universal 2)  
**Updated:** 2025-07-27 (JST)  
**互換方針:** UKADOC「**外部からのSHIORI Event**」の**イベント名・意味・Reference順**を踏襲。Windows依存の通信路は **macOSネイティブ**に置換。  
**想定読者:** Ourin（ベースウェア）実装者・外部アプリ開発者。

---

## 目次
- [1. 目的と範囲](#1-目的と範囲)
- [2. トランスポート（通信路）](#2-トランスポート通信路)
  - [2.1 Socket SSTP (TCP/9801)](#21-socket-sstp-tcp9801)
  - [2.2 SSTP-over-HTTP (拡張)](#22-sstp-over-http-拡張)
  - [2.3 DirectSSTP‑Mac as XPC (拡張)](#23-directsstp-mac-as-xpc-拡張)
- [3. 文字コード/改行/パス表現](#3-文字コード改行パス表現)
- [4. イベント互換ルール](#4-イベント互換ルール)
- [5. フレーム例（SSTP/HTTP/XPC）](#5-フレーム例sstphttpxpc)
- [6. セキュリティ/サンドボックス](#6-セキュリティサンドボックス)
- [7. テスト観点チェックリスト](#7-テスト観点チェックリスト)
- [8. 変更履歴](#8-変更履歴)

---

## 1. 目的と範囲
- **外部アプリ/他ゴースト/プラグイン**等が発火する「外部SHIORI Event」を、Ourin 上で**語彙互換**のまま受信・転送する。  
- 本ページは **UKADOCの集録**に基づく互換実装ガイドであり、個別イベントの詳細は **各発行元の公式**を正とする。

## 2. トランスポート（通信路）

### 2.1 Socket SSTP (TCP/9801)
- **送受信**: `NOTIFY SSTP/1.x` / `SEND SSTP/1.x` 等の**SSTP/1.x**フレームを **TCP:9801**で受信。  
- **応答**: `SSTP/1.x 200 OK` / `204 No Content` など（[NOTIFY]はスクリプト無視）。  
- **互換**: 原典どおり **CRLF 改行**, `Charset:` 任意指定（なければ UTF‑8）。

### 2.2 SSTP-over-HTTP (拡張)
- **メソッド/パス**: `POST /api/sstp/v1`  
- **ヘッダ**: `Content-Type: text/plain; charset=<enc>`（推奨）  
- **ボディ**: **SSTP/1.xの生テキスト**（`NOTIFY ...` ～ `CRLFCRLF`）。  
- **目的**: Firewalls/プロキシ越しや HTTP 標準ログの活用。互換維持のため **SSTP文法は変更しない**。

### 2.3 DirectSSTP‑Mac as XPC (拡張)
- **IPC**: `NSXPCListener(machServiceName: "jp.ourin.sstp")` を使う**Machサービス**として受信。  
- **インターフェース**: `deliverSSTP(request: Data, reply: (Data)->Void)`（UTF‑8/CP932を受理）。  
- **用途**: ローカル高速配送・プロセス隔離。

## 3. 文字コード/改行/パス表現
- **文字コード**: 既定 **UTF‑8**。互換のため **CP932/Shift_JIS**受理→内部UTF‑8正規化。`Charset:` 指定があれば優先。  
- **改行**: 受信は **CRLF** を厳守（内部処理は LF 正規化可）。  
- **パス**: **POSIX絶対パス**または **`file://` URL**を標準。Windows形式が来た場合は受信側で正規化。

## 4. イベント互換ルール
- **[NOTIFY] 明記のイベント**は必ず NOTIFY で通知され、**返却スクリプトは無視**。  
- **無印**は状況に応じ **GET/NOTIFY いずれも**あり得る。  
- Ourin は**未知のイベント名でも透過**で SHIORI/3.0 へ横流し（語彙保持）。

## 5. フレーム例（SSTP/HTTP/XPC）

### 5.1 Socket SSTP（TCP/9801, NOTIFY）
```
NOTIFY SSTP/1.1
Sender: ExternalApp
Charset: UTF-8
Event: OnRequestValues
Reference0: OtherGhost
Reference1: プロフィール
Reference2: LIFE

\r\n
```

### 5.2 SSTP-over-HTTP（POST）
```
POST /api/sstp/v1 HTTP/1.1
Host: 127.0.0.1
Content-Type: text/plain; charset=UTF-8
Content-Length: <len>

NOTIFY SSTP/1.1
Sender: ExternalApp
Event: OnRequestValues
...
```

### 5.3 DirectSSTP‑Mac（XPC）
- `request` には **SSTP/1.x の生バイト列**を渡す。応答は `SSTP/1.x 200 OK ...` の生バイト列。

## 6. セキュリティ/サンドボックス
- **受信バインド**: 既定は `127.0.0.1` のみ（ローカル限定）。  
- **パス受領**: `file://` 正規化と、必要時 **security‑scoped URL** 管理。  
- **XPC**: `NSXPCListener` の**エクスポートインターフェース**を厳密化、署名/識別子で接続制御。

## 7. テスト観点チェックリスト
- [ ] CRLF 行末・`Charset:` 解釈・CP932混在の受理  
- [ ] [NOTIFY]/無印の動作差・返却コード（200/204/400 等）  
- [ ] Socket/HTTP/XPC のいずれでも同一イベントが SHIORI へ渡ること  
- [ ] ローカルバインド・ポート占有時の自動再試行  
- [ ] 大きな本文・複数 `ReferenceN`・未知イベント名の透過

## 8. 変更履歴
- 2025-07-27: 初版（3.0M‑Mac）。
