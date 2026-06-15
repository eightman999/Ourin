# Ourin（桜鈴）実装監査レポート — AUDIT_CLAUDE

- **監査対象**: Ourin（桜鈴） — macOSネイティブ伺かベースウェア（Swift/SwiftUI + C++ YAYA VM）
- **監査日**: 2026-06-14
- **監査ブランチ**: `claude/clever-franklin-u7ok7p`
- **照合した一次仕様**: UKADOC（`ukatech/ukadoc` ミラー: SakuraScript一覧 / SHIORIイベント一覧 / SHIORI 3.0 / プロパティシステム / descript・install / NAR / SSTP）、YAYA言語仕様、SSP 2.8.x のデファクト挙動
- **手法**: カテゴリA〜Jごとにソースを精読し、UKADOC一次仕様と突き合わせ、`file:行番号` 単位で根拠を提示。主要な指摘（9件）は監査者が直接コードを再読して裏付けを確認済み。

> **環境に関する注記**: 本監査はクラウド実行環境のクローン（`/home/user/Ourin`）に対して実施した。UKADOC本サイト（ssp.shillest.net）はネットワークポリシー上 403 となるため、GitHubミラー（`raw.githubusercontent.com/ukatech/ukadoc`）から一次仕様を取得した。SSPバイナリ（`ssp_2_8_27f.exe`）の実機Wine実行は当環境では不可のため、SSP挙動は仕様＋既知のデファクトから推定している。実機ゴースト互換テストは静的解析ベース（emily4 同梱）であり、動的検証は未実施。

---

## 準拠度スコア一覧

| カテゴリ | 領域 | スコア | 重み |
|---|---|:---:|:---:|
| A | SHIORI プロトコル | 6/10 | ×2 |
| B | SSTP プロトコル | 7/10 | ×1 |
| C | SakuraScript | 7/10 | ×2 |
| D | SHIORIイベント | 6/10 | ×1 |
| E | プロパティシステム | 5/10 | ×1 |
| F | YAYA言語VM | 4/10 | ×1 |
| G | プラグインシステム | 6/10 | ×1 |
| H | NARパッケージ | 5/10 | ×1 |
| I | FMO | 5/10 | ×1 |
| J | バルーン・シェル・リソース | 4/10 | ×1 |

**全体準拠度スコア（SHIORI・SakuraScript を重み2倍とした加重平均）: 5.7 / 10**

加重計算: `(A6×2 + C7×2 + B7 + D6 + E5 + F4 + G6 + H5 + I5 + J4) / 12 = 68 / 12 ≈ 5.7`（単純平均は 5.5）。

総評: ワイヤプロトコルの語彙互換（SHIORI/3.0・SSTP/1.x・SakuraScript・PLUGIN/2.0M）は広くカバーされ、骨格としては「動く」水準にある。一方で、(1) **YAYA VM の根本的な実行欠陥**（ループ・実数・連結演算子）、(2) **SERIKO/2.0 element 合成の未実装**、(3) **イベント Reference 配置・SakuraScript 引数書式の細部バグ**、(4) **文字コード往復（Shift_JIS）の欠落**、という4系統の問題が、実在ゴーストの動作可否に直結する。プロトコルの「形」はできているが、辞書/シェルが依存する「中身」の正確性に課題が集中している。

---

# 詳細監査

## A. SHIORI プロトコル

### 準拠度スコア: 6/10
GET/NOTIFY の往復、CRLF＋空行終端のワイヤ構文、主要ヘッダ（ID/Reference*/Sender/SenderType/SecurityLevel/SecurityOrigin/Status/BaseID）の生成、TEACH→OnTeach の 2.x 写像など、語彙・挙動互換の骨格は揃っている。一方で、(1) ネイティブ backend が応答/要求を UTF-8 固定で処理し `Charset` ヘッダによる Shift_JIS デコードを一切行わない、(2) ステータスコード 311/312 のメッセージ文字列が UKADOC（OnTeach 用）と全く異なる誤り、(3) SHIORI 要求生成パスが 3 系統に分裂し最小パス（`ShioriHost`）が SenderType/Status/SecurityLevel を欠落させる、という標準逸脱がある。仕様準拠の中核は機能するが、文字コードとエラーコードの逸脱が実害となり得るため減点。

### 実装済み（仕様準拠）
- 先頭行 `GET/NOTIFY SHIORI/3.0` + CRLF + 空行終端の生成 → Ourin/SSTP/SSTPDispatcher.swift:367-384（`buildRequest`）, Ourin/SSTP/BridgeToSHIORI.swift:133-147
- GET/NOTIFY メソッド両対応（GET は値返却前提、NOTIFY は通知）→ Ourin/SSTP/SSTPDispatcher.swift:418-478（`sendNotify`/`sendGet`）
- TEACH（2.x レガシー）→ OnTeach 写像と NOTIFY 化 → Ourin/USL/ShioriLoader.swift:232-251（`originalMethod == "TEACH"` で id=OnTeach、method=NOTIFY）
- Reference0..N の数値順整列（Reference10 問題回避）→ Ourin/SSTP/SSTPDispatcher.swift:387-414
- ヘッダ網羅性（SSTP経路）: SenderType/SecurityLevel/SecurityOrigin/Status/BaseID/Marker/Age/ErrorLevel/X-SSTP-PassThru-* を生成 → Ourin/SSTP/SSTPDispatcher.swift:614-658
- SenderType 既定値（SSTP 由来は `external,sstp`）→ Ourin/SSTP/SSTPDispatcher.swift:623
- SecurityLevel/SecurityOrigin 連動 → Ourin/SSTP/SSTPDispatcher.swift:616-622, Ourin/SHIORIEvents/EventBridge.swift:24-28
- Status ヘッダの動的供給と応答 Status による状態更新 → Ourin/SSTP/SSTPDispatcher.swift:631-635, 172-189
- 応答 Charset ラベルの寛容な解釈（SJIS/CP932/MS932/Windows-31J/sjis を同系受理、既定 UTF-8）→ Ourin/SSTP/EncodingAdapter.swift:8-14, Ourin/ExternalServer/EncodingNormalizer.swift:6-10
- 応答ヘッダの解析（Value/ValueNotify/Marker/BaseID/ErrorLevel/Reference0/Age/MarkerSend/X-SSTP-PassThru-*）→ Ourin/SSTP/SSTPDispatcher.swift:701-739
- 不正要求への 400 / モジュール失敗への 500 返却（YAYA backend）→ Ourin/USL/ShioriLoader.swift:86, 90

### 実装済み（要修正）
- **ステータスコード 311/312 のメッセージ文字列が誤り**: 現在 311→"Insecure"、312→"No Content (Not Trusted)" を出力 vs UKADOC では 311=OnTeach（追加情報要求）、312=OnTeach（無効）。"Insecure" は SecurityLevel の概念と混同した誤記。
  - 根拠: spec_shiori3.html ステータスコード（311=OnTeach need more, 312=OnTeach invalid）
  - 修正箇所: Ourin/USL/ShioriLoader.swift:271-272
  - 修正案: `case 311: statusText = "OnTeach (need more)"` / `case 312: statusText = "OnTeach (invalid)"`。コード値自体は一致するため再生は通るが、ログ・互換性検証で誤解を招く。
- **ネイティブ backend の応答デコードが UTF-8 固定で Charset ヘッダを無視**: 現在 `String(data:, encoding: .utf8)` 固定 vs 仕様では応答先頭の `Charset` ヘッダに従ってボディをデコードすべき。Shift_JIS で `Value:` を返す移植 SHIORI が文字化け/nil化する。
  - 根拠: spec_shiori3.html「Charset header governs decode/encode of the body」
  - 修正箇所: Ourin/USL/ShioriLoader.swift:431（BundleBackend）, 510（DylibBackend）, 346/755（XPC）
  - 修正案: 応答バイト列の先頭 `Charset:` 行を ASCII で先読みし `EncodingAdapter.decode(data, charset:)` でデコード。要求送出側も Charset に応じてエンコードすべき（現状 `Data(text.utf8)` 固定: 416, 501, 310）。
- **`ShioriHost.request`（BridgeToSHIORI 経由）が主要ヘッダを欠落**: 現在 `GET/Charset/Sender/ID/Reference*` のみで SenderType・Status・SecurityLevel・SecurityOrigin を付けない vs SSTPDispatcher 経路では付与。経路によりヘッダ充足度が不均一。
  - 根拠: spec_shiori3.html Request headers
  - 修正箇所: Ourin/SSTP/BridgeToSHIORI.swift:133-147
  - 修正案: `SenderType: internal` 既定と `Status: \(ShioriStatusStore.shared.currentStatus)` を補完。
- **YAYA backend が NOTIFY 応答にも常に `Value:` を付与**: NOTIFY は値を返さない前提（Value 無視）だが `buildResponse` は method に依らず Value を出力し、dispatcher も NOTIFY 応答の `res.value` を読む（notifyReturnIgnored で一部のみ抑止）。
  - 根拠: spec_shiori3.html「NOTIFY (no return value; Value ignored)」
  - 修正箇所: Ourin/USL/ShioriLoader.swift:283-285, Ourin/SSTP/SSTPDispatcher.swift:425/447
  - 修正案: 厳密準拠なら NOTIFY で Value を出力・参照しない。ただし SSP も NOTIFY 返値を再生する実装があり、現行（限定リスト）は実互換上許容範囲。低優先。

### 未実装（重要度: 高/中/低）
- **応答ボディの Charset エンコード/デコード往復（中）** — Shift_JIS⇔UTF-8 双方向変換が SHIORI モジュール ABI 境界で未適用。Shift_JIS 出力ゴースト（旧 YAYA/里々系 DLL を C ABI 化したもの）で文字化け。
- **SHIORI/2.x バイナリ互換層（低）** — docs 自身が「3.0 一本化、2.x 未対応」と明記（SHIORI_3.0M_SPEC_ja-jp.md:203-204）。TEACH→OnTeach 写像のみ存在。純 2.x DLL ゴーストは動作不可。設計判断に近いが標準からの逸脱。
- **BaseID による互換イベント自動フォールバック（低）** — BaseID は透過コピーのみ（SSTPDispatcher.swift:639, 722）で、未知イベント時のフォールバック解決ロジック無し。
- **ValueNotify（実験的）の能動利用（低）** — 応答解析では拾う（SSTPDispatcher.swift:706）が再生側で未活用。仕様も experimental。

### 互換性リスク
- **応答 Charset 無視**: SSP は応答の `Charset: Shift_JIS` を尊重。Ourin のネイティブ/XPC backend は UTF-8 固定のため、Shift_JIS で応答する移植 SHIORI（旧 DLL を 3.0M C ABI 化・SJIS 辞書の里々系）で Value が文字化け/欠落。
- **311/312 メッセージ誤記**: TEACH モードゴーストのデバッグ時に挙動を誤認させる温床。
- **NOTIFY 返値の扱い**: SSP は原則無視。Ourin は限定リスト外の NOTIFY 返値を再生（SSTPDispatcher.swift:434）するため、NOTIFY 応答に装飾スクリプトを返す設計のゴーストで発話タイミングがずれうる。
- **要求 SenderType 固定値**: 全 SSTP 由来が `external,sstp` 固定（SSTPDispatcher.swift:623）。SSP は communicate/sakuraapi/plugin 等で細分化。発生源で分岐するゴーストで一部分岐に到達しない可能性。
- **プラットフォーム差異（減点対象外）**: DLL バイナリ互換（GlobalAlloc 規約）の非提供は macOS 設計上不可避で、Bundle/XPC + C ABI への置換は 3.0M が明示的に容認。XPC 分離も Ourin 独自拡張。

---

## B. SSTP プロトコル

