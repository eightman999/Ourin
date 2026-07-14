# スタブ実装の本実装化計画（STUB_COMPLETION_PLAN）

作成日: 2026-07-08
根拠: Sonnetによるコード実測棚卸し（Swift側58件・yaya_core側8件のTODO/stub系ヒットを全件精査）＋PLUGIN_BRIDGE計画Phase5-9突合監査。
ドキュメントの自己申告ではなく、各項目はファイル:行まで実コードで確認済み。

## 進行中（本計画のスコープ外・別途完了報告）

以下は2026-07-08の互換性向上ラウンドで着手済みのため本計画から除外する。

- SHIORI SecurityLevel external伝播（SSTP外部入口）
- バルーン左上ピクセル透過（レガシー画像）
- SAORI `.plugin` バンドル対応
- NAR複合種別インストール
- Plugin bridge Phase 8 fixture一式・Phase 9 行列テスト

## Phase 1: ゴースト互換性への影響が大きいもの（P0）

- [x] **1-1. lexicon（単語クラス辞書）の実装** — 2026-07-08 実装済み（codex）
  - `Ourin/Resources/SakuraScriptLexicon.json`（組み込み語彙）を新設し、`EnvironmentExpander` 初期化時に確認済み10キー（`%ms`/`%mz`/`%ml`/`%mc`/`%mh`/`%mt`/`%me`/`%mp`/`%m?`/`%dms`）のみ注入。回帰テスト追加、ビルド成功、.app内へのリソース配置確認済み。
  - 未対応: ユーザー辞書での上書き口はdocsで仕様確認できなかったため新設せず（既存の `lexicon` 直接代入は維持）。**実ゴーストでの表示確認は未実施（検証待ち）。**
- [x] **1-2. `\j[label]` スクリプト内ラベルジャンプ** — 2026-07-08 実装済み（codex）
  - `SakuraScriptEngine.swift` のparse後にラベル解決を追加。`\j[ID]` のうちURL/file/mailto・`On...`イベント以外を `\_a[ID]...\_a` 位置へ解決（仕様: SAKURASCRIPT_FULL 1980-1984, 1153-1165行）。テスト3件追加、SakuraScriptEngineTestsスイート全パス確認済み。
  - 未対応: `\_a[ID]` 以外のラベル定義構文はdocsに存在せず対象外。
- [x] **1-3. SHIORI 2.x互換の正式実装** — 難易度: 大 — **2026-07-08 ユーザー決定: 互換性あり（正式実装する）→ 同日中にコア部分実装完了、2026-07-09 監査でスコープ再確認**
  - 実装済み: `Ourin/USL/Shiori2CompatAdapter.swift`（455行、新規）が `Shiori2CompatBackend` として `GET Version` バックエンド版数検出／3.0イベント→`GET Sentence SHIORI/2.2`+`Event:`+`Reference0-7`変換／2.xレスポンス（Sentence/BalloonOffset等）→3.0 `Value:`変換／`TEACH`→2.4/311/312往復／Shift_JISエンコードを実装。`ShioriLoader.swift:846,853,855` でXPC/Bundle/Dylib全バックエンド生成経路にラップ配線済み。`OurinTests/ShioriLoaderTests.swift:54-253`（7テスト）で完了条件（2.x応答→3.0相当変換がゴースト応答として機能）を満たすことを確認。
  - **未対応（新規TODO、`docs/AUDITS_TODO.md` A節に追記）**: `buildWordRequest`/`buildStringRequest`/`buildStatusRequest`/`buildOwnerGhostNameRequest`/`buildOtherGhostNameRequest`/`buildCommunicateRequest`（`Shiori2CompatAdapter.swift:339-422`）は単体テスト無し・呼び出し元未確認。`buildUserSentenceRequest`（`:339-348`）は `ID: OnTalk` 判定だが実イベントIDは `OnTalkRequest`（`EventID.swift:361`）のみで到達不能（`docs/SHIORI_2X_COMPAT_SPEC_ja-jp.md`も「要検証事項4」と明記）。旧 `ShioriLoader.swift:433-498`（`YayaBackend.parseRequest/buildResponse`）は別方向（Ourin自身が2.xサーバとして受ける側）の実装で新アダプタと未統合のまま並存（二重実装リスク）。

## Phase 2: 表示・UX系の機能欠落（P1）

