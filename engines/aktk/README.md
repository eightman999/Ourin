# aktk の macOS mruby / SHIOLINK ローカルビルド

[kinokon/aktk](https://github.com/kinokon/aktk) の固定C++実装に、[mruby 3.4.0](https://github.com/mruby/mruby/tree/3.4.0) の実SDKを静的リンクします。

```sh
python3 engines/aktk/build.py
```

両上流のrevisionとアーカイブSHA256を `UPSTREAM.json` に固定しています。mrubyの既存API（mrb_open / mrb_load_file / mrb_funcall / mrb_bool / RSTRING_PTR）を使い、Rubyスクリプトを実際に評価します。mrbgemsは同じ固定アーカイブに含まれるcoreのdefault gemboxだけで、追加gemや外部SDKを取得しません。

ビルド補助には既存Ruby 4.0.7とRake 13.3.1、clangを使用します。Ruby/Rakeの版を確認し、systemへのインストールや設定変更は行いません。取得済みアーカイブは `--archive /absolute/aktk.tar.gz --mruby-archive /absolute/mruby.tar.gz`、Ruby/Rakeの所在は `--ruby` / `--rake`、出力先は `--output` で指定できます。SDKは一時ディレクトリでビルドして破棄します。

出力は `build/engines/aktk/aktk-shiolink`。元の `shiori,aktk.dll` を維持して、同じディレクトリへ `SHIOLINK.ourin.ini` を追加します。

```ini
[SHIOLINK]
module=aktk.dll
executable=/absolute/path/to/build/engines/aktk/aktk-shiolink
arguments=[]
charmode=UTF-8
```

Ourinの明示的module選択からSHIOLINK接続を使います。Windows DLLをmacOSで直接実行する方式ではありません。mruby stateは同じ子process/threadでロード・要求・終了し、Ourin本体から隔離します。

元の契約は `index.rb` を読み、`_load(path)`、`_request(電文)`、`_unload` を呼ぶものです。固定上流にはRuby辞書例や配布ゴーストがありません。`example/index.rb` は実mrubyで計算・日本語応答・絵文字往復・ファイルI/Oによる保存復元・例外を実行する自作fixtureです。上流辞書の改変や、protocolを返すだけの代替interpreterではありません。既存の第三者aktkゴースト全体を確認したとは扱いません。

`AktkEngineTests` は `module=aktk.dll` を持つ設定を本番Factoryで選択し、実processによるロード、日本語/絵文字、NOTIFY、例外と型不一致の500応答、例外後の続行、保存・再起動、不正source時の失敗、子process回収を確認します。先に上のビルドを実行してください。`OURIN_AKTK_EXECUTABLE` で成果物の所在を変更できます。

`BUILD.json` にSDK静的libraryのhash・上流sourceのhash・Ruby/Rakeの実版を記録します。mrubyのMIT本文とLEGALを保存します。aktk自身の固定上流にはLICENSEや再配布許諾を確認できないため、任意ローカルビルドのみとし、アプリへの自動同梱や配布は追加しません。移植差分は [PATCHES.md](PATCHES.md) に記録しています。
