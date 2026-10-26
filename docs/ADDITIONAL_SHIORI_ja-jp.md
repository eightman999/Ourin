# 追加 SHIORI 互換エンジン

更新: 2026-10-25。対象は開発版です。公開済み v0.0.1.21 のバイナリには、この追加7栞は含まれません。

Ourin は灯・ese-shiori・偽栞・忍・翡翠・結奈・美坂の macOS 向け互換実装を同梱します。[opera7133/utatane-modules](https://github.com/opera7133/utatane-modules) の MIT ライセンスによる独立した実装を、帰属表示付きの依存ライブラリとして使用しています。元の Windows DLL そのものではなく、全機能・全ゴーストの完全互換は保証しません。結奈は実験的対応です。

| 栞 | `descript.txt` の指定 | 同梱ライブラリ | 辞書の主な入力 | 新規状態ファイル |
| --- | --- | --- | --- | --- |
| 灯 | `shiori,akari.dll` | `libakari.dylib` | `.txt` / `.azr` | `akari-vars.json` |
| ese-shiori | `shiori,ese-shiori.dll` | `libese-shiori.dylib` | `eseai.ini` / `eseai_*.txt` | `ese-shiori-state.json` |
| 偽栞 | `shiori,niseshiori.dll` | `libniseshiori.dylib` | `ai*.txt` / `.dtx` | `nise-shiori-state.json` |
| 忍 | `shiori,shino.dll` | `libshino.dylib` | `ai*.txt` | `shino-state.json` |
| 翡翠 | `shiori,hisui.dll` | `libhisui.dylib` | `hisui_base/*.tlk` など | `hisui-state.json` |
| 結奈（実験的） | `shiori,yuhna.dll` | `libyuhna.dylib` | `dic.ydf`（YDF/1.07） | `yuhna-state.json` |
| 美坂 | `shiori,misaka.dll` | `libmisaka.dylib` | `misaka.ini` / 辞書 | `misaka_vars.json` |

通常の SHIORI 選択から native runtime へ接続します。`shiori\akari.dll` のような指定では、その DLL が本来存在するサブフォルダを `loadu` に渡します。ライブラリが置かれるアプリの Frameworks フォルダを辞書ルートにはしません。既存の macOS モジュールがある場合はそちらを優先します。`nise-shiori.dll` も偽栞の別名として認識します。曖昧な `shiori.dll` や `ai*.txt` だけから、この追加7栞のどれかを推測しません。

状態ファイルは既定で辞書フォルダに保存します。上流互換の環境変数 `UTATANE_GHOST_STATE_DIR` が明示されている場合はその絶対パスが優先されます。Ourin 自身はこのプロセス全体の環境変数をゴーストごとに切り替えません。Windows 版の保存データからの全面的な移行は未検証です。

## ソースとライセンス

- 固定 revision: `d0cc4cfa3d06aade166363d3864b56e750852328`
- `git archive REV native LICENSE` の SHA-256: `613ca0cf0b02d68062cc66f3d743620ebdacb8c0e7c0cbcc6dbbec0c702c4054`
- [固定版 MIT ライセンス](https://github.com/opera7133/utatane-modules/blob/d0cc4cfa3d06aade166363d3864b56e750852328/LICENSE): Copyright (c) 2026 opera7133
- Ourin の変更: `native/Package.swift` の最低 macOS バージョンを 14 から 13 へ変更するパッチのみ。
- 元 Windows 版のライセンスと、この独立互換実装のライセンスは別です。Ourin 本体の Apache-2.0 ライセンスも変更しません。

`engines/additional/build.sh` が取得した固定 commit のアーカイブをハッシュ照合し、パッチ適用後に SwiftPM で arm64 / x86_64 をソースからビルドします。カタログの macOS 14 向け既成バイナリは使いません。7ライブラリは `OurinShioriABI=ukagaka-int32` を明示し、32ビット長の `loadu/load/request/unload` と malloc/free の所有権規約で読み込みます。

`engines/package.sh` がアプリの Frameworks に署名したライブラリ、Resources/EngineMetadata に ABI 宣言、Resources/EngineLicenses に MIT 全文・帰属 NOTICE・固定版一覧を組み込みます。開発用の出力ディレクトリにはバイナリの `SHA256SUMS` も作成します。

## 検証と残件（2026-10-25）

`engines/additional/verify.py` は Ourin が作成した最小辞書を一時フォルダにコピーして実ライブラリを検証します。灯・ese-shiori・偽栞・忍・翡翠・結奈の6種について、次を arm64 と Rosetta x86_64 の両方で確認しました。

- 日本語を含む辞書パスから `loadu`、OnBoot、OnAITalk、OnClose、未定義 NOTIFY の 204 応答。
- 辞書の構文で変数を 37 に変更し、保存ファイル生成後に unload。
- 別プロセスで再ロードし、OnBoot や代入イベントを送る前の OnRecall が保存済みの 37 を返すこと。
- 二重 load が拒否されても先にロードしたセッションの状態を破壊しないこと。元の fixture 辞書が書き換わらないこと。

全7ライブラリの14アーキテクチャ slice の最低 OS は `vtool` で `13.0` を確認しました。実行環境は macOS 26.6.2、Swift 6.3.3 です。macOS 13 実機および Intel Mac 実機での動作確認とは区別します。

アプリ経路の回帰試験は `AdditionalShioriEngineTests`（in-process / 実 XPC / 通常 factory / 保存再ロード / 二重 load の状態保護）と `MisakaEngineTests` にあります。関連6 suiteは59テスト・99実行、失敗0。[実行結果](SHIORI_EXPANSION_VERIFICATION_2026-10-25.md)を参照してください。新7栞での配布ゴーストの実画面、SAORI、全辞書構文、Windows 版との応答比較、保存形式の移行は未検証です。

上流の標準 ABI 実装はエンジンごとにプロセス内 singleton を使います。同じライブラリを同じプロセスへ二重にロードすると2つ目は失敗します。Ourin の XPC は接続ごとにセッションを持ちますが、接続ごとに独立 PID が与えられるとは限りません。従って同じ栞を使う複数ゴーストの同時実行は対応済みとは扱いません。別の追加栞を同時使用する場合も、今回の単独エンジン検証だけで全面保証はしません。

再現コマンド:

```sh
bash engines/additional/build.sh
python3 engines/additional/verify.py --output /tmp/ourin-additional-results.json
arch -x86_64 /usr/bin/python3 engines/additional/verify.py --output /tmp/ourin-additional-x86-results.json
```