- [x] **2-1. バルーン `--option=fixed`（固定背景）** — 難易度: 小
  - 2026-07-08 実装済み: `BalloonImage.isFixed` をパース〜`BalloonView`描画まで配線。ビルド＋BalloonTests 5件パス。**実表示での目視確認は未実施（検証待ち）。**
- [x] **2-2. バルーン垂直配置（valign）→ 誤検知につき対応不要** — 2026-07-08 実測で確定
  - 正しいコマンドは `\f[valign,top/center/bottom]`（`\_v`はサウンド系で無関係、本計画の旧記載は誤り）。
  - 実装は既に存在し稼働中: `GhostManager.swift:2451-2466` が `vm.textVAlign` へ代入し、`BalloonView.swift:76,133-142` で描画反映。パーサーテストも既存（`SakuraScriptEngineTests.swift:1042-1051`）。
  - `BalloonRichTextViewModel.handleValignCommand` は**呼び出し元ゼロの未使用クラス内のスタブ**（クラスごとデッドコードの可能性が高い）。削除するかはユーザー判断待ち。実装は行わない。
- [x] **2-3. SSTP 210 Break の `nobreak` キューイング** — 2026-07-08 実装済み（Sonnet）
  - UKADOC仕様確認の上、busy時ブロッキング待機（`SSTPBreakQueue`新規、既定5秒タイムアウト→409）→解消後に通常経路へ進む実装。テスト3件（キューイング後200／タイムアウト409／busy解消で続行）、ビルド＋SSTP系テスト全パス。
  - 残課題: busy判定は `ShioriStatusStore.currentStatus` 基準。真の「スクリプト実行完了待ち」には `GhostManager.isPlaying` への接続が必要（スコープ外・要検討）。
- [x] **2-4. 動画レンダラ（`playVideo`）** — 2026-07-08 実装済み（deep-reasoner設計→codex実装、設計書: docs/VIDEO_RENDERER_DESIGN_ja-jp.md）
  - `VideoPlayerWindow.swift` 新規（AVPlayerView別窓方式）、`\![sound,play,<動画>]` ディスパッチ配線、stop/pause/resume/wait対応、ゴースト終了時クリーンアップ、テスト5件（直列化済み）。
  - 未対応: `--balance` の実適用（パースのみ）、`sound,load` プリロード（ログのみ）。**実機での動画再生・目視確認は未実施（検証待ち）。**
  - **新規TODO（2026-07-09監査で判明、`docs/AUDITS_TODO.md` J節に追記）**: `videoFileSupport`（`GhostManager+Display.swift:145-155`）が `.unsupported` 判定する `avi/wmv/mpg/mpeg/mpe/mpv/mkv/webm/flv` は、`playVideo`（同ファイル307-320行）が `OnVideoPlayEx` を発火してログ出力するだけで実際の再生もエラー通知も行わないサイレント失敗。意図的非対応か未着手か要確認。

## Phase 3: プラグイン・周辺システム（P1〜P2）

- [x] **3-1. Plugin menuのホストメニュー統合（PLUGIN_BRIDGE Phase 7 未達分）** — 2026-07-08 実装済み（codex）
  - `PluginRegistry` にmenuモデル（`message.*.txt` 言語切替つき表示名解決）を追加し、右クリック/OwnerDrawメニューへ「プラグイン」サブメニューとして列挙。選択時は該当pluginのみへ `OnMenuExec` 送信。仕様上 Ref0=CGWindowID列のため、選択項目IDは **Ref5** に格納（本計画の旧記載「Reference0にID」は仕様と矛盾しており誤り）。`notifyplugin` 呼び出し元の `dispatchNotify` 移行も完了。テスト追加、ビルド＋plugin系テスト全パス。**実UI操作での確認は未実施（検証待ち）。**
