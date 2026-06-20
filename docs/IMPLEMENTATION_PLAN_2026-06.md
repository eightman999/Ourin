# Ourin 実装計画 — 2026-06 残課題（UKADOC 一次仕様照合）

**作成日**: 2026-06-20
**対象ブランチ**: `claude/ultracode-effort-1xxdwf`
**照合した一次仕様**: UKADOC（`raw.githubusercontent.com/ukatech/ukadoc/master/manual/` 経由。`ssp.shillest.net` および `ukagakadreamteam.github.io` ミラーはネットワークポリシー上 403 のため不可）、YAYA 言語仕様、リポジトリ内 `docs/`。
**手法**: 4 カテゴリ（SakuraScript / SHIORIイベント / プロパティ＋SERIKO / YAYA VM＋SSTP/FMO）を並列に精読し、live UKADOC とソースを `file:行番号` 単位で突き合わせた静的解析。

> **前提**: 本計画は `AUDIT_CLAUDE.md`（2026-06-14）の P0–P3 指摘が commit `8b0acef` / `b80afac` で実装済みであることを確認した**うえで**、なお残るギャップを再調査したもの。動的なゴースト実機検証は当環境では未実施のため、各 `file:行番号` は静的解析時点の位置であり、着手時に再確認すること。

## 実装進捗（2026-06-20）

- ✅ **P0 全項目（スプリント1）完了** — SHIORI 選択肢/Balloon/Ghost切替/Install/Surface/FileDrop2 の Reference 修正、SERIKO `periodic` 間隔、SSTP body 配線。
- ✅ **P1 全項目（スプリント2）完了**
  - YAYA `SAVEVAR`/`RESTOREVAR`・`SETDELIM`/`GETDELIM`（**Linux で yaya_core をビルドし IPC 経由で動作検証済み**: 変数の保存復元・配列往復・SPLIT 区切り）
  - プロパティ `scope(N).surface.num`/`animation.num` SET の副作用反映
  - SakuraScript WebSocket 一式
  - SERIKO `interpolate`/`insert`/`alternativestop` メソッド
- ⏳ **P2/P3 未着手** — 以下に記載。Swift 側は当環境でコンパイル検証不可のため、Xcode が使える環境での着手・検証を推奨。

> 注: Swift 変更（P0 の一部・P1-2/P1-4/P1-5）は当 Linux 環境では `xcodebuild` 不可のため静的レビューのみ。C++（yaya_core）変更は実ビルド＋実行で検証済み。

---

## 0. サマリー（残ギャップの分布）

| 領域 | 解決済み（直近 commit） | 残 High | 残 Med | 残 Low |
|---|---|---|---|---|
| YAYA VM | for/foreach・break/continue・++/--・Real型・&・SPRINTF・%()・UTF-8文字列 | SAVEVAR/RESTOREVAR, SETDELIM/GETDELIM | FUNCTIONEX, GETTYPE(Real), FENUM絶対パス | READFMO, TOAUTO, HMC ほか |
| SSTP/FMO | 9821ポート, FMO標準フィールド | 本番経路のbody破棄 | Owned-SSTP bypass, COMMUNICATE Surface header | — |
| SHIORIイベント | Mouse系, 時刻系, OnFileDrop2発火, Update系 | OnChoiceEnter/Select の Ref 誤り | Balloon系/Ghost系 Ref, OnKeyPress, OnWindowState* | OnTranslate ほか |
| プロパティ/SERIKO | system.monitor/disk/theme/power/network, os.*, element合成, alias/surfacetable/append | animation.num SET, surface.num SET, periodic間隔 | interpolate/insert/alt系, collisionex, use_self_alpha, balloon margin適用 | locale細分 ほか |
| SakuraScript | http/rss, archive, scaling, alpha, bind, reload系 | WebSocket 一式 | effect/filter描画, zorder/sticky強制, selectmode矩形 | balloonnum意味, doc整合 |

**全体方針**: 「形（語彙互換）」はほぼ完成。残るのは**(a) 既存実装の Reference/引数の細部バグ**、**(b) 実ゴーストが依存する永続化・遅延発火・プロパティ書込みの欠落**、**(c) 描画系の本実装（effect/SERIKO補間）**の 3 系統。(a)(b) を優先する。

---

## P0 — 高影響・低コスト（quick wins、まず着手）

実ゴーストの動作可否に直結するが、修正は局所的なもの。

