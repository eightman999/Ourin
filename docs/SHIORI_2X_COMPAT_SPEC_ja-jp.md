# SHIORI/2.x 互換仕様書（Ourin実装用）

作成日: 2026-07-08
出典: http://usada.sakura.vg/contents/shiori.html （Materia時代の公式SHIORI仕様。以下「原典」）
用途: Ourin の SHIORI/2.x 互換レイヤー（`Ourin/USL/ShioriLoader.swift`）実装の正本。
方針: 原典で確認できた項目のみ「確定」。原典に無い項目（SHIORI/2.6 の詳細等）は「要検証」として明示する。

## 0. 共通事項（確定）

- 全リクエストは唯一のエントリポイント `request` で行う（2.0以降）。
- ワイヤ形式はHTTP/SSTP類似: 全行 CR+LF 区切り、1行目に `<コマンド> <バージョン>`、2行目以降にヘッダ、**CR+LF 2つでターミネート**。
- 文字コードの慣例は `Charset: Shift_JIS`（原典の全例示がShift_JIS）。
- **SecurityLevel ヘッダは全リクエストに必ず付与される**（原典「セキュリティ」節）: `local`（本体・ゴースト・ローカルSSTP、信用できる）/ `external`（それ以外）。
- OnClose等の基礎的なものを除きイベントは無視可能。無視する場合は **204 No Content** を返す。

### ステータスコード（確定）

| コード | 意味 |
|---|---|
| 200 OK | 正常終了 |
| 204 No Content | 正常終了・返すデータなし |
| 310 Communicate | **deprecated**（2.1由来、2.3bのTo/Age方式に置換） |
| 311 Not Enough | TEACHで情報不足 |
| 312 Advice | TEACH内の最新ヘッダが解釈不能 |
| 400 Bad Request | リクエスト不備 |
| 500 Internal Server Error | サーバ内エラー |

## 1. SHIORI/2.0 — 基礎プロトコル（確定）

### GET Version
```
GET Version SHIORI/2.0
Sender: Nobody
Charset: Shift_JIS
```
→ `SHIORI/2.0 200 OK`（クライアントはこのバージョン情報でリクエストレベルを変える）

### NOTIFY OwnerGhostName
```
NOTIFY OwnerGhostName SHIORI/2.0
Sender: Nobody
Ghost: さくら
Charset: Shift_JIS
```
→ `SHIORI/2.0 200 OK`。`Ghost:` = 動作中のゴースト名。2.0のNOTIFYはこれのみ。

### GET Sentence（2.0 = ユーザー入力）
```
GET Sentence SHIORI/2.0
Sender: User
Charset: Shift_JIS
Sentence: おはよー。
```
→
```
SHIORI/2.0 200 OK
Sender: First
BalloonOffset: 0,0[1]0,0
Sentence: \0\s0おはよー。\e
```
- レスポンスヘッダ: `Sender:`=SHIORIのID、`Sentence:`=さくらスクリプト、`BalloonOffset:`=省略可（バイト値1とカンマ区切り、sakura.x/sakura.y/kero.x/kero.y、シェル設定をオーバーライド）。

### GET Word
```
GET Word SHIORI/2.0
Sender: materia
Type: \ms
Charset: Shift_JIS
```
→ `SHIORI/2.0 200 OK` + `Word: さくら`
- `Type:` の値（単語クラス、確定）: `\ms`人 / `\mz`無機物 / `\ml`集合 / `\mc`社名 / `\mh`店名 / `\mt`技 / `\me`食物 / `\mp`地名 / `\m?`非限定 / `\dms`長めの名詞。
  （Ourinの `EnvironmentExpander` lexicon 10キーと同一体系）

### GET Status
```
GET Status SHIORI/2.0
Sender: Nobody
Charset: Shift_JIS
```
→ `SHIORI/2.0 200 OK` + `Status: 0,0,0,0,0,0`（neuron,neuronm,neuronk,neurond,neurone,synapse。AIグラフ用・無視可）

## 2. SHIORI/2.2 — イベント（確定）

```
GET Sentence SHIORI/2.2
Sender: Nobody
Event: OnDisplayChange
Reference0: 32
Reference1: 1280
Reference2: 1024
SecurityLevel: external
Charset: Shift_JIS
```
- `Event:` = イベント識別子（unique・一定・一意）。
- `Reference0..7` = 付帯情報。**2.2のReference上限は8個（Reference7まで）**。
- 応答は 200 OK + `Sentence:`（発話する場合）or 204（無視）。

