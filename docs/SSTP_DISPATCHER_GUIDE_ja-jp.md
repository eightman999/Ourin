# SSTP Dispatcher ガイド

## 概要

`Ourin/SSTP/SSTPDispatcher.swift` はパースされた `SSTPRequest` を受け入れて、SHIORI ブリッジロジックへルーティングします。

対応メソッド：

- `SEND`
- `NOTIFY`
- `COMMUNICATE`
- `EXECUTE`
- `GIVE`
- `INSTALL`

非対応メソッドは `400` を返します。

## ディスパッチフロー

主要エントリー：

- `SSTPDispatcher.dispatch(request:)`

コアルート関数：

- `routeToShiori(request:method:)`

フロー：

1. イベント名の解決 (`Event` ヘッダー オーバーライドまたはメソッドデフォルト)
2. References の抽出 (`Reference0..N`、plus `Sentence`/`Command` 特別処理)
3. SHIORI ヘッダー構築
4. `BridgeToSHIORI.handleResponse(...)` を呼び出し（完全な SHIORI/3.0 wire 応答を返す）
5. SHIORI レスポンスフィールドをマップ (`Script`, `Value`, `ValueNotify`, `Data`, `ReferenceN`, status 等)
6. SSTP wire レスポンスを発行

### SHIORI ブリッジへのルーティング（稼働中ゴースト対応）

`routeToShiori` は `BridgeToSHIORI.handleResponse` を呼び出します。旧実装が `handle`（値のみ返す）を使用していたのに対し、`handleResponse` は完全な SHIORI/3.0 wire 文字列を返すため `mapShioriResponse` が `ReferenceN`・`ValueNotify`・`Status` 等を保持できます。

`BridgeToSHIORI.handleResponse` の解決順序は以下のとおりです：

1. **テスト/登録済みリソース** (`Resource` イベントのみ) — テスト用スタブ値
2. **ネイティブ SHIORI バンドル** (`SHIORI_BUNDLE_PATH` 環境変数で設定) — `ShioriHost` 経由
3. **稼働中ゴースト** (`liveGhostResolver`) — `AppDelegate` が起動時に設定する `YayaAdapter` 等への参照

`liveGhostResolver` が設定されると、外部 SSTP リクエストは実際にロードされた YAYA ゴーストへ届きます。これ以前は `SHIORI_BUNDLE_PATH` が未設定の場合にゴーストが応答しない問題がありました。

#### SHIORI メソッドの対応付け

| SSTP メソッド | SHIORI メソッド | 理由 |
|---|---|---|
| `NOTIFY` | `NOTIFY SHIORI/3.0` | 返値を期待しない通知（UKADOC SHIORI method 仕様） |
| `SEND` | `GET SHIORI/3.0` | スクリプト返値を期待 |
| `COMMUNICATE` | `GET SHIORI/3.0` | スクリプト返値を期待 |
| `EXECUTE` | `GET SHIORI/3.0` | スクリプト返値を期待 |
| `GIVE` | `GET SHIORI/3.0` | スクリプト返値を期待 |

## ヘッダープロパゲーション

Dispatcher が保持/正規化するもの：

- `Charset`
- `Sender`
- `SenderType`
- `SecurityLevel`
- オプション `SecurityOrigin`

`X-SSTP-PassThru` はレスポンスで保持されます。

## メソッド固有動作

- `NOTIFY` は SHIORI から `ValueNotify` が返された場合は `200`、それ以外は `204` を返す
- `EXECUTE` は `Command` ヘッダーを検証し、ない場合は `400` を返す
- `COMMUNICATE` は `Sentence` を references に注入する
- `GIVE` は `OnChoiceSelect` をデフォルトとする
- `INSTALL` は `OnInstall` をデフォルトとする

## レスポンスモデル (`SSTPResponse`)

`Ourin/SSTP/SSTPResponse.swift` がレスポンス形式を一元管理：

- デフォルトステータスメッセージ付きステータスライン
- 順序付きキー出力 (`Charset`, `Sender`, `Script`, `Data`, `X-SSTP-PassThru` など)
- `toWireFormat()` が CRLF 区切り wire 文字列を出力

対応ステータスメッセージ：

- `200`, `204`, `210`
- `4xx` 一般的な検証/セキュリティエラー
- `5xx` サーバー能力エラー
- `512 Invisible`

## テスト

- `OurinTests/SSTPDispatcherTests.swift`
- `OurinTests/SSTPResponseTests.swift`

テストはルーティング、マッピング、プロパゲーション、wire フォーマットを検証します。

## ReferenceN の保持

`mapShioriResponse` は SHIORI 応答の `Reference0` から `ReferenceN` をすべて SSTP 応答ヘッダへ反映します（旧実装では `Reference0` のみが取り出されていました）。UKADOC の規定では SHIORI 応答の `ReferenceN` は SSTP 応答へそのまま転送します。

## 現在のステータス

**ステータス**: 稼働中ゴーストとのエンドツーエンド統合完了 / 2026-06-28

### 実装済みコンポーネント

#### ✅ **SSTPDispatcher.swift** (完全)
以下を含む完全に機能するリクエストパーサーとディスパッチャー：
- すべての SSTP メソッド (SEND, NOTIFY, COMMUNICATE, EXECUTE, GIVE, INSTALL) をパース
- イベント解決 (Event ヘッダーまたはメソッドデフォルト)
- Reference 抽出 (Reference0..N, Sentence, Command)
- ヘッダー正規化とプロパゲーション
- `BridgeToSHIORI.handleResponse` 経由で稼働中ゴーストへルーティング

#### ✅ **BridgeToSHIORI.swift** (完全)
ライブゴーストブリッジの実装：
- `handleResponse` — 完全な SHIORI/3.0 wire 応答を返す（SSTP ディスパッチャ向け）
- `handle` — 値のみ返す（GhostManager / ResourceBridge 等の内部用）
- `liveGhostResolver` — `AppDelegate` が起動時に YayaAdapter を登録するクロージャ
- `BridgeShioriResponse` 構造体で応答を構造化したまま受け渡し（CR/LF を含む Value の行注入を防止）
- `serializeWire` でヘッダ値の CR/LF を除去してから wire 文字列へ直列化
- 同期 IPC タイムアウト: **2 秒**

#### ✅ **SSTPResponse.swift** (完全)
以下を含む完全に機能するレスポンスビルダー：
- すべてのステータスコード (200, 204, 210, 4xx, 5xx, 512)
- Wire フォーマット生成 (toWireFormat())
- ヘッダー順序付けと形式
- Charset、Sender、Script、Data ハンドリング
- X-SSTP-PassThru 保持

---

## 動作上の注意

- Dispatcher は意図的にステートレスです。
- SHIORI マッピングは寛容です：非 `SHIORI/` レスポンステキストはスクリプトペイロードとして扱われます。
- `liveGhostResolver` が nil の場合（ゴースト未ロード時）、`BridgeToSHIORI.handleResponse` は空文字列を返し、ディスパッチャは `503 Service Unavailable` を返します。
- マルチライン ghost Value（改行を含む Sakura Script 等）は `BridgeShioriResponse` で構造化したまま保持され、`serializeWire` が wire 化する際に CR/LF を除去します。Sakura Script の改行は `\n` トークンで表現されるため、生の改行除去は表示上安全です。
