# 灯（Akari）プラグインのネイティブ化

確認日: 2026-10-25。対象はうかてん、うかどんゅう、すどはいくゅうの3件です。[15件の変換一覧・配布元](plugin-ports.md)に元の配布ページとダウンロード先を掲載しています。

## 実装

元のAZR辞書を改変せず、Ourin用`.plugin`から灯の互換エンジンへPLUGIN要求を渡します。元のWindows DLLをmacOS用バイナリとして実行する方式ではありません。

各プラグインが専用の`akari_helper`プロセスを持ちます。Swiftエンジンのグローバル状態とObjective-Cクラスをプロセス単位で分離し、複数のプラグインを同時に読み込めます。要求にはサイズ上限と期限を設け、異常終了・プロトコル不正・応答不能を成功扱いにしません。プロセス分離はOSの権限制限そのものではありません。

上流の`pluginResponse`をC ABIから利用できるようにし、PLUGIN応答をSHIORI応答へ読み替えません。`PLUGIN/2.0M`の要求行は既存辞書向けに`PLUGIN/2.0`へ正規化します。ID、Reference、Charsetなどのヘッダーは保持します。終了時は辞書の`unload`（または`unloadPlugin`）を実行します。

## 自作辞書による回帰

```sh
bash engines/additional/build.sh
bash engines/plugins/build.sh
python3 -B engines/plugins/test_akari_adapter.py
```

6テスト成功、失敗0。実際に生成したbundleとネイティブhelperを利用しています。

- UTF-8、Reference12、Script、Targetおよび要求行の保持
- 不正プロトコルの拒否、要求ハンドラー不在時のPLUGIN 204
- `unload`での保存と再ロード
- bundle外を指す設定の拒否
- 2つのプラグインの同時実行、一方の終了後も他方が応答すること
- helperが起動した孫プロセスもアンロード時に回収すること

## 実配布物の検証範囲

3件の無改変配布物でload、version、OnMenuExec、OnSecondChange、unload、再loadを検証しました。うかどんゅう・すどはいくゅうは2回目のOnMenuExecでbooting Scriptを返しました。うかてんはネットワーク禁止の実bundle試験でメニュー204となり、固定HTTP応答を与える別のエンジン試験でメニューを確認しました。version応答や200だけではメニュー表示・天気取得・SNS連携の成功と判定しません。うかどんゅうとすどはいくゅうは最初のOnMenuExecを初期化に使うため、空のScriptだけで失敗とは判定できません。

天気のネットワーク取得、SNS認証・投稿、HandUtil/httpc/imgctl/textcopy2など外部SAORI、実画面での操作は別の検証項目です。認証情報や投稿先の設定は変更していません。Intel用バイナリも生成していますが、実行検証はApple Silicon上です。

## 成果物と取得物

生成物はローカルの`build/plugin-ports/`に保持します。bundleには機能のため元の辞書・素材が含まれます。調査用NARと使い捨て実行コピーを削除しても、生成物内のpayloadは残ります。元の第三者配布物や生成bundleをOurinのGit/Webで再配布していません。

型付き初期化、公式の`_eventdict`と辞書pairの追加、空応答を二重実行しない処理を修正しました。自作4回帰と無改変3作品のメニュー試験1件は全5件成功、元辞書79ファイルのハッシュは一致しています。HTTPは固定fixtureであり、気象API実接続の成功とは区別します。
