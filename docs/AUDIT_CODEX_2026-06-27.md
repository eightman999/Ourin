# Ourin 互換性監査レポート（Codex, 2026-06-27）

## 監査範囲

- 対象リポジトリ: `/Users/eightman/Desktop/software_develop/Ourin`
- 監査方法: 静的コード監査。UKADOC / Crow / YAYA資料と実装を照合。
- SSP 2.8.27f: `/Users/eightman/Downloads/ssp_2_8_27f.exe` は存在確認済み。ただし Wine が未導入のため実行観察は未実施。
- 現在のドキュメント数: `docs/*.md` は 99 件。
- 現在のテストファイル数: `OurinTests/` 直下は 38 ファイル。
- 追記: `surfaces*.txt` 全読み込み不足は 2026-06-27 に修正済み。詳細は `docs/COMPAT_FIXES_2026-06.md` を参照。

## 仕様根拠

- [UKADOC SHIORI/3.0](https://ssp.shillest.net/ukadoc/manual/spec_shiori3.html)
- [UKADOC SSTP](https://ssp.shillest.net/ukadoc/manual/spec_sstp.html)
- [UKADOC SakuraScript](https://ssp.shillest.net/ukadoc/manual/list_sakura_script.html)
- [UKADOC SHIORIイベント](https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html)
- [UKADOC プロパティシステム](https://ssp.shillest.net/ukadoc/manual/list_propertysystem.html)
- [UKADOC install.txt](https://ssp.shillest.net/ukadoc/manual/descript_install.html)
- [UKADOC NAR](https://ssp.shillest.net/ukadoc/manual/dev_nar.html)
- [UKADOC Plugin](https://ssp.shillest.net/ukadoc/manual/spec_plugin.html)
- [UKADOC Balloon](https://ssp.shillest.net/ukadoc/manual/descript_balloon.html)
- [UKADOC surfaces.txt](https://ssp.shillest.net/ukadoc/manual/descript_shell_surfaces.html)
- [Crow reference](http://crow.aqrs.jp/reference/all/)
- [おおやしまデータベース](https://www.ooyashima.net/db/)

## A. SHIORI プロトコル

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）

- SHIORI/3.0 GET/NOTIFY フレーム生成、`Charset` / `Sender` / `SenderType` / `SecurityLevel` / `ReferenceN` の基本ヘッダー生成。根拠: UKADOC SHIORI/3.0。対応: `Ourin/SHIORIEvents/EventBridge.swift:526`, `Ourin/SSTP/SSTPDispatcher.swift:614`
- YAYA経路の `GET` / `NOTIFY` / `TEACH` 解析と `TEACH` 互換マッピング。対応: `Ourin/USL/ShioriLoader.swift:413`, `Ourin/USL/ShioriLoader.swift:464`
- Bundle/Dylib SHIORI要求・応答の `Charset` 検出と変換。対応: `Ourin/USL/ShioriLoader.swift:623`

### 実装済み（要修正）

- `BridgeToSHIORI` 経由の native SHIORI host は常に `GET SHIORI/3.0` を生成する。NOTIFYイベントは仕様上 `NOTIFY SHIORI/3.0` で送る必要がある。
  - 根拠: UKADOC SHIORI method仕様
  - 修正箇所: `Ourin/SSTP/BridgeToSHIORI.swift:129`
  - 修正案: `ShioriHost.request` に method 引数を追加し、`EventBridge.sendNotify` / SSTP NOTIFY 経路から `NOTIFY` を伝播する。
- SSTP側でSHIORI応答をマップする際、`Reference0` だけを明示保持し、`Reference1+` が落ちる。
  - 修正箇所: `Ourin/SSTP/SSTPDispatcher.swift:671`
  - 修正案: `Reference(\d+)` を全て数値順で保持し、SSTP応答へ反映する。

### 未実装（重要度: 高）

- SHIORI 2.x ABI互換。現在は2.x形式を3.0モデルへ寄せる一部処理に留まり、旧SHIORIモジュールの直接互換はない。

### 互換性リスク

- NOTIFYがGETとして届く経路では、ゴースト側が「返答してよいイベント」と誤判定し、不要発話や副作用が出る。

## B. SSTP プロトコル

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）

- `SEND` / `NOTIFY` / `COMMUNICATE` / `EXECUTE` / `GIVE` / `INSTALL` のルーティング。対応: `Ourin/SSTP/SSTPDispatcher.swift:12`
- raw SSTPパース、CRLFヘッダー処理、`IfGhost` / `Script` / `Option` の基本処理。対応: `Ourin/SSTP/SSTPParser.swift`, `Ourin/SSTP/SSTPRequest.swift`
- HTTP `/api/sstp/v1` と raw TCP の入口、HTTP body読み取り。対応: `Ourin/ExternalServer/SstpHttpServer.swift:49`, `Ourin/ExternalServer/SstpTcpServer.swift:48`

### 実装済み（要修正）

- TCP / HTTP listener は `host` 引数をログに出すだけで bind には使っていない。local専用のつもりでも全IFで待ち受ける可能性がある。
  - 根拠: SSTP標準の基本は localhost:9801
  - 修正箇所: `Ourin/ExternalServer/SstpTcpServer.swift:29`, `Ourin/ExternalServer/SstpHttpServer.swift:31`
  - 修正案: `NWListener` を host 指定で作るか、外部許可時だけ全IF bindにする。
- raw TCP経路はヘッダー終端までのデータだけを `onRequest` に渡す。SSTP body利用ケースがある場合に破棄される。
  - 修正箇所: `Ourin/ExternalServer/SstpTcpServer.swift:54`

### 未実装（重要度: 中）

- EXECUTE拡張の応答形式は実装されているが、SSPのデファクト形式との照合テストが不足。

### 互換性リスク

- 外部SSTPクライアントやHTTP Originつきクライアントで、SSPより強い拒否・別応答になる可能性がある。

## C. SakuraScript

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）

- `\0` / `\1`, `\s[]`, `\n`, `\w[]`, `\_w[]`, `\q[]`, `\![...]`, `\__*` 系の広範な字句解析。対応: `Ourin/SakuraScript/SakuraScriptEngine.swift:65`
- `\![raise,notify,embed,timerraise,change,set,getproperty,anim,move,resize,...]` の多くを実行側で処理。対応: `Ourin/Ghost/GhostManager.swift:1182`
- SERIKO定義の解析とSakuraScriptアニメーション制御の接続。対応: `Ourin/Animation/SerikoParser.swift:112`, `Ourin/Ghost/GhostManager+Animation.swift:119`
- `surfaces***.txt` の全読み込みとファイル名順結合。対応: `Ourin/Animation/SerikoParser.swift`, `Ourin/Ghost/GhostManager+Animation.swift`

### 実装済み（要修正）

- スコープ切替時に他スコープのバルーンを消す処理があり、SSPの複数スコープ同時表示と差が出る可能性がある。
  - 修正箇所: `Ourin/Ghost/GhostManager.swift:2576`
  - 修正案: scopeごとの表示寿命を分離し、明示クリア命令でのみ閉じる。
- SERIKO描画メソッド、collisionex、レンダリング完全一致は引き続き未検証。
  - 根拠: UKADOC surfaces.txt
  - 修正箇所: `Ourin/Animation/SerikoParser.swift`, `Ourin/Ghost/GhostManager+Animation.swift`

### 未実装（重要度: 高）

- UKADOC SakuraScript一覧との差分を機械生成する網羅テスト。パーサ・実行とも広いが、細部互換は未検証。

### 互換性リスク

- 演出・選択肢・入力・SERIKOを多用するゴーストで、SSPと表示順や待機挙動がずれる。

## D. SHIORIイベント

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）

- `EventID` は広範な `On*` イベントを定義。対応: `Ourin/SHIORIEvents/EventID.swift:1`
- 起動・終了・サーフェス・時刻・入力・D&D系イベントの発火経路がある。対応: `Ourin/Ghost/GhostManager.swift:631`, `Ourin/SHIORIEvents/TimerEmitter.swift:50`, `Ourin/SHIORIEvents/InputMonitor.swift:35`, `Ourin/SHIORIEvents/DragDropView.swift:111`

### 実装済み（要修正）

- `EventBridge.start(enableAutoEvents:)` の既定が `false`。通常起動経路で有効化される箇所はあるが、経路により自動イベントがqueueのみになるリスクが残る。
  - 修正箇所: `Ourin/SHIORIEvents/EventBridge.swift:65`, `Ourin/Ghost/GhostManager.swift:2714`
  - 修正案: 実ゴーストロード完了時の標準イベント有効化を一箇所に集約し、テスト/開発時だけ明示無効にする。
- イベントごとのReference個数・順序は完全な表駆動ではない。

### 未実装（重要度: 中）

- UKADOCイベント一覧に対するReference網羅テスト。

### 互換性リスク

- 時刻・マウス・通信イベントを条件分岐に使うYAYA辞書で、Reference差異が発話分岐の不一致になる。

## E. プロパティシステム

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）

- `system`, `baseware`, `ghostlist`, `activeghostlist`, `currentghost`, `balloonlist`, `currentghost.balloon`, `pluginlist` 等のprovider。対応: `Ourin/Property/PropertyManager.swift:16`
- `currentghost.balloon.*` は最長prefix解決で到達可能。対応: `Ourin/Property/PropertyManager.swift:113`

### 実装済み（要修正）

- `sakura.*`, `kero.*`, `ghost.*`, `shell.*` の標準名前空間エイリアスが不足。
  - 根拠: UKADOC プロパティシステム
  - 修正箇所: `Ourin/Property/PropertyManager.swift:16`, `Ourin/Property/GhostPropertyProvider.swift`
  - 修正案: `currentghost.scope(0)` を `sakura.*`、scope(1)を `kero.*` に写す互換providerを追加する。

### 未実装（重要度: 中）

- 読み取り専用/読み書きプロパティ仕様表との完全照合。

### 互換性リスク

- プロパティ参照でシェル/バルーン/スコープ状態を制御するゴーストのUIが崩れる。

## F. YAYA言語VM

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）

- C++ helperとして辞書ロード、関数、条件分岐、ループ、配列、正規表現、多数のbuiltinを実装。対応: `yaya_core/IMPLEMENTATION_STATUS.md`, `yaya_core/src/VM.cpp`
- `dic`, per-dic encoding, `include`, `dicdir`, `_loading_order.txt`, CP932変換を実装。対応: `Ourin/USL/ShioriLoader.swift:187`, `yaya_core/IMPLEMENTATION_STATUS.md`

### 実装済み（要修正）

- `&` のby-reference、standalone `when`、配列要素代入の一部が部分実装。
  - 根拠: `yaya_core/IMPLEMENTATION_STATUS.md`
  - 修正箇所: `yaya_core/src/Parser.cpp`, `yaya_core/src/VM.cpp`
- `MKDIR` / `RMDIR` / `FENUM` と一部Windows依存系builtinがstub。
  - 修正箇所: `yaya_core/src/VM.cpp:2724`

### 未実装（重要度: 高）

- 実在YAYAゴーストの回帰テストセット。Emily4は読み込み基準があるが、発話結果の完全一致までは未保証。

### 互換性リスク

- 高度なYAYA辞書で、ロードは成功しても分岐・副作用・ファイル操作がSSP/YAYA本家と一致しない。

## G. プラグインシステム

### 準拠度スコア: 5.5/10

### 実装済み（仕様準拠）

- `PLUGIN/2.0M` GET/NOTIFYフレーム、ID/Charset/Sender/SecurityLevel/ReferenceN。対応: `Ourin/PluginHost/PluginProtocol.swift`
- macOS `.plugin` / `.bundle` の load/request/unload lifecycle とイベント配送。対応: `Ourin/PluginHost/Plugin.swift`, `Ourin/PluginEvent/PluginEventDispatcher.swift`
- Windows DLL 由来 plugin を metadata-only として一覧・プロパティ互換ビューに出し、native 実行可能 plugin と区別。対応: `Ourin/PluginHost/PluginRegistry.swift`

### 実装済み（プラットフォーム差異を明文化済み）

- Windows Plugin 2.0 DLL資産はmetadata-only。`path` / `compatibilityPath` は元 DLL パス、`executablePath` は native 実体、`canDispatchRequests=false` は実行不可を示す。
  - 根拠: macOS は Win32 DLL/PE を直接ロードできないため、Mach-O `.plugin` / `.bundle` への移植が必要。
  - 対応: `docs/SPEC_PLUGIN_2.0M_ja-jp.md`, `Ourin/PluginHost/PluginRegistry.swift`

### 未実装（重要度: 中）

- SSPプラグインのバイナリ互換。これはmacOSでは主にプラットフォーム差異。

### 互換性リスク

- SSP用プラグイン前提のゴースト機能は、対応 `.plugin` / `.bundle` へ移植されていない場合、そのままでは動かない。

## H. NARパッケージ

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）

- NAR/ZIP判定、install.txt解析、基本種別の配置、refresh/delete処理。対応: `Ourin/NarInstall/LocalNarInstaller.swift:45`, `Ourin/NarInstall/Paths.swift`
- charset宣言、UTF-8/Shift_JIS fallback、zip slip対策。対応: `Ourin/NarInstall/InstallTxtParser.swift:21`, `Ourin/NarInstall/ZipUtil.swift`

### 実装済み（要修正）

- `refreshundeletemask` はUKADOCではコロン区切りだが、実装はカンマ分割で、コメントも「カンマ区切り」と誤記している。
  - 根拠: UKADOC install.txt `refreshundeletemask,ファイル名1:ファイル名2...`
  - 修正箇所: `Ourin/NarInstall/InstallTxtParser.swift:12`, `Ourin/NarInstall/InstallTxtParser.swift:102`
  - 修正案: `:` 区切りを正とし、互換のためカンマも寛容に受ける。
- `language`, `calendar skin`, `calendar plugin`, `calendar` 旧互換などのinstall種別が不足。

### 未実装（重要度: 中）

- 同時インストールの `*.directory`, `*.source.directory`, `*.refresh`, `*.refreshundeletemask` の完全処理。

### 互換性リスク

- 複合NARや更新NARで、追加バルーン/カレンダー/言語パック、refresh保護の挙動がSSPとずれる。

## I. FMO

### 準拠度スコア: 6.5/10

### 実装済み（仕様準拠）

- POSIX shared memory + named semaphoreで共有状態を公開。対応: `Ourin/FMO/FmoSharedMemory.swift`, `Ourin/FMO/FmoMutex.swift`
- SSP風の `id.key SOH value CRLF` レコードを生成し、`GetFMO` と共有メモリで共通利用。対応: `Ourin/FMO/FmoManager.swift:91`
- `FmoCompatibilityView` で FMO テキストを構造化し、macOS 実体差分に依存しない診断・テスト入口を追加。対応: `Ourin/FMO/FmoManager.swift`

### 実装済み（プラットフォーム差異を明文化済み）

- 共有メモリ名は `/ourin_fmo` / `/ourin_fmo_mutex` で、Windows/SSPのFMOグローバル名やHWND値との直接互換はない。
  - 根拠: macOS は Win32 FileMapping/HWND を提供しないため、POSIX共有メモリと Ourin ウィンドウ識別子へ写像する。
  - 対応: `docs/About_FMO_ja-jp.md`, `docs/About_FMO_en-us.md`, `Ourin/FMO/FmoManager.swift`

### 未実装（重要度: 低）

- Windows HWND互換。これはプラットフォーム差異として扱うべき。

### 互換性リスク

- FMOをWin32 APIで直接読むWindows向け外部ツールとは相互運用できない。macOS外部ツールは `EXECUTE GetFMO` または POSIX 共有メモリを使う。

## J. バルーン・シェル・リソース

### 準拠度スコア: 5.5/10

### 実装済み（仕様準拠）

- balloon `descript.txt` のcharset fallback、validrect/font/margin/arrow等のparse。対応: `Ourin/Ghost/BalloonConfig.swift`, `Ourin/Balloon/DescriptorLoader.swift`
- surface画像、PNA、alias、SERIKO定義の部分対応。対応: `Ourin/Ghost/GhostManager+Animation.swift:119`, `Ourin/Animation/SerikoParser.swift`

### 実装済み（要修正）

- `surfaces*.txt` 全読み込みとSSP順序規則は修正済み。残課題はSERIKO描画メソッド、collisionex、レンダリング完全一致。
  - 修正箇所: `Ourin/Animation/SerikoParser.swift`, `Ourin/Ghost/GhostManager+Animation.swift`
- collisionの多角形/円形hit test、balloon右側表示、wordwrap/alignmentの細部が未検証。

### 未実装（重要度: 中）

- shell/balloon実物セットに対するレンダリング差分テスト。

### 互換性リスク

- 表情、当たり判定、SERIKOアニメーション、バルーン配置がSSPと違って見える。

## 最終サマリー

### 全体準拠度スコア

**6.0/10**

SHIORI と SakuraScript を重み2、その他カテゴリを重み1として加重平均した。

### クリティカルな互換性問題 Top 10

1. `BridgeToSHIORI` の NOTIFY→GET化
2. SHIORI 2.x ABI互換不足
3. SSTP応答で `Reference1+` が落ちる
4. YAYA VMのby-reference / standalone `when` / stub builtin
5. SakuraScriptのスコープ表示寿命と細部コマンド差分
6. SERIKO描画メソッド・collisionex・レンダリング完全一致の不足
7. SHIORIイベントReferenceの表駆動テスト不足
8. プロパティ標準alias不足
9. NAR `refreshundeletemask` 区切り誤りと複合install不足
10. FMO/PluginのWindows資産との直接互換なし（制約は文書化済み、実行互換は別設計）

### 推奨修正優先順位

1. SHIORI method伝播とSSTP `ReferenceN`応答を修正する。
2. SSTP TCP/HTTP bind範囲とraw TCP body処理を修正する。
3. NAR `refreshundeletemask` とinstall種別をUKADOC準拠にする。
4. SERIKO描画差分とSakuraScript高頻度コマンドの差分テストを追加する。
5. YAYA by-reference、standalone `when`、stub builtinを実ゴースト優先で埋める。
6. プロパティ `sakura.*` / `kero.*` / `ghost.*` / `shell.*` aliasを追加する。
7. イベントReference仕様を表駆動化し、UKADOCイベント一覧とのカバレッジを生成する。
8. FMO/Pluginの macOS 互換ビューを保守し、必要ならWine/外部連携を別設計にする。

### SSPとの主要な仕様解釈の差異

- NOTIFYの返値扱いとGET/NOTIFY method伝播。
- FMOの共有メモリ名・HWND意味論。
- Windows Plugin DLL互換をmacOS native pluginに置換している点。
- SERIKO描画メソッド、collisionex、shell/balloonレンダリング完全一致。
- NAR複合installおよびrefresh保護の細部。