原典記載の主要イベント（抜粋・確定）:
- OnFirstBoot(Ref0=Vanishカウント) / OnBoot / OnClose / OnWindowStateMinimize / OnWindowStateRestore / OnTeachStart
- OnGhostChanging(Ref0=次ゴースト名, Ref1=manual|automatic) / OnGhostChanged(Ref0=前ゴースト名) / OnShellChanging / OnShellChanged(Ref0=次シェル名)
- OnVanishSelecting / OnVanishSelected / OnVanishCancel / OnVanishButtonHold / OnVanished(Ref0=前ゴースト名)
- OnSecondChange / OnMinuteChange（Ref0=連続起動時間h, Ref1=見切れ, Ref2=重なり, Ref3=cantalk。bool は 0/1）
- OnSurfaceChange(Ref0=sakura側surface, Ref1=kero側surface) / OnSurfaceRestore
- OnMouseMove / OnMouseClick / OnMouseDoubleClick / OnMouseWheel（Ref0=x, Ref1=y, Ref2=wheel, Ref3=owner 0:Sakura/1:Kero, Ref4=当たり判定識別子）/ OnKeyPress(Ref0=キー文字)
- OnChoiceSelect(Ref0=選択肢ID) / OnChoiceTimeout(Ref0=タイムアウトしたスクリプト)
- OnSSTPBreak(Ref0=例外の起きたスクリプト)
- OnInstallBegin / OnInstallComplete(Ref0=種別 shell|ghost|balloon|plugin, Ref1=名前, Ref2=次オブジェクト名) / OnInstallFailure(Ref0=事由) / OnInstallRefuse(Ref0=指名ゴースト名)
- OnFileDropping / OnFileDropped / OnDirectoryDrop / OnWallpaperChange / OnURLDropping / OnURLDropped
- OnDisplayChange(Ref0=bpp, Ref1=width, Ref2=height) / OnNetworkHeavy / OnSSTPBlacklisting / OnRecommendsiteChoice
- OnUpdate系 / OnBIFF系 / OnSNTP系 / OnHeadlinesense系 / OnMusicPlay / OnNar系 / OnUpdatedata系

## 3. SHIORI/2.3b — ゴースト間対話（確定）

### NOTIFY（2.3）
```
NOTIFY OwnerGhostName SHIORI/2.3
Sender: materia
Ghost: さくら
Charset: Shift_JIS
```
```
NOTIFY OtherGhostName SHIORI/2.3
Sender: materia
GhostEx: なる[1]0[1]1
GhostEx: まゆら[1]0[1]1
Charset: Shift_JIS
```
- `GhostEx:` はバイト値1区切りで「ゴースト名, sakura側surface ID, kero側surface ID」。起動中の他ゴーストの数だけ積み重ねる（いなければ0個）。識別子がGhostExなのは過去互換のため。

### 対話（To/Age/Reference方式）
- SHIORIが話しかける: 200 OK レスポンスに `To:`（相手ゴースト名）と `Age:` を付ける。`Sentence:` が Direct SSTP (COMMUNICATE/1.2) で相手へ送られる。`Reference0..7` で任意の追加情報（内容規約なし・省略可）。
- 受信側: クライアントが `GET Sentence SHIORI/2.3` を発行。通常のGET Sentenceとの違いは (a) `Age:` がある、(b) `Sender:` が Nobody ではなく相手ゴースト名、(c) `Surface: 0,10` 形式で相手サーフェス。
- 返答するときは `Sender` で来た名前を `To` に入れて返す。**Age は必ずインクリメント**。返答しない場合は To を省略。

## 4. SHIORI/2.4 — TEACH（確定）

```
TEACH SHIORI/2.4
Word: ガッツ石松
```
→ `SHIORI/2.4 311 Not Enough` + `Sentence: \h\s0ガッツ石松って何ですか？\e`
- クライアントは追加情報を `Reference0, 1, ...` に積んで再送。序数は311のたびに増える（上限なし）。
- 情報が揃ったら `200 OK` + `Sentence:`。解釈不能な最新ヘッダには `312 Advice`（最新Referenceのみ無効化、確定済みReferenceは再送される）。

## 5. SHIORI/2.5 — GET String（確定）

```
GET String SHIORI/2.5
ID: homeurl
Charset: Shift_JIS
```
→ `SHIORI/2.5 200 OK` + `String: http://sakura.mikage.to/`

定義済みID（確定）: `homeurl`（必須）/ `sakura.recommendsites`・`kero.recommendsites`・`sakura.portalsites`（バイト値1=カラム、バイト値2=行。サイト名,URL,バナーURL。省略可）/ `*.recommendbuttoncaption`・`updatebuttoncaption`・`vanishbuttoncaption`・`readmebuttoncaption`（省略可）/ `vanishbuttonvisible`（bool文字列、省略可）/ `username`（必須）/ `sakura.defaultleft`・`kero.defaultleft`（スクリーンx座標）。
→ Ourinでは SHIORI Resource（3.0の `Resource系イベント`）の2.x版に相当。

## 6. SHIORI/2.1 / 2.6 について

