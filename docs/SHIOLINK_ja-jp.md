# SHIOLINK 外部プロセス接続

[English](SHIOLINK_en-us.md) · 更新: 2026-10-25

[使い方ガイド](https://furinlab.com/ourin/guide/) · [公開ドキュメント](https://furinlab.com/ourin/docs/) · [対応状況・互換性](https://furinlab.com/ourin/compatibility/)

Ourin の開発版は `shiori,SHIOLINK.dll` を SHIOLINK 外部プロセスへ接続します。Windows DLLをロードする方式ではありません。Node.js、RubyなどのmacOS用実行環境と、SHIOLINKを話すエンジンは別途用意します。MiyoJSの全辞書互換性を保証するものではありません。

## 設定

DLLが置かれるディレクトリ（通常 `ghost/master`）の `SHIOLINK.ourin.ini` を優先し、存在しないときだけ `SHIOLINK.INI` を読みます。ファイル名とキーは大文字小文字を区別しません。設定ファイルは64 KiBまで、UTF-8またはShift_JISです。優先ファイルが不正なときに共通設定へ切り替えることはありません。

Ourin用設定では実行ファイルと引数を分けられます。

```ini
[SHIOLINK]
executable=/opt/homebrew/bin/node
arguments=["./node_modules/miyojs/bin/miyo-shiolink.js", "./dic"]
charmode=UTF-8
```

この例は実 npm 配布 `miyojs@2.0.3` で検証した設定です。`bin/miyo-shiolink.js` が実在する起動スクリプトで、次の引数 `./dic` を辞書ディレクトリとして読み込みます。

`arguments` はJSON文字列配列です。Nodeのパス・スクリプト名・辞書ディレクトリは導入した実環境に合わせてください。実行環境やnpmパッケージを自動インストールしません。

共通設定の `commandline` も、引用符でまとめた引数として解釈します。

```ini
[SHIOLINK]
commandline=/opt/homebrew/bin/node "./node_modules/miyojs/bin/miyo-shiolink.js" "./dic"
charmode=UTF-8
```

実行は `Process.executableURL` と `arguments` を使い、暗黙のシェルを挟みません。引用符の入れ子・エスケープ構文、環境変数展開、パイプ、リダイレクトは扱いません。複雑な引数にはJSON形式を使ってください。Windows形式の実行ファイル名（`.exe`、`.cmd`等）は拒否します。相対パスと作業ディレクトリはDLLのディレクトリが基準です。単独の実行名は同ディレクトリ、`/opt/homebrew/bin`、`/usr/local/bin`、`/usr/bin`、`/bin`の順で探します。

外部プロセスはOurinの実行権限を引き継ぎます。専用の追加サンドボックスやSAORIの自動中継はありません。

## 通信と失敗時の動作

- `*L:ディレクトリ` に続いて `version` 要求を送り、応答まで確認します。SHIOLINKにはload専用の成功応答がないため、これは通信の確認であり、辞書全体の正常性の保証ではありません。
- 各要求で一意な `*S:識別子` のエコーを照合し、SHIORI電文を送ります。通常のGET/NOTIFYは同じ経路です。
- `*U:` 後に正常終了を待ち、終了しない直接の子プロセスにはTERM、続いてKILLを送って回収します。
- 初期化は既定5秒、要求は呼出元指定（最大60秒）。期限は送信・同期・受信を合わせた時間です。同期違反、EOF、応答不正、期限超過、1 MiBを超える要求／応答ではセッションを閉じます。自動再起動はせず、ゴーストの再ロードで接続し直します。
- `charmode` はUTF-8（既定）とShift_JIS。UTF-16/32は行区切り方式に合わないため拒否します。変換できない送信文字は失敗となります。stderrは蓄積せず破棄します。

SHIORIPROXY、里珠の専用proxy wire、Windows DLL実行はこの機能の対象外です。SHIOLINKプロセスがさらに起動した孫プロセスの管理は、そのエンジン側の責任です。

## 検証

`ShiolinkTests` は実際にC製のテストプロセスを起動し、Unicode往復、GET/NOTIFY、loadディレクトリ、unload、同期エラー、停止・大量出力・EOF、子プロセス回収、設定の優先順位を確認します。実際のMiyoJSゴーストの互換性試験は別途必要です。

## 一次資料

- [ShiolinkJS transport](https://github.com/Narazaka/shiolinkjs/blob/master/lib/shiolink.ts)
- [ShiolinkJS usage](https://github.com/Narazaka/shiolinkjs/blob/master/Readme.md)
- [Sana の SHIOLINK.INI 設定例](https://github.com/Narazaka/sana/blob/master/README.md)

## MiyoJS 実エンジンの確認

2026-10-25、公式 npm の MiyoJS 2.0.3、shiolinkjs 1.x、js-yaml 3.14.1 と既存の macOS Node.js を隔離ディレクトリに用意し、実 adapter の LOAD → OnBoot / 日本語・絵文字 / OnClose → UNLOAD・PID 回収を確認しました。辞書は最小の検証用 YAML です。MiyoJS 2.0.3 は `safeLoad` を使うため js-yaml 3 系が必要で、4 系への自動更新には互換性がありません。

作者配布の MiyoPreview NAR は配布 URL のタイムアウトで取得できず、実配布ゴーストの確認は残っています。追加フィルタや全辞書互換性を確認済みとはしていません。準備済み master ディレクトリ（Node.js の設定と node_modules を含む）を使う再現コマンドは次のとおりです。一時コピーで実行し、元のディレクトリを変更しません。

### 検証用 master の作成

次の手順は Ourin リポジトリのルートで実行します。既存の Node.js・npm・Python 3 と Xcode Command Line Tools が必要です。新しい `/tmp` ディレクトリにバージョン固定の依存関係、最小辞書、実行中の Node.js の絶対パスを使った設定を作成します。既存ゴーストには書き込みません。これは栞接続用の最小サンプルで、シェル等を持つ配布ゴーストではありません。

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

最後のコマンドは実 adapter の LOAD、OnBoot、OnClose、UNLOAD、子プロセス回収を検査します。初回の npm install が生成した `package-lock.json` を保持すれば、同じ master 内で `npm ci --ignore-scripts --no-audit --no-fund` により依存関係を再現できます。

里珠の専用 TCP 接続については [里珠ガイド](RISHU_ja-jp.md) を参照してください。
