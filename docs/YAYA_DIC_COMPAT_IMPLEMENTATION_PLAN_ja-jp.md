# YAYA辞書互換性実装計画

## 目的

本ドキュメントは、Ourinの `yaya_core` 辞書サポートを実践的なYAYA/UKADOC互換性の目標と比較します。元々は実装計画でしたが、現在はPhase 0-10の完了状況と残存する制限事項も記録しています。

目標は単に `.dic` ファイルをより多く解析することではなく、フルスタックを通じて実際のYAYAゴーストが正しく動作することです:

- `yaya.txt` と辞書ロード規則
- YAYA言語構文と実行時セマンティクス
- YAYAシステム辞書（`yaya_base`）期待値
- SHIORI/3.0 リクエスト・応答互換性
- Ourin Swift統合とホストコールバック

## 参照スコープ

### 主要参照

- UKADOCトップページ: <https://ssp.shillest.net/ukadoc/manual/>
- UKADOC SHIORI/3.0: <https://ssp.shillest.net/ukadoc/manual/spec_shiori3.html>
- UKADOCイベント一覧: <https://ssp.shillest.net/ukadoc/manual/list_shiori_event.html>
- YAYA言語/SHIORI参照: <http://usada.sakura.vg/contents/shiori.html>
- YAYAシステム辞書リポジトリ: <https://github.com/YAYA-shiori/yaya-dic>
- yaya-dic システム辞書マニュアル: <https://github.com/YAYA-shiori/yaya-dic/blob/master/docs/manual_yaya_base.md>

### ローカル参照

- `yaya_core/src/Lexer.*`
- `yaya_core/src/Parser.*`
- `yaya_core/src/AST.hpp`
- `yaya_core/src/VM.*`
- `yaya_core/src/DictionaryManager.*`
- `yaya_core/src/YayaCore.*`
- `Ourin/USL/ShioriLoader.swift`
- `Ourin/Ghost/GhostManager.swift`
- `Ourin/Yaya/YayaAdapter.swift`
- `yaya_core/PARSER_PROGRESS_UPDATE.md`
- `yaya_core/IMPLEMENTATION_STATUS.md`
- `yaya_core/FUNCTION_REFERENCE.md`

## 現在の状態サマリー

本ドキュメントはYAYA辞書互換性の実装計画として開始されました。
Phase 0-10は既に実装され、フォーカスした回帰テストに対して検証されています。以下のセクションは、元のプリワーク ギャップ スナップショットではなく、最新監査時点での実装状況を記録しています。

`yaya_core` は以下の重要な基本機能をサポート:

- ブレース本体の関数定義
- 代入と複合代入
- `if` / `elseif` / `else`
- `while`, `for`, `foreach`
- `switch`, `case`, `when` の解析/実行時パス
- 文字列、整数、配列値
- `SHIORI3FW.Status` のような点付き識別子
- `reference[index]` と `_argv`
- 日本語名を含むUTF-8識別子
- `_in_` と `!_in_`
- 多くのYAYA組み込み関数
- JSON行IPC（Swift通信）
- SAORI/プラグイン操作の部分的なホストコールバック サポート
- `yaya.txt` 解析（`dic`, `include`, `dicdir`, `_loading_order.txt`, グローバル/各辞書文字セット、重複抑制）

このプロジェクトはWindowsの `yaya-shiori` のバイト単位クローンではありません。既知の制限事項は `yaya_core/IMPLEMENTATION_STATUS.md` で追跡されています。

## 互換性ギャップ マトリックス