### P0-1. SHIORI 選択肢イベントの Reference 修正 ★最優先
実害: メニュー／選択肢を使うゴースト全般で選択が辞書にルーティングされない。
- **OnChoiceEnter**: `Reference0` に `pendingChoices.count`（整数）を入れている。仕様は R0=選択肢ラベル, R1=選択肢ID。`Ourin/Ghost/GhostManager+System.swift:383`
- **OnChoiceSelect**: `Reference0` にラベルを入れているが、仕様は R0=`\q[label,ID]` の **ID**。SHIORI 辞書は ID でキーするため現状ルーティング不能。`GhostManager+System.swift:436-445`
- 併せて、1 クリックで Select+SelectEx+Hover が同時発火する点（`:441-448`）を仕様どおり整理。
- 修正方針: `\q` パース時に label と ID を保持する構造へ統一し、選択確定時に ID を R0（SelectEx は R0=ID, R1=label の仕様に合わせる）で送出。`docs/OURIN_SHIORI_EVENTS_3.0M_SPEC_ja-jp.md:289` の未チェック TODO と整合させる。

### P0-2. SERIKO `interval,periodic,N` が発火しない
実害: 最も一般的な定間隔アニメが無音で停止（`.unknown` に落ちる）。
- `Ourin/Animation/SerikoParser.swift:3-13`（`SerikoInterval` に `.periodic` ケース無し）→ `SerikoExecutor.swift:293-316` で never fire。
- 修正方針: `SerikoInterval` に `.periodic(Int)` を追加し、Executor に「N 秒ごとに必ず発火」を実装（legacy `AnimationEngine.swift:43` の挙動を移植）。

### P0-3. SSTP リクエスト body を本番経路へ配線
実害: EXECUTE/GIVE/SEND の本文・複数行ボディが本番で消える（モデル/パーサは対応済みだが未配線）。
- `Ourin/ExternalServer/OurinExternalServer.swift:55` が `SSTPParser.parseRequest(text: raw)` を body 無しで呼ぶ。`SSTPParser.swift:16` は空行で `break` し以降を破棄。
- 修正方針: 受信バイト列を「ヘッダ部（空行まで）」と「body 部」に分割し、`parseRequest(text:body:)`（`SSTPRequest.swift:31`）へ body を渡す。Charset は既存 `EncodingAdapter` でデコード。

### P0-4. Balloon 系イベントの Reference 修正
実害: 中断/閉じスクリプトを参照するゴーストが破綻。
- **OnBalloonBreak**: R0=scope 番号のみ送出。仕様 R0=中断されたスクリプト, R1=scope, R2=文字オフセット。`Ourin/Ghost/GhostManager+Balloon.swift:115`
- **OnBalloonClose**: R0=scope 番号。仕様 R0=閉じた時点で表示中のスクリプト。`GhostManager+Balloon.swift:116,163`

### P0-5. Ghost 切替イベントの Reference ズレ
- **OnGhostChanging**: R3 に「直前の path」を入れているが、仕様は切替**先**ゴーストの path。`GhostManager+System.swift:1581-1586`
- **OnGhostChanged**: R1 に「新ゴースト名」（仕様 R1=直前の切替スクリプト）。R7（新シェル）欠落。`GhostManager+System.swift:1601-1606`

### P0-6. その他の局所 Reference 修正（低コスト）
- **OnInstallComplete**: R2 に install path（仕様 R2=副名）。`GhostManager+System.swift:1468-1472`
- **OnSurfaceRestore**: R0=old/R1=new id（仕様 R0=sakura/R1=kero の現在サーフェス）。`GhostManager+Surface.swift:64-71`
- **OnFileDrop2**: ファイルごとに R0=name/R1=path の別イベント（仕様は Reference0 に 0x01 区切りの path リストを 1 イベント）。`Ourin/Ghost/DragDropView.swift:95`

---

## P1 — 高影響・中〜高コスト（実ゴースト互換の根幹）

### P1-1. YAYA `SAVEVAR` / `RESTOREVAR` の実装 ★最優先
実害: セーブデータ（好感度・既読・設定）を持つゴーストが永続化に失敗。多数のゴーストが依存。
- 現状 no-op stub。`yaya_core/src/VM.cpp:2275,2280`
- 修正方針: 指定変数群を JSON/独自バイナリで `~/Library/Containers/.../ghost/<id>/` 配下へ保存・復元。グローバル変数テーブル（`localScopes_` 外）を対象に、YAYA 既定の `_var.cfg` 相当パスを尊重。

