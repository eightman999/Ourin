# AYA5互換構成（公式YAYA Tc607-2）

このプラグインは**公式最新版YAYAの実interpreterを使うAYA5互換構成**です。原本AYA5のbinaryをmacOSで実行するものではなく、AYA1〜4の実装でもありません。

[公式YAYA README](https://github.com/YAYA-shiori/yaya-shiori/blob/Tc607-2/README.md)はAYA Ver.5を原型とすると明記しています。上流に付属する [原本ライセンス](https://github.com/YAYA-shiori/yaya-shiori/blob/Tc607-2/readme-original.txt) は「文 version 5.8、2005-06-23」です。現在のYAYAでは機能追加や修正が行われているため、旧AYA辞書すべての完全な挙動一致を主張しません。

```sh
python3 engines/aya/build.py
```

出力 `build/engines/aya/libaya5compat.dylib` は公式YAYAと同じ固定source・5依存から生成します。versionは公式の `GETSETTING(0)` が返す **Tc607-2** のままです。出力ファイル名や画面表示をAYA5互換とするために、version値をAYA5へ偽装しません。

POSIXの設定探索だけを追加し、`aya5.txt`（なければ `aya.txt`）と元のAYA5 DLL名を認識します。設定・辞書・変数保存ファイルの名前をghost側で書き換える必要はありません。`aya5_variable.cfg` / `aya_variable.cfg` の保存は実YAYAの機能です。独自に改名したDLLを複数置いた辞書や、複数の設定候補がある場合の探索は別途確認が必要です。

`example/` はCP932の自作辞書で、実interpreterによる日本語・表/ソ・半角カナ・CP932拡張文字・保存再ロードの検証用です。UTF-8構成との違いはwire設定も含めて明示します。AYA1〜4、Windows固有機能、Windows SAORIや全配布ghostは未確認です。

固定版・取得hash・ライセンス・依存・ビルド手順の詳細は [YAYAの記録](../yaya/README.md)を参照してください。
