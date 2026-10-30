# SHIOLINK 外部プロセス接続

[English](SHIOLINK_en-us.md) · 更新: 2026-10-30

[使い方ガイド](https://furinlab.com/ourin/guide/) · [公開ドキュメント](https://furinlab.com/ourin/docs/) · [対応状況・互換性](https://furinlab.com/ourin/compatibility/)

Ourinの開発版は `shiori,SHIOLINK.dll` をSHIOLINK外部プロセスへ接続します。[SHIORIエンジンプラグイン](SHIORI_ENGINE_PLUGINS_ja-jp.md)には、対応エンジンと必要な実行環境を同梱します。対応する `.plugin` を導入する場合、Node.js・Ruby・Python・.NETを別途インストールする必要はありません。以下は実行環境を自分で指定する手動設定の説明です。Windows DLLの実行やMiyoJSの全辞書互換性を保証するものではありません。

## 設定

DLLが置かれるディレクトリ（通常 `ghost/master`）の `SHIOLINK.ourin.ini` を優先し、存在しないときだけ `SHIOLINK.INI` を読みます。ファイル名とキーは大文字小文字を区別しません。設定ファイルは64 KiBまで、UTF-8またはShift_JISです。優先ファイルが不正なときに共通設定へ切り替えることはありません。

Ourin用設定では実行ファイルと引数を分けられます。

```ini
[SHIOLINK]
executable=/opt/homebrew/bin/node
arguments=["./node_modules/miyojs/bin/miyo-shiolink.js", "./dic"]
charmode=UTF-8
```

この例は実npm配布 `miyojs@2.0.3` で検証した設定です。`bin/miyo-shiolink.js` が実在する起動スクリプトで、次の引数 `./dic` を辞書ディレクトリとして読み込みます。

`arguments` はJSON文字列配列です。Nodeのパス・スクリプト名・辞書ディレクトリは導入した実環境に合わせてください。手動設定で実行環境やnpmパッケージを自動インストールすることはありません。

共通設定の `commandline` も、引用符でまとめた引数として解釈します。

```ini
[SHIOLINK]
commandline=/opt/homebrew/bin/node "./node_modules/miyojs/bin/miyo-shiolink.js" "./dic"
charmode=UTF-8
```

実行は `Process.executableURL` と `arguments` を使い、暗黙のシェルを挟みません。引用符の入れ子・エスケープ構文、環境変数展開、パイプ、リダイレクトは扱いません。複雑な引数にはJSON形式を使ってください。Windows形式の実行ファイル名（`.exe`、`.cmd`等）は拒否します。相対パスと作業ディレクトリはDLLのディレクトリが基準です。単独の実行名は同ディレクトリ、`/opt/homebrew/bin`、`/usr/local/bin`、`/usr/bin`、`/bin`の順で探します。

外部プロセスはOurinの実行権限を引き継ぎます。専用の追加サンドボックスやSAORIの自動中継はありません。

## 元のモジュール名を維持する

`SHIOLINK.ourin.ini` に `module=phiori.dll` 等を追加すると、`descript.txt` のWindows用モジュール名を維持したまま、その移植版を選べます。指定はDLLのファイル名（大文字小文字を区別しない）に一致する場合だけ有効です。相対サブディレクトリなら対象DLLと同じ場所に設定します。共通の `SHIOLINK.INI` への `module` 指定は拒否し、指定のない別DLLへは適用しません。

対応する導入済みプラグインを自動選択する場合は、手動の `module` 設定を追加する必要はありません。

## 通信と失敗時の動作

- `*L:ディレクトリ` に続いて `version` 要求を送り、応答まで確認します。SHIOLINKにはload専用の成功応答がないため、これは通信の確認であり、辞書全体の正常性の保証ではありません。
- 各要求で一意な `*S:識別子` のエコーを照合し、SHIORI電文を送ります。通常のGET/NOTIFYは同じ経路です。
- `*U:` 後に正常終了を待ち、終了しない直接の子プロセスにはTERM、続いてKILLを送って回収します。
- 手動設定の初期化は既定5秒。プラグインで指定する初期化期限は別に扱い、今回のscript/.NETパッケージは30秒、phioriは60秒です。要求は呼出元指定（最大60秒）。期限は送信・同期・受信を合わせた時間です。同期違反、EOF、応答不正、期限超過、1 MiBを超える要求／応答ではセッションを閉じます。自動再起動はせず、ゴーストの再ロードで接続し直します。
- `charmode` はUTF-8（既定）とShift_JIS。UTF-16/32は行区切り方式に合わないため拒否します。変換できない送信文字は失敗となります。stderrは蓄積せず破棄します。

SHIORIPROXY、里珠の専用proxy wire、Windows DLL実行はこの機能の対象外です。SHIOLINKプロセスがさらに起動した孫プロセスの管理は、そのエンジン側の責任です。

SHIORI/2.xの成功応答を返すエンジンは、既存の2.x互換処理へ接続します。以後のイベントをEvent等へ変換し、Sentenceを内部Valueへ正規化します。未知eventは204、NOTIFYの200も204になります。明示された `communication.version=SHIORI/2.x` は初期要求から適用します。2.xの通常wireはShift_JISで、UTF-8の強制指定は送信Charsetヘッダーにも反映します。unload時には互換状態をリセットし、3.xのUTF-8経路は維持します。Kanahebiの未変更2.2サンプルで確認しており、すべての旧栞の互換性を保証するものではありません。

## なし栞プラグインのプロセスと保存

`nashi.plugin` は `nashi.dll`、`ghost.json` または `nashi.json` から選択され、SHIOLINK子プロセスをゴーストごとに1つ起動します。別ゴーストの辞書・変数を同じVMへ上書きしません。上流形式の辞書を読み、保存先は `nashi_save.json` です。正常な `*U:` と途中要求のEOFの両方で上流のunload・保存処理を通します。強制終了時まで保存を保証するものではありません。

これは許諾された公式mainの1.0.4-alpha系を使うmacOS移植です。上流のversion応答 `1.0.0` は保持します。Windows用SAORIや編集GUI「なしスタジオ」の実行は含みません。[追加内容と検証記録](SHIORI_ADDITIONS_2026-10-30.md)を参照してください。

## 検証

`ShiolinkTests` は実際にC製のテストプロセスを起動し、Unicode往復、GET/NOTIFY、loadディレクトリ、unload、同期エラー、停止・大量出力・EOF、子プロセス回収、設定の優先順位を確認します。なし栞の並行プロセス・保存・再ロード等は `NashiEngineTests` と `engines/nashi/verify.py` が対象です。実際の配布ゴーストの互換性試験は別途必要です。

## 一次資料

- [ShiolinkJS transport](https://github.com/Narazaka/shiolinkjs/blob/master/lib/shiolink.ts)
- [ShiolinkJS usage](https://github.com/Narazaka/shiolinkjs/blob/master/Readme.md)
- [Sana の SHIOLINK.INI 設定例](https://github.com/Narazaka/sana/blob/master/README.md)

## MiyoJS 実エンジンの確認

2026-10-25、公式npmのMiyoJS 2.0.3、shiolinkjs 1.x、js-yaml 3.14.1と既存のmacOS Node.jsを隔離ディレクトリに用意し、実adapterのLOAD → OnBoot / 日本語・絵文字 / OnClose → UNLOAD・PID回収を確認しました。辞書は最小の検証用YAMLです。MiyoJS 2.0.3は `safeLoad` を使うためjs-yaml 3系が必要で、4系への自動更新には互換性がありません。

作者配布のMiyoPreview NARは配布URLのタイムアウトで取得できず、実配布ゴーストの確認は残っています。追加フィルタや全辞書互換性を確認済みとはしていません。準備済みmasterディレクトリ（Node.jsの設定とnode_modulesを含む）を使う再現コマンドは次のとおりです。一時コピーで実行し、元のディレクトリを変更しません。

### 検証用masterの作成

次の手順はOurinリポジトリのルートで実行します。既存のNode.js・npm・Python 3とXcode Command Line Toolsが必要です。新しい `/tmp` ディレクトリにバージョン固定の依存関係、最小辞書、実行中のNode.jsの絶対パスを使った設定を作成します。既存ゴーストには書き込みません。これは栞接続用の最小サンプルで、シェル等を持つ配布ゴーストではありません。

```sh
# Run from the Ourin repository root; Node.js, npm and Python 3 must be installed.
miyo_master="$(mktemp -d -t ourin-miyo-master)"
npm install --prefix "$miyo_master" --ignore-scripts --no-audit --no-fund --save-exact \
  miyojs@2.0.3 js-yaml@3.14.1 shiolinkjs@1.0.1 shiorijk@0.0.1 es6-promise@2.3.0
mkdir "$miyo_master/dic"
cat > "$miyo_master/dic/main.yaml" <<'YAML'
version: "2.0.3"
OnBoot: \h\s[0]起動。\e
OnClose: \h\s[0]終了。\e
OnUnicode: 桜鈴 🌸
YAML
node - "$miyo_master" <<'JS'
const fs = require('fs');
const path = require('path');
const args = ['./node_modules/miyojs/bin/miyo-shiolink.js', './dic'];
fs.writeFileSync(path.join(process.argv[2], 'SHIOLINK.ourin.ini'),
  `[SHIOLINK]\nexecutable=${process.execPath}\narguments=${JSON.stringify(args)}\ncharmode=UTF-8\n`);
JS
python3 scripts/verify_external_shiori.py miyo "$miyo_master"
```

最後のコマンドは実adapterのLOAD、OnBoot、OnClose、UNLOAD、子プロセス回収を検査します。初回のnpm installが生成した `package-lock.json` を保持すれば、同じmaster内で `npm ci --ignore-scripts --no-audit --no-fund` により依存関係を再現できます。

里珠の専用TCP接続については[里珠ガイド](RISHU_ja-jp.md)を参照してください。

翻訳: Codex。日英内容照合: 2026-10-30。実行結果は各検証レポートを参照してください。