| 領域 | 期待される動作 | 現在の動作 | 残存メモ |
| --- | --- | --- | --- |
| `yaya.txt` ロード | `dic`, `include`, `dicdir`, `_loading_order.txt`, 文字セットヒント、順序付きロード対応 | SwiftコレクターでJSON IPC エントリ構造化実装 | `_loading_order.txt` は実YAYA-dic `dic`/`dicif` 行とレガシー形式をサポート |
| システム辞書 | `dicdir, yaya_base` は意図された順序でyaya-dicをロード | 欠落 `dicif` スキップで実装・テスト済み | Emily4 スモーク結果: 33/33 辞書ロード |
| 各辞書符号化 | ファイルレベル文字セットは異なる可能性があり尊重される | `dic_entries` 経由でエンドツーエンド実装 | CP932/UTF-8 混在辞書検証 |
| パーサー信頼性 | 実辞書はタイムアウトなく解析 | ブロックリテラル、ラベル、`switch`, `case/when`, 後置 `--` あいまいさで改善 | 既知のパーサー偏差は実装ステータスに残存 |
| `case/when` セマンティクス | マッチする `when` 本体のみ実行；`others/default` フォールバック動作 | 専用AST/実行時実装 | 最初マッチングと非選択ブランチの副作用なし検証 |
| `switch` セマンティクス | 実YAYA switch/ブロックリテラル慣用法対応 | `--` 区切りとネストブロック形式をインデックス選択で実装 | インデックス セマンティクスはサポートYAYA慣用法に意図的 |
| ブロックリテラル | `{ ... -- ... }` とネスト/ラベル付きブロック対応 | 配列リテラルで実装；可変要素は後置 `--` による変異もはやなし | `++` は後置インクリメントのまま（区切り文字ではない） |
| 関数宣言 | `array`, `sequential`, `nonoverload`, `when`, 宣言メタデータ処理 | 複数宣言レジストリとメタデータAPI実装 | `nonoverload` は最新定義が優先；スタンドアロン `when` ディスパッチ制限あり |
| 動的辞書 | `DICLOAD`, `DICUNLOAD`, `UNDEFFUNC`, 実行時辞書追加動作 | ソース所有権付き実装 | 相対パスは `ghost/master` 下でサンドボックス化 |
| 変数永続化 | `SAVEVAR`, `RESTOREVAR`, 設定、一時変数管理 | JSON型保持と `REGISTERTEMPVAR` 除外で実装 | パスはサンドボックス化；辞書値は `Value` サポートに依存 |
| SAORI | `FUNCTIONLOAD`, `FUNCTIONEX`, `SAORI` はホストで動作 | Swift `SaoriManager` IPC経由実装；`Result` と `Value*` 解析 | `valueex` は暗黙変数ではなく組み込み公開 |
| SHIORI/3.0 ヘッダー | リクエスト/応答ヘッダーはUKADOC期待値に一致 | 大文字小文字無視重複排除と `ref` オーバーレイで実装 | ヘッダーカバレッジはフィクスチャテストとともに拡大予定 |
| 正規表現・ユーティリティ関数 | yaya-dic関数は実YAYAのように動作 | `RE_ASEARCH`, `RE_ASEARCHEX`, `ISEVALUABLE`, グローバル定義、文字セットID含む高インパクト項目実装 | Windows専用/ディレクトリシムは互換性スタブのまま |

## 実装計画

### Phase 0: ドキュメントとテスト ベースライン

動作を変更する前に、明確で実行可能な互換性ベースラインを作成。

タスク:

- `yaya_core/IMPLEMENTATION_STATUS.md` を更新して以下を区別:
  - 実装済み
  - 部分的
  - 互換性スタブ
  - 非対応
- `yaya_core/FUNCTION_REFERENCE.md` をスタブ状態がソースコードに一致するよう更新
- パーサー/ロード互換性フィクスチャを追加:
  - シンプル `dic`
  - 再帰的 `include`
  - `dicdir`
  - `_loading_order.txt`
  - `case/when`
  - `switch`
  - `--` 付きブロックリテラル
  - ネストラベル付きブロック
- Emily4/yaya-dic スモークテスト ハーネス追加（以下報告）:
  - ロード ファイル数
  - 失敗ファイル
  - 解析時間
  - 代表イベントのリクエスト結果

受け入れ基準:

- 開発者が1つのコマンドを実行すると現在のパーサー/実行時互換性が表示
- ドキュメントはスタブ機能の完全サポートをもはや主張しない

### Phase 1: `yaya.txt`, `dicdir`, ロード順序

