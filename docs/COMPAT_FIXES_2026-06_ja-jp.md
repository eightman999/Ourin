# 互換性修正レポート (2026-06-10)

監査レポート（→ 集約先 [AUDITS_COMPLETED.md](AUDITS_COMPLETED.md) / [AUDITS_TODO.md](AUDITS_TODO.md)）の P0/P1 指摘に基づく互換性修正の記録。
目的は「既存ゴーストが起動し、自然に喋り、基本的なSSTP連携が動く」こと。

## 修正済み (P0)

### 1. YAYA辞書の CP932 / Shift_JIS → UTF-8 変換
- `yaya_core/src/DictionaryManager.cpp`: iconv による CP932→UTF-8 変換を実装。
  - 優先順位: UTF-8 BOM → yaya.txt の `charset` 指定 → 自動判定（UTF-8妥当性チェック → CP932変換）。
  - 既存の UTF-8 辞書を壊さないため、charset 宣言が CP932 でも内容が妥当な非ASCII UTF-8 なら UTF-8 として読む。
  - 変換失敗は `[DictionaryManager] ERROR:` でログ。全辞書失敗時のみ load が false を返す。
- Swift側: `parseYayaConfigFile` が `charset,` 行を収集し `YayaAdapter.load(encoding:)` に渡す。
- `yaya_core/CMakeLists.txt` に iconv リンクを追加。

### 2. SSTP応答行の二重プレフィクス
- `ExternalServer/SstpParser.swift`: version から `SSTP/` を剥がして保持（"SSTP/SSTP/1.x" の修正）。
- テスト: `ExternalServerTests.responseStatusLineHasSinglePrefix` 等。

### 3. SSTP SEND の Script バルーン再生
- `ExternalServer/SstpRouter.swift`:
  - Event無し SEND → SHIORI を介さず Script ヘッダを直接再生。
  - Event有り SEND → SHIORI 応答スクリプト（無ければ Script ヘッダ）をバルーン再生。
  - `Option: nodescript` はバルーン再生のみ抑止し、イベント処理は行うよう修正。
- `EventBridge.playScriptOnGhosts(_:ghostName:)` を新設（ReceiverGhostName による絞り込み対応）。

### 4. OnSecondChange / OnMinuteChange / OnHourTimeSignal
- `TimerEmitter.swift`: Reference0=OS連続起動時間(hour)、Reference1=見切れ、Reference2=重なり、Reference4=放置秒 を付与。
  - 見切れ/重なり判定は未実装のため安全な暫定値 0（TODO コメントあり）。
  - 放置秒は CGEventSource の全入力イベント経過秒。
- `EventBridge.swift`: Reference3（トーク再生可否 = `GhostManager.canPlayTalkNow()`）をセッション毎に設定し、
  cantalk=1 なら GET（返値スクリプト再生）、cantalk=0 なら NOTIFY（返値無視）に切替。

### 5. Reference の数値順ソート
- `EventBridge.swift` / `PluginProtocol.swift`: ReferenceN を数値順に整列（辞書順だと Reference10 < Reference2）。
- 非Referenceキーは位置引数（refs）に混入しない。欠番は "" でパディング。
- `InputMonitor.swift`: マウス/キーイベントのパラメータを UKADOC 準拠の ReferenceN 形式に変更
  （Reference0=X, 1=Y, 2=ホイール, 3=スコープ, 4=当たり判定, 5=ボタン, 6=デバイス種別）。
  キャラクターウィンドウ内では左上原点のローカル座標。

## 修正済み (P1)

### SakuraScript タグ意味論（GhostManager.swift）
| タグ | 旧（誤） | 新 |
|---|---|---|
| `\t` | 100msポーズ | タイムクリティカルセクション（\e/スクリプトブレークまでマウス系イベント抑止） |
| `\-` | 改行 | 当該ゴースト終了（OnClose 応答末尾の定番動線） |
| `\v` | 設定ウィンドウを開く | stay-on-top（最前面表示） |
| `\4` / `\5` | Zオーダー変更 | 相方キャラから離れる / 接触する距離まで水平移動 |
| `\*` | 選択肢ダイアログ表示 | 選択肢をタイムアウトさせない |
| `\a` | 選択肢ダイアログ表示 | 旧仕様 OnAITalk を GET で発生、返値再生 |
| `\&[ID]` | アンカーイベント誤発火 | 実体参照（数値文字参照 + 主要名前付き実体）。イベントは発火しない |
| `\_V` | `\_v` に吸われ再生実行 | 大小文字を保持し再生完了待ちとして処理 |
| `\j[ID]` | ハンドラ無し（黙殺） | URL/fileオープン + Onイベントジャンプ（GET→返値再生）。未対応形式はログ |

