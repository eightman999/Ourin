# KAGARI 実配布ゴーストの macOS 対応（2026-10-25）

開発版の KAGARI ホストに不足していた Lua native module を追加した。下表の配布 NAR を一時領域へ展開し、辞書を変更せず、ネットワーク禁止・一時領域外への書き込み禁止の sandbox で実エンジンを実行した。初回と再読み込みの 2 周で、読み込み、起動、本体ダブルクリック、終了、アンロードの全 40 操作が成功した。

これは SHIORI ランタイム層の確認であり、描画・ゲーム完走・AI 生成・すべての SAORI の互換性を保証するものではない。配布版への収録状況はリリースノートを参照。

| 配布物 | 2 周の load/unload | OnBoot / OnMouseDoubleClick / OnClose | 残る依存・確認範囲 |
|---|---|---|---|
| [knowledgeable_kernel v2.0.0](https://github.com/Tatakinov/knowledgeable_kernel/releases/download/v2.0.0/knowledgeable_kernel.nar) | 成功 | 全て 200、非空応答 | `os_detect` SAORI は未ロード。会話本文・画面表示の正当性は未判定 |
| [盤上の隅っこで 1.0.0](https://github.com/Tatakinov/banjou_no_sumikko_de/releases/download/1.0.0/banjou_no_sumikko_de.nar) | 成功 | 全て 200、非空応答 | `quoridor` / `gomoku` / `connect6` / `TexasHoldem` / `process` / `backgammon` / `othello` / `mahjong` SAORI は未ロード。ゲーム完走は未確認 |
| [よみびとみならい v1.1.0](https://github.com/Tatakinov/yomibito_minarai/releases/download/v1.1.0/yomibito_minarai.nar) | 成功 | 全て 200、非空応答 | `budoux` / `word2vec` SAORI は未ロード。AI 生成は未確認 |
| [desktop_tempter 1.0.0](https://github.com/Tatakinov/desktop_tempter/releases/download/1.0.0/desktop_tempter.nar) | 成功 | 全て 200、非空応答 | 基本メニュー応答まで。ゲーム完走・他ゴーストとの通信は未確認 |

イベントの Reference0–4 は `100,100,0,0,""`。配布物の `0Poke` ハンドラーを本体ダブルクリックから呼ぶ。存在しない `head` コリジョン名を指定した場合に 204 が返ることは、栞ロード失敗とは区別する。

[本文を含まない実測 JSON](kagari-fixes-results.json) に配布 URL、NAR SHA-256、イベントごとの状態・文字数、2 周目結果、Lua 全ファイルの変更なし検査を記録した。終了時に一時取得した NAR・展開物・生の診断ログを削除する。ゴースト本体はリポジトリに同梱しない。

## ホスト側の変更

`libkagari.dylib` に module を静的リンクし、Lua `package.preload` に登録する。配布物の Linux `.so` や Windows DLL を置換したり、辞書へダミー関数を書き込んだりしない。

- `luachild`、`lua-utf8`、`socket.core`、`lpeg` は固定した上流ソースからビルドする。
- `fh` は POSIX `poll` / `fcntl` による readable / blocking 操作、`iconv` は macOS iconv による実変換を提供する。変換不正はエラーを返す。
- `clipboard.set` は CP932 を UTF-8 に変換して macOS Pasteboard に書く実装。モジュール import だけでは clipboard に触れない。今回の検証は import のみで、ユーザーの clipboard は変更していない。
- `rand.native` は KOTORI の Lua wrapper が使う callable uint32 値を `std::mt19937` で生成する。Ourin 実装の同一 seed 再現、`uniform(max)` の `[0,max)` と正規分布を自作 fixture で検査した。元 Windows module と乱数列・未使用 distribution API の完全一致は未検証。
- `saori_universal.native` は同 stem の macOS `.dylib` / `.so` を POSIX SAORI の `long` 長さ ABI（`loadu` または `load` / `request` / `unload`）で扱う。この契約の自作 native fixture で実呼び出しを検査した。任意 ABI の推定や Windows DLL の実行はしない。native がなければ load は false、request は 503 となり、成功扱いにしない。

## 作業ディレクトリと隔離

`chdir(2)` によるプロセス全体の cwd 変更を使わない。Lua state ごとの root を registry に保持し、`luachild.dir` / `dirent` / `currentdir` / `chdir`、`io.open` / `lines`、`loadfile` / `dofile` の相対パスを解決する。`luachild.spawn` は `posix_spawn_file_actions_addchdir_np` により子プロセスだけに cwd を設定する。`os.execute` や `io.popen` 等、列挙していない API の相対パス互換性は今回の対象外。

Ourin の通常 native 実行は `jp.ourin.shiori` XPC サービスを使う。明示的な in-process 実行でもこの実装は host cwd を変更しない。回帰では 2 つの Lua state、2 つの KAGARI instance を同時に保持し、それぞれの同名ファイルの読み出し、子プロセス cwd、ロード失敗、アンロード後まで確認した。

## 再現とライセンス

```sh
OURIN_KAGARI_UNIVERSAL=1 bash engines/kagari/build.sh build/engines/kagari
PYTHONDONTWRITEBYTECODE=1 python3 engines/kagari/tests/test_native_modules.py \
  --library build/engines/kagari/libkagari.dylib
```

arm64 / x86_64 の universal dylib をビルドし、arm64 で上記 9 分類の回帰を実行した。x86_64 の実行と GUI はこの検証に含めない。自作 fixture の C native SAORI を一時コンパイルするため Xcode Command Line Tools が必要。

依存の URL、固定 revision、アーカイブ SHA-256、license は [modules/DEPENDENCIES.json](../../engines/kagari/modules/DEPENDENCIES.json) に記録する。毎回取得アーカイブを照合して展開し、ゴースト内の native binary をビルド入力にしない。

| 上流 | 固定版 | license |
|---|---|---|
| [Tatakinov/luachild](https://github.com/Tatakinov/luachild/tree/efcb09bd6059f5852313bfd431106a75344f4038) | `efcb09bd6059f5852313bfd431106a75344f4038` | MIT と Unlicense の notice を両方保持 |
| [starwing/luautf8](https://github.com/starwing/luautf8/tree/a47b1433473a2509d77ad28f59a976716d187927) | `a47b1433473a2509d77ad28f59a976716d187927` | MIT |
| [LuaSocket](https://github.com/lunarmodules/luasocket/tree/95b7efa9da506ef968c1347edf3fc56370f0deed) | 3.1.0 (`95b7efa9da506ef968c1347edf3fc56370f0deed`) | MIT |
| [LPeg](https://www.inf.puc-rio.br/~roberto/lpeg/) | 1.1.0 | MIT |

ビルド出力へ `LICENSE.luachild-MIT.txt`、`LICENSE.luachild-Unlicense.txt`、`LICENSE.luautf8.txt`、`LICENSE.luasocket.txt`、`LICENSE.lpeg.html` と module manifest を保存する。既存の `engines/package.sh` が `LICENSE*` をアプリの ThirdPartyNotices に取り込む。Ourin が追加した adapter は `engines/kagari/modules/native_modules.cpp` に分離している。
