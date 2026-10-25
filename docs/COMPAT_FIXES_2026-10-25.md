# 互換性修正レポート (2026-10-25)

[#109](https://github.com/eightman999/Ourin/issues/109)（FINE）と[#118](https://github.com/eightman999/Ourin/issues/118)（scriptbox）のローカル修正記録です。z.ai workerの変更を引き継ぎ、FINEの宛先選択と公開wireからの回帰試験を追加しました。委譲処理はtimeout終了であり、workerの正常完了とは扱いません。

## #109 FINEのwireと単一宛先配送

### 根拠と未確定範囲

Issueに記載されたSSP 2.8.35fの`ProcNotifyFINE @0x68adf0`要約を照合対象にしています。要約内のReferenceの説明には矛盾があるため、全記述を確定仕様とは扱いません。現在の実装契約は下表とし、公開wire→実EventBridge登録fixtureへの配送を回帰試験します。SSP実プロセスとの同一入力による差分試験は未実施です。

| 項目 | 現在の実装契約 | 旧実装 |
|---|---|---|
| サブコマンド | リクエスト行 `FINE <subcommand> [SSTP/x.y]` | Reference0 |
| MessageSendの宛先 | Reference0: name / sakura.name / ディレクトリ名。そこで一致しなければReference1: kero.name | Reference1 / Reference2等にずれ |
| MessageSendの本文 | Reference3 | Reference4 |
| SetScript / SetScriptPartialの初期文字列 | Reference0 | サブコマンド文字列と兼用 |
| 未知・空のサブコマンド | 501 | 空の場合400 |

`SSTPParser`はリクエスト行の第2トークンをversionスロットへ載せるため、FINEではその値をサブコマンドとして解釈し、応答を`SSTP/1.4`で返します。通常SSTPの版数解析は変更していません。

### 宛先選択

`EventBridge.playFineScript`が、main thread上で登録済みセッションを読み、一意の対象へだけ再生を予約します。

- さくら側の名前が一致した場合はそれを優先し、別のゴーストに一致するけろ名へも同時配送しません。
- さくら側に一致がない場合だけ、けろ名の一致を使います。
- 両名未指定・一致なし・候補が複数の場合は**420 Refuse、配送なし**です。同じmanagerの重複登録は候補を重複計上しません。
- SSPの`GetPreferredActiveGhost`に相当するMessageSend fallbackは未対応です。未確認の優先選択を全ゴーストへの配信で近似しません。
- 本文がない要求は400、一意の宛先に配送を予約できた場合は200です。

旧Ourin独自の`FINE SSTP/1.4` + `Reference0: MessageSend/SetScript/...`は**501で拒否**します。未公開の統合版で確認された誤配線への暫定互換を残さず、Reference0を宛先・初期文字列・サブコマンドで兼用しないための整理です。呼び出し側はサブコマンドをリクエスト行へ移し、上表のReferenceへ合わせてください。

SetScript / SetScriptPartialは既存の優先ゴースト用入力窓経路を使い、Reference0を初期値として渡します。MessageSendの宛先選択とは別の処理です。

### 追加した回帰試験

`OurinTests/SSTPCompatRegressionTests.swift`は`eventBridgeIsolated`で他suiteの登録セッションから分離します。`SSTPParser.parseRequest`で生wireを解析し、実EventBridgeへ一時GhostManagerと記録用runtimeを登録します。

- 2体登録時、Reference0とReference1が別ゴーストへ一致しても、さくら側の1体だけへReference3本文が届くこと。Reference2/4のダミー本文は届かないこと。
- さくら名が空または不一致の場合に、けろ名が一意ならその1体だけへ届くこと。
- 宛先未指定・不一致・さくら名複数一致・けろ名複数一致を420として、どのruntimeにも本文が届かないこと。
- SetScriptとSetScriptPartialで実入力ダイアログの`NSTextField.stringValue`がReference0と一致すること。
- 旧Reference0サブコマンド形式を501にし、再生も入力窓生成も行わないこと。
- 本文欠落400、未知サブコマンド501、ゴースト不在420の既存確認。

`OurinTests/SSTPDispatcherTests.swift`の関連7テストも行サブコマンド／Reference3本文へ更新しました。テストfixtureは既存app delegate・ゴーストを退避して復元し、登録・入力窓・再生を終了時に片付けます。Swift構文確認と差分検査を実行済み。追加テストを含む最終OurinTests全体は1,541実行ケース成功・失敗0件（`/tmp/ourin-delegated-unit-final-r4-20261025.xcresult`）。実入力窓の手動操作とSSP比較は未実施です。

## #118 [compat/Input] scriptbox の open / close 誤配線修正

### 誤り（旧実装）

`\![open,...]` 用ロジックの `case "textareabox"` と `case "scriptbox"` が
`\![close,...]` 分岐の switch 内に誤配置されていた（GhostManager.swift）。

- `\![close,scriptbox,ID]` が入力窓を **開く**（close で open される誤配線）。
- `\![close,textareabox,ID]` も同様に textareabox を開こうとする。
- `\![open,scriptbox,...]` と `\![open,textareabox,...]` は case が無いため
  default へ落ちて `openURL("scriptbox")` として扱われる。

### 正本とイベント意味論

- scriptbox は SSP 固有の入力種別（GetTypeText case 1、UKADOC のさくらスクリプト
  一覧には未収録）。基本 UI とイベント発火は inputbox と同族で、決定 → OnUserInput、
  取消／タイムアウト → OnUserInputCancel。
- `\![close,inputbox]` 同族の close はキャンセルイベントを発生させない。
- `\![open,textareabox,...]` は UKADOC 2.9.10（ID, 表示時間, テキスト, --placeholder 等）。

### 修正

- `Ourin/Ghost/GhostManager+Input.swift`（新設）: scriptbox / textareabox の
  引数解析（`parseInputBoxCommand`。inputbox と同じ位置指定／`--id=`/`--timeout=`/
  `--text=`/`--placeholder=` の優先度）と open 関数（`openScriptBox` は inputbox と
  同一の単一行ダイアログ、`openTextAreaBox` は既存の textareabox ダイアログ）。
- `Ourin/Ghost/GhostManager.swift`: open 分岐へ `case "scriptbox"` /
  `case "textareabox"` を追加（拡張へ委譲）。close 分岐から誤配置された open 用
  case を除去し、`case "scriptbox"` は `\![close,inputbox]` と同じ
  `closeInputDialog(id:)`（イベント無し）で閉じる。

### テスト（`OurinTests/ScriptBoxTests.swift`、新設）

- 引数解析: 位置指定形式 / オプション形式 / 引数なしの default ID /
  位置指定と `--id` の優先度 / textareabox の placeholder。
- open 配線: `\![open,scriptbox]` が openURL に落ちず inputbox 同族の
  モーダレスダイアログを開くこと（実ダイアログ生成まで検証）。
- close 配線（回帰の核心）: 開いた scriptbox に対する `\![close,scriptbox,ID]` が
  既存の窓を閉じ、**新しい窓を開かない**こと。未知 ID の close も何も開かないこと。

## 実行

```
xcodebuild -project Ourin.xcodeproj -scheme Ourin \
  -only-testing:OurinTests/ScriptBoxTests \
  -only-testing:OurinTests/SSTPCompatRegressionTests test
```

Xcode プロジェクト全体の build / test は統合作業者が一括実行する。
新規ファイルは fileSystemSynchronizedGroups（objectVersion 77）により自動取り込みされる。