- [x] **3-2. 行列テストで発見したPLUGINイベントの仕様ギャップ4件** — 2026-07-08 解消（GLM）。①OnInstallComplete複数値API追加（0x01結合・後方互換維持） ②`dispatchNotifyPlugin`/`dispatchNotify`でNOTIFY強制の専用経路追加（Ghost側呼び出し元の移行は残タスク） ③balloonpathlistは仕様確認の結果「Ref0のみが正、現状はスーパーセットで違反ではない」と結論し現状維持 ④reasons語彙はDEBUG警告のみ追加。行列テストFIXME 0件・全パス。
  - `OnInstallComplete` の0x01区切り複数値未対応（`onInstallComplete(type:name:path:)` が単一String）
  - `notifyplugin` のNOTIFY強制がディスパッチャに無い（呼び出し元責務になっている）
  - `balloonpathlist` が仕様上Ref0のみだが複数Reference共通コードを共有
  - `OnOtherGhostTalk` の reasons 語彙バリデーション欠如
  - 該当: `OurinTests/PluginEventDispatchMatrixTests.swift` の `// FIXME: 仕様とのギャップ` コメント箇所。
  - 完了条件: 各FIXMEが解消され行列テストがスキップ無しでパス。
- [x] **3-3. SHIORI Resource永続化のSSP互換化** — 2026-07-08 実装済み（GLM）
  - ghostKey付きモードで `data/profile/<ghost>/` ファイルストアを使用。UserDefaults→ファイルの初回移行（冪等・UserDefaults側データは削除しない）。移行テスト3件（UserDefaultsのみ→移行／ファイル優先／新規書き込みはファイル）全パス。旧グローバルモードはUserDefaultsのまま互換維持。

## Phase 4: yaya_core 低頻度組み込み関数（P2）

- [x] **4-1. `FREADENCODE` / `FWRITEDECODE`** — 2026-07-08 実装済み。iconvによる実エンコード変換（CP932↔UTF-8往復を実機IPC＋iconvコマンド独立検証で確認）。
- [x] **4-2. `LSO`** — 2026-07-08 実装済み。`lastSelectedIndex_` をparallel選択時に記録して返す。実機IPC検証済み。
- [x] **4-3. `OUTPUTNUM`** — 2026-07-08 実装済み。本家仕様は「関数名を実行し候補数を返す」であり、本計画の旧記載（printf型フォーマット）は誤りだった。array型3候補→3、未定義関数→-1 を実機IPC検証済み。
- 完了メモ: クリーンビルド成功（`./build.sh`、警告なし）。yaya_coreにテスト機構が無いため実機IPC検証で代替（テスト基盤導入は別途検討）。

## Phase 5: 検証・掃除（小粒）

- [x] **5-1. `fmoOperation` オーバーライドの裏取り** — 2026-07-08 確認済み: `YayaCore::fmoOperation`（`yaya_core/src/YayaCore.cpp:109`）がオーバーライドしJSON IPCでホストへフォワード。VM.hppの既定はフォールバックであり機能欠落ではない。対応不要。
- [x] **5-2. 古いTODOコメントの除去** — 2026-07-08 完了。配線済み（`OurinApp.swift:232,237`）を実測確認の上、TODO 2行を配線先注記に置換。
- [x] **5-3. ドキュメント訂正** — 2026-07-08 完了。`PLUGIN_BRIDGE_COMPLETION_PLAN_ja-jp.md` に監査記録セクション（過大申告✅の経緯と対応）を追記。`AUDITS_TODO.md` の完了6項目（SecurityLevel/210 Break/lexicon/NAR複合/透過処理、日英両方）と推奨対応順序を実測反映。

## 対応しない（意図的スタブとして維持）

- `GETMEMINFO` / `SETTAMAHWND`（Windows固有API、macOSでは無意味）
- `EmBeD_HiStOrY`（非標準・稀有）
- `EventReferenceSpec.swift` の DEBUG時 `assertionFailure`（開発時検証用として正常）
- `GhostManager.swift:551,664,690` の起動時プレースホルダサーフェス（正常フロー）
- PluginScaffolder生成物のダミー実行体（移植ツールの仕様として明示済み。生成物の完成は資産ごとの個別移植タスク）
- `SstpHttpServer.swift:145` MCPネイティブメソッド（-32601応答は意図的）

## 委譲方針

- 小粒・機械的（2-1, 3-2, 4-x, 5-2）: Sonnet fast-worker または GLM
- 中粒・配線系（1-1, 1-2, 2-3, 3-1, 3-3）: Codex / GLM（ファイル領域が重ならないよう分割）
- 大粒・設計必要（2-4動画, 1-3を実装する場合のSHIORI 2.x）: deep-reasoner設計→Codex実装→Sonnet検証の3段
- 各タスクは完了条件を明記して委譲し、統合後に `xcodebuild build` ＋ 可能ならテスト実行で検証する。
