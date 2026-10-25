# プラグインのmacOSネイティブ依存機能

確認日: 2026-10-25。これは開発版の個別機能検証で、公開版への収録や15作品すべての完全互換を示しません。

## 実装と利用範囲

`engines/plugin-native/` に、既存YAYA辞書から呼ばれるWindows依存部分を置き換える2本のSAORI backendを実装しました。元の辞書や配布アーカイブは書き換えません。汎用YAYA `.plugin` adapterが、明示設定されたモジュール名だけを以下のbackendへ接続します。

|元のモジュール|macOS backend|実装範囲|
|---|---|---|
|`dll/proxy_ex.dll`|`OurinGetWindowTitle.dylib`|`/charset,sjis` と `./getWindowTitle.exe` の呼出。前面アプリのフォーカスウィンドウのタイトルをAccessibility APIで取得|
|`exec/exec.dll`|`OurinSendTalk.dylib`|`hide,..\SendTalk.exe,<本文>` の呼出。棒読みちゃんのTCP command 1を送信|

両者は汎用コマンド実行proxyではありません。上表以外の実行ファイルや引数構成は501で拒否します。Windows実行ファイル、シェル、PowerShellを起動する処理はありません。

### ABIと配置

- `request(const uint8_t *borrowed, size_t length, size_t *responseLength)`。返却バッファはモジュール所有で、同じスレッドの次の呼出まで有効です。
- `loadu(char *owned, size_t length)` はmalloc所有のパスを受け取り解放します。`unload()` を公開します。
- `GET Version SAORI/1.0` と `EXECUTE SAORI/1.0` を処理します。応答はUTF-8です。
- このbackend境界の入力は、汎用adapterが渡す**UTF-8のVM文字列**です。旧辞書が`Charset: Shift_JIS`を選んでも、二重に再デコードしません。Windows DLLの生Shift_JISバイトをそのまま受け付けるABIではありません。
- `Resources/adapter.json` の `saori_backends` に正規化した相対モジュール名を設定し、backendを `Resources/backends/` に配置します。先頭`./`の除去、区切り文字`\`から`/`への変換、小文字化はadapter側の契約です。
- backendの失敗を上位PLUGIN側へ伝える必要があります。ロード成功やバージョン応答だけを、機能成功として扱いません。

ビルドと回帰テスト:

```sh
bash engines/plugin-native/build.sh /tmp/ourin-native-backends
python3 engines/plugin-native/test_native.py
```

出力はarm64 / x86_64 Universal 2 dylib、deployment targetはmacOS 11です。ビルド済み第三者バイナリをリポジトリへ追加する手順ではありません。

## 作品ごとの照合

### GetWindowTitle

[作者の公開ソース](https://github.com/ambergon/ukagakaPlugin_getWindowTitle)はYAYA as pluginです。`main.uka` がproxy_ex経由で `getWindowTitle.exe` を実行し、`OnRecieveGetWindowTitle` のReference0へ結果を返します。C# helperはWin32の `GetForegroundWindow` / `GetWindowText` に依存します。

今回のbackendはmacOSのフォーカスアプリ・ウィンドウ・タイトルを順に照会します。タイトル中の引用符とパーセントを除き、バックスラッシュを二重化する元helperの出力規則も維持します。CR/LFはヘッダ注入を防ぐため空白へ変換します。Accessibility許可がないと420、前面アプリやタイトルを取得できないと503と `X-Ourin-Error` を返します。アプリ名で代用した成功応答や、権限ダイアログの自動表示は行いません。API照会には短いタイムアウトを設定しています。

作者READMEは同梱利用を認めていますが、一般的なSPDXライセンスの指定は確認していません。今回の実装は公開インターフェースに対する独自実装であり、元のC#・DLL・辞書を同梱していません。

根拠: [YAYA側のイベント処理](https://github.com/ambergon/ukagakaPlugin_getWindowTitle/blob/master/main.uka)、[Windows helper](https://github.com/ambergon/ukagakaPlugin_getWindowTitle/blob/master/dll/getWindowTitle.cs)。

### DBdiary

[作者の公開ソース](https://github.com/ambergon/UkagakaPlugin_DBdiary)もYAYA as pluginです。独立したWindows backendではなく、UTF-8の `FOPEN` / `FREAD` / `FWRITE` と入力イベントが中心です。このため別のネイティブ日記実装で置換せず、汎用YAYA adapterで既存辞書を動かす対象としています。

`OnCallInputBeautifulDiary` / `OnCallInputDirtyDiary` は入力欄を開くスクリプトを返し、入力イベントで `Diary/` 配下へ追記します。`OnCheckWrittenDiary` は当日の日記の先頭行または `notExist` / `notWrite` を `OnRecieveCheckWrittenDiary` で返します。元仕様自体が先頭行の読取なので、複数行全体の返却と混同しません。保存・再起動・再読取とOurin入力欄へのイベント往復は、モジュールロードとは別の検証が必要です。

作者READMEには同梱配布と `main.uka` の改変許可があります。今回、第三者辞書の変更・再配布は行っていません。[根拠となるイベント実装](https://github.com/ambergon/UkagakaPlugin_DBdiary/blob/master/main.uka)。

### Nightwork 棒読みちゃん連携プラグイン

[作者配布ページ](https://nightwork.sakura.ne.jp/ukagaka/tools/BouyomiChan_PLUGIN/BouyomiChan_PLUGIN.html)と2024-12-08配布NAR内のテキストを照合しました。YAYA辞書がサクラscriptを話者タグ付き本文に変換し、`SAORI("exec\exec.dll", "hide", "..\SendTalk.exe", 本文)` を呼びます。本文にはLFによる複数行が含まれます。NAR SHA-256:

```text
66db2fec2de9bd0a47f9d7fcc41c078edb754ca3583b926474d4f5643cf551c8
```

今回の `OurinSendTalk.dylib` はこの呼出の送信部分を実装します。`127.0.0.1:50001` に接続し、リトルエンディアンの command=1、speed/tone/volume=-1、voice=0、UTF-8、本文バイト長、本文を送ります。接続・送信の合計待機は2秒以内、失敗は503です。`OURIN_BOUYOMI_PORT` は1〜65535の範囲でloopbackポートだけを変更できます。既定ポートを勝手に探索しません。

送信先には棒読みちゃん本体または明示的に設定した互換サービス／転送先が必要です。macOS backendは音声合成エンジンを提供しません。TCP送信成功は、音声の再生完了を意味しません。作者READMEには改造許可と、アーカイブ再配布時の再配布明記条件があります。今回のリポジトリには配布NAR・exec.dll・SendTalk.exe・辞書を同梱していません。

### apxxxxxxe/Bouyomi

[公開リポジトリ](https://github.com/apxxxxxxe/Bouyomi)はGo製のコアを持ちます。[TCP送信実装](https://github.com/apxxxxxxe/Bouyomi/blob/main/core/speak/tcp.go)は `localhost:50001` への上記バイナリ形式ですが、送信前に `BouyomiChan.exe` のプロセス存在を確認しています。TCP部分はmacOSでも実装可能です。さらに `core/data/voice.go` はWindowsレジストリのSAPI音声一覧を読み、`core/data/util.go` はWindows専用の `NoInheritHandles` を使います。辞書は起動時と発声時に `EXECUTE(core.exe,...)` を呼ぶため、proxy_exだけを置換しても動きません。Windowsプロセス探索、話者・設定・イベント処理を含むこの作品全体の移植完了は、Nightwork向けSAORIのTCP試験からは導けません。個別のライセンス確認なしにGoソースをOurinへ転載していません。

### CeVIO-Talker / SSP-AIVOICE

**追加のローカルTTS対応:** 明示opt-inで、元2プラグインの辞書・設定メニューをIrodoriへ接続し、各2cyclesのロード・設定復元・実音声生成と再生プロセス正常終了を確認しました。[導入手順・パラメータ互換・検証範囲](local-tts.md)を参照してください。以下のWindows依存は元製品の音声を使う場合の契約です。

両作品はYAYAからproxy_ex経由でC# helperへ接続します。確認した版の通信はHTTP/TCPではありません。

|作品|元実装の通信と依存|macOS側の現在の扱い|
|---|---|---|
|[CeVIO-Talker](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker)|Windows NamedPipe `UkagakaPlugin/CeVIO_Talker`、2バイト長＋UTF-16LE、`CeVIO.Talk.RemoteService2` / `Talker2`|Windows側サービスと専用APIが必要。未対応依存として記録|
|[SSP-AIVOICE](https://github.com/opera7133/SSP-AIVOICE)|Windows NamedPipe `UkagakaPlugin/AIVOICE`、同じ長さ付きUTF-16LE、`AI.Talk.Editor.Api` / `TtsControl`|Windows側エディタと専用APIが必要。未対応依存として記録|

Windowsサービスを別途提供するなら明示的なネットワークbridge設計は可能ですが、現在の配布物にはそのHTTP/TCP口は確認できません。macOSの別音声で代用して「元製品で発声成功」とは扱いません。公開ソースがあることだけを、依存ライブラリや音声製品の再配布許可と解釈しません。Windowsサービス／実音声は今回起動していません。

一次ソース: [CeVIO client](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/blob/master/dll/client.cs)、[CeVIO server](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/blob/master/dll/myserver.cs)、[AIVOICE client](https://github.com/opera7133/SSP-AIVOICE/blob/main/dll/client.cs)、[AIVOICE server](https://github.com/opera7133/SSP-AIVOICE/blob/main/dll/server.cs)。CeVIOのREADMEには別リポジトリのV2への案内がありますが、現在のカタログにある旧版をV2に置き換えて検証していません。

### TMIDI Messages

[作者説明](https://github.com/JiayuYangX/tmidi_msg)と [C++実装](https://github.com/JiayuYangX/tmidi_msg/blob/main/tmidi_msg.cpp)を照合しました。PLUGIN/2.0の `OnSecondChange` を契機に、Win32 DDEMLでTMIDIサービスの `getstatus` / `gettitle` を照会し、テンプレートへ曲名を入れて返します。ユーザーが用意したTMIDI Playerが必要です。

元の古いSSTP送信機能を置き換えるためのDDE設計であり、このpluginにそのまま接続できるTCP/HTTP受信口はありません。macOS上にDDEを名乗る成功stubを置いても互換動作にはなりません。この依存に対し、今回 `tmidi_plugin.mm` にmacOS側の専用 `.plugin` を、`tmidi_windows_bridge.py` に独自のWindows DDE clientを実装しました。元C++の複製ではありません。Windows producerはloopbackでのみ待ち受け、利用者が明示設定したSSH port-forward等を経由してmacOS側から照会します。Windows実機でのproducer動作は未検証です。READMEはpluginコードの自由な利用・改変を記載していますが、TMIDI Player本体の条件は別です。第三者C++は転載していません。

### TMIDI `.plugin` の実装・設定

```sh
bash engines/plugin-native/build_tmidi.sh build/plugin-ports/tmidi-msg.plugin
PYTHONDONTWRITEBYTECODE=1 python3 engines/plugin-native/test_tmidi.py
```

初回の再生中曲を抑止し、停止後の同曲再生・曲変更でScriptを返し、pause/resumeでは重複通知しません。複数instanceの同時変更も後続pollで届けます。元の `sstp_sample.txt`、WRD区分、`$title` / `$format` を扱います。OnMenuExecとその他イベントは元実装と同じく内容を返しません。

`Resources/tmidi-bridge.json` に `{ "port": 50002 }` を利用者が設定するか、Ourinプロセスの `OURIN_TMIDI_BRIDGE_PORT` で明示指定します。既定は未設定503です。接続先は必ず127.0.0.1、全体2秒・応答1MiB・32instanceを上限にします。Windows producerはDDEの読取queryだけを実行し、任意コマンドやDDE Execute/Pokeを受け付けません。ネットワーク公開やファイアウォール変更は行いません。

[接続手順・JSON契約・制約](tmidi-bridge.md)を参照してください。生成bundleには独自producerと同説明も同梱します。実TMIDIで動くにはWindows側の検証・TMIDI Player・明示した接続が必要です。生成に成功したことと、Windowsからの実曲名取得成功は区別します。

## 検証結果と未確認範囲

`python3 engines/plugin-native/test_native.py`: **6テストPASS、0失敗**。

`PYTHONDONTWRITEBYTECODE=1 python3 engines/plugin-native/test_tmidi.py`: **6テストPASS、0失敗**。macOSの実dylibと合成TCP producerの往復で、状態遷移・複数instance・テンプレート・不正応答・未接続を検証しました。Windows producerのquery制限／エラー伝達を検証し、非WindowsでDDEを偽装して起動しないことも確認しました。合計12テストです。

- Universal 2 dylibをビルドし、別のPythonプロセスから実際にロードしてSAORI要求・応答を確認。
- 不正書式、重複ヘッダ、不正UTF-8、未知の実行対象を拒否。
- 日本語・話者タグ・LF複数行を含むTCPパケットをローカル受信socketの全バイトと照合。
- 接続拒否を503として伝達し、成功Resultを返さないことを確認。
- タイトルのエスケープ／改行除去を別のネイティブ実行体で確認。
- 実Accessibility API呼出は `503 focused_application_unavailable`。この環境で前面ウィンドウのタイトル取得成功は**未検証**。ユーザーの画面タイトルはログへ出力していません。

この試験は合成したSAORI入力によるbackend検証です。元配布辞書→YAYA→SAORI→外部サービス→実音声という全経路の検証は別に記録します。実際の棒読みちゃんの発声、CeVIO/AIVOICE、TMIDI PlayerのDDE、Ourin GUI入力欄とDBdiaryの往復は、この6テストの成功範囲に含めません。x86_64はUniversalのビルドを確認したもので、このテスト実行環境でのIntel実機動作を意味しません。

## ライセンスと一時資料

今回追加したbackendと試験コードはOurinのApache-2.0に従う独自コードです。本文はリポジトリの文書ライセンスCC BY-SA 4.0に従います。公開ソースはインターフェースと依存の照合に使用し、第三者ソース・辞書・素材・Windowsバイナリはコミット対象にしていません。今回の調査用テキストと専用一時build出力は削除済みです。必要な生成成果物は `build/plugin-ports/` に残しています。別担当が継続使用している検証用配布物はその担当の後処理対象です。

## 灯（Akari）作品の空メニュー修正

[灯の作者資料](https://le.silk.to/akari.php)の `_eventdict` と `_customrequest` の説明を照合しました。イベント辞書に値がなければ文字列へ変換して空判定し、イベント関数を呼びます。移植エンジンは宣言した型を初期化時に失い、`nil` と空文字列を区別したため、この経路を飛ばしていました。

`engines/additional/akari-values.patch` は型情報を初期化時の既存castへ渡し、組込イベント辞書と単独辞書要素の登録を実装します。また、`_customrequest` が空Scriptを返した場合にイベントを再実行するfallbackを除去し、作品が意図した初回空応答を保ちます。既存parserは型別の未初期化既定値を持っていたため、その規則自体は追加・置換していません。全言語機能やWindows依存を新たに実装したものではありません。

```sh
python3 engines/additional/test_akari_values.py
# 明示取得した未改変配布辞書があるときだけ実作品テストを有効化
python3 engines/additional/test_akari_values.py --fixtures /path/to/plugin-fixtures
```

2026-10-25: **5テストPASS、0失敗、0skip**（自作4回帰＋実3作品を含む1回帰）。`ukaten` は設定メニュー、`ukadonyu` / `sudohaikuyu` は初回空・2回目起動Scriptを確認しました。元辞書を書き換えず、状態保存は別一時ディレクトリ、HTTPは自作の固定JSONで置換しています。実際の気象API、SSTP、SAORI、GUI操作や作品全機能の成功を意味しません。fixture省略時は実作品の1テストが明示skipになります。

`bash engines/additional/build.sh` でUniversal 2を再生成し、`libakari.dylib` のarm64/x86_64とad-hoc署名を確認しました。TMIDIのbundleも最終生成時のad-hoc署名を追加し、厳密署名検査と6回帰を通過しています。

## Windows音声プラグインの再判定

追加検証では、プラグイン内のEXECUTE/EXECUTE_WAITをhostへ接続し、明示mapのない外部プログラムを拒否します。CeVIO-TalkerとSSP-AIVOICEはload時に必要なWindows helperを起動できないため、以前のload成功判定を訂正しました。専用API・named pipeを含むWindows bridgeは残件です。

apxxxxxxe/Bouyomiはproxy_ex.dllの`/charset`・`core.exe -l/-count/-hash`、外部実行の`-e/-g/-v`を使います。[音声一覧](https://github.com/apxxxxxxe/Bouyomi/blob/dd917482a00ba5200e0d833c29126af570b7401c/core/data/voice.go)はWindows SAPI/registry、voice設定は元YAYAテキスト保存に依存します。NightWork向けSendTalkの実装だけでは互換になりません。下記の追加実装で標準音声の限定TCP経路を確認しました。SAPI音声、Windowsプログラムの起動、旧設定の移行は残件です。

UGMの限定HTTP helperと実配布物での結果は[プラグイン一覧](plugin-ports.md#ugmの追加対応と検証範囲)へ。


## Bouyomiの限定TCP対応（追加検証）

`generate.py --bouyomi-tcp-backend` で明示した場合に、`proxy_ex.dll` の `/charset` と `core.exe -l/-count/-hash`、`EXECUTE(core.exe, -e/-g/-v)` をOurin側の限定実装へ接続します。元Goソースは転載せず、元YAYA辞書も変更しません。

- 起動設定が空の `-e` は、起動対象なしとして完了します。非空のWindowsプログラムパスは拒否し、実行したようには扱いません。
- 音声一覧は棒読みちゃんの標準0–8です。Windows SAPI音声は提供しません。`JapaneseOnly` は上流のSAPI列挙に対する絞り込みなので、この標準一覧には影響しません。
- `-count` はホストのメニューイベントで受け取った対象ゴーストの `ghost/master/descript.txt` だけを読みます。symlinkによる範囲外参照と応答ヘッダーへの制御文字混入は拒否します。
- 元の声質選択イベントから保存したOurin形式の設定を読み、話者ごとの音声番号をTCP packetへ反映します。旧YAYAテキスト保存の移行は未対応です。
- 接続先はloopbackの50001番（明示的な検証用設定は `OURIN_BOUYOMI_PORT`）。実行ファイルやshellへ入力を渡しません。接続できない場合やSAPI音声指定は失敗になります。

配布物の元辞書3件を保持したまま、2周のload・version・メニュー・音声選択・unload/reloadを検証しました。未設定の標準音声、保存したscope 0/1の音声番号、quicksection除外、日本語本文を合成receiverが受け取る実socketで照合しました。発声イベントの204はScriptなしの正常応答で、packetの実受信を別に検査しています。

この結果は棒読みちゃん実機の音声再生、全Sakura Script構文、Ourin GUI、Intel実行の確認ではありません。Windows音声エンジンやCeVIO/AIVOICEの依存は残ります。[変換結果一覧](plugin-ports.md)も参照してください。
