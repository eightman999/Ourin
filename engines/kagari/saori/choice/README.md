# choice SAORI 互換モジュール

Ourin が独自に実装した macOS POSIX ABI モジュール。元 `choice.dll` のソース移植ではありません。成功だけを返す代替ではなく、渡された引数から `arc4random_uniform` でランダムに１件を選び、その実際の値を返します。追加依存は macOS libc/C++ 標準ライブラリだけです。ソースのライセンスは隣の `LICENSE` (MIT)。元 DLL や ghost の再配布許諾を意味しません。

契約の一次資料は実配布 `mosu.nar` 内の `ghost/master/saori/choice/README`（ふるごむ作、CP932）です。「（choice,Ａ,Ｂ,Ｃ）」「引数のうちランダムにどれか１つを返す。」と記されています。サンプル辞書だけから動作を推測したものではありません。原 DLL の公開ソースは確認できませんでした。

検証対象を固定する SHA-256:

- mosu.nar: `a663e0a32de13dd28b8b18e7a806f31a764d8e5ead7754f4901dc3838a764688`
- 同梱 README: `e03effd5e37692b7e70e89c084a06b26c0a849400eef355177629bc22c1a2a72`
- 同梱 choice.dll: `eba803f91f8968e800ff3a4e46eb12136407a21fb6a48f6d114088bc5e821c70`

要求/応答形式・Charset・空の引数の位置保持は [UKADOC SAORI 概要](https://ssp.shillest.net/ukadoc/manual/spec_saori_ex.html) に従います。`GET Version SAORI/1.0` に自己識別を返し、`EXECUTE` は連続する `Argument0...N` から選択した生の bytes を `Result` に返します。UTF-8/CP932 を変換しないため、応答 Charset は要求と一致します。省略時は Shift_JIS。引数なし・疎番号・重複ヘッダ・不正要求は400、割り当て失敗等は500とする境界は Ourin 側の定義です。元 DLL との比較実行環境は無く、乱数分布、未記載の入力、厳密なエラー/バージョン応答の一致は未確認です。

手動ビルド・実検証（元 NAR は改変しません）:

```sh
engines/kagari/saori/choice/build.sh
python3 engines/kagari/saori/choice/test_choice.py build/engines/kagari/saori/choice/choice.dylib
python3 engines/kagari/verify_kagari_mosu.py build/engines/kagari/libkagari.dylib \
  /path/to/mosu.nar --choice-module build/engines/kagari/saori/choice/choice.dylib
```

ビルドは macOS 13+ Universal2 dylib を出力し、ソースと成果物のハッシュを表示します。POSIX entry は `load(char*,long)->int`, `unload()->int`, `request(char*,long*)->char*`。load/request 入力をモジュールが `free`、応答を呼出元が `free` します。

verifier は一時展開へ `choice.dylib` を追加するだけで元 `choice.dll`、saori.conf、全辞書を維持します。KAGARI の実 Lua 辞書の `t_Key -> talkRandom -> choice` を呼び、実際の「文字列1/2/3が選ばれたよ。」、起動・会話・保存・別 process 再load を確認します。choice は匿名ランダムトークなので128回までの有界呼出しで見つからなければ明示的にFAIL。SAORI 未配置も完了扱いにしません。
