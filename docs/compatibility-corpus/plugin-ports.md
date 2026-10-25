# 15プラグインのmacOS `.plugin` 変換

確認日: 2026-10-25。公開配布物15件を調査し、YAYA 11件、灯（Akari）3件、専用native 1件のローカル変換成果物を生成しました。DLLの改名ではなく、実際の辞書を既存VMまたはnative engineで実行するadapterです。

**生成15/15と完全互換15/15は異なります。** YAYA 11件ではloadと再load成功9/11、対象イベントのScript応答6/11、load拒否2/11です。DBdiaryは実保存と再読込まで確認しています。CeVIO・AIVOICE・GetWindowTitleの対象操作は依存機能のエラーを501で返しました。Ourin実GUIでの操作確認はこの表に含みません。灯3件もload/reload成功、TMIDIはnativeロードとloopback bridgeを確認し、全体のロード成功は13/15です。完全互換・実サービス接続の成功率ではありません。

## 一覧

すべて `build/plugin-ports/<id>.plugin` に生成済みです。配布先は作者のオリジナル配布物であり、Ourin変換版の再配布リンクではありません。

|作品 / 作者|言語・engine|条件 / 一次資料|配布先|実行層・結果|残る依存・制限|
|---|---|---|---|---|---|
|UkagakaGhostMessenger / ろすえん / lost_nd_xxx|YAYA, Go, HTML/JavaScript / yaya|[MIT（本体）・画像等は個別条件](https://github.com/lost-nd-xxx/UkagakaGhostMessenger/blob/5de6b36bfea89bf601ca527f9955ffd8a49c5437/LICENSE)|[作者・release](https://github.com/lost-nd-xxx/UkagakaGhostMessenger/releases/tag/2.0.1) · [ダウンロード](https://github.com/lost-nd-xxx/UkagakaGhostMessenger/releases/download/2.0.1/UkagakaGhostMessenger.nar)|load拒否|functions.dic:753 と event.dic:209 の hash foreach（key,value）構文が未対応。11辞書中2件parse失敗を検出してload拒否。Go Webサーバー起動、FREADJSON/FWRITEJSONも未対応。|
|tmidi_msg / JiayuYangX|C++/Win32 / native|[作者READMEにpluginコードの利用・改変許可（SPDX明示なし）](https://github.com/JiayuYangX/tmidi_msg/blob/e70cc6bc0cd8006ba48e82326fafe9042d25bd96/README.en.md)|[作者・release](https://github.com/JiayuYangX/tmidi_msg/releases/tag/v1.1.0) · [ダウンロード](https://github.com/JiayuYangX/tmidi_msg/releases/download/v1.1.0/tmidi_msg.nar)|native C ABI・実TCP loopbackを確認|専用native adapterと合成loopback bridgeの6回帰PASS。Windows DDE producerと実TMIDI Playerは未検証。未接続503。|
|stampcollection / postic / YAYA-shiori整備班|YAYA / yaya|[作者readmeで再配布・改変配布可](https://github.com/YAYA-shiori/stampcollection/blob/79221c64fef156106eacafe89f8189bc0a4a5811/readme.txt)|[作者・release](https://github.com/YAYA-shiori/stampcollection/releases/tag/v20260330102740-79221c6) · [ダウンロード](https://github.com/YAYA-shiori/stampcollection/releases/download/v20260330102740-79221c6/stampcollection.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 200 OK|メニューScript応答確認。スタンプ入手、玉/tamac.exe連携、実画面は未検証。|
|Wallet of Unyu / Don / nikolat|YAYA / yaya|[CC0-1.0（本体）](https://github.com/nikolat/wallet_of_unyu/blob/1b583968bd4ff7a245b4fb21489e3e1e1ab1817c/LICENSE)|[作者・release](https://github.com/nikolat/wallet_of_unyu/releases/tag/v1.2.0) · [ダウンロード](https://github.com/nikolat/wallet_of_unyu/releases/download/v1.2.0/wallet_of_unyu.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 200 OK|メニューScript応答確認。残高API、認証・送受金は未検証。|
|Bouyomi / 日野つみ / HinoTsumi|YAYA, Go / yaya|[明示ライセンス未確認](https://github.com/apxxxxxxe/Bouyomi/blob/dd917482a00ba5200e0d833c29126af570b7401c/readme.txt)|[作者・release](https://github.com/apxxxxxxe/Bouyomi/releases/tag/v1.5.1) · [ダウンロード](https://github.com/apxxxxxxe/Bouyomi/releases/download/v1.5.1/Bouyomi.nar)|load拒否|起動時のWindows core.exe実行が未対応でload拒否。Go helperはWindows音声registry・process探索・NoInheritHandlesに依存。|
|うかてん / Don / nikolat|灯（Akari）辞書 / akari|[辞書はpublic domain宣言](https://github.com/nikolat/ukaten/blob/6bc355842625d7c9cf5c7e75f523759bd77ef9e2/readme.txt)|[作者・release](https://github.com/nikolat/ukaten/releases/tag/v1.0) · [ダウンロード](https://github.com/nikolat/ukaten/releases/download/v1.0/ukaten.nar)|load・version・unload・再load成功。固定HTTP fixtureでメニュー応答|実bundleのネットワーク禁止時はメニュー204。気象API実接続・実UIは未検証。|
|うかどんゅう / Don / nikolat|灯（Akari）辞書, YAYA補助 / akari|[NYSDL 0.9982（辞書）・各モジュール別条件](https://github.com/nikolat/ukadonyu/blob/497bcc9c3a5ac224f3946abc9210b2f9026dd560/licence.txt)|[作者・release](https://github.com/nikolat/ukadonyu/releases/tag/v2.2) · [ダウンロード](https://github.com/nikolat/ukadonyu/releases/download/v2.2/ukadonyu.nar)|load・version・unload・再load成功。2回目メニューでbooting Script|Mastodon認証・投稿、Windows SAORI、実UIは未検証。|
|ukagakaPlugin_CeVIO-Talker / ambergon|YAYA, C# / yaya|[明示ライセンス未確認](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/blob/eb7a36d30ef329da97e6c8a6e9f41ad14af25044/readme.md)|[作者・release](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/tag/version1.0.7) · [ダウンロード](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/download/version1.0.7/ukagakaPlugin_CeVIO-Talker.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 501 Host Capability Unavailable|メニュー要求は501。CeVIO AI専用.NET API・Windows named pipe/helperが未対応。|
|SSP-AIVOICE / wamo / opera7133|YAYA, C# / yaya|[明示ライセンス未確認](https://github.com/opera7133/SSP-AIVOICE/blob/9b9911f07e5143c98d19dbd5d8cbc08a54dff86b/readme.md)|[作者・release](https://github.com/opera7133/SSP-AIVOICE/releases/tag/v1.0.2) · [ダウンロード](https://github.com/opera7133/SSP-AIVOICE/releases/download/v1.0.2/AIVOICE.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 501 Host Capability Unavailable|メニュー要求は501。A.I.VOICE Editor API・Windows named pipe/helperが未対応。|
|ukagakaPlugin_getWindowTitle / ambergon|YAYA, C# / yaya|[作者READMEに同梱利用許可（SPDX明示なし）](https://github.com/ambergon/ukagakaPlugin_getWindowTitle/blob/236f0057a13631cddf871ad66e2ddcbdea8f90a9/readme.md)|[作者・release](https://github.com/ambergon/ukagakaPlugin_getWindowTitle/releases/tag/1.0.0) · [ダウンロード](https://github.com/ambergon/ukagakaPlugin_getWindowTitle/releases/download/1.0.0/ukagakaPlugin_getWindowTitle.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 501 Host Capability Unavailable|macOS AX backend同梱。実要求は前面window/権限条件不足で501。実タイトル取得成功は未検証。|
|UkagakaPlugin_DBdiary / ambergon|YAYA / yaya|[作者READMEに同梱配布・main.uka改変許可（SPDX明示なし）](https://github.com/ambergon/UkagakaPlugin_DBdiary/blob/690a9d78f1aaf91c22b5d2aef8cf0edd9a166038/readme.md)|[作者・release](https://github.com/ambergon/UkagakaPlugin_DBdiary/releases/tag/1.0.1) · [ダウンロード](https://github.com/ambergon/UkagakaPlugin_DBdiary/releases/download/1.0.1/UkagakaPlugin_DBdiary.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 200 OK|入力用Script、日記実ファイル保存、unload/reload後の再読取を確認。Ourin GUI入力欄との往復は未検証。|
|CharameLNetwork / Don / nikolat|YAYA, HTML/CSS / yaya|[NYSDL 0.9982（辞書）](https://github.com/nikolat/CharameLNetwork/blob/e11b8210c5a635e7c34efa7880e5787842592655/readme.txt)|[作者・release](https://github.com/nikolat/CharameLNetwork/releases/tag/v0.5) · [ダウンロード](https://github.com/nikolat/CharameLNetwork/releases/download/v0.5/CharameLNetwork.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 200 OK|メニューScript応答確認。外部Webサービス/SSTPによる実イベント往復は未検証。|
|balloonselector / Don / nikolat|YAYA / yaya|[Unlicense（本体）・YAYA BSD-3-Clause](https://github.com/nikolat/balloonselector/blob/04ac6c086a03f1394c572d0748e4bdd190046c77/LICENSE)|[作者・release](https://github.com/nikolat/balloonselector/releases/tag/v2.4.0) · [ダウンロード](https://github.com/nikolat/balloonselector/releases/download/v2.4.0/balloonselector.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 200 OK|メニューScript応答確認。実hostのバルーン一覧取得・切替とGUI表示は未検証。|
|棒読みちゃん連携プラグイン / NightWork|YAYA, Windows送信helper / yaya|[明示ライセンス未確認](https://nightwork.sakura.ne.jp/ukagaka/tools/BouyomiChan_PLUGIN/BouyomiChan_PLUGIN.html)|[作者・release](https://nightwork.sakura.ne.jp/ukagaka/tools/BouyomiChan_PLUGIN/BouyomiChan_PLUGIN.html) · [ダウンロード](https://nightwork.sakura.ne.jp/ukagaka/tools/BouyomiChan_PLUGIN/BouyomiChan_PLUGIN(20241208).nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 200 OK|メニューScript応答確認。TCP SendTalk backendは実socket6回帰で検証済み。元辞書から実棒読みちゃん発声までの全経路は未検証。|
|すどはいくゅう / Don / nikolat|灯（Akari）辞書 / akari|[NYSDL 0.9982（辞書）・各モジュール別条件](https://github.com/nikolat/sudohaikuyu/blob/998d8f65c86cc541a34c6fbec2e721fcb0ba0ba2/licence.txt)|[作者・release](https://github.com/nikolat/sudohaikuyu/releases/tag/v0.4) · [ダウンロード](https://github.com/nikolat/sudohaikuyu/releases/download/v0.4/sudohaikuyu.nar)|load・version・unload・再load成功。2回目メニューでbooting Script|外部API・Windows SAORI、実UIは未検証。|

## 変換方式と検証

YAYA adapterは別helper processへPLUGIN/2.0・2.0Mの生要求を渡します。GET/NOTIFY、Reference、Script、Event、Target、204と文字コードを保持し、SHIORIへの便宜的変換やイベント直接呼出で成功を作りません。辞書が一部だけparseされる場合、未ロードのhandlerを空200で隠さずloadを拒否します。外部実行・未対応SAORIも非成功応答として伝えます。

灯も専用helperで実engineをロードします。同一processへ複数Swift dylibをロードすることを避け、bundleごとの状態を分離します。TMIDIは専用native受信部と明示設定のloopback bridgeです。[native依存機能・試験](plugin-native.md)と[灯adapterの検証](plugin-akari.md)を参照してください。

YAYAの自作辞書によるnative ABI回帰は11 PASS、既存ファイル永続化回帰は9 PASSです。UTF-8/CP932、完全な応答wire、204、保存再load、未対応SAORI、部分parse失敗、ヘッダーの重複と順序、本文保持、TOAUTOEX、hash入れ子代入と従来数値配列を検証しています。adapterとhelperはUniversal 2の出力を確認しました。Intel実機および実GUIは未検証です。

実配布物はコピーをsandbox内で検証し、ネットワークを拒否し、書込先をそのコピーと `/dev/null` に限定しました。取得済みの原本は変更していません。DBdiaryは自作の入力文字列を実ファイルへ保存し、unload→再load後に同じ本文をイベント応答から確認しました。全会話本文や取得した画面タイトルは公開結果に含めません。

### UGMの残件

PARSEHEADERを[上流YAYAの実装契約](https://github.com/YAYA-shiori/yaya-shiori/blob/3ccd7c26f23e56d71a305f1a80e5937588d27cb5/sysfunc.cpp)に照合して追加しました。start/header/key/value/rawvalue/body、CRLF/LF、重複キーのlast-wins、選択的なTOAUTOEX変換を扱います。既存VMのDictionaryへ文字列キーの読書き、IHASH、HASH_EXIST/SIZE/KEYS/VALUESも追加しました。型付きhashキー全般・hash要素の参照渡し・JSONファイル関数の完全対応は宣言しません。

実UGM 2.0.1の `dict/functions.dic:753` と `dict/event.dic:209` は `foreach hash ; key, value` 構文を使い、現在のparserは2変数foreachを扱えません。指定11辞書のうち2件がparseに失敗するため、最終adapterはloadを拒否します。PARSEHEADERだけを直した中間状態の空200は成功実績に数えていません。Go製Webサーバー起動、FREADJSON/FWRITEJSON、保存移行も残件です。

### 保存と外部依存

Ourin独自の変数保存は `Resources/state/yaya-variables.json` に置き、元YAYAの `yaya_variable.cfg` を上書きしません。旧テキスト形式・暗号化された既存変数の自動移行は未実装です。辞書自身のFWRITE等は変換成果物のpayload内に保存します。

GetWindowTitleとNightWorkは明示したモジュール名だけをnative backendへ接続します。任意コマンドの実行、権限付与、認証、投稿、送金は行っていません。合成socketの成功を実音声やWindows DDE実機の成功に置き換えません。

## ローカル再生成

リポジトリrootで実行します。`source_dir` は利用者が別途取得・安全に展開したプラグインのdescript.txtがあるディレクトリ、`output_bundle` は未作成の出力パスを指定してください。

```sh
bash yaya_core/build.sh
bash engines/plugins/build.sh
collector_dir="$(mktemp -d -t ourin-plugin-collector)"
python3 engines/plugins/prepare_collector.py --output-dir "$collector_dir"
python3 engines/plugins/generate.py \
  --source "$source_dir" --output "$output_bundle" --engine yaya \
  --adapter build/engines/plugins/OurinYayaPlugin.dylib \
  --helper yaya_core/build/yaya_core \
  --collector "$collector_dir/yaya_plugin_collector" \
  --source-url "$author_page"
python3 engines/plugins/test_yaya_adapter.py -v
python3 yaya_core/tests/test_file_persistence.py -v
```

`generate.py --help` は灯のengine指定（adapterと同じディレクトリのhelperを自動同梱）と `--saori-backend` の明示mapも説明します。生成はsourceへの書込、シンボリックリンク、既存出力の上書きを拒否し、ファイル数と総容量を制限します。元の辞書・素材・Windows DLLは利用者のローカルpayloadとして保持し、OurinのリポジトリやWebには追加しません。実際に使うバイナリはInfo.plistが指定するnative adapterです。

## 成果物の保持と資料の削除

今回の15件はユーザーが求めた変換成果物なので、`build/plugin-ports/` にローカル保持します。辞書型14件は元payloadを含み、TMIDIはOurinのnative実装とbridge手順を含みます。この場所はgitの対象外です。以前の92件互換性コーパスで全取得物を削除した処理とは目的・保持範囲が異なります。今回の生NAR・調査用展開物・試験コピーは検証後に削除し、配布URL・checksum・応答metadata・削除結果だけを残します。

[機械可読の調査・検証結果](plugin-ports-results.json)には作者、ライセンス根拠、source revision、NAR SHA-256と検証層を記録します。ライセンス不明を自由な再配布許可とは扱いません。今回のadapterはOurinのApache-2.0、説明文はリポジトリのCC BY-SA 4.0です。

取得資料の後処理は完了済みです。生NAR・展開物・原著ソース調査コピーを削除し、変換成果物15件を保持しています。

## 統合テスト

2026-10-25、arm64の実アプリ/XCTest環境で関連18 suite、192テスト（パラメータを含む226実行）、失敗0、SKIP 0。PluginHost、legacy metadata、イベント配送、YAYA組み込み・配列・ファイル・Emily4、native ABI、KAGARIと追加栞を確認しました。

ロード失敗を拒否する変更により、成功時にも0を返していた既存の自作plugin fixtureが失敗しました。fixtureをAPI契約どおり非0へ修正し、ロード失敗専用fixtureではrequest/unloadを呼ばないことも確認しました。

OurinTests全体の試行は、SoundPlayerTestsでmacOS AudioQueueの出力開始タイムアウトが繰り返されたため中断しました。音声系を含む全体成功とは報告しません。今回の関連suiteは上記のとおり再実行済みです。CIにはnative adapter、KAGARI module、灯の自作辞書回帰も追加しています。