### 準拠度スコア: 7/10
SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE の全メソッドが単一スタック（`SSTPDispatcher`）に集約され、TCP/HTTP を 9801 単一ポートで多重化する設計（`UnifiedSstpListener`）は UKADOC/SSP の実運用に正しく合致している。ステータスコード表・X-SSTP-PassThru 透過・Option(notify/nodescript/nobreak/notranslate)・SecurityLevel/SecurityOrigin・EXECUTE の各 Command・Entry/Cookie セッション管理まで広くカバーしており、語彙互換は高水準。一方で、(1) 本番経路でリクエストボディが完全に破棄される、(2) Charset ヘッダが受信デコードに一切反映されない（CP932 デコーダが死蔵）、(3) ID（Owned SSTP）バイパス未実装、(4) COMMUNICATE の Surface リクエストヘッダ未対応、といった標準逸脱があり減点。プラットフォーム差異（WM_COPYDATA Direct SSTP の XPC 置換）は仕様準拠の範囲。

### 実装済み（仕様準拠）
- 5メソッド全ディスパッチ（SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE、INSTALL拡張含む）→ Ourin/SSTP/SSTPDispatcher.swift:54-66
- `Option: notify` 付き SEND を NOTIFY として扱う SSP 2.6.76 互換挙動 → Ourin/SSTP/SSTPDispatcher.swift:52-53
- TCP 9801 + HTTP `/api/sstp/v1` の単一ポート多重化（先頭行 `... HTTP/` で判別）→ Ourin/ExternalServer/UnifiedSstpListener.swift:67-76
- HTTP は常に 200 OK で SSTP レスポンスを内包 → Ourin/ExternalServer/SstpHttpServer.swift:105-112
- リクエスト構文解析（CRLF・空行終端・`key: value`・ヘッダ受信順保持）→ Ourin/SSTP/SSTPParser.swift:7-24, Ourin/SSTP/SSTPRequest.swift:85-100
- レスポンス整形 `SSTP/1.x <code> <msg>` CRLF + ヘッダ出力順制御 → Ourin/SSTP/SSTPResponse.swift:55-65
- ステータスコード表（200/204/210/400/404/408/409/413/420/500/501/503/505/512）→ Ourin/SSTP/SSTPResponse.swift:67-87
- EXECUTE Command 群（GetName/GetNames/GetVersion/GetFMO/Quiet/Restore/Get/SetProperty/Get/SetCookie/DumpSurface 等）と「データを返す」セマンティクス → Ourin/SSTP/SSTPDispatcher.swift:416-522
- COMMUNICATE の Reference シフト（Reference0=Sender, Reference1=Sentence, Reference2+=元 ReferenceN）→ Ourin/SSTP/SSTPDispatcher.swift:596-605
- GIVE→OnChoiceSelect/SHIORI 振り分け（レガシー受理）→ Ourin/SSTP/SSTPDispatcher.swift:559-561, 580-581
- SecurityLevel local/external 判定 + SecurityOrigin 優先（localhost/127.0.0.1/::1 のみ local）→ Ourin/SSTP/SSTPDispatcher.swift:530-537, 849-854
- HTTP 経由は Origin から SecurityOrigin/SecurityLevel を強制注入 → Ourin/ExternalServer/SstpHttpServer.swift:136-146
- GetFMO は local 限定（external は 420 Refuse）→ Ourin/SSTP/SSTPDispatcher.swift:424-435
- ReceiverGhostName 未発見時 404 / ゴースト未登録時 512 → Ourin/SSTP/SSTPDispatcher.swift:92-114
- nobreak: busy 時 409 Conflict、非 busy 時 210 Break → Ourin/SSTP/SSTPDispatcher.swift:115-143
- 413 / 505 / 501 → Ourin/SSTP/SSTPDispatcher.swift:25-34, 15-24, 67-75
- X-SSTP-PassThru-* の往復透過 → Ourin/SSTP/SSTPDispatcher.swift:777-786, 738-739
- XPC DirectSSTP（macOS の WM_COPYDATA 置換、Ourin 拡張）→ Ourin/ExternalServer/XpcDirectServer.swift:44-58

### 実装済み（要修正）
- **本番 TCP/HTTP 経路でリクエストボディが完全に破棄される**
  - 根拠: `SstpTcpServer` は `header = buffer.subdata(in: 0..<range.lowerBound)` のみをデコードして `onRequest?(text)` に渡し、`\r\n\r\n` 以降を捨てる。`OurinExternalServer.handleRaw` も body 引数なしで呼ぶ。body を保持するのは未使用の `SSTPListener` だけ。（監査者確認済み: SstpTcpServer.swift:55, 82-85）
  - 修正箇所: Ourin/ExternalServer/SstpTcpServer.swift:54-62, Ourin/ExternalServer/OurinExternalServer.swift:52, Ourin/SSTP/SSTPListener.swift:5
  - 修正案: 生 SSTP 経路でも `\r\n\r\n` 以降をボディとして抽出し `parseRequest(text:body:)` に渡す。本番経路を `SSTPListener` 相当に統一。
- **Charset ヘッダが受信デコードに反映されない（CP932 デコーダ死蔵）**
  - 根拠: `SstpTcpServer.decode`/`SstpHttpServer.decode` は「UTF-8 失敗→shiftJIS」固定フォールバックで Charset 値を参照しない。`EncodingAdapter.decode(_:charset:)`/`EncodingNormalizer` は実装済みだが SSTP 受信経路から一度も呼ばれない（参照ゼロ）。
  - 修正箇所: Ourin/ExternalServer/SstpTcpServer.swift:82-85, Ourin/ExternalServer/SstpHttpServer.swift:131-134, Ourin/SSTP/EncodingAdapter.swift:6-14
  - 修正案: 先頭行＋Charset を一次パースし最終デコードを `EncodingAdapter.decode(data, charset:)` 経由に置換。
- **ID（Owned SSTP）バイパスが未実装**
  - 根拠: `dispatch`/`buildShioriHeaders`/`resolveSecurityLevel` に `ID` ヘッダ参照がない。
  - 修正箇所: Ourin/SSTP/SSTPDispatcher.swift:35-50, 530-537
  - 修正案: 自プロセス発行 ID を `SstpSessionStore` で管理し、一致時は 420 ブロックと external 制限をバイパス。
- **COMMUNICATE の Surface リクエストヘッダが SHIORI に渡らない**
  - 根拠: `extractReferences` は COMMUNICATE で Sentence/Sender のみ挿入し、固有 `Surface` を処理しない。
  - 修正箇所: Ourin/SSTP/SSTPDispatcher.swift:596-605, 639-648
  - 修正案: COMMUNICATE 時に `Surface` を SHIORI ヘッダ（または Reference）へ転送。

### 未実装（重要度: 高/中/低）
- **ID（Owned SSTP）バイパス（中）** — external 制限下で自発 SSTP がブロックされうる。
- **COMMUNICATE Surface リクエストヘッダ転送（低）** — 相手ゴーストのサーフェス指定が落ちる。
- **ポート 9821（SSP 互換待受）（低）** — 仕様任意・自ドキュメントでも optional。9801 固定。
- **EXECUTE の SetProperty/GetProperty の SecurityLevel ガード（中）** — GetFMO のみ local 限定で、`handleExtendedExecuteCommand`（SSTPDispatcher.swift:472-479）に securityLevel チェックなく external でも実行可能。

### 互換性リスク
- ボディ破棄により、将来 SSTP がボディ（添付）を運ぶクライアントと相互運用不能（現状 SEND/NOTIFY はヘッダのみで顕在化しにくい潜在リスク）。
- Charset 無視デコードは `Shift_JIS` 明示かつ UTF-8 として不正なバイト列（半角カナ・特定漢字）で文字化け/`String` 生成失敗。SJIS 主体の旧来クライアント互換に影響。
- `dispatch` は SEND の Event 無し時に Script を直接バルーン再生（SHIORI 非経由）。IfGhost 書式（`\0名,\1名`）想定外のクライアントで意図しないデフォルト再生になりうる（SSTPDispatcher.swift:146-167）。
- external 制限は `OURIN_SSTP_LOCAL_ONLY`/`config.securityLocalOnly` 依存で、`SSTPListener`/`DirectSSTPXPC` 直接経路は既定（制限なし）になる（DirectSSTPXPC.swift:37, SSTPListener.swift:56）。経路ごとにポリシー不統一。
- HTTP の `Origin: null`（file:// 等）を受理するため、ローカル HTML からの external 級アクセスが local 扱いになりうる（SstpHttpServer.swift:155-159）。

---

## C. SakuraScript

### 準拠度スコア: 7/10
Ourin implements a very broad slice of the UKADOC SakuraScript universe — scope, surface, animation/SERIKO linkage, the entire `\![...]` family (events, sound, open/input dialogs, move/resize, set/reset, lock/unlock, anim, bind, change/call, update/vanish), choices, anchors, jumps, and `%`-variable expansion are all genuinely wired from parser to executor. The score is held back by (a) several tokens that the parser tokenizes but no executor consumes (`\_n`, `\__v`, `\__t`/`\__c`), (b) a real argument-format bug in `\c[char,N]`/`\c[line,N]` (parsed as comma args, executor expects `=`), (c) `\s[alias]` non-numeric surface aliases collapsing to surface 0, and (d) the `\f[...]` font set missing several documented subcommands. The documentation (`SUPPORTED_SAKURA_SCRIPT.md`) is mostly honest but over-claims `\c[...]` and `\_l[x,y]` correctness. Because this category is weighted ×2, the parsed-but-ignored tokens and the `\c` bug are the main deductions.

### 実装済み（仕様準拠）

**Scope**
- `\0 \h \1 \u` — parser `SakuraScriptEngine.swift:211-215` → executor `GhostManager.swift:878-879` (`.scope`), applied at `processNextUnit` `GhostManager.swift:2415-2438`.
- `\pID \p[ID]` — parser `:217-229` → same `.scope` path.

**Surface / Animation (SERIKO)**
- `\sID \s[ID]` (numeric) — parser `:230-242` → `updateSurface` `GhostManager+Surface.swift:11-12`.
- `\i[ID]`, `\i[ID,wait]` — parser `:243-262` → `.animation` `GhostManager.swift:905-914`; `wait` enqueues `.waitAnimation`, resumed by `serikoExecutor.onAnimationFinished` `GhostManager+Animation.swift:83-90`, gating at `GhostManager.swift:2466-2475`. SERIKO linkage is real (executor + loop timer + finish callback).
- `\![anim,clear|pause|resume|stop|offset|add(overlay|overlayfast|base|move|bind|text)]` — `GhostManager.swift:1981-2058`.
- `\![bind,...]` / `\![bind-noevent,...]` — `executeBindCommand` `GhostManager.swift:1822-1823, 2059-2060`.

**Balloon / Text**
- `\n`, `\n[half]`, `\n[percent]` — parser `:263-277` → `handleNewline` `GhostManager+Balloon.swift:710-735`.
- `\bID \b[ID]` (+fallback first-id) — parser `:315-339` → `switchBalloon(to:)` `GhostManager.swift:892-895`.
- `\C` (append) — parser `:340-343` → `appendModeEnabled` `GhostManager.swift:897-901`.
- `\_b[path,x,y]` balloon image — `handleBalloonImage` `GhostManager+Balloon.swift:244`.
- `\_l[x,y]` cursor move (abs/relative `@`) — `handleCursorMove` `GhostManager+Balloon.swift:375-387`.
- `\![set,*]` balloon controls (autoscroll/balloonoffset/balloonalign/balloonmarker/balloonnum/balloontimeout/balloonwait/choicetimeout/serikotalk) — `GhostManager.swift:1647-1805`.
- `\![*]`/`%*` marker, `\![#|X|<|>]` — `GhostManager.swift:2120-2131`; `%*` shortcut in parser `:185-189`.

