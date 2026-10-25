# 15プラグインのmacOS `.plugin` 変換

確認日: 2026-10-25。公開配布物15件を調査し、YAYA 11件、灯（Akari）3件、専用native 1件のローカル変換成果物を生成しました。DLLの改名ではなく、実際の辞書を既存VMまたはnative engineで実行するadapterです。

**生成15/15と完全互換15/15は異なります。** 最新のロード成功は **12/15**（YAYA 8/11、灯3/3、native TMIDI 1/1）です。YAYAの対象イベントでScriptを確認したのは7件、GetWindowTitleは必要な画面・権限条件が揃わず501です。UGMは追加修正によりロード・メニュー・loopback HTTP配信・合成保存データの維持まで成功しました。GUI全操作や実サービス接続の成功率ではありません。

**前回集計の訂正:** 13/15としていた結果には、CeVIO・AIVOICEの必須Windows helper起動失敗を無視したロード成功2件が含まれていました。プラグインのEXECUTEを明示したhost実行mapへ接続し、未対応の起動を失敗として扱ったため、この2件はロード拒否へ訂正しました。UGMの改善1件を加え、最新値は12/15です。

## 一覧

すべて `build/plugin-ports/<id>.plugin` に生成済みです。配布先は作者のオリジナル配布物であり、Ourin変換版の再配布リンクではありません。