- **2.1（310 Communicate）は deprecated**（原典明記）。実装しない。310を受け取った場合は無視してよい（要検証: SSPの実挙動）。
- **SHIORI/2.6**: 原典ページのメニューは2.5まで。2.6の詳細仕様は原典に存在しない。SSP実装では `GET Sentence SHIORI/2.6` 等のバージョン表記が使われる（Ourinの既存フォールバックも `GET SHIORI/2.6` を送っていた）。**2.6固有の追加仕様は未確認 — 実装上は「2.5までの全機能＋バージョン番号2.6」として扱い、要検証と明記する。**

## 7. Ourin実装方針: 3.0イベント → 2.xリクエスト変換

前提: Ourin内部は3.0イベント駆動。SHIORIモジュールが2.x系と判明した場合（GET Versionの応答行 or descript等）、以下のマッピングで2.x形式に変換して送る。

| Ourin内部（3.0） | 2.xリクエスト | 備考 |
|---|---|---|
| 各種 `GET` イベント（OnBoot等、2.2に存在するID） | `GET Sentence SHIORI/2.2` + `Event:` + `Reference0..7` | Referenceは**最大8個で切り詰め**（超過分は送らない） |
| `NOTIFY` イベント | 同上（2.xにNOTIFYイベント形式は無い） | 応答 `Sentence:` は破棄（3.0 NOTIFYの意味を維持） |
| ユーザー入力（OnTalk/communicate入力） | `GET Sentence SHIORI/2.0` + `Sentence:` | Sender: User |
| OwnerGhostName通知（起動・切替時） | `NOTIFY OwnerGhostName SHIORI/2.3` + `Ghost:` | |
| 他ゴースト一覧通知（installedghostname相当） | `NOTIFY OtherGhostName SHIORI/2.3` + `GhostEx:`×n | |
| communicate受信（OnCommunicate） | `GET Sentence SHIORI/2.3` + `Sender:`=相手名 + `Age:` + `Surface:` | |
| 単語要求（lexicon補完等、Ourinが必要とする場合） | `GET Word SHIORI/2.0` + `Type:` | |
| SHIORI Resource取得 | `GET String SHIORI/2.5` + `ID:` | 3.0 Resource名→2.5 IDの対応は同名を基本とする（要検証） |
| TEACH | `TEACH SHIORI/2.4` + `Word:`/`Reference*` | 311/312/200 の応答処理必須 |
| 2.2に存在しないイベント（OnMouseWheel以降の新イベント等） | **送らない** | 3.0固有イベントを2.xへ勝手に流さない |
| SecurityLevel | 全リクエストに `SecurityLevel: local|external` を付与 | 2.2原典で必須 |

## 8. 2.xレスポンス → 3.0内部表現への変換規則

- ステータス行 `SHIORI/2.x <code> <phrase>` → 3.0の `SHIORI/3.0 <code>` 相当として解釈。
- `Sentence:` → 3.0の `Value:` に相当（さくらスクリプト。`\h\s0...\e` 等の旧形式スクリプトはOurinのSakuraScriptEngineがそのまま解釈する）。
- `Word:` / `String:` / `Status:` → それぞれの要求元（GET Word / GET String / GET Status）の値として返す。
- `To:` + `Age:`（+`Reference*`）付き200 OK → 他ゴーストへのcommunicate送信要求として `SSTPDispatcher` 経由のルーティングに接続（3.0の `Reference0`=相手名のcommunicate応答に相当）。
- `BalloonOffset:` → `sakura/kero.balloonoffset.x/y` プロパティのオーバーライドとして適用（省略時は何もしない）。
- 311/312（TEACH中間応答） → 既存の `ShioriLoader` TEACH処理（3.0では312相当へマップ済み）と整合させる。
- 204 → 3.0の204と同じ（無視）。
- 文字コード: リクエスト・レスポンスとも既定 Shift_JIS（CP932）でエンコード/デコード。レスポンスに `Charset:` があればそれを優先。

## 9. 未確認・要検証事項

1. **SHIORI/2.6 の固有仕様**（原典に無い。SSPソース・他資料での裏取りが必要）
2. GET String の 3.0 Resource名との厳密な対応表（同名前提の妥当性）
3. 310 Communicate 受信時のSSP実挙動（無視でよいか）
4. `GET Sentence SHIORI/2.0`（ユーザー入力）を発行するUI経路がOurinに存在するか（入力ボックス実装との接続）
5. 2.2イベント一覧とOurinの3.0イベント発火箇所の完全な対応（本書の表は主要イベントのみ。全216箇所の突合は実装時に行う）
6. `Sender: materia` の値をOurinでは何にするか（`Ourin` を送る想定だが、Sender値でクライアント判定する古いSHIORIが存在する可能性 — 互換性優先なら要検討）