Ourinが標準YAYAレイアウトを直接ロード。

タスク:

- SwiftのparseYayaConfigFile拡張:
  - `dicdir, path` 認識
  - オプションコメント・空白
  - 各 `dicdir` 内の `_loading_order.txt`
- `dicdir` エントリを `ghost/master` 相対で解決
- `_loading_order.txt` が存在する場合:
  - ディレクトリの宣言/デフォルト文字セットで読み込み
  - 空白行・コメント無視
  - リスト順で有効エントリのみロード
- `_loading_order.txt` が存在しない場合:
  - 確定的辞書順で `.dic` ファイルをロード
- 構造化データとして辞書ロードエントリを表現:
  - 相対パス
  - オプション符号化
  - ソース設定ファイル
  - ソース行
- JSON IPC `load` コマンドを拡張し構造化辞書メタデータを渡す（遷移期間は現在の文字列リスト互換性維持）
- 安定した最初出現の重複抑制
- `include` のサイクル防止を維持

受け入れ基準:

- 以下を持つゴースト:

```txt
dicdir, yaya_base
```

yaya-dicの意図された辞書セットを意図された順序でロード。

- `dic, file.dic` のみを使用する既存ゴーストは変更なくロード続行。

### Phase 2: 符号化モデル

辞書デコードを予測可能かつShift_JIS/CP932ヘビーゴースト互換に。

タスク:

- `yaya.txt`, インクルード設定ファイル、各辞書エントリから発見した文字セット宣言を保持
- 各辞書符号化ヒントを `DictionaryManager` に渡す
- 現在のUTF-8 BOMと有効UTF-8自動検出セーフガード保持
- `_loading_order.txt` を同じ文字セット戦略でデコード
- 以下テスト追加:
  - BOM付きUTF-8
  - BOM無しUTF-8
  - CP932辞書
  - UTF-8辞書を含むCP932設定
  - 有効UTF-8コンテンツの不正文字セット宣言

受け入れ基準:

- 日本語識別子・文字列付きCP932 YAYA辞書が文字化けなくロード
- UTF-8辞書はCP932として誤変換されない

### Phase 3: パーサー文法完成

既知Emily4パーサー ギャップを閉じ、許容的だが誤った解析を削除。

タスク:

- 専用ASTノード導入:
  - `CaseNode`
  - `WhenClauseNode`
  - YAYA特有セマンティクス付き `SwitchNode`
  - `BlockLiteralNode`
  - `LabeledBlockNode`
  - `ArrayLiteralNode` / タプルリテラル
- `case expr { when a,b { ... } others { ... } }` 実装
- スタンドアロン `when` を文法が実際に許可する場所のみ実装
- ブロックリテラル（`--` 区切り）実装
- ネストラベル付きブロック形式実装:

```yaya
{{LABEL
    ...
}}LABEL
```

- `switch` 解析を見直し、実YAYAディクショナリー慣用法をサポート
- 重要トークンをサイレントにスキップして不正実行時動作を生成するパーサー「成功」パスを削除
- 進行保証とパーサータイムアウト保護を維持

受け入れ基準:

- `yaya_core/PARSER_PROGRESS_UPDATE.md` に失敗として記載されたすべてのファイルがタイムアウトなく解析
- `case/when`, `switch`, `--` ブロックリテラル、ラベル付きブロック用パーサー テストがAST形状をアサート

### Phase 4: 高度な構文の実行時セマンティクス

新しく解析された構文が正しく動作。

タスク:

- `case/when` 実行（case式を1回評価して最初のマッチング句のみ実行）
- `others` / `default` フォールバック実装
- ブロックリテラル評価規則実装
- 配列リテラル・タプル動作を現在の `Value` 配列と一貫性を持って実装
- 配列要素代入と複合代入修正:
  - `arr[i] = value`
  - `arr[i] += value`
  - `arr[i] ,= value`
- 非選択 `when` 本体が実行されないように副作用動作テスト追加

受け入れ基準:

- `case/when` 実行時動作はYAYA例とEmily4期待値に一致
- 配列要素代入は対象要素のみ変異