### YAYA 正規表現（yaya_core/src/VM.cpp）
- RE_SEARCH / RE_MATCH / RE_GREP が直近マッチ状態を保持。
- **RE_GETSTR / RE_GETPOS / RE_GETLEN / RE_OPTION / RE_REPLACEEX を実装**。
- 引数順を本家YAYA準拠の `RE_xxx(対象文字列, 正規表現)` に修正（旧実装は逆順だった。
  emily4 等の実在ゴーストは本家順で呼ぶため旧実装では全滅していた）。
- RE_SEARCH の戻り値も本家準拠の 1/0 に修正（旧: 位置 or -1）。
- 回帰用辞書: `yaya_core/examples/re_test.dic` / `re_test2.dic`。

### YayaCore SHIORI応答ヘッダ（yaya_core/src/YayaCore.cpp）
- `"Value: "` の部分文字列検索を廃止し、応答をヘッダ単位でパース。
- Value 以外のヘッダ（Reference0 / ValueNotify / Status / Balloon 等）を `headers` として Swift 側へ全引き渡し。
- フレームワークが返すステータスコード（200/204等）も伝搬。

### 起動・終了イベント
- OnBoot: Reference0=シェル名。2回目以降の起動もすべて OnBoot（OnSecondBoot は UKADOC に存在しないため削除）。
- OnFirstBoot: Reference0=vanish回数（`OurinVanishCount`、executeVanish で記録）。
- OnClose: `GhostManager.beginCloseSequence` が GET で送出（Reference0=終了理由）→ 応答スクリプト再生 →
  `\-` または再生完了で終了確定。`applicationShouldTerminate` で `.terminateLater` を返し連携。
- EventBridge.stop() の応答破棄つき OnClose 送信は削除（二重送信防止）。

## 修正済み (P2の一部)

- PropertyManager: `system.*` をキャッシュ対象から除外（system.second 等の固定化を解消）。
- CLAUDE.md の yaya_core 記述を実態（C++/CMake）に更新。

## 追加修正済み (2026-06-12)

### 見切れ（mikire）/ 重なり（kasanari）の実判定
- `GhostManager+Window.swift`: `mikireScopes()` / `kasanariScopes()` を新設。
  キャラクターウィンドウの矩形と所属スクリーンの可視フレームを比較し、はみ出しているスコープ ID
  を見切れ、互いに矩形が交差しているスコープ ID を重なりとしてカンマ区切りで返す。
- `EventBridge.swift`: 時刻系イベント（OnSecondChange/OnMinuteChange/OnHourTimeSignal）の
  Reference1/Reference2 をセッション毎に上書き設定。
- `TimerEmitter.swift`: 暫定値 0 ではなく空文字列（=該当なし）を既定値とし、コメントを更新。

### COMMUNICATE の Reference マッピング
- `SSTP/SSTPDispatcher.swift` / `ExternalServer/SstpRouter.swift`:
  Reference0=送信元ゴースト名（Sender ヘッダ）、Reference1=発言内容（Sentence ヘッダ）、
  Reference2+ = SSTP の ReferenceN へ 2 つシフト。旧実装は Reference0=Sentence のみで
  送信元ゴースト名が抜けていた（UKADOC OnCommunicate 非準拠）。

### SHIORI/2.x 互換フォールバックを削除
- `SSTP/BridgeToSHIORI.swift`: 3.0 形式ヘッダで 2.6 を名乗っていたフォールバックを撤去し
  SHIORI/3.0 一本化。2.x はバイナリ IPC で形式互換性がないため、旧実装は実 SHIORI/2.x には
  届かない無意味な分岐だった。

### SSTPスタックの一本化（P2-10 解消）
- `OurinExternalServer`（TCP/HTTP/XPC/分散通知の全経路）を `SSTPParser` + `SSTP/SSTPDispatcher`
  へ直結し、`ExternalServer/SstpRouter.swift` / `ExternalServer/SstpParser.swift`（SstpMessage）を削除。
  メトリクス記録（ServerMetrics）と解析失敗時の 400 応答は `OurinExternalServer.handleRaw` が担う。
