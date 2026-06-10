以下は 静的コード監査ベースの初回レポートです。UKADOC/YAYA/Crow は仕様根拠として参照対象にしましたが、ssp_2_8_27f.exe の Wine 実行・バイナリ解析は今回未実施です。xcodebuild test -scheme Ourin -destination platform=macOS -derivedDataPath /
  private/tmp/ourin-dd は署名証明書不足でビルド前に失敗しました。

  仕様根拠: SHIORI 3.0 (https://ssp.shillest.net/ukadoc/manual/spec_shiori3.html), SSTP (https://ssp.shillest.net/ukadoc/manual/dev_sstp.html), SakuraScript (https://ssp.shillest.net/ukadoc/manual/list_sakura_script.html), SHIORI Events
  (https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html), Property (https://ssp.shillest.net/ukadoc/manual/list_propertysystem.html), NAR/install (https://ssp.shillest.net/ukadoc/manual/dev_nar.html), descript/install
  (https://ssp.shillest.net/ukadoc/manual/descript_install.html), YAYA (http://usada.sakura.vg/contents/specification.html), Crow reference (http://crow.aqrs.jp/reference/all/), おおやしまDB (https://www.ooyashima.net/db/)

  ## A. SHIORI プロトコル

  ### 準拠度スコア: 6/10

  ### 実装済み（仕様準拠）

  - SHIORI/3.0 の基本リクエスト解析: GET/NOTIFY/TEACH、ID、Reference* を解析 → Ourin/USL/ShioriLoader.swift:196
  - SHIORI 2.x 風レスポンスへの一部変換: TEACH 204 -> 312 → Ourin/USL/ShioriLoader.swift:247

  ### 実装済み（要修正）

  - Charset 処理: yaya.txt の辞書 encoding を読んでいるが、YAYA load は常に utf-8
      - 根拠: SHIORI/YAYA 系ゴーストは Shift_JIS/CP932 辞書が一般的
      - 修正箇所: Ourin/USL/ShioriLoader.swift:73, yaya_core/src/DictionaryManager.cpp:78
      - 修正案: dic,...,encoding を YayaAdapter.load に渡し、C++ 側で CP932→UTF-8 変換する

  - Bundle/Dylib SHIORI の入出力が UTF-8 固定
      - 修正箇所: Ourin/USL/ShioriLoader.swift:401, Ourin/USL/ShioriLoader.swift:480
      - 修正案: Charset ヘッダーに従って request/response bytes を変換する

  ### 未実装（重要度: 高）

  - SHIORI 2.x 互換は最小限。2.x のイベント/レスポンス差分を吸収する層が薄い
  - エラー時 status text/header の網羅性が限定的

  ### 互換性リスク

  - Shift_JIS SHIORI/YAYA ゴーストでイベント名・辞書文字列・レスポンス本文が壊れる可能性が高い

  ## B. SSTP プロトコル

  ### 準拠度スコア: 5.5/10

  ### 実装済み（仕様準拠）

  - Dispatcher 側は SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE/INSTALL を分岐 → Ourin/SSTP/SSTPDispatcher.swift:35
  - TCP 9801 と HTTP エンドポイントの実装あり → Ourin/ExternalServer/SstpTcpServer.swift:29, Ourin/ExternalServer/SstpHttpServer.swift:29

  ### 実装済み（要修正）

  - ExternalServer のレスポンス行が SSTP/SSTP/1.x になる
      - 根拠: parse が version = "SSTP/1.4" を保持し、build 側で再度 SSTP/ を付ける
      - 修正箇所: Ourin/ExternalServer/SstpRouter.swift:150
      - 修正案: version は 1.4 のみ保持、または build 側を "\(version) ..." にする

  - nodescript が SHIORI dispatch 自体を省略する
      - 修正箇所: Ourin/ExternalServer/SstpRouter.swift:87
      - 修正案: イベントは送信し、Script 返却だけ抑止する

  ### 未実装（重要度: 高）

  - ExternalServer 経路の GIVE は SHIORI に届かず 204 固定 → Ourin/ExternalServer/SstpRouter.swift:115
  - Reference1..n の SSTP response 取り込みが限定的。Dispatcher は Reference0 のみ明示処理 → Ourin/SSTP/SSTPDispatcher.swift:658

  ### 互換性リスク

  - SSTP クライアントが status line 不正で応答を拒否する
  - SEND/GIVE/nodescript 利用アプリとの互換性が低い

  ## C. SakuraScript

  ### 準拠度スコア: 6.5/10

  ### 実装済み（仕様準拠）

  - \0/\1/\p[]、\s[]、\n、\w[]、\_w[]、\q[]、\![...] の主要パースあり → Ourin/SakuraScript/SakuraScriptEngine.swift:211
  - \![raise|notify|embed|timerraise|change|set|getproperty] など多数を実行側で処理 → Ourin/Ghost/GhostManager.swift:881

  ### 実装済み（要修正）

  - サーフェス overlay が surface<ID>.png 固定で、ゼロ埋め・PNA・scope 命名・alias を使わない
      - 修正箇所: Ourin/Ghost/GhostManager+Surface.swift:152
      - 修正案: base surface と同じ候補探索/PNA 合成を overlay にも適用する

  - スコープ切替時に他 scope のバルーンを閉じる動作は同時会話系ゴーストと衝突しやすい
      - 修正箇所: Ourin/Ghost/GhostManager.swift:2240

  ### 未実装（重要度: 中）

  - UKADOC の全 SakuraScript コマンドとの差分表は未生成。パーサは広いが完全性は未確認
  - \__t/\__q 等のメタタグは処理が限定的

  ### 互換性リスク

  - Seriko overlay/animation を多用するシェルで表示崩れ
  - 複数キャラ同時発話・選択肢・クリック待ちの SSP 差異

  ## D. SHIORIイベント

  ### 準拠度スコア: 5.5/10

  ### 実装済み（仕様準拠）

  - EventID に 400 件超の On* 定義あり → Ourin/SHIORIEvents/EventID.swift:1
  - OnBoot/OnFirstBoot/OnSecondBoot を起動時 GET として送る実装あり → Ourin/Ghost/GhostManager.swift:2331

  ### 実装済み（要修正）

  - EventBridge.start(enableAutoEvents: false) がデフォルトで、自動イベントが queue されるだけになる
      - 修正箇所: Ourin/SHIORIEvents/EventBridge.swift:40
      - 修正案: 通常起動時は auto events を有効化し、無効時も明示 dispatch 経路を分離する

  - Reference 順序が辞書キー文字列ソートで Reference10 が Reference2 より前になり得る
      - 修正箇所: Ourin/SHIORIEvents/EventBridge.swift:275

  ### 未実装（重要度: 中）

  - UKADOC イベント一覧との機械的カバレッジ表が未整備
  - 各イベントの Reference 個数・意味の仕様照合テストが不足

  ### 互換性リスク

  - 時刻/マウス/システムイベント依存ゴーストが無反応になる可能性

  ## E. プロパティシステム

  ### 準拠度スコア: 4.5/10

  ### 実装済み（仕様準拠）

  - %property[...] 展開、system/baseware/ghostlist/currentghost 等の provider あり → Ourin/Property/PropertyManager.swift:14

  ### 実装済み（要修正）

  - prefix 分割が最初の . 固定のため currentghost.balloon.* provider が到達不能
      - 修正箇所: Ourin/Property/PropertyManager.swift:82
      - 修正案: 最長 prefix match に変更する

  - CPU 使用率が常に 100% 近くになる計算
      - 修正箇所: Ourin/Property/PropertyManager.swift:282

  ### 未実装（重要度: 高）

  - sakura.*、kero.*、ghost.*、shell.* 名前空間の UKADOC 全量には届いていない
  - 読み取り専用/読み書きの仕様表と provider 実装の対応が不足

  ### 互換性リスク

  - メニュー/バルーン/シェル状態を property で参照するゴーストの UI が壊れる

  ## F. YAYA VM

  ### 準拠度スコア: 5/10

  ### 実装済み（仕様準拠）

  - Lexer/Parser/VM は関数、条件分岐、ループ、配列、正規表現、SAORI 系 builtins まで広く実装 → yaya_core/src/Lexer.cpp:36, yaya_core/src/Parser.cpp:86, yaya_core/src/VM.cpp:533

  ### 実装済み（要修正）

  - 辞書 encoding 引数を無視し、バイト列をそのまま読む
      - 修正箇所: yaya_core/src/DictionaryManager.cpp:78

  - 失敗辞書があっても load が true を返す
      - 修正箇所: yaya_core/src/DictionaryManager.cpp:136

  ### 未実装（重要度: 高）

  - RE_ASEARCH*、CHARSET*、ZEN2HAN/HAN2ZEN、SAVEVAR/RESTOREVAR、DICLOAD/DICUNLOAD、READFMO などが stub/TODO
  - EXECUTE が system() 直呼びで安全境界がない

  ### 互換性リスク

  - 多くの既存 YAYA 辞書が文字化けまたは builtins 未実装で停止する

  ## G. プラグインシステム

  ### 準拠度スコア: 4/10

  ### 実装済み（仕様準拠）

  - PLUGIN/2.0M の GET/NOTIFY frame 構築と bundle load/unload/request あり → Ourin/PluginHost/Plugin.swift:15, Ourin/PluginHost/PluginProtocol.swift:202

  ### 実装済み（要修正）

  - plugin request/response が UTF-8 固定
      - 修正箇所: Ourin/PluginHost/Plugin.swift:35

  - Reference header が文字列ソート
      - 修正箇所: Ourin/PluginHost/PluginProtocol.swift:224

  ### 未実装（重要度: 高）

  - Windows Plugin 2.0 DLL 互換は対象外。macOS bundle 独自拡張として明示が必要
  - SAORI 互換レイヤーは YAYA 内蔵寄りで、PluginHost 側仕様としては薄い

  ### 互換性リスク

  - 既存 SSP プラグイン資産は基本的にそのまま動かない

  ## H. NARパッケージ

  ### 準拠度スコア: 5/10

  ### 実装済み（仕様準拠）

  - .nar/.zip 判定、PK header 確認、install.txt parse、delete.txt 処理、更新 URL 抽出あり → Ourin/NarInstall/LocalNarInstaller.swift:39

  ### 実装済み（要修正）

  - shell install がグローバル Application Support/Ourin/shell/<directory> になっており、ghost 所属 shell の扱いが不正確
      - 修正箇所: Ourin/NarInstall/Paths.swift:30, Ourin/NarInstall/NarRegistry.swift:54

  - install.txt/delete.txt コメント処理がファイル間で不統一

  ### 未実装（重要度: 中）

  - 差分更新、更新ログ、accept 条件、既存 SSP の細かな上書き規則が不足

  ### 互換性リスク

  - シェル単体 NAR、追加バルーン、複合 NAR のインストール先が SSP とずれる

  ## I. FMO

  ### 準拠度スコア: 3/10

  ### 実装済み（仕様準拠）

  - POSIX 共有メモリ/名前付きセマフォで 64KB 領域を確保し、長さ + bytes を書く実装あり → Ourin/FMO/FmoSharedMemory.swift:24

  ### 実装済み（要修正）

  - 共有メモリを作成直後に shm_unlink しており、他プロセスが名前で open できない
      - 修正箇所: Ourin/FMO/FmoSharedMemory.swift:36, Ourin/FMO/FmoBridge.c:22
      - 修正案: プロセス生存中は名前を保持し、終了時 cleanup で unlink

  - isAnotherInstanceRunning の既定名が /ninix、通常 FMO 初期化は /ssp_fmo
      - 修正箇所: Ourin/FMO/FmoManager.swift:17

  ### 未実装（重要度: 高）

  - Windows SSP FMO の名前・key/value 形式・外部プロセス可視性との意味的互換が不足

  ### 互換性リスク

  - SSTP GET Version/FMO 参照系ツールや他ベースウェア連携が Ourin 起動中ゴーストを発見できない

  ## J. バルーン・シェル・リソース

  ### 準拠度スコア: 5.5/10

  ### 実装済み（仕様準拠）

  - ghost/balloon descript.txt を UTF-8/Shift_JIS fallback で parse → Ourin/Ghost/GhostConfiguration.swift:466, Ourin/Ghost/BalloonConfig.swift:73
  - surfaces.txt animation/collision/point/alias の一部処理あり → Ourin/Animation/AnimationEngine.swift:164, Ourin/Animation/SerikoParser.swift:121

  ### 実装済み（要修正）

  - BalloonView が 400x150 固定で、バルーン画像サイズ/validrect/clip に追従しない
      - 修正箇所: Ourin/Ghost/BalloonView.swift:13

  - balloon image は balloon<type><index>.png 固定で、仕様上の派生名や追加リソース探索が弱い
      - 修正箇所: Ourin/Ghost/BalloonConfig.swift:187

  ### 未実装（重要度: 中）

  - surfacetable.txt の体系的処理が見当たらない
  - descript の全キー、surfaces.txt の全 Seriko 構文、バルーンのスケール/配置規則は未完全

  ### 互換性リスク

  - 実在バルーンでテキスト位置・サイズ・矢印・マーカーが SSP とずれる

  ## 最終サマリー

  全体準拠度スコア: 約 4.9/10
  重み: SHIORI と SakuraScript を 2 倍、他カテゴリ 1 倍。

  クリティカルな互換性問題 Top 10

  1. YAYA/SHIORI の Shift_JIS/CP932 変換不足
  2. ExternalServer SSTP response line が SSTP/SSTP/1.x
  3. FMO を作成直後に unlink し外部参照不能
  4. YAYA builtins の stub が多い
  5. nodescript がイベント dispatch まで止める
  6. GIVE が ExternalServer 経路で SHIORI に届かない
  7. Property prefix 解決で currentghost.balloon.* が死んでいる
  8. SHIORI/Plugin/Event Reference の文字列ソート
  9. Seriko overlay の surface 探索が base surface と違う
  10. NAR shell install 先が SSP の ghost 所属 shell とずれる

  推奨修正優先順位

  1. 文字コード基盤: SHIORI/YAYA/SSTP/Plugin の CP932 対応を一本化
  2. SSTP ExternalServer: status line、nodescript、GIVE、Reference handling を修正
  3. YAYA VM: stub builtins のうち CHARSET*、DICLOAD、SAVEVAR、RE_ASEARCH* を優先
  4. FMO: 名前付き共有メモリを外部プロセスから見える形に修正
  5. Property: 最長 prefix match と UKADOC 名前空間表を実装
  6. Seriko/surface: overlay 画像探索、PNA、alias、surfacetable を統合
  7. NAR: shell/balloon/plugin の install target と差分更新を SSP 互換に寄せる

  SSPとの差異

  - 今回は SSP バイナリ実行による実測は未実施です。コード上で明確な差異は、FMO の可視性、SSTP response line、Shift_JIS 辞書処理、Plugin の macOS bundle 固有化、NAR shell 配置です。
  - テストは署名証明書 "Mac Development" 不足で実行完了していません。