### Phase 5: 関数宣言・ディスパッチ セマンティクス

YAYA関数宣言メタデータをより忠実にサポート。

タスク:

- シンプル `functions_[name] = func` レジストリを複数宣言をホールドできるレジストリで置換
- 追跡:
  - ソース辞書
  - 宣言順序
  - 関数型
  - 属性
  - 有効化/未定義状態
- 以下セマンティクス完成:
  - `array`
  - `sequential`
  - `nonoverload`
  - `when`
- 実装または完成:
  - `FUNCDECL_READ`
  - `FUNCDECL_WRITE`
  - `FUNCDECL_ERASE`
  - `GETFUNCINFO`
  - `GETFUNCLIST`
  - `ISFUNC`
  - `UNDEFFUNC`

受け入れ基準:

- 複数同名関数は宣言メタデータに従ってディスパッチ
- シーケンシャル関数は正しい順序で連結
- 配列関数は文字列ロスなく配列値を返す

実装成果:

- ソースID、宣言順序、有効状態、修飾子フラグ付き複数宣言関数レジストリ実装
- デフォルト同名宣言は宣言順序で連結
- `nonoverload` は蓄積を無効化（最新定義が優先）
- `FUNCDECL_READ`, `FUNCDECL_WRITE`, `FUNCDECL_ERASE`, `GETFUNCINFO`, `GETFUNCLIST`, `ISFUNC`, `UNDEFFUNC`, `EVAL` がレジストリを使用
- 制限: `when` 属性は記録されるが、スタンドアロン `when` ディスパッチは暗黙switch状態をモデル化していない

### Phase 6: 動的辞書操作

実行時辞書ロード・アンロード実装。

タスク:

- `DICLOAD(filename)` 実装:
  - `ghost/master` 下で安全に解決
  - 設定文字セット戦略で辞書レジストリに解析・登録
- `DICUNLOAD(filename)` 実装:
  - その辞書のみが所有する関数をアンレジスター
  - 他辞書の関数を保持
- `APPEND_RUNTIME_DIC(code)` 実装:
  - コード文字列を一時実行時辞書として解析
  - 合成ソースIDを割り当て
- 動的操作は `GETLASTERROR` / `SETLASTERROR` 経由でエラーを報告

受け入れ基準:

- 辞書は実行時に新しいイベントを定義、呼び出し、アンロード、そして確認可能
- 動的ロード失敗は既存レジストリを破損しない

実装成果:

- `DICLOAD` と `DICUNLOAD` は `VMCallback` と `DictionaryManager` 経由実装、各ロードファイルにソースID割り当て
- `APPEND_RUNTIME_DIC` はコード文字列を合成実行時ソースに解析
- `DICUNLOAD` はアンロード元ソース所有の宣言のみ削除
- 実行時辞書パスはゴースト ルート下の相対パスに制限；絶対パスと親トラバーサル拒否

### Phase 7: 変数永続化・設定

実ゴーストが必要とする共通永続化関数実装。

タスク:

- `SAVEVAR(file)` と `RESTOREVAR(file)` 実装
- ファイルを `ghost/master/var` 下に保存（より厳格な既存規約を確認）
- `Value` 型をロスなく序列化:
  - 文字列
  - 整数
  - 実数
  - 配列
  - 辞書（現在 `Value` でサポートされている場合）
- 実装:
  - `GETSETTING`
  - `SETSETTING`
  - `GETDELIM`
  - `SETDELIM`
  - `DUMPVAR`
- yaya-dicが使用する一時変数登録実装:
  - `REGISTERTEMPVAR` / `UNREGISTERTEMPVAR` 組み込み
  - yaya-dic フレームワークが存在する場合、`SHIORI3FW.RegisterTempVar` などのフレームワークレベル呼び出しはそれらの組み込みにマップ
  - アンロード時クリーンアップ動作

受け入れ基準:

- ユーザー変数はアンロード/リロードで生存
- 登録一時変数は永続化されない
- 永続化はゴースト ディレクトリを超えられない

実装成果:

