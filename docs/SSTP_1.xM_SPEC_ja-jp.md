
# SSTP/1.xM — macOS 差分仕様（Draft）
**Status:** Draft  
**Updated:** 2025-07-26  
**Audience:** Ourin（桜鈴）/ ベースウェア実装者・クライアント開発者  
**Scope:** UKADOC **SSTP/1.x** の語彙と挙動を維持しつつ、**macOS ネイティブ**（Network.framework + XPC）で安全に動作させるための差分を定義する。  
**非目標:** WindowsのWM_COPYDATAに代表されるバイナリ互換。語彙・挙動の互換のみ。

---

## 目次
- [1. 方針と非目標](#1-方針と非目標)
- [2. 用語](#2-用語)
- [3. 互換ポリシー（そのまま踏襲）](#3-互換ポリシーそのまま踏襲)
- [4. macOS 差分（置き換える/追加する）](#4-macos-差分置き換える追加する)
- [5. 文字コードポリシー](#5-文字コードポリシー)
- [6. ヘッダ差分（受理/非適用）](#6-ヘッダ差分受理非適用)
- [7. ステータスコード](#7-ステータスコード)
- [8. SSTP over HTTP（互換）](#8-sstp-over-http互換)
- [9. 例（SEND/NOTIFY/EXECUTE）](#9-例sendnotifyexecute)
- [10. 参考実装パラメータ（推奨既定値）](#10-参考実装パラメータ推奨既定値)
- [11. 適合チェックリスト](#11-適合チェックリスト)
- [12. 付録 A: XPC 版 DirectSSTP の最小IF](#12-付録-a-xpc-版-directsstp-の最小if)

---

## 1. 方針と非目標
- **ワイヤ（メソッド/ヘッダ/CRLF終端）は SSTP/1.x 準拠**。`SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE`、`Charset`、`Sender`、`Option` 等の解釈は原典を踏襲。**keep‑alive は前提とせず、通信毎に切断**。  
- **輸送レイヤ**：TCP サーバを **Network.framework** で実装（既定ポート **9801/tcp**。SSP 互換用に 9821 を任意対応）。**既定はループバックのみ**。  
- **DirectSSTP の置換**：Windows の `WM_COPYDATA` に依存する DirectSSTP を、macOS では **XPC（NSXPCConnection）** による同等 IPC として規定。

## 2. 用語
- **(Socket)SSTP**：TCP 上でやりとりする SSTP。  
- **DirectSSTP**：OS の IPC を使う軽量 SSTP。macOS では **XPC** とする。  
- **SSTP over HTTP**：HTTP のメッセージボディに SSTP リクエスト/レスポンスをそのまま載せる互換ブリッジ。

## 3. 互換ポリシー（そのまま踏襲）
- **SSTP の概要とポート**：SSTP はゴースト間汎用通信。実装は 9801/tcp（SSP は 9821 を使用可）。**現在の実運用は 9801 が主**。ローカルホスト限定の待受が標準。  
- **構文**：`CRLF` 改行、**空行で終端**。**Charset ヘッダは必須**（省略時はエラー扱いか実装依存で OS 既定にフォールバック）。**レスポンスには追加データが付く場合がある**。**リクエストとレスポンスで SSTP の版が異なることがある**ため、**版番号に依存した解釈は禁止**。  
- **メソッド**：`NOTIFY`（イベント通知）、`SEND`（スクリプト送出）、`COMMUNICATE`（ユーザ入力相当の反応）、`EXECUTE`（状態取得/制御）、`GIVE`（旧仕様）を保持。

## 4. macOS 差分（置き換える/追加する）
### 4.1 (Socket)SSTP（TCP）
- **実装**：`NWListener(using: .tcp, on: 9801)` で起動。**既定は 127.0.0.1/::1 に限定**して bind。外部公開は設定で明示。  
- **バインドアドレス**：`SstpTcpServer.makeListener(host:port:)` は `host` パラメータに基づいて bind 先を決定する。`127.0.0.1` / `localhost` / `::1` などの特定アドレスは `NWParameters.requiredLocalEndpoint` を設定してそのアドレスのみにバインドする。`0.0.0.0` / `::` / 空文字列のときだけ全インターフェースで待ち受ける（`SstpHttpServer` も同じ `makeListener` を使用）。  
- **TCP body 転送**：TCP ハンドラはヘッダ終端（`\r\n\r\n`）の検出後、**ヘッダ＋本文（body）を含むバッファ全体** を SSTP スタックへ渡す。以前の実装では body が破棄されていたが、`SSTPParser` は空行以降を body として取り込むため全体を渡す必要がある。  
- **サンドボックス**：App Sandbox 下では、サーバは **`com.apple.security.network.server`**、クライアントは **`com.apple.security.network.client`** を付与。  
- **ファイアウォール**：アプリケーション・ファイアウォール有効時は、**受信を許可**する必要がある。署名/ダウンロードアプリの自動許可設定がある。

### 4.2 DirectSSTP（macOS XPC 版）
- **実体**：`App.app/Contents/XPCServices/ukagaka.sstp.xpc` などの **XPC サービス**。  
- **IF**：`executeSSTP(request: Data, withReply: (Data)->Void)`（**リクエスト/レスポンスの内容は SSTP/1.x テキスト**）。  
- **接続**：`NSXPCConnection(serviceName:)` or `NSXPCConnection(machServiceName:)`。必要に応じてコード署名要件を設定。  
- **セキュリティ**：XPC は**同一開発者署名**での疎通が基本。外部プロセスとの接続には Mach サービス/エンドポイントの設計が必要。

### 4.3 受信ゴーストの特定
- **ReceiverGhostName** を推奨。**ReceiverGhostHWnd** は macOS では **非適用**（無視）。  
（(Socket)SSTP でもゴーストを**名前**で固定可能。見つからない場合は **404 Not Found** を返す。）

## 5. 文字コードポリシー
- 既定は **UTF‑8**。  
- 互換のため、`Shift_JIS`/`Windows‑31J`/`CP932`/`SJIS` 等のラベルは **同一系（CP932 ≒ Windows‑31J）として受理**する。WHATWG Encoding では `shift_jis` と `windows-31j` を**同一のデコーダ**で扱う。

## 6. ヘッダ差分（受理/非適用）
- **保持**：`Sender`、`SecurityLevel`（local/external）、`SecurityOrigin`、`Option`（`nodescript`/`notranslate`/`nobreak`）、`ID`（Owned SSTP）、`X‑SSTP‑PassThru-*`。  
- **非適用**：`HWnd`（DirectSSTP 専用）→ macOS では XPC のため **無視**。`ReceiverGhostHWnd` も同様。  
- **SEND 特有**：`Option: notify` を実装（SSP 2.6.76 相当の挙動）。

### 6.1 Owned SSTP
- `ID`は、対象ゴーストへSHIORI `uniqueid`として通知済みの値、または対象ゴーストのFMOレコードIDと完全一致した場合だけ有効。
- `ReceiverGhostName`指定時は、そのゴーストに属するIDだけを照合する。省略時はプライマリゴーストだけを照合する。
- 有効なOwned要求はSHIORIへ`SecurityLevel: local`として渡す。不明IDや対象違いは昇格せず、元のセキュリティ文脈を維持する。
- 外部HTTP Originからの要求は、IDが一致してもOwnedへ昇格しない。

## 7. ステータスコード
- **200 OK**（返り値つき）/ **204 No Content**（返り値なし）/ **210 Break**（実行はされたがブレーク）/ **400**/ **404**/ **408**/ **409**/ **413**/ **420**/ **500**/ **501**/ **503**/ **505**/ **512** を維持。

## 8. SSTP over HTTP（互換）
- **エンドポイント**：`POST http://localhost:9801/api/sstp/v1`、`Content‑Type: text/plain`、**Content‑Length 必須**。  
- **応答**：HTTP は常に **200 OK**（中身は SSTP レスポンス）。**Origin が localhost 以外**の場合は**強制的に external**扱いとなる。

## 9. 例（SEND/NOTIFY/EXECUTE）

### 9.1 SEND（最小）
```
SEND SSTP/1.0
Charset: UTF-8
Sender: Ourin
Script: \h\s0こんにちは

```

**Response**
```
SSTP/1.4 200 OK
Charset: UTF-8
Script: \h\s0受信したよ

```

### 9.2 NOTIFY（イベント通知のみ）
```
NOTIFY SSTP/1.0
Charset: UTF-8
Sender: Media Player
Event: OnMusicPlay
Reference0: 自由の翼
Reference1: Linked Horizon

```

### 9.3 EXECUTE（情報取得）
```
EXECUTE SSTP/1.1
Charset: UTF-8
Sender: Ourin
Command: GetName

```

## 10. 参考実装パラメータ（推奨既定値）
- **Port**: 9801/tcp（必要なら 9821 も待受）。
- **Bind**: 127.0.0.1 / ::1（外部公開はオプトイン）。
- **Charset**: 既定 UTF‑8、SJIS 系ラベルは CP932 として受理。

## 11. 実装状況（Implementation Status）

**更新日:** 2026-06-28

### 11.1 Ourin ホスト側の実装

- [x] **TCP SSTP サーバ**: `SstpTcpServer.swift` にて Network.framework を使用して実装済み
- [x] **HTTP SSTP サーバ**: `SstpHttpServer.swift` にて実装済み
- [x] **XPC DirectSSTP**: `XpcDirectServer.swift` および `DirectSSTPXPC.swift` にて実装済み
- [x] **SSTP パーサー**: `SSTPParser.swift` にてリクエスト解析を実装済み（順序保持ヘッダ対応）
- [x] **SSTP ディスパッチャ**: `SSTPDispatcher.swift` にて全メソッド処理を実装済み
- [x] **SSTP↔SHIORI ライブゴーストブリッジ**: `BridgeToSHIORI.swift` にて `liveGhostResolver` 経由で稼働中ゴースト（YAYA）へルーティング実装済み
- [x] **文字コード対応**: UTF-8 既定、Shift_JIS/CP932 の受理機能を実装済み
- [x] **統合管理**: `OurinExternalServer.swift` にて TCP/HTTP/XPC の統合管理を実装済み
- [x] **完全な SSTP/1.x プロトコル**: 全メソッドおよび主要オプションヘッダを実装済み

### 11.2 実装済みの機能

1. **SocketSSTP (TCP)**
   - Network.framework による TCP サーバ実装
   - ポート 9801 でのリスニング
   - `requiredLocalEndpoint` によりローカルホスト限定の受信（127.0.0.1/::1）。`0.0.0.0`/`::` 指定時は全インターフェースで受信
   - 全 SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE/INSTALL メソッドの処理
   - ヘッダ＋body 全体を SSTP スタックへ転送（body 破棄なし）

2. **SSTP over HTTP**
   - HTTP サーバの実装（`SstpTcpServer.makeListener` を共用）
   - `/api/sstp/v1` エンドポイント
   - Content-Type: text/plain でのリクエスト受信

3. **DirectSSTP (XPC)**
   - NSXPCConnection によるプロセス間通信
   - `OurinSSTPXPC` プロトコルの実装
   - `executeSSTP(_:withReply:)` メソッドの実装

4. **リクエスト処理**
   - CRLF + 空行終端の解析
   - `Charset` ヘッダの処理
   - `SecurityLevel`/`SecurityOrigin` の解釈と `securityLocalOnly` ポリシー
   - `ReceiverGhostName` によるゴースト固定（未発見は 404）
   - `Option` の全パターン (`nodescript`/`notranslate`/`nobreak`)

5. **ルーティングと SHIORI ブリッジ**
   - `SSTPDispatcher.swift` によるリクエストの SHIORI への転送（全経路を一本化、旧 `SstpRouter` は廃止）
   - `BridgeToSHIORI.handleResponse` が完全な SHIORI/3.0 wire 応答を返す
   - `liveGhostResolver` 経由で YayaAdapter（稼働中 YAYA ゴースト）へ届く
   - SSTP NOTIFY は `NOTIFY SHIORI/3.0`、SEND/COMMUNICATE/EXECUTE/GIVE は `GET SHIORI/3.0` として伝播
   - `mapShioriResponse` が `Reference0`..`ReferenceN` を全て SSTP 応答へ反映

6. **マルチライン Value の安全な輸送**
   - `BridgeShioriResponse` 構造体で応答を構造化して保持
   - `serializeWire` がヘッダ値の CR/LF を除去してから wire 文字列へ直列化（行注入・スクリプト切断防止）
   - 同期 IPC タイムアウト: 2 秒

### 11.3 外部公開設定

- 現在はローカルホスト限定が既定
- `host` パラメータに `0.0.0.0` / `::` を指定することで全インターフェースで受信可能（オプトイン）

## 12. 適合チェックリスト
- [x] CRLF と空行終端の正しい処理（実装済み）  
- [x] `Charset` 必須（UTF‑8 推奨）。SJIS 系は CP932 として受理（実装済み）  
- [x] `SecurityLevel`/`SecurityOrigin` の解釈（実装済み）  
- [x] `ReceiverGhostName` によるゴースト固定（未発見は 404）（実装済み）  
- [x] **DirectSSTP (macOS)** = **XPC** で `request(Data)->Data` の橋渡し（実装済み）  
- [x] **SSTP over HTTP** `/api/sstp/v1` を localhost 限定で実装（実装済み）
- [x] SSTP→SHIORI メソッド対応（NOTIFY→`NOTIFY SHIORI/3.0`、他→`GET SHIORI/3.0`）（実装済み）
- [x] SHIORI 応答の全 `ReferenceN` を SSTP 応答へ転送（実装済み）
- [x] TCP/HTTP リスナーが設定 `host` に従い `requiredLocalEndpoint` でバインド（実装済み）
- [x] TCP raw path が body を含む全リクエストを SSTP スタックへ転送（実装済み）
- [x] マルチライン Value の CR/LF 除去による行注入防止（実装済み）

## 13. 付録 A: XPC 版 DirectSSTP の最小IF
```swift
@objc public protocol OurinSSTPXPC {
    func executeSSTP(_ request: Data, withReply reply: @escaping (Data) -> Void)
}
// Host側: NSXPCConnection(serviceName: "app.ourin.sstp") で接続し、
// requestはSSTPテキスト(UTF-8)をData化して送る。
```
