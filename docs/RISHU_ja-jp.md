# 里珠 (Rishu/Proxy) 接続

[English](RISHU_en-us.md) · 更新: 2026-10-25

[使い方ガイド](https://furinlab.com/ourin/guide/) · [公開ドキュメント](https://furinlab.com/ourin/docs/) · [対応状況・互換性](https://furinlab.com/ourin/compatibility/)

2026-10-25 時点でこの機能は開発版に実装済みで、公開配布版には未収録です。

Ourin 開発版は `shiori,rishu_proxy.dll` を里珠の Perl 外部プロセスへ接続します。実験的対応です。ゴーストに同梱された `rishu_remote.pl` と、そのスクリプトが必要とする Perl モジュールが必要です。Windows の `rishu.dll` を直接実行する機能ではありません。

## 配置と実行環境

`rishu_proxy.dll` の位置として指定されたディレクトリに `rishu_remote.pl` を置きます。上流 1.1.32 のサンプルは隣接する `lib/Rishu/Remote.pm` などを読み込みます。元の配布構成を保持してください。

Perl は既定で `/usr/bin/perl` を使います。これは Ourin に同梱されたランタイムではなく、利用環境に存在する必要があります。別の Perl を使う場合は、Ourin 起動環境の `OURIN_RISHU_PERL_EXECUTABLE` に実行可能ファイルの絶対パスを指定します。古いゴーストが要求するモジュールの互換性は、その Perl 環境にも依存します。

Ourin はシェルや Windows 向け `rishu_proxy.ini` のコマンドを実行せず、`Perl rishu_remote.pl --port <一時ポート>` を引数に分けて起動します。スクリプトや辞書を自動書換えしません。

## 通信と終了

- Ourin が `127.0.0.1` のみで一時 listener を作成します。公式 `--port` モードの子プロセスは `INADDR_LOOPBACK` に接続するクライアントです。外部インターフェースには公開しません。
- `PROXY LOAD/REQUEST/UNLOAD/EXIT RISHU/1.1` と `Original-Response`、`Content-Length` を扱います。SHIOLINK の `*L/*S/*U` とは別のプロトコルです。
- SHIORI 電文は既定 Shift_JIS。`shiori.encoding` / `shiori.force_encoding` による UTF-8 も扱い、`shiori.escape_unknown` を反映します。LOAD のディレクトリ文字列は Shift_JIS で表現できる必要があります。
- 起動・要求に期限を設け、フレームを最大 1 MiB に制限します。不正な応答、接続失敗、タイムアウトではセッションを無効化し、起動した子プロセスを終了・回収します。正常終了時は UNLOAD と EXIT を送ります。
- 子がさらに作る孫プロセスや、スクリプト固有のファイル保存はそのエンジン側の責任です。

## 確認済み範囲

2026-10-25、[公式 1.1.32 配布](https://www.mikage.to/PerlShiori/snap/rishu-1.1.32.tar.gz) の未改変 `rishu_remote.pl` と実 Swift adapter を接続し、LOAD、Content-Length 付き応答、GET/NOTIFY、Shift_JIS の日本語 Reference、UNLOAD、EXIT、PID 回収を確認しました。公式サンプルは要求を echo するプログラムで、人格ゴーストの会話検証ではありません。Nayuki などの配布ゴースト全体の互換性は未確認です。

公式ソースを展開したディレクトリから再現できます。スクリプトは一時コピーを使用し、ソース元を変更しません。ダウンロードや Perl の導入は行いません。

```sh
python3 scripts/verify_external_shiori.py rishu /path/to/rishu-1.1.32
```

`RishuProxyTests` は実 Perl プロセスで、通常応答、UTF-8 / Unicode escape、起動待ち、ハング、切断、不正長、過大応答と子プロセス回収を検証します。

## 一次資料

- [作者の配布・説明ページ](https://www.mikage.to/PerlShiori/)
- 上記配布の `lib/Rishu/Remote.pm`、`rishu_remote.pl`、`rishu_proxy.txt`

上流ファイルや第三者ゴーストは Ourin リポジトリに再配布していません。