- `SAVEVAR` と `RESTOREVAR` はグローバル変数をJSON型タグで永続化
- 永続化パスはゴースト ルート下にアンカー；絶対/親トラバーサル パスを拒否
- `REGISTERTEMPVAR` と `UNREGISTERTEMPVAR` が保存除外リストを維持
- `GETSETTING`, `SETSETTING`, `GETDELIM`, `SETDELIM`, `GETLASTERROR`, `SETLASTERROR`, `GETERRORLOG`, `CLEARERRORLOG`, `GETCALLSTACK`, `DUMPVAR` はVM状態でバック

### Phase 8: SAORI・ホスト操作

YAYA と Ourin Swift ホスト機能間のブリッジを完成。

タスク:

- YAYAbuilt-in完成:
  - `LOADLIB`
  - `UNLOADLIB`
  - `REQUESTLIB`
  - yaya-dic ラッパー `FUNCTIONLOAD`, `FUNCTIONEX`, `SAORI`
- すべてのSAORI呼び出しを `YayaAdapter.handlePluginOperation` 経由でルート
- SAORI応答を解析・設定:
  - `Result` からの戻り値
  - `valueex`
  - `valueex0`, `valueex1`, ...
  - ステータス/エラー変数
- SAORI文字セット設定を尊重:
  - `CHARSETLIB`
  - `CHARSETLIBEX`
  - リクエスト/応答文字セット ヘッダー
- 小さな確定的SAORIフィクスチャで統合テスト追加

受け入れ基準:

- yaya-dic SAORIヘルパー関数が実SAORI モジュール または フィクスチャで動作
- マルチ値SAORI応答がYAYAコードから可視

実装成果:

- `LOADLIB`, `UNLOADLIB`, `REQUESTLIB` がホストIPC経由 `YayaAdapter` / `SaoriManager` にルート
- `REQUESTLIB` が `Result` と順序付き `Value0..` 値を解析；追加値は `valueex` と `valueex0..15` で公開
- `FUNCTIONLOAD`, `FUNCTIONEX`, `SAORI` がyaya-dicスタイル ラッパーで利用可
- `CHARSETLIB` と `CHARSETLIBEX` がデフォルトSAORI リクエスト文字セットを設定

### Phase 9: SHIORI/3.0・UKADOCヘッダー互換性

リクエスト/応答処理をUKADOCと整列。

タスク:

- `YayaCore` / `YayaAdapter` 内のリクエスト ヘッダー構築を拡張:
  - `Sender`
  - `SenderType`
  - `SecurityLevel`
  - `SecurityOrigin`
  - `Status`
  - `BaseID`
  - `Reference*`
  - `X-SSTP-PassThru-*`
- 呼び出し元提供ヘッダーを誤った重複なく保持
- 応答ヘッダー解析:
  - `Value`
  - `ValueNotify`
  - `Reference*`
  - `Marker`
  - `MarkerSend`
  - `SecurityLevel`
  - `ErrorLevel`
  - `ErrorDescription`
  - `BalloonOffset`
  - `Age`
  - `X-SSTP-PassThru-*`
- すべての関連ヘッダーをSwiftに返す
- `GET` / `NOTIFY` 動作を確認:
  - `GET` は `Value` を使用
  - `NOTIFY` は `Value` を無視但し `ValueNotify` 処理可能
- `capability` 処理をUKADOCのリクエスト/応答 capability 通知期待値と整列

受け入れ基準

- UKADOCドキュメント ヘッダーは `yaya_core` ラウンドトリップ可能
- 応答 `Reference*` と `ValueNotify` 付きイベント動作

実装成果:

- リクエスト構築は `Charset`, `Sender`, `SenderType`, `SecurityLevel` のデフォルト含む
- 呼び出し元提供ヘッダーは大文字小文字無視重複排除で1回発出；`ID` は重複なし
- 呼び出し元 `Reference*` ヘッダーを保持，その後 `ref` 配列が最終 `Reference0..N` ソースでオーバーレイ
- 応答解析は汎用ヘッダーをSwiftに返す（`Value`, `ValueNotify`, `Reference*`, `X-SSTP-PassThru-*` 含む）