- 一本化時の確認事項（旧チェックリスト）の結果:
  - **応答行形式**: `SSTPParser` は version を "SSTP/1.x" のまま保持し `SSTPResponse` がそのまま
    ステータス行に使うため二重プレフィクスは発生しない（旧 SstpParser の正規化は不要に）。
  - **Script ヘッダのバルーン再生配線**: `SSTPDispatcher` に追加。Event 無し SEND は SHIORI を
    介さず Script ヘッダを直接再生、Event 有りの SEND/COMMUNICATE/EXECUTE 等（NOTIFY 以外）は
    確定スクリプトを `EventBridge.playScriptOnGhostsResolving` で再生。
  - **nodescript の意味**: バルーン再生のみ抑止に修正（応答の Script ヘッダ・SHIORI 送出は維持。
    UKADOC spec_sstp「バルーンのSSTP表示を無効にする」）。SHIORI 応答側 ScriptOption の
    nodescript も同様の扱い。
  - **IfGhost の順序保持パーサ**: `SSTPRequest` を順序保持の `headerEntries` ベースに変更し、
    UKADOC「IfGhostによるスクリプト振り分け」を実装。IfGhost は直後の Script と出現順で対応付け、
    最初の IfGhost より前の Script はデフォルトスクリプト。「さくら」「エミリ」「えみりぃ」は
    デフォルトゴースト扱い。「\0側名,\1側名」書式は \0 側名で照合（\1 側名の照合は未対応）。
    旧実装の `IfGhost: 名前=スクリプト` 独自書式は廃止。重複 Option ヘッダもマージされる。
- セキュリティポリシー: 旧 SstpRouter の `securityLocalOnly`（既定 true）は
  `SSTPDispatcher.dispatch(request:securityLocalOnly:)` の引数として外部サーバ経路から伝搬。
  未指定（SSTPListener 等の内部経路）は従来どおり環境変数 `OURIN_SSTP_LOCAL_ONLY` に従う。
  判定は SecurityOrigin 優先（origin がローカル以外なら external 扱い）に統一し、
  メソッド種別によらず dispatch 冒頭で 420 を返す。
- 旧 SstpRouter との意図的な挙動差:
  - ゴースト不在時の 512 は「ReceiverGhostName 指定かつ GhostRegistry 空」の場合のみ
    （旧: NarRegistry のインストール済みゴースト全体で判定）。
  - SEND（Event 有り）で SHIORI 応答が空の場合は 503（旧: 200 + Script ヘッダ）。
    SHIORI 応答が空でなく Script も無い場合の Script ヘッダ保険は維持。
  - GIVE は SHIORI へルーティング（旧: 無条件 204）。
- テスト: `ExternalServerTests` を新経路（`OurinExternalServer.handleRaw`）向けに全面更新、
  `SSTPDispatcherTests` に Event 無し SEND / IfGhost 振り分け（一致・不一致・別名・ペア書式）/
  重複 Option のテストを追加。nodescript の期待値を「Script ヘッダ維持」に変更。

### NAR インストーラ
- `NarInstall/InstallTxtParser.swift`: `refresh` / `refreshundeletemask` /
  `balloon.directory` / `balloon.source.directory` を専用フィールドにパース。
- `NarInstall/LocalNarInstaller.swift`:
  - `accept` の誤用を解消（旧: target 存在 + accept 未指定で常に conflict 失敗 →
    新: type=ghost/balloon/plugin/package の再インストールを許容。type=shell のみ
    `accept` を親ゴースト名として検証ログを出す）。
  - `refresh,1` 指定時に設置先をクリアしてから展開。`refreshundeletemask` の各正規表現に
    合致するパスは残す（UKADOC 準拠）。
  - type=ghost で `balloon.directory` が設定されている場合、`<NAR>/balloon/<source>` か
    `<NAR>/<source>` のいずれかを balloon インストール先（`balloon/<directory>`）へ追加展開。
- `Web/WebNarInstaller.swift`: 同じ accept 誤用を撤去し、再インストール（更新）を許容。

### SERIKO / surfaces*.txt 読み込み
- `Animation/SerikoParser.swift`: `SurfaceDefinitionLoader` を追加し、シェルディレクトリ内の
  `surfaces***.txt` を全てファイル名順で読み込むようにした（UKADOC/SSP仕様）。
  `surfaces.txt` が存在しない場合でも `surfaces2.txt` 等を読み込む。
- `Ghost/GhostManager+Animation.swift`: 単体 `surfaces.txt` 読み込みを廃止し、上記ローダで結合した
  定義を既存のSERIKO/alias/surfacetableパーサへ渡すように変更。
- 既存互換維持のため、`alias.txt` / `surfacetable.txt` は `surfaces*.txt` 群の後に結合する。
- `SerikoParserTests`: ファイル名順読み込み、`surfaces.txt` 不在時の wildcard 読み込み、
  ディレクトリ/非対象ファイル除外を追加。