### P1-2. プロパティ `animation.num` SET / `surface.num` SET
実害: `\![set,property,...]` 経由でアニメ起動・サーフェス変更を行うゴーストが無反応。
- **animation.num**: getter/setter/`ScopeData` フィールドが完全に存在しない（read も write も無い）。`Ourin/Property/GhostPropertyProvider.swift:106-194`
- **surface.num**: getter のみ（`:439`）、`set()` に分岐無しで write 不可。
- 修正方針: `ScopeData` に animationNum を追加。setter で scope 解決 → `surface.num` は `GhostManager` のサーフェス変更へ、`animation.num` は `SerikoExecutor` の `start` 起動へ配線。`b80afac` で deferred と明記された項目。

### P1-3. YAYA `SETDELIM` / `GETDELIM` の機能化
実害: 区切り文字を設定して配列⇔文字列変換する旧 AYA/YAYA 辞書が誤動作。
- 現状: `GETDELIM` はハードコード `","` を返し（`VM.cpp:2454`）、`SETDELIM` は値を保存せず（`:2460`）、`SPLIT` も参照しない（`:1278`）。
- 修正方針: VM にカレント区切り状態を持たせ、`SPLIT`（引数省略時）・配列→文字列の自動連結・`GETDELIM` が参照するよう統一。

### P1-4. SakuraScript WebSocket 一式
実害: ネット連携する現代ゴーストで `\![execute,websocket]` 系が完全無反応（唯一の完全 MISSING ファミリ）。
- `\![execute,websocket,URL,...]` / `\![send,websocket,URL,data]` / `\![send,websocket-binary,...]` / `\![close,websocket,URL]` / `\![cancel,websocket,URL]`。コードに痕跡なし。
- 修正方針: `URLSessionWebSocketTask` で接続管理（URL キー）。受信を `OnWebSocketMessage` 等のイベントへ。`GhostManager+System.swift` の http 実装（`:721`）と同様のパターンで配線。

### P1-5. SERIKO アニメメソッドの本実装
実害: `interpolate`/`insert`/`alternativestop` に依存するシェルが破綻、`alternativestart` がランダム選択にならない。
- `interpolate`/`insert`/`alternativestop`/`parallelstart`/`parallelstop` が `.unknown` に落ちる。`SerikoParser.swift:51-66`
- `alternativestart` が `start` のエイリアス（ランダム代替選択なし）。`SerikoExecutor.swift:174-180`
- 修正方針: メソッド enum を拡張し、`alternativestart` はパターン候補からランダム 1 件、`interpolate` はフレーム補間、`insert` はシーケンス挿入を実装。

---

## P2 — 中影響（機能完全性）

### P2-1. SakuraScript `\![effect]` / `\![effect2]` / `\![filter]` の描画実装
現状: `EffectConfig`/`FilterConfig` を VM に保存しログするのみ、視覚変換なし。`Ourin/Ghost/GhostManager+Effects.swift:14-57`
方針: CoreImage ベースのトランジション/フィルタを `CharacterView` へ適用（config 構造とプラミングは既存）。エフェクトプラグイン機構が無いため、組込みエフェクト名（appear/dissolve 等）優先。

### P2-2. `\![set,zorder]` / `\![set,sticky-window]` の強制
現状: グルーピング状態のみ保存、keep-front / co-drag の強制なし。`GhostManager.swift:1703-1706,1834-1839`
方針: `NSWindow.level` と orderWindow による前後固定、ドラッグ同期で連動移動。

### P2-3. `\![enter,selectmode]` 実矩形・collisionmode 可視化
現状: select-mode が `Reference0` に固定 `"0,0,0,0"`（実座標取得なし）。`GhostManager+System.swift:1989`
方針: マウス選択矩形を実取得して R0 に格納。collisionmode は当たり領域オーバレイ表示。

### P2-4. YAYA `FUNCTIONEX`／関数型修飾子・GETTYPE(Real)・FENUM 絶対パス
- `nonoverload`/`sequential`/`array`/`void`/`when` 関数定義修飾子と匿名関数が未対応。`yaya_core/src/Parser.cpp:86`
- `GETTYPE` に `Type::Real` 分岐が無く Real が type 0(void) を返す。`VM.cpp:983`
- `FENUM` が絶対パス・`..` を拒否（YAYA は絶対ゴーストパス前提）。`VM.cpp:1751`

### P2-5. SHIORI `OnKeyPress` / `OnWindowStateMinimize|Restore`
- `OnKeyPress` 未生成（KeyDown/KeyUp のみ）。`Ourin/SHIORIEvents/InputMonitor.swift:155-156`
- `OnWindowStateMinimize/Restore` がドキュメント化のみで発火経路なし。
方針: 既存入力/ウィンドウ監視に発火点を追加（R0=key code / minimize reason）。