### Phase 10: 組み込み関数監査

ソース・ドキュメントに対してすべての組み込み関数を監査。

タスク:

- `FUNCTION_REFERENCE.md` のすべての組み込み関数を以下に分類:
  - 実装済み
  - 部分的
  - スタブ
  - macOSで意図的に非対応
- 高インパクト部分的/スタブ関数完成:
  - `RE_ASEARCH`
  - `RE_ASEARCHEX`
  - `ISEVALUABLE`
  - `GETERRORLOG`
  - `GETCALLSTACK`
  - `GETFUNCINFO`
  - グローバル定義関数
  - 文字セットID/名前関数
- Windows特有関数をmacOSがサポートできない場合は明示的互換性シムとして維持
- 意図的偏差をドキュメントに記録

受け入れ基準:

- 関数ドキュメントが動作に一致
- スタブ関数は実装されるか意図的非対応としてドキュメント化

実装成果:

- `RE_ASEARCH` と `RE_ASEARCHEX` が `std::regex` で実装
- `ISEVALUABLE` が正確に1つ完全式を解析（`1 +` など不正入力は `0` 返す）
- `GETERRORLOG`, `GETCALLSTACK`, `GETFUNCINFO`, グローバル定義関数、文字セットID/名前ヘルパー実装
- 残存スタブはディレクトリ操作またはWindows専用/プラットフォーム シムとしてドキュメント化

## テスト戦略

### ユニット テスト

- 高度な句読点とUTF-8識別子のLexer トークン テスト
- 新しくサポートされた各構文のパーサー ASTテスト
- 実行時セマンティクスのVMテスト
- 順序付きロード/アンロード動作のDictionaryManagerテスト
- `yaya.txt` 設定解析のSwiftテスト

### 統合テスト

- 最小ゴースト:
  - シンプル `OnBoot`
  - `reference[]`
  - `_argv`
  - 永続化
- yaya-dic ゴースト:
  - `dicdir, yaya_base`
  - `request`
  - `capability`
- Emily4互換性:
  - すべてのターゲット辞書ロード
  - 代表イベント実行
  - パーサー タイムアウトなし

### 回帰メトリクス

各フェーズの前後でこれらのメトリクスを追跡:

- 設定から発見された辞書数
- 正常に解析された辞書数
- 辞書あたりの解析時間
- 総ロード時間
- 警告/エラー数
- 代表イベント成功率
- ホスト操作の成功/失敗数

## リスク管理

### パーサー あいまいさ

YAYA構文は許容的で歴史的互換性駆動。不明トークンをサイレントにスキップし続けるのではなく、専用ASTノード追加。サイレント回復は診断モードに限定。

### 互換性 vs セキュリティ

ファイル、コマンド、SAORI、動的辞書操作は安全なパスまたは明示的ホスト仲介操作に制限のまま。Windowsの YAYA 動作に正確に一致するためにファイルアクセスを拡大しない（Ourinセキュリティ決定なしに）。

### ドキュメント 乖離

動作を変更する各フェーズは以下を更新:

- 実装ステータス
- 関数参照
- 互換性マトリックス
- テスト またはフィクスチャ

## 推奨順序

1. Phase 0: ベースライン・ドキュメント — **完了**
2. Phase 1: `dicdir` ・ロード順序 — **完了**
3. Phase 2: 符号化モデル — **完了**
4. Phase 3: パーサー文法完成 — **完了**
5. Phase 4: 実行時セマンティクス — **完了**
6. Phase 5: 関数宣言セマンティクス — **完了**
7. Phase 6: 動的辞書操作 — **完了**
8. Phase 7: 永続化/設定 — **完了**
9. Phase 8: SAORIホスト統合 — **完了**
10. Phase 9: SHIORI/3.0 ヘッダー — **完了**
11. Phase 10: 組み込み監査 — **完了**

最高の直近互換性ゲインはPhase 1、3、4から来る（yaya-dic標準ロード展開、既知Emily4パーサー失敗を解除）。
