# CeVIO・A.I.VOICEプラグインのローカルTTS互換

確認日: 2026-10-25。開発版のOurinでは、CeVIO-TalkerとSSP-AIVOICEの元辞書を変更せず、Irodoriによるローカル音声合成へ接続できます。声選択・ゴーストへの割当・設定保存を元のプラグインメニューで扱います。CeVIO・A.I.VOICE製品の音声ライブラリやWindowsエディタを起動する機能ではなく、声はIrodori独自のものです。

[15プラグインの標準port検証](plugin-ports.md)に記録したロード成功13/15は、その条件での結果として保持します。本ページの追加条件では、明示的にローカルTTSを選んだ **2/2** のロード、元メニュー、設定復元、実MLX音声生成と再生プロセスの正常終了を確認しました。全ゴースト・全機能の完全互換率を表す数値ではありません。

## 対象と配布元

元プラグインは作者の配布物を別途入手してください。次のリンクはOurin変換版の再配布ではありません。

|プラグイン|確認した版|配布元・ダウンロード|生成時の指定|
|---|---|---|---|
|ukagakaPlugin_CeVIO-Talker / ambergon|version1.0.7|[作者・release](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/tag/version1.0.7) · [NAR](https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/download/version1.0.7/ukagakaPlugin_CeVIO-Talker.nar)|`--local-tts-backend cevio`|
|SSP-AIVOICE / wamo / opera7133|v1.0.2|[作者・release](https://github.com/opera7133/SSP-AIVOICE/releases/tag/v1.0.2) · [NAR](https://github.com/opera7133/SSP-AIVOICE/releases/download/v1.0.2/AIVOICE.nar)|`--local-tts-backend aivoice`|

同名の別バージョン、CeVIO-Talker V2、製品APIを直接使う独自ゴーストは、この2本の検証には含めません。元辞書・Windows DLL・音声モデルはOurinのリポジトリやWebページへ転載していません。

## 必要な環境

確認環境はApple M2 Max・32 GBメモリ、macOS arm64、Python 3.13.11、mlx-audio 0.6.1、MLX 0.32.4です。Python実行環境、FFmpeg、開発版Ourinのソースとビルド環境が必要です。現時点ではモデル取得から起動までを自動化したアプリ内インストーラはありません。

モデルは [mlx-community/Irodori-TTS-v4.1-Small-MF-fp16](https://huggingface.co/mlx-community/Irodori-TTS-v4.1-Small-MF-fp16)、revision `db0263236d010d4beb6ca67c529f410a6f71d755` を使用します。固定snapshotは約1.98 GB、検証したPython環境は約461 MiBでした。音声キャッシュ用の空きも必要です。モデルの配布条件は[上流モデルカード](https://huggingface.co/Aratako/Irodori-TTS-v4.1-Small-MF#-license--ethical-restrictions)を参照してください。

以下のコマンドはOurinのリポジトリrootで実行します。モデルは共有ディレクトリを参照し、各プラグインに複製しません。

```sh
python3.13 -m venv build/tts-runtime
build/tts-runtime/bin/python -m pip install -r engines/tts/requirements-lock.txt
build/tts-runtime/bin/python engines/tts/download_model.py \
  --destination "$HOME/dev/data/models/irodori-tts-v4.1-small-mf-fp16"
```

取得スクリプトは固定revisionとファイルのSHA-256を確認します。既存の保存先がある場合は検証し、不一致を上書きして修復しません。検証用の依存情報は `engines/tts/DEPENDENCIES.json` に記録しています。

## 音声サービスの起動

FFmpegをPATHから実行できる状態で、Ourinの起動前に次を実行します。

```sh
build/tts-runtime/bin/python engines/tts/server.py \
  --python build/tts-runtime/bin/python \
  --model "$HOME/dev/data/models/irodori-tts-v4.1-small-mf-fp16" \
  --work-dir build/tts-runtime/audio
```

標準出力に `"ready": true` が出たら準備完了です。サービスは `127.0.0.1:50731` だけで待ち受けます。プラグインは起動済みサービスを確認するため、準備前にOurinを起動するとロードに失敗します。その場合はサービス準備後にOurinを再起動してください。サービスを終了するときは起動したターミナルでCtrl+Cを押します。

ポートを変更する場合はサーバーの `--port` と、Ourinプロセスへ渡す環境変数 `OURIN_LOCAL_TTS_PORT` を同じ値にします。既定ポートなら環境変数は不要です。`--no-play` はWAV生成だけを行う検証用オプションで、読み上げには指定しません。

モデルは起動時に一度ロードし、合成時はローカルのモデル・tokenizer・codecだけを使います。各声の初回発話時に基準となる短い参照音声を生成し、`work-dir/references/` に保存します。このディレクトリを保持すると再起動後も参照音声を再利用できます。同じ文章・設定の音声キャッシュはサービスが管理します。

## 元プラグインから `.plugin` を作る

NARを独立したディレクトリへ展開し、`descript.txt` がある場所を `source_dir` に指定します。`output_bundle` は未作成の `.plugin` パスにしてください。次はCeVIO-Talkerの例です。

```sh
bash yaya_core/build.sh
bash engines/plugins/build.sh
python3 engines/plugins/prepare_collector.py --output-dir build/plugin-collector

source_dir="/path/to/extracted/CeVIO-Talker"
output_bundle="/path/to/new/CeVIO-Irodori.plugin"
python3 engines/plugins/generate.py \
  --source "$source_dir" --output "$output_bundle" --engine yaya \
  --adapter build/engines/plugins/OurinYayaPlugin.dylib \
  --helper yaya_core/build/yaya_core \
  --collector build/plugin-collector/yaya_plugin_collector \
  --source-url "https://github.com/ambergon/ukagakaPlugin_CeVIO-Talker/releases/tag/version1.0.7" \
  --local-tts-backend cevio
```

SSP-AIVOICEでは展開元と未作成の出力先を変更し、`--local-tts-backend aivoice` と[確認したreleaseのURL](https://github.com/opera7133/SSP-AIVOICE/releases/tag/v1.0.2)を指定します。ローカルTTS指定と、他のSAORI・Bouyomi・UGM backend指定は同時使用できません。

生成物には元のpayloadが含まれます。自分の環境で使用するコピーとして扱い、元データや既存設定を上書きしない場所に作成してください。保存状態は生成物内の `Contents/Resources/state/yaya-variables.json` へ書き込みます。元製品で使っていた旧設定ファイルの自動移行は行いません。

Ourin終了中に、生成した `.plugin` をOurinのリソース保存先の `plugin/` フォルダへ配置し、音声サービス準備後にOurinを起動します。現実装の通常保存先は書類フォルダの `Ourin/plugin/`（通常は `~/Documents/Ourin/plugin/`）です。書類フォルダが利用できない場合はApplication Supportの `Ourin/plugin/` にフォールバックします。互換検索先としてApplication Supportの `Ourin/PlugIns/` も走査します。Sandbox版では書類・Application Supportがコンテナ内へ解決されるため、実際に使用中のOurinリソース保存先を確認してください。同じプラグインIDの古いコピーがある場合は、どちらを使うか確認し、設定を保全してから整理してください。

## 声と読み上げ対象の設定

1. Ourinで対象プラグインのメニューを開きます。元メニューの「インストール済み」にはIrodoriの声が表示されます。
2. `IrodoriAkari`（明るい女性声）、`IrodoriAoi`（落ち着いた男性声）、`IrodoriNagi`（柔らかい中性声）から選びます。
3. 「喋らせる対象」で、ゴースト切替メニューに表示される名前を設定します。「設定していないゴーストに対する読み上げ」では既定の声、または「読み上げない」を選べます。
4. 元の設定画面から音量・速度などを調整します。設定はOurin側の保存領域へ保存され、再ロード後も維持します。

**同じゴーストには通常どちらか一方の音声プラグインを割り当てます。** CeVIO用とAIVOICE用の両方に割り当てると、それぞれが同じ発話を要求するため、重複読み上げや待ち時間が発生します。

声の割当は元プラグインと同じく**ゴースト名単位**です。scope 0・1などのキャラクター別割当を、この2本の機能として追加してはいません。元辞書が `OnOtherGhostTalk` のSakura Scriptを読み上げ本文へ変換し、その本文と設定を音声サービスへ渡します。

## パラメータの扱い

数値を受け付けることと、製品と同じ声になることは区別します。

|設定|実際の処理|互換性の範囲|
|---|---|---|
|CeVIO Volume、AIVOICE Volume|FFmpegで音量を変更し、リミッターを適用|ゼロで無音。CeVIOは50を倍率1とし、製品固有の音量曲線までは再現しない|
|CeVIO Speed/Tone、AIVOICE Speed/Pitch|DSPで速度とピッチをそれぞれ反映|AIVOICEは指定倍率。CeVIOは50を中立、0〜100を倍率0.5〜2へ変換する近似|
|AIVOICE MiddlePause/LongPause|句読点・改行で分割した音声の間に指定ミリ秒の待ちを追加|指定範囲を検証。合成音声にも自然な間が入るため、聞こえる総ポーズ長の厳密一致は保証しない|
|CeVIO Alpha|声の明るさをIrodoriの文章指示へ変換|近似。声道・声質パラメータの数値等価性は未検証|
|CeVIO ToneScale、AIVOICE PitchRange|抑揚の強さを文章指示へ変換|近似。数値に比例した変化や製品との一致は未検証|
|CeVIOの喜び・怒り・悲しみ、AIVOICE StyleJ/A/S|感情と強さを文章指示へ変換|近似。感情の可聴変化・混合比の再現性は聴感評価が必要|

CeVIOの感情一覧は3項目を返します。任意の製品voiceの全感情セットを提供するものではありません。未知の声・範囲外の値・不正な要求を成功として受け付けません。

新しい発話は、同じプラグインsessionの旧発話を置き換える設計です。unload時も待機中の発話と再生を停止し、古い生成結果を後から再生しません。GPU処理の途中停止は協調キャンセルなので、そのGPU演算がPythonへ戻るまで待つ場合があります。下記では、実証した層と追加確認が必要な層を分けています。

## 実音声経路の再検証

サービスを再生有効で起動し、次の2つの変換済みbundleを `--source-root` の直下に用意します。

- `ukagakaplugin-cevio-talker.plugin`
- `ssp-aivoice.plugin`

```sh
python3 engines/tts/verify_plugins.py \
  --source-root build/plugin-ports \
  --port 50731 \
  --output build/local-tts-live-results.json
```

この試験はbundleの使い捨てコピーを使い、2回のロード・設定復元・実音声再生、発話の置換、再生中のunload停止を検証します。再生停止の試験があるため `--no-play` のサービスでは完了しません。元bundleの辞書は書き換えません。出力はローカルパス・sessionを含む詳細記録です。Web公開用の `local-tts-results.json` はそこから検証メタデータだけを抜粋したもので、詳細記録をそのまま公開していません。

## 確認した結果と残件

元CeVIO-Talker・SSP-AIVOICEをそれぞれ使い捨てコピーで2回ロードし、元辞書のSHA-256不変、メニュー表示、選んだ声・設定の再ロード後の維持を確認しました。CeVIO側はIrodoriAkari、AIVOICE側はIrodoriAoiを使い、元プラグインの発話イベントから実MLXの48 kHz WAV生成、DSP、`afplay`の正常終了まで実行しています。

サービスがreadyを返した後、今回の短い試験文の初回音声生成・DSP完了までの時間はCeVIO経路約3.10秒、AIVOICE経路約1.35秒でした。これはコールド起動時間や全文章の速度保証ではありません。再ロード後の同文はキャッシュが使われるため、初回生成と同じ性能測定として比較しません。

worker単独では、生成中キャンセルから約0.43秒でキャンセル応答が返り、同一プロセスで次の実音声生成に成功しました。キャンセル対象の出力・一時WAVが残らないことも確認しています。追加の元プラグイン試験では、両製品の経路で旧発話のキャンセルと新発話の再生完了、再生中のunloadによる停止を確認しました。今回のunload停止はCeVIO経路約3.4 ms、AIVOICE経路約5.9 msでした。固定時間以内の停止保証ではありません。

自動回帰では、ローカルTTS adapter 9件、YAYA core 38件、既存YAYA adapter 11件、Bouyomi adapter 10件、Irodori worker 13件、音声サービス6件が成功しました。Xcodeの関連検証は19集計テスト、失敗0です。元2プラグインの設定・発話要求・保存再ロードに加え、不正要求・サービス不在・タイムアウトも検証しました。

実際に起動したOurinでも、SSTPによる通常の発話を元プラグインへ配送し、実MLX合成から `afplay` の正常終了までCeVIO・AIVOICEの両経路で確認しました。これはアプリ内の発話経路を実行した結果であり、全メニュー・入力欄を手操作して確認したという意味ではありません。[機械可読の検証結果](local-tts-results.json)には、配布元・モデルrevision・辞書ハッシュと検証範囲を記録しています。

残る確認事項は、Ourin実GUIの全メニュー・入力欄の手操作、各ゴーストの通常会話を含む網羅的な操作、製品との聴感比較、固有名詞などの読み精度、各感情・声質値の出音への反映、Intel Mac、上記以外のCeVIO/A.I.VOICE依存ゴースト／プラグインです。モデル・推論サービスはアプリへ標準同梱されていません。

[プラグイン全体の変換一覧](plugin-ports.md) · [元Windows依存とmacOS backendの照合](plugin-native.md)
