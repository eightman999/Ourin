# KAGARI / もす 実ゴースト検証 — 2026-10-25

## 結果

KAGARI の実ネイティブライブラリで、最小 Lua ゴーストの起動・ダブルクリック・終了・別プロセスからの再ロードと、存在しないパスの load 拒否を確認した。**公開ゴースト『もす』の起動は未完**。LuaSocket、luautf8、luachild、lua-iconv を正規ソースから macOS 向けにビルドして先へ進めたが、`saori_universal.native` が不足し `kagari_load` は `-1` を返す。実ゴーストの OnBoot / 会話 / 終了 / 保存 / 再ロードは成功していない。

検証対象は ctypes から呼び出した実 KAGARI POSIX ABI。Ourin GUI・XPCでの操作を実証した記録ではない。配布 NAR と辞書の Lua ファイルは変更せず、ネイティブ依存は `/tmp` の展開コピーに追加した。ユーザーのインストール済みゴーストには触れていない。

## 実行と証跡

専用 worktree のルートで実行:

```sh
python3 engines/kagari/verify_kagari_mosu.py \
  build/engines/kagari/libkagari.dylib \
  --workdir /tmp/ourin-mosu-verified-20261025
```

結果: **exit 2（実ゴースト互換未完）**。

| 検査 | 結果 |
| --- | --- |
| 最小 Lua: OnBoot / OnMouseDoubleClick / OnClose | PASS、200 と非空 Value |
| 最小 Lua: unload / 別プロセスからの再ロード | PASS |
| 不正な load ディレクトリ | PASS、-1 |
| 正規依存4プロジェクトの macOS ビルド | PASS |
| もす: load | FAIL、`saori_universal.native` 不足 |
| もす: OnBoot / ダブルクリック / OnClose | 未到達 |
| もす: 保存 / 再ロード後の値確認 | 未到達 |
| 元 NAR の SHA256 不変 | PASS |

- JSON結果: `/tmp/ourin-mosu-verified-20261025/summary.json`
- 実ゴースト失敗ログ: `/tmp/ourin-mosu-verified-20261025/ghost-first.log`
- KAGARI: Universal `x86_64 arm64`、今回は arm64 Python から実行
- KAGARI SHA256: `633624e65761feecde7fd079e1c3e74826d7e1732e6dab143d09c70989ba0b56`
- 元 NAR: `/tmp/ourin-real-ghosts-20261025/mosu.nar`
- 元 NAR SHA256（前後一致）: `a663e0a32de13dd28b8b18e7a806f31a764d8e5ead7754f4901dc3838a764688`
- 入手先: [もす配布サイト](https://tatakinov.github.io/mosu/)

## 追加した検証用ネイティブ依存

これらは実ゴースト検証用の一時コピーにのみ配置した。アプリへの同梱・再配布は行っていない。ビルドのソースと各成果物 SHA256 は summary.json に保存。

| 正規ソース | 固定 revision | 出力 |
| --- | --- | --- |
| [LuaSocket](https://github.com/lunarmodules/luasocket) | `95b7efa9da506ef968c1347edf3fc56370f0deed`（v3.1.0） | `socket/core.so`, `mime/core.so` |
| [luautf8](https://github.com/starwing/luautf8) | `a47b1433473a2509d77ad28f59a976716d187927` | `lua-utf8.so` |
| [作者の luachild fork](https://github.com/Tatakinov/luachild) | `efcb09bd6059f5852313bfd431106a75344f4038` | `luachild.so` |
| [lua-iconv](https://github.com/ittner/lua-iconv) | `a94fdb1f6d50c22bb59330df607bb0848d0ba673` | `iconv.so` |

Lua 5.4.4 ヘッダーを使用。luachild は POSIX 実装を選択し、Apple Clang 用に `-include signal.h` を追加した。偽の成功値を返す stub は使っていない。

## 残る障壁

`corelib/saori_basic/init.lua` が `saori_universal.native` を require する段階で停止する。配布 NAR にあるのは Windows DLL。[kotori 上流](https://github.com/Tatakinov/kotori)（確認 revision `f161ffc62a642b67602ffd3bc42097e3885a2b5f`）には `native.so` と `fh/init.so` もあるが、`file` でいずれも **Linux x86-64 ELF** と確認した。この調査範囲では対応するネイティブ実装のソースは見つかっていない。macOS で使用可能な正規実装またはソースを確保し、ABIとライセンスを確認して移植する必要がある。

`fh` も `process` から要求されるため次の候補。後段には lanes/SSL 等の依存が残る可能性があり、現在の1件を解消すれば完全対応するとは断定していない。ゴーストの Lua を書き換えて require を回避する方法は採用していない。

## 検証スクリプトの修正

- 返却ポインタを `c_void_p` で受け、応答を読み取った後に `free`。以前の `c_char_p` による所有ポインタ喪失を修正。
- 各ライフサイクルを独立した子プロセスで実行し、120秒で停止。native load/request の停止にも適用。
- SHIORI 200 と非空 Value を要求し、500、204、空応答、空 Value を成功にしない。
- OnMouseDoubleClick を実行対象に追加。
- もすでは OnMenu による間隔変更（30秒→1分）を行い、終了時の `kagari_save.lua` と、別プロセス再ロード後の「1分」応答を確認する構成。ただし現状は load 失敗のため未到達。
- 元 NAR の前後 SHA256、各工程の JSON、標準出力を保存。
- ZIP 展開パスが検証ディレクトリから外れないことを確認。

検証ハーネス自身について、空応答/500/204/空 Value の拒否、正常200の受理を確認した。無限ループする使い捨て Lua の load を0.5秒のテスト設定で停止し、timeout を FAIL とすることも確認した。最小ゴーストの成功と実ゴースト未完を同じ成功状態にまとめない。