### FMO / Plugin macOS 制約と互換ビュー
- `FMO/FmoManager.swift`: `FmoCompatibilityView` / `FmoCompatibilityEntry` を追加し、
  `id.key\x01value\r\n` の FMO テキストを `id` ごとの field 辞書として読めるようにした。
  `EXECUTE GetFMO` と POSIX 共有メモリ本文は従来どおり同じ `buildSnapshot()` 出力を使う。
- `PluginHost/PluginRegistry.swift`: `PluginCompatibilityEntry` と `compatibilityEntries` を追加し、
  `path` / `compatibilityPath`（SSP 互換の元 DLL パス）、`executablePath`（macOS native 実体）、
  `packagePath`、`executionState`、`canDispatchRequests` を明示した。
- `Property/PluginPropertyProvider.swift`: `pluginlist.index(n).executionstate` と
  `pluginlist.index(n).candispatchrequests` を追加し、`executablepath` / `packagepath` でも plugin を
  名前付き参照できるようにした。
- `ContentView.swift`: 開発ツールの plugin 一覧を `compatibilityEntries` ベースに変更し、
  legacy Windows DLL を metadata-only として表示する一方、イベント送信対象にはしない状態を明確化。
- `docs/About_FMO_*.md` / `docs/SPEC_PLUGIN_2.0M_*.md`: Windows FileMapping / Win32 HWND /
  Windows DLL バイナリ互換は対象外であり、macOS では POSIX 共有メモリと Mach-O `.plugin` / `.bundle`
  を使うことを明文化。

## 未修正・残課題（次に直すべきもの）

### ~~SSTPスタックの二重実装（P2-10）~~
**解消済み**（上記「SSTPスタックの一本化」参照）。`OurinExternalServer` → `SSTPDispatcher` に
一本化し、SstpRouter / 旧 SstpParser を削除。チェックリスト4項目（応答行形式 / バルーン再生配線 /
nodescript / IfGhost 順序保持）はすべて SSTPDispatcher 側で対応済み。
残差異: IfGhost「\0側名,\1側名」書式の \1 側名照合は未対応（\0 側名のみで照合）。

### その他の未修正
- ~~見切れ/重なりの実判定~~: **修正済み**（上記参照）。
- ~~COMMUNICATE の Reference マッピング~~: **修正済み**（上記参照）。
- ~~FMO（P2-13）~~: **修正済み**。共有メモリ名を `/ourin_fmo` / `/ourin_fmo_mutex` に統一し、
  SSP 互換レコード形式（`id.key\x01value\r\n`）に移行。プロセス生存中は名前を保持し、
  外部プロセスからアタッチ可能。クラッシュ後の残留リソースは次回起動時に上書き再作成。
  SSTP EXECUTE GetFMO も同一の `buildSnapshot()` を使用。`hwnd` / `kerohwnd` / `hwndlist` は
  Win32 HWND ではなく、Ourin 実行中の安定・非ゼロなウィンドウ識別子。
  残差異: Wine sidecar 対応・Windows パス互換は対象外。
- ~~NAR（P2-14）~~: **一部修正済み**（balloon.directory / accept / refresh / refreshundeletemask）。
  残: type=shell の設置先パスが UKADOC では `ghost/<accept>/shell/<directory>/` のところ
  現状は `shell/<directory>/` 直下。本格対応は別タスクへ。
- ~~SERIKO surfaces*.txt 全読み込み~~: **修正済み**。`surfaces***.txt` をファイル名順に全て結合し、
  既存パーサへ渡す。残差異: SERIKO描画メソッド、collisionex、レンダリング完全一致は別タスク。
- ~~SHIORI/2.x 互換層~~: **削除済み**（上記参照）。
- Wine sidecar による Windows DLL SHIORI/SAORI 実行: 今回対象外。将来の実験枠として検討余地のみ残す。
- 既知の不安定テスト: `MoveCommandTests` が NSWindow のメインスレッド違反でテストプロセスごと
  クラッシュさせることがある（master でも再現する既存問題。別タスク化済み）。

## 検証状況

- `xcodebuild -scheme Ourin build`: 成功（CODE_SIGNING_ALLOWED=NO）。2026-06-12 追加修正後も再ビルド成功。
- `xcodebuild test`（MoveCommandTests 除外）: 全テストパス（0失敗）。新規テスト追加:
  ExternalServerTests（SSTP/SSTP プレフィクス、SEND Script、nodescript）、ReferenceOrderingTests。
  2026-06-12 追加修正分は ExternalServerTests / ReferenceOrderingTests を再実行し全パスを確認。
- yaya_core: CP932辞書 / BOM付きUTF-8辞書 / auto判定の実地ロード、RE_GETSTR/RE_GETPOS/RE_GETLEN/RE_OPTION、
  SHIORI応答ヘッダ引き渡しを JSON IPC 経由で動作確認済み。
