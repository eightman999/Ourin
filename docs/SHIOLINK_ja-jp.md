# SHIOLINK 外部プロセス接続

[English](SHIOLINK_en-us.md) · 更新: 2026-10-25

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

`arguments` はJSON文字列配列です。Nodeのパス・スクリプト名・辞書ディレクトリは導入した実環境に合わせてください。実行環境やnpmパッケージを自動インストールしません。

共通設定の `commandline` も、引用符でまとめた引数として解釈します。

```ini
[SHIOLINK]
commandline=/opt/homebrew/bin/node "./engine/main.js"
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