### P2-6. SSTP Owned-SSTP バイパス・COMMUNICATE Surface ヘッダ
- Owned-SSTP（`ID:` ヘッダ／同一プロセス）バイパス未実装。`Ourin/SSTP/SSTPDispatcher.swift:35-46`
- 受信 COMMUNICATE の `Surface` リクエストヘッダ未処理（応答側のみ対応）。`SSTPDispatcher.swift:596-605`

### P2-7. SERIKO `collisionex` 形状・`seriko.use_self_alpha`・balloon margin 適用
- `collisionex` の ellipse/region 未対応、polygon/circle は bounding-box 近似。`Ourin/Animation/AnimationEngine.swift:239-289`
- `seriko.use_self_alpha`（PNA 無しの自己アルファ PNG）未対応。参照なし。
- balloon `marginx`/`marginy`/`wordwrappointright` がパースのみで `BalloonView` 未使用（dead）。`Ourin/Ghost/BalloonConfig.swift:174-176`

---

## P3 — 低〜中影響（カバレッジ拡張・整合）

- **プロパティ細分**: `system.network.{type,cost,downlink}`、`os.locale.language/country`、`os.dst`、`monitor.bpp`、`disk.type`、`power.battery.lifetime`、`currentghost.balloon.scope.background.color/scaling`、`scope.scaling`/`currentmonitor.*`。`Ourin/Property/PropertyManager.swift`, `GhostPropertyProvider.swift`
- **SERIKO 間隔の追加モード**: `talk,N`（文字数カウント）、`bind` 状態ゲート、`starttalk/endtalk`、`mousemove`、間隔合成（`bind+random,5`）。`SerikoParser.swift`
- **YAYA 低頻度 stub**: `READFMO`/`TOAUTO`/`LOGGING`/`DICLOAD`/`GETSETTING` ほか（`VM.cpp:2295-2628`）。`READFMO`/`TOAUTO` を優先。
- **SakuraScript 意味整合**: `\![set,balloonnum]` を bool ではなく `file,current,max`（DL 進捗）として再実装。`\_m` を `\_u` と別意味（byte コード）に。`GhostManager.swift:1776,2199-2209`
- **SHIORI 残**: `OnTranslate`、`OnInstallCompleteEx`、`OnInstallRefuse`、`OnBootupComplete`、`OnVanished`/`OnVanishButtonHold`/`OnGhostCalling` の Ref 補完。

### ドキュメント整合（コード実態に合わせて更新）
- `docs/SUPPORTED_SAKURA_SCRIPT.md` / `SAKURASCRIPT_COMMANDS_SUPPORTED_en-us.md`: `\![effect]`/`\![filter]`/`\![set,zorder]`/`sticky-window` を ✅→⚠️（状態保存のみ）へ降格。WebSocket 未対応を明記。`_en-us` の古い「未実装」節は実態（実装済み）と矛盾するため除去。
- `docs/OURIN_SHIORI_EVENTS_3.0M_SPEC_ja-jp.md`: 選択肢/Balloon/Ghost 系 Reference の現状バグを反映。

---

## 実装順序（推奨スプリント）

1. **スプリント1（P0 一括）**: SHIORI Reference 修正群（P0-1,4,5,6）＋ SERIKO periodic（P0-2）＋ SSTP body 配線（P0-3）。いずれも局所修正で回帰テストを追加しやすい。
2. **スプリント2（永続化・プロパティ）**: SAVEVAR/RESTOREVAR（P1-1）＋ animation.num/surface.num SET（P1-2）＋ SETDELIM（P1-3）。
3. **スプリント3（描画・ネット）**: WebSocket（P1-4）＋ SERIKO メソッド（P1-5）＋ effect/filter 描画（P2-1）。
4. **スプリント4（強制・補完）**: zorder/sticky（P2-2）、selectmode（P2-3）、YAYA FUNCTIONEX 系（P2-4）、SHIORI OnKeyPress/WindowState（P2-5）。
5. **スプリント5（P3＋doc）**: カバレッジ拡張とドキュメント整合。

## 検証方針
- 各 P0 Reference 修正には UKADOC 期待値を埋めた SHIORI スタブによる単体テスト（`OurinTests`）を追加。
- YAYA 系（SAVEVAR/SETDELIM/FUNCTIONEX）は `yaya_core` の既存テストハーネス（`all_functions_test` 等）にケース追加し `./build.sh` で検証。
- SERIKO periodic / メソッドと effect 描画は emily4 同梱シェルでの実機目視（Xcode 実行）を最終確認とする。
- SSTP body は TCP/HTTP 両経路へ EXECUTE/GIVE のボディ付きリクエストを投げる E2E を追加。