**Font**
- `\f[align|valign|name|height|color|shadowcolor|shadowstyle|bold|italic|strike|underline|sub|sup|default|disable|outline|anchor.font.color]` — parser `:450-461` → `GhostManager.swift:2216-2381`. Tri-state honored.

**Wait / Flow**
- `\w<n>` (1-9 ×50ms) — `GhostManager.swift:1009-1021`; `\_w[ms]` `:1022-1025`; `\__w[clear|ms|animation,ID]` `:1026-1038`.
- `\t` (time-critical section, correctly NOT a pause) `GhostManager.swift:916-921`; ends at `\e` `:2451-2452`.
- `\x`, `\x[noclear]` — parser `:360-373` → `.clickWait` `GhostManager.swift:923-925, 1039-1041`.
- `\e` end + state reset — `GhostManager.swift:2446-2453`.
- `\_q` quick toggle `:1042-1043`; `\![quicksection,true/false]` `:1210-1212`.

**Choice / Anchor**
- `\q[title,ID]` / `\q[title,script:...]` / refs — `handleChoiceCommand` `GhostManager+System.swift:280-301`.
- `\__q[id0,id1,...]` — `handleQueuedChoiceCommand` `GhostManager+System.swift:304-313`.
- `\*` (choice timeout disable, correct UKADOC semantics) `GhostManager.swift:932-936`; `\z` cancel `:927-930`; `\-` (ghost termination, correct) `:952-957`; `\a` (legacy OnAITalk, correct) `:938-950`; `\a[...]`→`_a` `:382-397`; `\_a[ID/OnEvent,refs]` anchor `:2148-2160`; `\&[id]` entity reference (numeric+named) `resolveEntityReference` `GhostManager.swift:758-778, 2190-2198`.

**Event family** (`\![raise|notify|raiseother|notifyother|raiseplugin|notifyplugin|embed|timerraise|timernotify|timerraiseother|timernotifyother|timerraiseplugin|timernotifyplugin]`) — `GhostManager.swift:1050-1148`; `\![embed]` inlines result tokens `GhostManager+System.swift:317-330`.

**Sound** — `\8[file]` `GhostManager.swift:993-995`; `\_v[file]` `:2172-2176`; `\_V` (wait) `:1000-1007`; `\![sound,play|load|loop|wait|pause|resume|stop|option]` `:1605-1646`.

**Open / System** — `\j[ID]` `handleJumpCommand` `GhostManager.swift:781-821`; `\![open,...]` broad set (browser/mailer/editor/explorer/teachbox/communicatebox/inputbox/passwordinput/dateinput/sliderinput/timeinput/ipinput/configurationdialog/ghostexplorer/...) `:1310-1553`; `\![close,...]` `:1554-1569`; `\![change,ghost|shell|balloon]` `:1149-1165`; `\![call,ghost]` `:1166-1173`; `\v` (stay-on-top, correct UKADOC) `:978-983`; `\6`/`\7` (SNTP, correct UKADOC) `:985-991`; `\+`/`\_+` boot `:967-976`; `\![vanishbymyself]` `:1968-1972`; `\![update*]` `:1952-1967`; `\![enter/leave,*mode]` `:1570-1604`.

**Env vars / properties** — `%month %day %hour %minute %second %username %selfname %selfname2 %keroname %screenwidth %screenheight %property[...] %charname[n] %ms..%me %exh` etc. — `EnvironmentExpander.swift:114-188`; `\![get/set,property]` `GhostManager.swift:1174-1209`.