|作品 / 作者|言語・engine|条件 / 一次資料|配布先|実行層・結果|残る依存・制限|
|---|---|---|---|---|---|
|UkagakaGhostMessenger / ろすえん / lost_nd_xxx|YAYA, Go, HTML/JavaScript / yaya|[MIT（本体）・画像等は個別条件](https://github.com/lost-nd-xxx/UkagakaGhostMessenger/blob/5de6b36bfea89bf601ca527f9955ffd8a49c5437/LICENSE)|[作者・release](https://github.com/lost-nd-xxx/UkagakaGhostMessenger/releases/tag/2.0.1) · [ダウンロード](https://github.com/lost-nd-xxx/UkagakaGhostMessenger/releases/download/2.0.1/UkagakaGhostMessenger.nar)|load・version・メニュー・HTTP・保存再読込成功|元辞書11件無改変、2cyclesで確認。loopback専用native helper。jsstp/FMO/SEND、実GUI、旧savedata.adb移行は未検証。|
|tmidi_msg / JiayuYangX|C++/Win32 / native|[作者READMEにpluginコードの利用・改変許可（SPDX明示なし）](https://github.com/JiayuYangX/tmidi_msg/blob/e70cc6bc0cd8006ba48e82326fafe9042d25bd96/README.en.md)|[作者・release](https://github.com/JiayuYangX/tmidi_msg/releases/tag/v1.1.0) · [ダウンロード](https://github.com/JiayuYangX/tmidi_msg/releases/download/v1.1.0/tmidi_msg.nar)|native C ABI・実TCP loopbackを確認|専用native adapterと合成loopback bridgeの6回帰PASS。Windows DDE producerと実TMIDI Playerは未検証。未接続503。|
|stampcollection / postic / YAYA-shiori整備班|YAYA / yaya|[作者readmeで再配布・改変配布可](https://github.com/YAYA-shiori/stampcollection/blob/79221c64fef156106eacafe89f8189bc0a4a5811/readme.txt)|[作者・release](https://github.com/YAYA-shiori/stampcollection/releases/tag/v20260330102740-79221c6) · [ダウンロード](https://github.com/YAYA-shiori/stampcollection/releases/download/v20260330102740-79221c6/stampcollection.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 200 OK|メニューScript応答確認。スタンプ入手、玉/tamac.exe連携、実画面は未検証。|
|Wallet of Unyu / Don / nikolat|YAYA / yaya|[CC0-1.0（本体）](https://github.com/nikolat/wallet_of_unyu/blob/1b583968bd4ff7a245b4fb21489e3e1e1ab1817c/LICENSE)|[作者・release](https://github.com/nikolat/wallet_of_unyu/releases/tag/v1.2.0) · [ダウンロード](https://github.com/nikolat/wallet_of_unyu/releases/download/v1.2.0/wallet_of_unyu.nar)|load → 対象イベント → unload → 再load / PLUGIN/2.0 200 OK|メニューScript応答確認。残高API、認証・送受金は未検証。|
|Bouyomi / 日野つみ / HinoTsumi|YAYA, Go / yaya|[明示ライセンス未確認](https://github.com/apxxxxxxe/Bouyomi/blob/dd917482a00ba5200e0d833c29126af570b7401c/readme.txt)|[作者・release](https://github.com/apxxxxxxe/Bouyomi/releases/tag/v1.5.1) · [ダウンロード](https://github.com/apxxxxxxe/Bouyomi/releases/download/v1.5.1/Bouyomi.nar)|load拒否|proxy_ex.dllの/charset・音声一覧等が未map。Windows SAPI/registry、core.exe起動・発声、旧YAYAテキストvoice設定が残件。|
|うかてん / Don / nikolat|灯（Akari）辞書 / akari|[辞書はpublic domain宣言](https://github.com/nikolat/ukaten/blob/6bc355842625d7c9cf5c7e75f523759bd77ef9e2/readme.txt)|[作者・release](https://github.com/nikolat/ukaten/releases/tag/v1.0) · [ダウンロード](https://github.com/nikolat/ukaten/releases/download/v1.0/ukaten.nar)|load・version・unload・再load成功。固定HTTP fixtureでメニュー応答|実bundleのネットワーク禁止時はメニュー204。気象API実接続・実UIは未検証。|
|うかどんゅう / Don / nikolat|灯（Akari）辞書, YAYA補助 / akari|[NYSDL 0.9982（辞書）・各モジュール別条件](https://github.com/nikolat/ukadonyu/blob/497bcc9c3a5ac224f3946abc9210b2f9026dd560/licence.txt)|[作者・release](https://github.com/nikolat/ukadonyu/releases/tag/v2.2) · [ダウンロード](https://github.com/nikolat/ukadonyu/releases/download/v2.2/ukadonyu.nar)|load・version・unload・再load成功。2回目メニューでbooting Script|Mastodon認証・投稿、Windows SAORI、実UIは未検証。|
|ukagakaPlugin_CeVIO-Talker / ambergon|YAYA, C# / yaya|[明示ライセンス未確認](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/blob/eb7a36d30ef329da97e6c8a6e9f41ad14af25044/readme.md)|[作者・release](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/tag/version1.0.7) · [ダウンロード](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/download/version1.0.7/ukagakaPlugin_CeVIO-Talker.nar)|load拒否（以前の成功判定を訂正）|load内EXECUTEのWindows helper起動が未対応。専用音声API・named pipeも未対応。|
|SSP-AIVOICE / wamo / opera7133|YAYA, C# / yaya|[明示ライセンス未確認](https://github.com/opera7133/SSP-AIVOICE/blob/9b9911f07e5143c98d19dbd5d8cbc08a54dff86b/readme.md)|[作者・release](https://github.com/opera7133/SSP-AIVOICE/releases/tag/v1.0.2) · [ダウンロード](https://github.com/opera7133/SSP-AIVOICE/releases/download/v1.0.2/AIVOICE.nar)|load拒否（以前の成功判定を訂正）|load内EXECUTEのWindows helper起動が未対応。専用音声API・named pipeも未対応。|
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

実配布物はコピーをsandbox内で検証し、UGM HTTP検証ではloopbackだけを許可、それ以外はネットワークを拒否し、書込先をそのコピーと `/dev/null` に限定しました。取得済みの原本は変更していません。DBdiaryは自作の入力文字列を実ファイルへ保存し、unload→再load後に同じ本文をイベント応答から確認しました。全会話本文や取得した画面タイトルは公開結果に含めません。

### UGMの追加対応と検証範囲

YAYAのハッシュ反復（単変数では値、2変数ではキーと値）、ユーザー関数の配列引数の1段展開と参照引数の書戻しを修正しました。後者の誤りで `PLUGINFW.MakeResponse(status, headers)` のヘッダーが1個だけ選ばれていた問題も解消しています。配列をそのまま受け取るJSON等の組み込み関数は、値を保持します。

`PARSEJSON` / `DUMPJSON` / `FREADJSON` / `FWRITEJSON` と、Ourin独自SAVEVAR内のhash保存を追加しました。UTF-8 BOM・コメント、整数/実数・bool/VOID、入れ子、64bit整数、charset、pretty、エラー値を[上流YAYAの実装](https://github.com/YAYA-shiori/yaya-shiori/blob/3ccd7c26f23e56d71a305f1a80e5937588d27cb5/sysfunc.cpp)と照合しています。既存の変数保存形式を書き換える移行機能ではありません。

[UGMの元ヘルパー](https://github.com/lost-nd-xxx/UkagakaGhostMessenger/blob/5de6b36bfea89bf601ca527f9955ffd8a49c5437/localweb/__server_golang/main.go)に相当する静的HTTP配信をnative実装しました。`--ugm-http-helper` で明示同梱した場合だけ `localweb/ugm_server.exe` をこの実装へ接続します。127.0.0.1限定、HTML root以外やsymlinkへのアクセスを拒否し、shutdown.signal・親process終了・unloadで停止します。port競合や既存shutdownは成功に数えません。任意のexeやshell commandを許可する機能ではありません。

実UGM 2.0.1を一時コピーし、元辞書11件のSHA-256不変を確認しました。合成の設定・保存データを与え、2cyclesのload → version（Value）→ OnMenuExec（Script・Event・Reference・Marker）→ HTML/JSON取得 → unloadを実行しました。保存フラグのWeb JSON反映、再ロード後の保存維持、running.signal削除、port解放も確認しています。一時コピーは削除済みです。

残件はブラウザーJSとOurin間のjsstp/FMO/SEND往復、実GUIでの通知・送受信、旧savedata.adbからの移行です。HTTP配信の成功をこれらの動作保証にはしていません。型付きhashキー全般の完全互換も宣言しません。

```bash
# 既存の生成例へ明示オプションを追加してUGM用bundleを生成
# --ugm-http-helper build/engines/plugins/ugm_http_helper
python3 engines/plugins/verify_ugm_bundle.py "$ugm_bundle"
```

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

### 追加修正後の回帰

hash foreach 8、ユーザー関数引数10、JSON 8、既存ファイル保存9、YAYA adapter 11、UGM HTTP 7、UGM adapter 4の計57回帰がPASS。UGMの実配布物probeは別に上記2cyclesで検証しました。同じVMを使う他のYAYAプラグイン10件も一時コピーで再検証し、起動依存の判定訂正を一覧へ反映しています。

追加前のPR #218 head `25f90b8` は[CI全5項目成功](https://github.com/eightman999/Ourin/actions/runs/40176454744)。追加修正後は関連18 suite・192テスト/226実行がPASS、失敗0・SKIP 0。これらを未実施のGUI検証や公開版バイナリへの収録と混同しません。