**Escape sequences** — `\\`→`\`, `\%`→`%` (`SakuraScriptEngine.swift:199-208`); `\]`/`\[` inside brackets (`:122-134`); quoted-arg `""` comma/quote rules (`:544-587`). Verified correct.

### 実装済み（要修正）
- **`\c[char,N]` / `\c[line,N]` text-erase — BROKEN argument format.** 現在: parser splits on comma → args `["char","5"]` (`SakuraScriptEngine.swift:344-355`), but executor `handleTextClear` reads `char=N`/`line=N` by splitting on `"="` (`GhostManager+Balloon.swift:678-687`), so `charsToClear`/`linesToClear` stay 0 and nothing is erased. **（監査者確認済み）** 正しい: UKADOC uses `\c[char,N]` (comma). 修正案: parse positional `args[0]=="char"`/`"line"` with `Int(args[1])`. Only bare `\c`/`\c[all]` currently work.
- **`\s[alias]` non-numeric surface alias ignored.** 現在: parser does `tokens.append(.surface(Int(num) ?? 0))` (`SakuraScriptEngine.swift:241`), so `\s[surface.smile]` becomes surface **0**. `surfaceAliases` is `[Int:Int]` (`GhostManager+Surface.swift:12`). 正しい: string surface aliases from `descript`/`alias.txt`. 修正案: keep raw string token, resolve string→id before `updateSurface`.
- **`\_l[x,y]` documented as supported but coordinate semantics are partial.** `SUPPORTED_SAKURA_SCRIPT.md:34` marks ✅, but only cursorX/cursorY VM fields are moved (`GhostManager+Balloon.swift:375-387`); whether the renderer positions subsequent text at that coordinate is not enforced. 修正案: verify `appendText` honors cursorX/Y, else downgrade doc to ⚠️.
- **`\f[outline]` reinterprets numeric as width** (`GhostManager.swift:2360-2377`) — acceptable extension but diverges from strict boolean spec. Low severity.
- **Doc over-claim: `\![change,ghost]` "✅".** `switchGhost` is called (`GhostManager.swift:1156`) but cross-process ghost swap depends on availability; recommend ⚠️.

### 未実装（重要度: 高/中/低）
- **[高] `\_n` (no-autoscroll / wrap control)** — parsed as `command("_n")` (`SakuraScriptEngine.swift:462-515`, test exists) but **NO executor case** (`default: break` `GhostManager.swift:2383-2384`). Silently dropped. Common in real ghosts.
- **[高] `\s[alias]` string aliases** — see 要修正; missing functionality for alias-based shells.
- **[中] `\__v` (voice disable / alternate reading)** — parsed as `command("__v")` but no executor → ignored. (Distinct from `\_v`/`\_V` which work.)
- **[中] `\__t` (teachbox meta) and `\__c`** — only `\![open,teachbox]` exists (`GhostManager.swift:1419-1425`); the meta-tag forms are not parsed/executed.
- **[中] `\_s[...]` synchronized-scope speech** — `\_s` toggles `syncScopes` (`GhostManager.swift:2134-2142`) but `processNextUnit` clears other scopes' balloons (`:2417-2421`), contradicting parallel sync talk.
- **[中] `\__w[ms]` base-reset edge cases** — partial.
- **[低] `\4`/`\5`, `\![move]`/`\![moveasync]`** — implemented (`GhostManager.swift:959-965, 2086-2102`) but advanced options (`--base-offset`, multi-stage) incomplete per doc.
- **[低] `\f[cursorstyle/...]`, `\f[anchorstyle/...]`** — only `anchor.font.color` exists; cursor/anchor style families missing.
- **[低] legacy `\q<digit>[...]` numeric choice** — not parsed (only `\q[...]`).
- **[低] `\_!`/`\_?` literal passthrough** — parsed/emitted but no executor case; inner text still shown, but "disable sakura-script interpretation" guarantee not enforced.

### 互換性リスク
- **`\c[char,N]` no-op is a correctness landmine**: ghosts using progressive text-erase (countdown/typewriter-delete) appear frozen. High impact; silent failure.
- **Parsed-but-ignored tokens (`\_n`, `\__v`, `\__t`, `\_!`/`\_?`)**: scripts won't error but layout/voice/teach behavior diverges silently — hard to diagnose.
- **`\s[alias]`→0 collapse**: any shell using named surface aliases shows the wrong (id 0) surface throughout — very visible regression.
- **`\_s` "sync" + forced single-scope balloon clearing**: simultaneous two-character speech is serialized, breaking dual-talk.
- Unknown `%foo` returned verbatim (spec-friendly); `%et`/`%wronghour` randomized per spec intent (note non-determinism in tests).
- Verbose `NSLog` per text segment (`EnvironmentExpander.swift:34-108`) is a log-spam/perf risk under heavy talk (not correctness).

---

## D. SHIORIイベント

### 準拠度スコア: 6/10
イベント識別子のカタログ（EventID.swift、約400件）は UKADOC をほぼ網羅し、macOS 由来のシステムイベント（電源/ディスプレイ/ロケール/セッション/ネットワーク等）も豊富にブリッジしている。boot/close は GET で正しく送出され、時刻系イベントの Reference3（トーク可否）に応じた GET/NOTIFY 切替も UKADOC 準拠で実装されている。一方、**マウス系/サーフェス系イベントの Reference 配置が仕様と複数箇所でずれている**ため、ゴースト辞書が ReferenceN を直接参照すると誤動作する致命的な不整合がある。NOTIFY 専用イベントの返値無視リストや SecurityLevel/SecurityOrigin の付与は適切。

### 実装済み（仕様準拠）
- **BOOT/CLOSE（GET、Reference 準拠）**: `OnFirstBoot` Ref0=vanish回数 — GhostManager.swift:2516-2518。`OnBoot` Ref0=シェル名 — GhostManager.swift:2528-2530。`OnClose` Ref0=reason を GET 送出 — GhostManager.swift:708,718。いずれも NOTIFY ではなく GET で送り応答スクリプトを再生（GhostManager.swift:615）。
- **時刻系（GET/NOTIFY 切替 + Reference3）**: TimerEmitter.swift:55-73,79-88 で OnSecondChange/OnMinuteChange/OnHourTimeSignal 発火、Ref0=連続起動時間, Ref4=放置秒数。Reference3（トーク可否）を EventBridge.swift:296-317 がセッション毎に設定し、cantalk=1 なら GET、0 なら NOTIFY に切替。Ref1/Ref2（見切れ/重なり）も EventBridge.swift:302-305 で上書き。UKADOC レイアウトに整合。
- **SSTP系**: OnSSTPBreak（SSTPDispatcher.swift:118,131）、OnSSTPBlacklisting（SSTPDispatcher.swift:38）を NOTIFY 送出。
- **COMMUNICATE（Reference 準拠）**: SSTPDispatcher.swift:596-605 で Ref0=Sender, Ref1=Sentence, Ref2+=SSTPのReferenceN。UKADOC に一致。
- **SURFACE 補助**: OnSurfaceRestore を 15 秒後に発火（GhostManager+Surface.swift:59-66）。OnShellChanged/Changing Ref0=旧, Ref1=新（GhostManager+Surface.swift:231,245）。
- **キーボード**: OnKeyDown/OnKeyUp Ref0=文字, Ref1=keyCode（InputMonitor.swift:166-171）。
- **NOTIFY 返値無視リスト**: EventBridge.swift:350-362 で basewareversion/各種 NotifyInfo 系の返値を無視（UKADOC 準拠）。
- **ReferenceN 数値順整列**: EventBridge.swift:393-414 の `orderedRefs` で Reference10 が Reference2 より前に並ぶ辞書順バグを回避。

### 実装済み（要修正）
1. **OnSurfaceChange の Reference 意味が仕様と逆/誤り（最大の実害）** — GhostManager+Surface.swift:48-52 で `Reference0=String(oldSurfaceID)`, `Reference1=String(id)`（新サーフェスID）。**（監査者確認済み）** UKADOC は **Ref0=sakura(scope0)サーフェスID, Ref1=kero(scope1)サーフェスID**（旧→新ではない）。surface 連動辞書がほぼ全て誤動作する。修正案: Ref0=sakura現在surface, Ref1=kero現在surface とし、旧ID/変化スコープは別 Reference へ。修正箇所 GhostManager+Surface.swift:48-52。
2. **OnMouseMultipleClick の連続クリック回数が Reference7 に入らない** — InputMonitor.swift:232-238 で回数を `multi["count"]`（補助ヘッダ）に格納。UKADOC は **Ref7=clickCount** を位置引数として要求するが、`count` は ReferenceN でないため `orderedRefs`（EventBridge.swift:404）に含まれずゴーストが回数を取得できない。修正案: `multi["Reference7"] = String(clickStreak)`。修正箇所 InputMonitor.swift:233。
3. **マウス系 Reference6=inputType が "mouse" 固定**（InputMonitor.swift:406）— タッチ非対応の macOS では許容範囲だが UKADOC 完全準拠には touch 判別が必要（軽微）。
4. **OnVanishSelecting/Selected を即時 NOTIFY し選択 UI を経由しない** — GhostManager.swift:1970-1972 で vanishbymyself が OnVanishSelecting→OnVanishSelected を即時送出後に executeVanish。UKADOC では OnVanishSelecting は確認前イベントでキャンセル可能（OnVanishCancel）。修正案: 確認ダイアログ→結果で Selected/Cancel を分岐。
5. **OnFileDrop2/OnDirectoryDrop が未生成、旧 OnFileDrop と独自 OnDragDrop/OnFileDropped を発火** — DragDropView.swift:79-83。現代ゴーストは **OnFileDrop2（Ref0=name, Ref1=path）** を待つため反応しない。修正案: OnFileDrop2 として送出。修正箇所 DragDropView.swift:78-84。
6. **標準イベントと独自エイリアスの二重発火** — LocaleObserver.swift:15-16（OnLocaleChange + OnLanguageChange）、SpaceObserver.swift:15-16、SleepObserver（OnSysSuspend + OnSleep + OnCacheSuspend）が無条件で同時発火。両対応ゴーストでトーク重複の可能性（軽微〜中）。
7. **OnChoiceSelect の独自 Reference レイアウト** — GhostManager+System.swift:437-441 で Ref0=タイトル, Ref{index+1}=タイトル。UKADOC は Ref0=選択ID。アンカー系（OnAnchorSelect 等）は EventID 定義のみで発火経路が見当たらない。

### 未実装（重要度: 高/中/低）
- **（高）OnFileDrop2 / OnFileDropEx / OnWallpaperChange の標準ドロップ系** — EventID 定義はある（EventID.swift:141-142,399）が DragDropView は旧/独自イベントしか発火しない。
- **（高）OnMouseEnter/Leave の collisionID（領域単位）連動** — InputMonitor.swift:265-282 はウィンドウ単位のみで、当たり判定領域単位の Enter/Leave 遷移検出が無い。
- **（中）OnInstallComplete(Ref0=id,Ref1=name,Ref2=name2)** — `executeInstall`（GhostManager+System.swift:1229-1255）は失敗時 OnInstallFailure のみ送出で、成功時の正規 Reference を構築しない。
- **（中）OnGhostChanged/Changing の発火経路** — EventID 定義あり（EventID.swift:159-160）だが標準 Reference（旧/新ゴースト名・shell・path）を送る箇所が確認できない。
- **（低）OnBatteryLow/Critical/ChargingStart/Stop** — EventID 定義あり（EventID.swift:28-32）だが PowerObserver は独自 OnPowerSourceChanged のみ発火。
- **（低）OnScreenSaverStart/End を screensDidSleep にマッピング**（SleepObserver.swift:26-31）— macOS 差異として許容範囲。

### 互換性リスク
- **OnSurfaceChange の逆レイアウト（要修正1）が最大の実害**: 標準ゴーストの surface 連動辞書が誤った値を受け取り、サーフェス追従や着せ替え判定が崩れる。
- **独自イベント名/名前付きヘッダの混入**: システムイベントの多くが独自ヘッダ名（`Appearance`, `Source`, `State`, `Status`, `Load` 等）を ReferenceN ではなく名前付きヘッダで渡す（AppearanceObserver.swift:35, PowerObserver.swift:43 等）。`orderedRefs` で位置引数に含まれず、ReferenceN しか読めない既存ゴーストからは値が見えない。
- **二重エイリアス発火**（要修正6）は両対応ゴーストでトーク重複の互換リスク。
- **プラットフォーム差異（許容）**: Windows 固有の OnRecycleBinEmpty 系（GhostManager+System.swift:1289-1300 で `.Trash` 直接操作の独自イベント）、OnTabletMode 等はプラットフォーム差異。

---

## E. プロパティシステム

### 準拠度スコア: 5/10
全名前空間（system / baseware / ghostlist / activeghostlist / currentghost / balloonlist / headlinelist / pluginlist / history / rateofuselist）のプロバイダが実装され、`%property[...]` 展開・`\![get,property,...]`・`\![set,property,...]` の3経路すべてが配線されている点は良好。汎用プロパティ名・index(n)・名前指定アクセス・SERIKO カーソル/ツールチップの SET など、UKADOC 語彙の中核をかなり広くカバーしている。一方で、(1) `currentghost.balloon.*` プロバイダが**プレフィックス分割の設計欠陥により完全に到達不能**（dead code）、(2) UKADOC で READ/WRITE と定義される `surface.num`/`animation.num` が読み取り専用かつ `animation.num` は未実装、(3) `system.*` の OS 情報マッピングが自仕様と矛盾し `os.build` 等が欠落、(4) `system.monitor/power/disk/network/theme/dnd` 系がまるごと未実装、という重大な穴がある。

> **`\p[]` と `%property[]` の区別（プロンプト指摘の明確化）**: 監査項目原文の「`\p[]` によるプロパティ参照」は**用語の誤り**。実 SakuraScript で `\p[]`（`\p0`/`\p1`）は**スコープ／キャラクタ選択子**であり、プロパティアクセスではない。プロパティアクセスは (1) `%property[path]`、(2) `\![get,property,...]`、(3) `\![set,property,...]` の3経路のみ。Ourin もこの3経路で正しく配線されている（EnvironmentExpander.swift:177-179, GhostManager.swift:1176-1209）。

### 実装済み（仕様準拠）
- `%property[path]` 展開（再帰・循環参照ガード depth<16）→ PropertyManager.swift:168-202, EnvironmentExpander.swift:177-179
- `\![get,property,イベント名,プロパティ名]`（値を Reference0 に載せて発火）→ GhostManager.swift:1176-1188
- `\![set,property,プロパティ名,値]` → GhostManager.swift:1203-1209
- `system.*` を非キャッシュ化して動的値が固定されない設計 → PropertyManager.swift:97-124
- `system.*`: year/month/.../dayofweek, cursor.pos（左上原点変換）, cpu.(num/vendor/name/clock/features/load), memory.(phyt/phya/load), os.(type/name/parenttype/parentname/Rosetta検出) → PropertyManager.swift:223-263, 269-339
- `baseware.name`="Ourin" / version / build / path → BasewarePropertyProvider.swift:8-17
- ghostlist/activeghostlist/currentghost の汎用プロパティ・count・index(n)・(name/sakuraname/path) → GhostPropertyProvider.swift:218-261, 381-422
- currentghost.status, shelllist.count/current/index/(name), scope(n).{surface.num/x/y/rect/name/seriko.defaultsurface} → GhostPropertyProvider.swift:264-316, 319-375, 437-458
- SET: shelllist(name).menu, mousecursor.*, seriko.cursor/tooltip.* → GhostPropertyProvider.swift:151-194, 595-637
- balloonlist/headlinelist/pluginlist/history.*/rateofuselist.* の count/index/named アクセス → 各プロバイダ

### 実装済み（要修正）
- **`currentghost.balloon.*` が完全に到達不能（最重要・dead code）**
  現在: `register("currentghost.balloon", provider: ...)`（PropertyManager.swift:26）。正しい挙動: `currentghost.balloon.scope(0).num` 等が解決されること。根拠: `get`/`set` は**最初のドットだけ**でプレフィックスを切り出す（PropertyManager.swift:101 `firstIndex(of: ".")`）ため、`currentghost.balloon.scope(0).num` は prefix=`currentghost` で GhostPropertyProvider にディスパッチされ、そこは `balloon.scope(...)` を処理しない（GhostPropertyProvider.swift:264-316）→ 常に nil。2部構成キー登録は**どの get でも引かれない dead code**。**（監査者確認済み: PropertyManager.swift:26, 99-114）** 修正案: `get`/`set` を「最長一致プレフィックス」方式に変更（`currentghost.balloon` → なければ `currentghost`）。修正箇所 PropertyManager.swift:82-124。
- **`scope(ID).surface.num` が読み取り専用（UKADOC では READ/WRITE）** — set 経路なし（GhostPropertyProvider.swift:439-440 read のみ）。修正案: `set(key:)` に `scope(n).surface.num` を追加し描画切替と連動。
- **`scope(ID).animation.num`（READ/WRITE）が未実装** — `animation.num` キーの read/write がコードに存在しない。修正案: ScopeData に animationNum を追加。
- **`system.os.version`/`os.build` のマッピング不整合** — `os.version` → `kern.osversion`（ビルド番号）を返し `os.build` キー未実装（PropertyManager.swift:236）。自仕様 PROPERTY_1.0M_SPEC §4.1 では version=`kern.osrelease`, build=`kern.osversion`。修正案: 両キーを正す。
- **ドキュメントが実装に未追従** — docs/PropertySystem_ja-jp.md は「書込可は shelllist.menu のみ」「history/rateofuse は今後」と記述（167-219行）だが実装は seriko cursor/tooltip SET・history・rateofuselist を持つ。逆に 79-86行は `currentghost.balloon.*` が動く前提だが上記の通り到達不能。

### 未実装（重要度: 高/中/低）
- **【高】`currentghost.scope(ID).animation.num`（RW）**
- **【高】`system.monitor.count` / `monitor.index(ID).(work/rect/dpi/primary)`** — マルチモニタ情報。
- **【中】`system.power.(source/battery.percent/lifetime/flag)`**
- **【中】`system.network.(status/ipaddress/type)`**
- **【中】`system.disk.*`**
- **【中】`system.os.locale/timezone.offset/uptime/unixtime/idletime/arch`**
- **【中】`system.theme.app.mode/theme.os.mode`（ダーク/ライト）, `system.dnd.mode`**
- **【中】`currentghost.scope(ID).scaling` と `currentghost.balloon.scope(ID).(background.color/scaling)`** — フィールド無し。
- **【低】`history.*` / `rateofuselist.*`** — 解決経路はあるが空配列で生成され（PropertyManager.swift:29-30）常に count=0、データ未連携。

### 互換性リスク
- **`currentghost.balloon.scope(...).*` を使うゴーストが全滅**: バルーン寸法を property 経由で取得するスクリプトが空値を受け取りレイアウト計算が破綻。
- **`surface.num` の SET 期待**: `\![set,property,currentghost.scope(0).surface.num,n]` でサーフェス切替を期待するゴーストで黙って失敗（set が false）。
- **`os.version` の意味ズレ**: `%property[system.os.version]` がビルド番号（例 `23F79`）を返し表示が崩れる。
- **`history.*`/`rateofuselist.*` が常に 0/空**: 使用率・履歴依存の分岐が常に未使用扱い。
- **空配列ディスカバリのキャッシュ固定**: 起動時 discover で固定され missing 値もキャッシュ（PropertyManager.swift:109-122）。インストール後のランタイム更新経路が無いと古い値が残る。

---

## F. YAYA言語VM

### 準拠度スコア: 4/10
実装はC++ヘルパープロセス（yaya_core、JSON line IPC で Swift と通信）。`yaya_core/src/` に Lexer/Parser/VM/DictionaryManager/Value/YayaCore が実在し、約140個の組み込み関数がディスパッチテーブル（`builtins_` マップ, VM.cpp:622-2448）に登録されている。基本文法（関数定義・if/elseif/else・while・switch(index式)・三項・`+= -= *= /= %=`・`,=` 配列連結・`reference[N]`・`_argv`/`_argc`・`%(var)` 補間）と、文字列/正規表現/配列/SHIORI 統合の主要 API は揃っている。charset 処理（iconv による CP932/UTF-8 自動判定, DictionaryManager.cpp:118-171）と SAORI ブリッジ（LOADLIB/UNLOADLIB/REQUESTLIB → Swift, VM.cpp:2321-2362）も機能する。しかし、(1) `for`/`foreach` がループ条件・反復変数を完全に破棄して `while(1)` に縮退、(2) `break`/`continue` が no-op、(3) 後置/前置 `++`/`--` が変数を変更しない、(4) 浮動小数点（Real型）が存在せず全数学が整数切り捨て、(5) `&` 文字列連結演算子が機能しない、という根幹的欠陥があり、実ゴーストの多くが破綻するため中位スコアに留める。

### 実装済み（仕様準拠）
- 字句解析: コメント `//` `/* */` `#` `--`、UTF-8 BOM除去、ヒアドキュメント `<<' >>'`、16進リテラル `0x` → Lexer.cpp:36-72,164-199,439-480
- 関数定義 `Name { ... }`、if/elseif/else、while、三項 `?:` → Parser.cpp:86-160, VM.cpp:326-343,306-314
- 代入と複合代入 `= += -= *= /= %=`、配列連結 `,=`（`__concat_assign__`）→ VM.cpp:464-495
- `reference[N]`（SHIORI参照）を ArrayAccess と `__index__` の両経路で解決 → VM.cpp:419-426,513-519
- `_argv`/`_argc` を関数ローカルスコープに設定、`_` 接頭辞変数のローカルスコープ化 → VM.cpp:173-179,206-228
- 配列: IARRAY/ARRAYSIZE/ASEARCH/ASEARCHEX/ASORT/ARRAYDEDUP/ANY、`__array_literal__`、`reference` 乱択化 → VM.cpp:763-775,1145-1213, Value.cpp:24-34
- 文字列: SUBSTR/REPLACE/ERASE/INSERT/SPLIT/STRSTR/CUTSPACE/TOUPPER/TOLOWER/CHR/CHRCODE/GETSTRBYTES → VM.cpp:837-963,1090-1142
- 正規表現（std::regex/ECMAScript）: RE_SEARCH/RE_MATCH/RE_GREP/RE_REPLACE(EX)/RE_SPLIT/RE_OPTION/RE_GETSTR/RE_GETPOS/RE_GETLEN、本家準拠の (str, pattern) 引数順 → VM.cpp:1799-1943
- 型変換: TOINT/TOSTR/TOREAL/GETTYPE(EX)/CV*、ハッシュ/エンコード: STRDIGEST(md5/sha1/crc32)/STRENCODE/STRDECODE(url,base64) → VM.cpp:780-808,2005-2052
- ファイルI/O: FOPEN(パストラバーサル防御あり)/FCLOSE/FREAD/FWRITE/FCOPY/FMOVE/FDEL/FRENAME/FENUM/FSIZE/MKDIR/RMDIR → VM.cpp:1438-1772
- SAORI: LOADLIB/UNLOADLIB/REQUESTLIB を Swift `SaoriManager` へ橋渡し → VM.cpp:2321-2362, YayaAdapter.swift:306-362
- SHIORI統合: `request` 関数があれば生 SHIORI リクエスト文字列を渡してフレームワーク（SHIORI3FW/SHIORI3EV）に委譲、無ければ id 関数を直接呼ぶ。応答ヘッダ全体をパースして Swift へ返す。NOTIFY 専用イベントの 204 処理 → YayaCore.cpp:157-275
- .dic ロード＋charset: iconv で CP932↔UTF-8、BOM・宣言・自動判定の三段 → DictionaryManager.cpp:62-171
- Swift側 IPC/spawn: Bundle 補助実行体として yaya_core を起動、改行区切り JSON で通信、stderr 監視、host_op コールバック、unload で graceful→SIGKILL → YayaAdapter.swift:39-294

### 実装済み（要修正）
- **`for` ループがループ条件と反復式を完全に破棄して `while(1)` に縮退**。現在: ヘッダ全体を読み捨て `cond = LiteralNode("1")` を生成（"condition not preserved" とコメント明記）。**（監査者確認済み: Parser.cpp:756-758）** 正しい: 初期化・条件・増分を保持して反復実行。修正箇所 `parseFor`（Parser.cpp:684-758）。修正案: 専用 ForNode（init/cond/incr/body）を AST に追加し VM で評価。break 修正と併せないと無限ループ化。
- **`foreach array; var { }` が配列反復もループ変数束縛も行わず `while(1)` に縮退**。Parser.cpp:751-801。修正案: ForeachNode を追加し VM で配列を反復、要素を setVariable。
- **`break` / `continue` が no-op**。「proper implementation would need loop context」とコメントし `Value()` 返却のみ。**（監査者確認済み: VM.cpp:549-557）** 修正案: BreakException/ContinueException を投げ、ループ実行側で捕捉。
- **後置/前置 `++` `--` が変数を変更しない**。Parser が `__postinc__`/`__postdec__` の CallNode を生成（Parser.cpp:1233-1235）するが VM に該当ハンドラが無く（**監査者確認済み: VM.cpp に postinc 文字列なし**）、未知関数として void を返し変数は不変。`_i++` 文は黙って無視される。修正案: `__postinc__` 等を `+=` 経路で実装。
- **浮動小数点（Real型）が存在しない**。Value は Void/Integer/String/Array/Dictionary のみ（**監査者確認済み: Value.hpp:12-17 に Real/Double 無し**）。TOREAL は TOINT のエイリアス（VM.cpp:792-795）、SQRT/SIN/COS/TAN/LOG/POW は `static_cast<int>` で切り捨て（VM.cpp:985-1037）。`SQRT(2)`→1, `SIN(1)`→0。修正案: Real 型を追加し小数リテラル・数学関数を実数化。
- **`&` 文字列連結演算子が機能しない**。`&` を単項前置として `UnaryOpNode("&")` にパース（Parser.cpp:1158-1160）するが evaluateUnaryOp に `&` ハンドラが無く void を返す（VM.cpp:608-612）。修正案: `&` を二項連結演算子として parseAddition 級に追加し `asString()+asString()`。
- **`STRFORM`/`SPRINTF` が書式を解釈しない**。STRFORM は単純連結のみ（VM.cpp:653-662）、SPRINTF は未登録。修正案: 書式指定子パーサを実装。
- **`%(...)` 文字列補間が変数参照のみで式・関数呼び出しを評価しない**（VM.cpp:2504-2512）。`%(_a+_b)` は未展開。修正案: interpolateString 内で式評価。
- **STRLEN/SUBSTR/ERASE/INSERT がバイト単位**（VM.cpp:647-650,873-928）。日本語で文字数とずれ、多バイト文字を分断し文字化けの恐れ。修正案: 文字単位処理。
- **多数のスタブ関数が固定値を返す**。GETSETTING/GETMEMINFO/READFMO/DICLOAD/DICUNLOAD/GETERRORLOG/GETCALLSTACK/LOGGING/RE_ASEARCH(EX) 等（VM.cpp:2107-2199,2266-2318,1945-1953）。

### 未実装（重要度: 高/中/低）
- 高: `for`/`foreach` の実反復、`break`/`continue`、`++`/`--` の副作用 — 反復処理を多用する実ゴーストが軒並み停止/タイムアウト（120s）
- 高: Real（浮動小数点）型と実数数学・小数リテラル — 確率計算・座標補間が破綻
- 高: `&` 二項連結演算子（多くの旧 AYA/YAYA 辞書が使用）
- 中: `SPRINTF` と書式付き `STRFORM`、`%(式)` 補間の式評価
- 中: 辞書内 `charset` ディレクティブの解釈（複数 .dic 混在 charset）／`SETSEPARATOR`・`SETDELIM` 実体化
- 中: 安定したマルチバイト文字単位の文字列操作
- 低: 周辺関数（GETSETTING/TRANSLATE/ZEN2HAN/HAN2ZEN 等）の精度、`RE_ASEARCH`（スタブ）

### 互換性リスク
- **カウンタ駆動ループを使う実ゴースト全般**: `for(_i=0;_i<n;_i++){...}` や `while(_i<n){...; _i++}` は増分が効かず `break` も効かないため 120 秒タイムアウトまで空回りし応答が空/遅延になる。AYA/YAYA 標準辞書・SHIORI3FW 系の内部ループ、選択肢列挙、配列走査が該当。**最も広範な破壊。**
- **`foreach` 利用ゴースト**: 反復・要素束縛が無く、メニュー生成・リスト列挙・配列加工が機能しない（空結果か無限ループ）。
- **小数・三角関数を使うゴースト**: アニメーション/確率重み/座標計算が整数切り捨てで破綻。
- **`&` 連結に依存する旧式辞書**: 連結結果が void になりトーク/タグ生成が欠落。`+` 連結に書き換えた辞書なら動作。
- **`SPRINTF`/書式付き STRFORM 依存**: 数値整形（ゼロ詰め時刻表示等）が崩れる。
- **多バイト文字を SUBSTR/STRLEN で切る処理**: 日本語の部分抽出が文字化け/不正バイト出力。
- 一方、**SHIORI3FW フレームワークを `request` 関数経由で正しく駆動**でき、charset 自動判定・SAORI 連携・`reference[]`・複合代入・`,=`・switch(index)・三項・正規表現は動作するため、ループ・実数・`&` を多用しない単純構成のゴースト（イベント→単純トーク返却型）は概ね動作する見込み。

---

## G. プラグインシステム

### 準拠度スコア: 6/10
PLUGIN/2.0M のワイヤ書式（`GET/NOTIFY PLUGIN/2.0M`・CRLF・空行終端・`ID`/`Reference*`/`Script`/`ScriptOption`/`Target`）は型・パーサ・ビルダー共に正しく実装され、ライフサイクル（load(u)/unload/request）・descript.txt 解析・XPC 隔離・SJIS 受理・Windowハンドルの macOS マッピングまで揃っている点は高評価。一方で、(a) ホスト→プラグインのリクエストに `SecurityLevel` が一切付かない、(b) 主経路である `PluginEventDispatcher.sendFrame` がプラグイン応答を完全に破棄し `Script:` を実行しない、(c) 2 系統の送信経路で文字コード扱いが食い違う、という重大な実装欠落があるため減点。SAORI 互換層は概ね良好。

### 実装済み（仕様準拠）
- PLUGIN/2.0M リクエスト/レスポンスの型・パーサ・ビルダー → Ourin/PluginHost/PluginProtocol.swift:86, 202
- Reference の数値順ソート → Ourin/PluginHost/PluginProtocol.swift:223-229
- ライフサイクル: `request`/`loadu`→`load`/`unloadu`→`unload` のシンボル解決と CFBundle ロード、`discoverAndLoad`/`unloadAll` → Ourin/PluginHost/Plugin.swift:27-33, Ourin/PluginHost/PluginRegistry.swift:20-45
- descript.txt 解析（name/id/filename/secondchangeinterval、UTF-8/Shift_JIS 自動判定）→ Ourin/PluginHost/PluginRegistry.swift:158-194
- version 応答の `Charset:` を以降の送信へ適用する文字コード交渉 → Ourin/PluginEvent/PluginEventDispatcher.swift:101-116, 35-44
- HWND 相当の macOS マッピング（NSWindow→CGWindowID、カンマ区切り）→ Ourin/PluginEvent/WindowIDMapper.swift:7-20, PluginEventDispatcher.swift:152-163
- 0x01 区切りリスト（installedplugin / OnOtherGhostTalk の Ref5 束ね）→ Ourin/PluginEvent/ListDelimiter.swift:5-13, PluginEventDispatcher.swift:121-123, 186-189
- XPC プロセス隔離（env で有効化、透過テキスト転送、インプロセスにフォールバックしない）→ Ourin/PluginHost/PluginXpcBackend.swift:33-63, 66-80, PluginEventDispatcher.swift:23-32
- プラグインごとの直列キューによる逐次配送と 3 秒タイムアウト警告 → Ourin/PluginEvent/PluginEventDispatcher.swift:57-59, 83-98
- SAORI/1.0: `EXECUTE SAORI/1.0` + `Charset`/`Sender`/`Argument0..N`/`SecurityLevel`/`SecurityOrigin`、応答 `Result`(body)/`Value*`、dlopen/dlsym ロード、`GET Version` ハンドシェイク → Ourin/SaoriHost/SaoriManager.swift:38-59, 121-139, SaoriLoader.swift:42-80, 86-107, SaoriProtocol.swift:178-191

### 実装済み（要修正）
- **メイン配送経路がプラグイン応答を破棄し `Script:` を実行しない**
  - 現在: `sendFrame` は `_ = self?.transportSend(req, to: plugin)` で戻り値を捨てる（**監査者確認済み: PluginEventDispatcher.swift:90**）。`OnMenuExec`/`OnGhostBoot` 等を GET で送ってもプラグインが返した `Script:`/`Target:`/`Event:` が誰にも渡らない。
  - 根拠: 仕様 §4「GET の場合は `PLUGIN/2.0 200 OK` で `Script:` 等を返せる」(docs/PLUGIN_EVENT_2.0M_SPEC_FULL_ja-jp.md:133, 150)。応答処理ロジック自体は `OurinPluginEventBridge.transportAction`（OurinPluginEventBridge.swift:86-102）に存在するが、`PluginEventDispatcher` 経路はこれを通っていない。
  - 修正箇所: Ourin/PluginEvent/PluginEventDispatcher.swift:88-96
  - 修正案: `transportSend` の戻り値を `PluginProtocolParser.parseResponse` でパースし、`OurinPluginEventBridge.transportAction`/`shouldHandleTarget` を介して runScript/emitEvent コールバックへ繋ぐ。`sendVersion`（同 101-116）は既に応答をパースしており、同パターンを適用できる。
- **ホスト→プラグインのリクエストに `SecurityLevel` が付かない**
  - 現在: `PluginFrame.build()` は `Charset`/`ID`/`Sender: Ourin`/`Reference*` のみ生成（PluginFrame.swift:15-28）。`Plugin.get/notify`（Plugin.swift:58-79）も `references` のみ。
  - 根拠: PLUGIN/2.0 はイベント配送時に `SecurityLevel`（local/external）を渡す。
  - 修正箇所: Ourin/PluginEvent/PluginFrame.swift:15-28
  - 修正案: 内部発火は `SecurityLevel: local`、外部 SSTP 由来の中継は `external` を付与。
- **文字コードの二経路不整合（リクエスト送信時に SJIS 化されない）**
  - 現在: `Plugin.send` は常に `Array(text.utf8)` でバイト化し応答も UTF-8 固定（Plugin.swift:38-48）。`PluginFrame`/`PluginProtocol` は `Charset` を交渉・宣言するのに実バイト列は常に UTF-8。`PluginEncodingNormalizer` は復号ヘルパだけ用意され `Plugin.send` から呼ばれていない。
  - 修正箇所: Ourin/PluginHost/Plugin.swift:37-48
  - 修正案: 交渉済み charset を `Plugin.send` に渡し `PluginEncodingNormalizer.encoding(from:)` でエンコード/デコード（SaoriLoader.send が既に正しく実装: SaoriLoader.swift:90-104）。
- **`Plugin._cfBundle` の強制アンラップが堅牢でない**
  - 現在: `CFBundleGetBundleWithIdentifier(self.bundleIdentifier!...)!`（Plugin.swift:99-101）。`CFBundleIdentifier` 欠落の `.plugin` でクラッシュ。
  - 修正案: `CFBundleCreate(url)` か `dlopen` 経由に変更し nil 時は throw。

### 未実装（重要度: 高/中/低）
- （高）GET イベントの `Script:` 実行が `PluginEventDispatcher` 経路で未配線 — 実質プラグインが描画/発話へ作用できない。
- （高）`SecurityLevel` の付与・伝播が全経路で未実装。
- （中）プラグインからのコールバック（SSTP/Direct SSTP）経路の公開導線が未整備。
- （中）`installedghostname`/`installedballoonname`/各 `*pathlist` 通知の発火点（インストール/切替時）の接続が不明瞭。
- （中）SAORI の `311 Insecure`/`312 Not Trusted` 判定が未実装（docs/SAORI_IMPLEMENTATION.md:143 が自認）。
- （低）OnMinuteChange 等の周期イベントは定義はあるが PluginEventDispatcher のタイマーは OnSecondChange のみ駆動（PluginEventDispatcher.swift:66-76）。
- （低）`PathNormalizer.posix` が Windows ドライブレター/バックスラッシュを素通し（PathNormalizer.swift:10-26）。

### 互換性リスク
- Windows ネイティブ `.dll` プラグインは macOS で直接ロード不可（**プラットフォーム差異**）。Ourin の方針は妥当（Loadable Bundle 化、C ABI 要求、XPC 隔離）。プロトコル/ブリッジ語彙互換は概ね達成しており移植は再ビルドで足りる。バイナリ互換は非目標（docs/SPEC_PLUGIN_2.0M_ja-jp.md:6, 34）。
- SAORI も dlopen で `.dylib`/`.so`/`.bundle` を読む（SaoriRegistry.swift:99-107）。Windows `.dll` SAORI は同様に直接非対応（プラットフォーム差異）。
- 文字コード往路が UTF-8 固定（Plugin.send）のため、CP932 前提の旧プラグインは宣言と実バイトの不一致で文字化け（これは差異でなく実装バグ）。
- 応答メモリ所有権はモジュール依存（`plugin_free` は任意）でリーク可能性（プロトコル契約の緩さ）。

---

## H. NARパッケージ

### 準拠度スコア: 5/10
ローカル `.nar`（ZIP）の検証・展開・`install.txt` 解析・Zip Slip 防止・ghost/balloon/shell/plugin の振り分け・`refresh`/`refreshundeletemask`・`delete.txt`・`updates2.dau` のダウンロード適用までは実装されており、基本フローは動作する。しかし (1) **shell/supplement の設置先が UKADOC と異なる**（`accept` で親ゴーストへネストせず全種をトップレベル `shell/<directory>` に置く）、(2) **`charset` フィールドを一切読まない**（推測デコードのみ）、(3) **`supplement`/`headline`/`language` 等の type 未対応**、(4) **`updates2.dau` の MD5 差分照合が無い**、(5) **`accept` がディレクトリ名で照合され descript.txt の name を見ない**、という仕様乖離があり 5/10 にとどまる。

### 実装済み（仕様準拠）
- ZIP 形式検証（拡張子 `nar`/`zip` + 先頭 `PK` マジック）→ Ourin/NarInstall/LocalNarInstaller.swift:41-44
- `/usr/bin/ditto` による安全展開 + Windows `\` 区切りパスの正規化 → Ourin/NarInstall/ZipUtil.swift:39-58, 61-99
- install.txt 必須キー（type/directory）検証 → Ourin/NarInstall/InstallTxtParser.swift:61-62
- `refresh,1` で設置先クリア、`refreshundeletemask` 合致パスを正規表現で保持 → Ourin/NarInstall/LocalNarInstaller.swift:76-77, 116-132
- Zip Slip 防止（正規化後 dst 配下確認・シンボリックリンク無視）→ Ourin/NarInstall/ZipUtil.swift:122-130
- `delete.txt` による不要資産削除（`..` 拒否）→ Ourin/NarInstall/LocalNarInstaller.swift:283-302
- type=ghost 同梱バルーンの `balloon/<dir>` 追加展開 → Ourin/NarInstall/LocalNarInstaller.swift:86-95, 148-164
- `__MACOSX`/`.DS_Store`/`Thumbs.db` 等の自動除外 → Ourin/NarInstall/ZipUtil.swift:7-37, 111-119
- ネットワーク更新の記述子取得（`updates2.dau`→`updates.txt`→`update.txt` フォールバック）と適用 → Ourin/NarInstall/LocalNarInstaller.swift:172-184, 194-234

### 実装済み（要修正）
- **shell の設置先が UKADOC と不一致** — 現在: `shell` → `base/shell/<directory>`（トップレベル）（**監査者確認済み: Paths.swift:36, 41-42**）。正しい: UKADOC では shell は `ghost/<accept>/shell/<directory>`（親ゴースト配下）。`accept` は設置先のパス構成要素。根拠: `validateShellAccept` は `accept` を存在確認のみに使う（LocalNarInstaller.swift:71-73, 105-112）。修正箇所 Paths.swift:30-43。修正案: `installTarget(forType:directory:accept:)` に拡張し shell は `ghost/<accept>/shell/<directory>`、supplement は `ghost/<accept>/` へ。
- **`charset` フィールドを読まない（推測デコードのみ）** — UTF-8→Shift_JIS の順で推測し `charset` 行は捨てる（InstallTxtParser.swift:20-26, 57-58）。自仕様も「`charset,UTF-8` を先頭に明記（推奨）」と謳う（NAR_INSTALL_1.0M_SPEC_ja-jp.md:61）。修正案: 先頭行の `charset` をプレスキャンし宣言エンコーディングを最優先。
- **`accept` の照合方法が誤り（ディレクトリ名照合）** — `ghost/<accept>` のディレクトリ存在のみ確認（LocalNarInstaller.swift:105-112）。正しい: `accept` は対象ゴーストの descript.txt の `name` と一致させる。修正案: descript の name を走査して突合。
- **`refreshundeletemask` の区切り文字が仕様と不一致の可能性** — 値をカンマ分割（InstallTxtParser.swift:46-50）。UKADOC のバンドル項目では区切りはコロン（`:`）。修正案: `:` とカンマ両方で分割。
- **`updates2.dau` を MD5 差分リストとして解釈しない** — `UpdateDescriptorParser` は各行先頭を URL として抽出のみで MD5 列を無視（InstallTxtParser.swift:67-96）、列挙ファイルを無条件再取得（LocalNarInstaller.swift:194-234）。修正案: 各行の MD5 を保持し `CryptoKit.Insecure.MD5` と比較し差分のみ取得。

### 未実装（重要度: 高/中/低）
- **高: `type=supplement` 未対応** — `installTarget` の switch に supplement が無く失敗（**監査者確認済み: Paths.swift:33-39**）。
- **高: `updates2.dau` の MD5 差分照合** — 「全件再ダウンロード」になっている。
- **中: `type=headline` 未対応**（Paths.swift:33-39）。
- **中: `bootghost` 未読込**（InstallTxtParser.swift:57-58、自仕様も未実装明記 NAR_INSTALL_1.0M_SPEC_ja-jp.md:213）。
- **中: SSP拡張 type（language/calendar/skin/package 実体展開）未対応** — `package` は switch にあるが複数項目の分解インストールが無い（Paths.swift:38）。
- **中: 競合解決 UI 未実装** — `directoryConflict` 型はあるが常に上書き（LocalNarInstaller.swift:66-78）。
- **低: 隔離属性（quarantine）の扱い未記載**。
- **低: WebNarInstaller が機能退行版** — `x-ukagaka-link` 経由は `refresh`/同梱バルーン/`delete.txt` を処理せず単純コピーのみ（WebNarInstaller.swift:93-131）。

### 互換性リスク
- **shell/supplement のパス構造が SSP 非互換**: トップレベル `shell/<dir>` に置くため、`accept` で親ゴーストへ紐付く SSP 配布物が正しい場所に入らず参照不能の可能性大（macOS 差異ではなく論理構造の乖離）。Paths.swift:30-43
- **`accept` が descript の name でなくディレクトリ名照合**: ゴースト name とディレクトリ名が別の配布物で常に「親ゴースト未検出」警告。
- **設置ルートが二重**: `OurinPaths.baseDirectory()` は `~/Library/Application Support/Ourin/` を返すが、ghost が空のときだけサンドボックスコンテナを返す（**監査者確認済み: Paths.swift:14-26**）。インストール先と既存ゴースト探索先が食い違い、サンドボックス有効時にインストールしたゴーストが一覧に出ない/別ルートに入るプラットフォーム差異リスク。
- **`charset` 無視による文字化け**: SJIS 宣言済みでも UTF-8 として偶然デコードされ `directory` 名が化けて設置先が壊れる恐れ。
- **`updates2.dau` 全件再取得**: 差分更新になっておらず帯域・サーバ負荷。

---

## I. FMO（Forged Memory Object）

### 準拠度スコア: 5/10
セパレータ規約（char(1)=SOH／CRLF）とエンコード（UTF-8、SSP系と一致）、複数ゴーストの連番ID付与、SSTP EXECUTE GetFMO 経由の公開、排他制御（named semaphore）といった「枠組み」は正しく実装され、テストでも format が検証されている（OurinTests/FmoTests.swift:7-112）。しかし公開しているフィールド集合が SSP/UKADOC 標準のサブセットにとどまり、他の伺かツールが期待する主要キー（`hwnd` は実値でなくダミー0、`fullname`/`hwndlist`/`kerohwnd`/`ghostpath`/`module.state` 等が欠落）を出していないため、共有メモリを直接読む既存ツールとの意味的互換は限定的。Mutex 名も SSP 標準（`Sakura`/`SakuraFMO`）でなく Ourin 独自（`/ourin_fmo_mutex`）。

### 実装済み（仕様準拠）
- レコード形式 `(id).(key)\x01(value)\r\n`（SOH 区切り＋CRLF 行終端）→ Ourin/FMO/FmoManager.swift:55-69
- エンコードは UTF-8（SSP の現行仕様と一致）→ Ourin/FMO/FmoManager.swift:74
- 複数ゴースト管理: 起動中の全 GhostManager から1ゴースト=1レコードを収集し連番ID付与 → Ourin/OurinApp.swift:355-368, FmoManager.swift:57
- SSTP EXECUTE `GetFMO` をサポートし共有メモリ書き込みと同一の `buildSnapshot` 出力を返す → Ourin/SSTP/SSTPDispatcher.swift:424-437, 525-528
- GetFMO に security level ガード（local のみ、それ以外 420）→ Ourin/SSTP/SSTPDispatcher.swift:425-435
- 排他制御: POSIX named semaphore でロック/アンロック → Ourin/FMO/FmoMutex.swift:51-60, FmoSharedMemory.swift:60-69
- 単一インスタンス強制: 共有メモリの存在で判定 → Ourin/OurinApp.swift:121-125, Ourin/FMO/FmoBridge.c:85-98
- クラッシュ後の残留 shm/semaphore を安全に復旧 → Ourin/FMO/FmoMutex.swift:26-38, FmoBridge.c:13-23
- バッファ先頭4バイトに長さ(uint32)、末尾NUL終端 → Ourin/FMO/FmoSharedMemory.swift:63-68, docs/About_FMO_ja-jp.md:84

### 実装済み（要修正）
- **共有メモリ／Mutex 名が SSP 標準と非互換** — 現在 shm=`/ourin_fmo`、mutex=`/ourin_fmo_mutex`（**監査者確認済み: FmoManager.swift:18-19**）／ SSP は FileMappingObject 名 `Sakura`、Mutex 名 `Sakura` 系。Ourin 独自名では shm 直読み互換は最初から不可。修正案: ドキュメントで「直読み互換は提供しない／GetFMO経由が唯一の互換 IF」と明示するか、レコードを標準準拠にして直読みパスを意味的互換に近づける。
- **標準フィールド集合の欠落（最重要）** — 出力キーは `name, keroname, path, shell, balloon, sakura.surface, kero.surface, hwnd(=0)` の8キーのみ（**監査者確認済み: FmoManager.swift:59-66**）。UKADOC/SSP の FMO は `path, hwnd, name, keroname, sakura.surface, kero.surface, kerohwnd, hwndlist, fullname, ghostpath, ghostname, module.state` 等を含む。`fullname`/`hwndlist`/`kerohwnd` は `\![raiseother]`/`OnOtherGhostBooted` 連携で他ゴーストが参照する中核。修正案: `FmoGhostRecord` にこれらを追加し `hwnd` には 0 でなくプロセス内で一意・安定な整数IDを割当。
- **`shell` フィールドは SSP 標準キーではない**（FmoManager.swift:62）— 害は小さいが標準外であることを留意/明記。
- **更新タイミングが Notification 1経路のみ** — `refreshFmo()` は `handleFmoRefresh` からのみ呼ばれる（OurinApp.swift:265-267, 371-375）。ドキュメントは OnBoot/終了/OnShellChanged/OnBalloonChange/OnSurfaceChange で更新と主張（About_FMO_ja-jp.md:88-94）。各イベントが確実に post している保証がコード上で確認できず、surface 変更でスナップショット陳腐化のリスク。

### 未実装（重要度: 高/中/低）
- **【高】標準 FMO フィールドキーの大半が未公開**: `hwnd`(実値), `kerohwnd`, `hwndlist`, `fullname`, `ghostpath`, `ghostname`, `module.state`（FmoManager.swift:59-66）→ 他ゴーストの相互識別・`\![raiseother]` 連携が成立しない。
- **【高】一意 HWND 相当 ID の不在**: レコードキーが配列 index（`enumerated()`）であり安定一意 ID を割り当てていない。ゴースト追加/削除で ID が再割当され外部参照が壊れる。
- **【中】Shift_JIS 出力の非対応**: UTF-8 固定（FmoManager.swift:74）。歴史的 Shift_JIS 前提の旧ツール直読みには非対応（SSP 現行 UTF-8 とは一致するため実害限定）。
- **【中】外部直読みプロセスの相互排他規約はドキュメント推奨に留まる**（About_FMO_ja-jp.md:84）。
- **【低】FMO 駆動イベント（`\![raiseother]`, `OnOtherGhostBooted`）の連携**は本カテゴリ範囲では未確認。

### 互換性リスク
- **直読み互換は事実上ゼロ**: shm 名 `/ourin_fmo`・Mutex 名 `/ourin_fmo_mutex` は SSP の `Sakura`/`SakuraFMO` と異なるため、既存 Windows/SSP 系ツールが期待する名前で FMO を直接マップできない。POSIX shm vs Win32 file-mapping のプラットフォーム差異もあるが、名前・schema 双方が独自のため意味的互換は GetFMO 経由のみ。
- **フィールド schema 不足による連携不能**: `fullname`/`hwnd`(一意)/`hwndlist` 欠落で、GetFMO を読めても他ゴーストが相手を特定して通信する標準フローが組めない。
- **ID 不安定性**: レコードIDが配列 index のため起動順や脱落でIDが変動し、外部キャッシュと不整合。
- **更新整合性**: 更新トリガが全て配線されている確証がなく陳腐化スナップショットを返す可能性（OurinApp.swift:371-375 の呼び出し元が単一）。

---

## J. バルーン・シェル・リソース

### 準拠度スコア: 4/10
descript.txt / surfaces.txt の基本パース（key,value 形式、CP932 フォールバック、animationN.interval/pattern/option、collision、座標系プロパティ）は動作する。しかし SERIKO/2.0 の中核である `elementN`（基底サーフェス合成）が完全に未実装で、これは現代の主要シェル（emily4、ほとんどの SSP 製シェル）が前提とする機能であり致命的。加えて `surfacetable.txt`（レガシー別名）、独立した `alias.txt`、`surface.append` ブロックも未処理。バルーン側も `maxwidth/maxheight/wordwrappointright/marginx/marginy` が `BalloonConfig` で全く読まれず、`BalloonView` のサイズは 400×150 にハードコードされ descript.txt のサイズ指定を無視している。

### 実装済み（仕様準拠）
- descript.txt の `key,value` パースと CP932 フォールバック → Ourin/Balloon/DescriptorLoader.swift:24-27
- balloon descript の主要座標系（origin.x/y, wordwrappoint.x/y, validrect.*, arrow0/1.x/y, sstpmarker/message, communicatebox, onlinemarker, number.*）→ Ourin/Ghost/BalloonConfig.swift:127-168
- balloon サーフェス画像の type 分岐（s/k/c）と PNA 別アルファ適用 → Ourin/Ghost/BalloonConfig.swift:186-220, 223-244
- ICO/CUR 内蔵パーサ（ICONDIR/ICONDIRENTRY、PNG ペイロード優先、32bpp DIB→RGBA、AND マスク補完）→ Ourin/Balloon/ICO.swift:38-115
- Image I/O 経由の汎用画像読込＋同名 `.pna` 別アルファ合成 → Ourin/Balloon/ImageLoader.swift:21-31, 52-63
- SERIKO サーフェスグループ（`surface0,3,5`）の複数 ID 展開 → Ourin/Animation/SerikoParser.swift:372-377
- `animationN.interval` / `animationN.patternM` / `animationN.option`（pingpong/series/exclusive 等）→ Ourin/Animation/SerikoParser.swift:162-360
- collision の数値版・collisionex（rect/circle/polygon）→ Ourin/Animation/AnimationEngine.swift:221-310
- リソースパス解決: 相対/絶対 `/`・`file://`・Windows 形式（`\`→`/`）吸収 → Ourin/ResourceBridge/ResourceBridge.swift:287-297
- リソースのキャッシュ(TTL=5s)・SET 上書き・recommendsites/portalsites の \x02/\x01 区切り展開 → Ourin/ResourceBridge/ResourceBridge.swift:35-60, 265-278

### 実装済み（要修正）
- **バルーンサイズが descript.txt を無視しハードコード** — 現在 `BalloonView` が `balloonWidth=400 / balloonHeight=150` 固定（BalloonView.swift:14-15, 25, 62）。正しくは枠サイズ＝サーフェス画像実寸（または `maxwidth/maxheight`、`validrect`）。修正箇所 BalloonView.swift:14-15／BalloonConfig.load。修正案: `BalloonImageLoader.loadSurface(0)` の size を採用、テキスト frame を validrect から算出。
- **`maxwidth/maxheight/marginx/marginy/wordwrappointright` 未パース**（BalloonConfig.swift:127-168）— UKADOC balloon descript の正式フィールド。`wordwrappoint.x` のみ読み、右折返し・余白が欠落。修正案: getInt で追加。
- **`balloons*.txt` 上書き合成のファイル名規則が不正確** — `hasPrefix("balloons")` で `balloons*.txt` のみ合成（DescriptorLoader.swift:13）。仕様では `balloonk*s.txt`(kero)・`balloonc*s.txt`(communicate) も対象（BALLOON_1.0M_SPEC §1）。修正案: prefix を `balloon` に緩める。
- **descript パーサが行コメントを無視する箇所が不統一** — `DescriptorLoader.parse` は `//` を除外しない（:30-34）一方 `BalloonConfig.load` は除外（:99）。二重実装で挙動分岐。修正案: 一本化。
- **`SerikoExecutor` の `random` 確率が SERIKO 定義と乖離** — `.random(t)` で 1/t 確率（SerikoExecutor.swift:301-303）、`sometimes/rarely` の固定値(0.2/0.05)も実シェルのテンポと乖離しうる。修正案: 1tick=何msかを定義し UKADOC 確率表に合わせる。

### 未実装（重要度: 高/中/低）
- **【高】SERIKO/2.0 `elementN,method,filename,x,y`（基底サーフェスの画像合成）** — `element` を扱うコードがリポジトリに存在しない（grep 0 件）。現代シェルは基底サーフェスを複数 PNG の element 合成で定義するため、無いとサーフェス自体が表示できない/不完全。
- **【高】`surfacetable.txt`（レガシー別名・定義）未対応** — 参照なし。古いシェルが破綻。
- **【高】独立 `alias.txt` 未対応** — `SerikoParser.parseSurfaceAliases` は surfaces.txt 内の `sakura.surface.alias { }` ブロックのみ（SerikoParser.swift:381-450）。別ファイル `alias.txt` は読み込まれない。
- **【中】`surface.append` ブロック未対応**（SerikoParser.swift:132-135）— `append123` を数値化できず ID 0 件で無視。
- **【中】複数 surface への一括登録が currentSurfaceID 単一に限定**（GhostManager+Animation.swift:153-156）。
- **【中】`cursor`（マウスカーソル）/ `seriko.alignmenttodesktop` 等 shell descript の `seriko.*` 未パース**。
- **【低】SERIKO `interval,N`（数値固定周期）が `SerikoInterval` に存在せず `.unknown`**（SerikoParser.swift:33）。AnimationEngine 側は `.periodic(N)` を持ち二重実装で不一致。
- **【低】collision の polygon が bounding box 近似**（AnimationEngine.swift:267-289）。

### 互換性リスク
- **SERIKO/2.0 `element` 合成依存シェル（emily4 含む現行 SSP 製の大半）が表示破綻** — element 行が完全に無視され、基底サーフェスを element で構築するシェルでキャラ本体が出ない/壊れる。**最大リスク。**
- **`alias.txt` を使うゴースト（多くの大型ゴースト）** — surfaces.txt 内インライン alias しか解釈せず、別ファイル alias のサーフェス参照が解決できず誤サーフェス表示。
- **`surfacetable.txt` 前提のレガシーシェル** — 完全非対応で表示不能。
- **`surface.append` で差分定義するシェル** — append ブロックが ID 0 件で無視され追記アニメ/当たり判定が消える。
- **大型バルーン／右寄せ折返しバルーン** — `BalloonView` 固定 400×150 と `wordwrappointright`/`maxwidth` 未対応でテキストがはみ出す・折返し位置ズレ。
- **`balloonk*/balloonc*` 上書きを使うバルーン** — `hasPrefix("balloons")` 限定で kero/communicate 用上書きが効かない。
- **プラットフォーム差異（許容）**: Retina `@2x/@3x`（RetinaImageLoader.swift:15-42）と座標 Y 軸反転（ResourceBridge.swift:110-115）は Ourin 拡張で macOS ネイティブ化として妥当。

---

# 最終サマリー

## 1. 全体準拠度スコア

**5.7 / 10**（SHIORI=A・SakuraScript=C を重み2倍とした加重平均。`68/12`。単純平均 5.5）。

- 最高: B SSTP（7）, C SakuraScript（7）
- 最低: J バルーン・シェル（4）, F YAYA VM（4）

プロトコルの「形」（リクエスト/レスポンス書式、メソッド網羅、コマンド語彙）は高水準。一方、辞書/シェルが依存する「実行の中身」（YAYA ループ/実数、SERIKO element、Reference/引数の細部）に欠陥が集中し、実ゴースト互換の天井を下げている。

## 2. クリティカルな互換性問題 Top 10（実在ゴーストが動かない原因になりうる順）

1. **【F】YAYA の `for`/`foreach` が機能しない + `break`/`continue` no-op + `++`/`--` 無効** — カウンタ駆動ループを使う実ゴースト全般が 120秒タイムアウトまで空回りし応答が空/遅延。最も広範な破壊。`Parser.cpp:756-758`, `VM.cpp:549-557`
2. **【F】YAYA に実数型(Real)が無い** — `SQRT/SIN/POW`・小数が整数切り捨て。確率・座標・アニメ計算が破綻。`Value.hpp:12-17`, `VM.cpp:985-1037`
3. **【J】SERIKO/2.0 `element` 基底サーフェス合成が未実装** — emily4 を含む現代シェルの大半でキャラ本体が表示されない。`SerikoParser.swift`（element 不在）
4. **【F】YAYA の `&` 文字列連結演算子が void を返す** — `&` 連結に依存する旧 AYA/YAYA 辞書のトーク/タグ生成が欠落。`Parser.cpp:1158-1160`, `VM.cpp:608-612`
5. **【D】OnSurfaceChange の Reference が逆/誤り** — Ref0=旧, Ref1=新 vs 仕様 Ref0=sakura, Ref1=kero。サーフェス連動辞書が誤動作。`GhostManager+Surface.swift:48-52`
6. **【C】`\c[char,N]`/`\c[line,N]` テキスト消去が無効** — パーサ(comma)と実行(`=`)の引数書式不一致で typewriter削除演出が固まる。`SakuraScriptEngine.swift:344-355` / `GhostManager+Balloon.swift:677-687`
7. **【J】`alias.txt` / `surfacetable.txt` 未対応** — 別名サーフェス定義を使う大型ゴースト/レガシーシェルが誤表示/非表示。`SerikoParser.swift:381-450`
8. **【C】`\s[alias]` 文字列サーフェス別名が surface 0 に潰れる** — 名前付き別名を使うシェルが常に誤サーフェス。`SakuraScriptEngine.swift:241`
9. **【A/B】SHIORI/SSTP 応答の Charset 無視（UTF-8固定）** — Shift_JIS 応答ゴースト/SJIS クライアントが文字化け。`ShioriLoader.swift:431/510`, `SstpTcpServer.swift:82-85`
10. **【E】`currentghost.balloon.*` プロパティが到達不能(dead code)** — バルーン寸法を property 取得するゴーストが空値を受け取りレイアウト破綻。`PropertyManager.swift:26, 101`

次点（重大だが上位より影響範囲が狭い）: 【G】プラグイン応答(`Script:`)の破棄、【D】OnFileDrop2 未送出、【H】shell/supplement の設置先誤り、【I】FMO 標準フィールド欠落、【C】`\_n`/`\__v` のパース済み無視。

## 3. 推奨修正優先順位（影響度×修正コスト）

### P0 — 即効性の高い小修正（高影響・低コスト、まず着手すべき quick wins）
- `\c[char,N]` の引数解釈を comma 位置引数に修正（C #6）
- OnSurfaceChange の Reference を sakura/kero レイアウトに修正（D #5）
- PropertyManager を最長一致プレフィックス方式にし `currentghost.balloon.*` を復活（E #10）
- `\s[alias]` を文字列のまま保持し alias 解決（C #8、alias.txt 実装と連動）
- SHIORI 311/312 メッセージ文字列の修正（A）
- OnMouseMultipleClick の clickCount を Reference7 に格納（D #2）

### P1 — 実ゴースト互換の根幹（高影響・高コスト、最優先の構造改修）
- **YAYA: 実 `for`/`foreach`・`break`/`continue`・`++`/`--` の実装**（F #1）← 最優先
- **YAYA: Real 型と実数数学・小数リテラル**（F #2）
- **YAYA: `&` 二項連結演算子**（F #4）
- **SERIKO/2.0 `element` 合成の実装**（J #3）
- `alias.txt` / `surface.append` / `surfacetable.txt` 対応（J #7）
- SHIORI/SSTP の Charset 往復（受信デコード＋送信エンコード）を `EncodingAdapter` 経由に統一（A/B #9）

### P2 — 機能完全性（中影響）
- プラグイン応答 `Script:` の実行配線（G）と `SecurityLevel` 付与
- OnFileDrop2 / OnGhostChanged / OnInstallComplete の標準 Reference 送出（D）
- NAR の shell/supplement 設置先を `ghost/<accept>/...` に修正、`charset`/`supplement` 対応（H）
- FMO の標準フィールド（fullname/hwndlist/一意hwnd）と命名整理（I）
- バルーンサイズの descript/画像実寸ベース化、`maxwidth` 等のパース（J）

### P3 — カバレッジ拡張（低〜中影響）
- プロパティ `system.monitor/power/network/disk/theme/dnd`・`animation.num`(RW)（E）
- SSTP body 保持・ID(Owned)バイパス・9821 待受（B）
- YAYA `SPRINTF`/書式 STRFORM・`%(式)` 補間・マルチバイト文字単位操作（F）
- `\_n`/`\__v`/`\__t` 等パース済みトークンの executor 実装（C）

## 4. SSP との主要な仕様解釈の差異

| 項目 | SSP（デファクト/仕様） | Ourin の実装 | 分類 |
|---|---|---|---|
| NOTIFY 応答 Value | 原則無視 | 限定リスト外を再生（SSTPDispatcher.swift:434） | 解釈差・要検討 |
| SenderType | communicate/sakuraapi/plugin 等に細分化 | `external,sstp` 固定（SSTPDispatcher.swift:623） | 解釈差 |
| `refreshundeletemask` 区切り | コロン `:` | カンマ（InstallTxtParser.swift:46-50） | 仕様逸脱 |
| install `accept` 照合 | descript.txt の `name` | ディレクトリ名（LocalNarInstaller.swift:105-112） | 仕様逸脱 |
| shell/supplement 設置先 | `ghost/<accept>/shell/...` | トップレベル `shell/<dir>`（Paths.swift:36） | 仕様逸脱 |
| FMO 共有名/Mutex 名 | `Sakura`/`SakuraFMO` | `/ourin_fmo`・`/ourin_fmo_mutex`（FmoManager.swift:18-19） | プラットフォーム差＋逸脱 |
| FMO エンコード | UTF-8（現行 SSP） | UTF-8（一致） | 準拠 |
| `\v` / `\6` `\7` の意味 | stay-on-top / SNTP | 同（GhostManager.swift:978-991） | 準拠（旧誤解実装を回避） |
| `\f[outline]` | boolean enable | 数値を線幅として解釈 | 独自拡張 |
| HTTP `Origin: null` | 通常 external 扱い | 受理し local 級になりうる（SstpHttpServer.swift:155-159） | 解釈差・要注意 |
| SERIKO `interval,random,N` | フレーム/秒基準 | 1/t 単純確率（SerikoExecutor.swift:301-303） | 解釈差 |

## 5. docs/ 内 Ourin 独自仕様書の修正提案（外部情報源＝UKADOC を正とする）

- **docs/PropertySystem_ja-jp.md** — 「書込可は `shelllist.menu` のみ」「history/rateofuse は今後」は実装に未追従（seriko cursor/tooltip SET・history・rateofuselist は実装済み）。逆に `currentghost.balloon.*`（79-86行）は動く前提だが**到達不能**。実装修正と同時に記述更新が必要。
- **docs/SUPPORTED_SAKURA_SCRIPT.md** — `\c[...]`（✅ だが実際は壊れている）、`\_l[x,y]`（✅ だが座標反映が不確実）、`\![change,ghost]`（✅ だが条件付き）を **⚠️** に降格。`\_n`/`\__v`/`\__t` は「パースのみ・未実行」と明記すべき。
- **docs/About_FMO_ja-jp.md** — FMO の共有名/フィールド schema が SSP 標準（`Sakura` 名・`fullname`/`hwndlist` 等）と異なる旨、および「直読み互換は提供せず GetFMO 経由が互換 IF」である旨を明示。
- **docs/NAR_INSTALL_1.0M_SPEC_ja-jp.md** — shell/supplement の設置先・`accept` 照合・`charset` 尊重・`refreshundeletemask` 区切りを UKADOC（descript_install.html）準拠に改め、実装側の修正と整合させる。
- **docs/SHIORI_3.0M_SPEC_ja-jp.md** — Charset 往復（Shift_JIS デコード）が ABI 境界で未実装である現状（203-204行の 2.x 非対応宣言とは別の制約）を追記。

---

*本レポートは静的解析（ソース精読＋UKADOC一次仕様照合）に基づく。主要指摘9件は監査者が直接コードを再確認済み。動的なゴースト実機互換テスト（emily4 等の実起動）は当環境では未実施のため、表示・動作の最終確認は実機検証を推奨する。*
