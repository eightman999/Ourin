# emo-rs の macOS Native 接続

固定した[上流emo-rs](https://github.com/ekicyou/emo-rs)のRust／LuaJIT実エンジンをビルドします。Windows DLLをロードせず、POSIXの `load/request/unload` と既存Ourin Native ABIを使用します。

```sh
python3 engines/emo-rs/build.py
```

必要環境はmacOS、Rust/CargoとClangです。実compiler版はBUILD.jsonへ記録します。上流アーカイブと依存shiori3 0.5.0のSHA256はUPSTREAM.json、全Cargo依存はCargo.lockで固定し、`cargo build --locked` を使います。cache/sourceは `build/deps/emo-rs`、成果物は `build/engines/emo-rs`。cache archiveも毎回hash検証します。検証時のhostはarm64で、Intel/Universal 2は未確認です。

成果物の `libemo.dylib` と `libemo.dylib.plist` をゴーストのSHIORIディレクトリへ置き、`shiori,emo.dll` で既存の代替module探索から接続します。検証用upstream-scriptは `emo/` と `dic/` を含む上流サンプルです。上流イベント本文とdic/save.lua、dic/conf.luaは変更していません。

## 移植内容

- 上流にはWindows exportsのみがあるため、POSIX専用entrypointを追加。標準ABI `ukagaka-long` をmetadataへ宣言し、malloc/freeの所有権、長さ上限、UTF-8、Rust panicのC境界隔離を処理する。イベント処理は上流Shiori3/Shiori/Luaを呼ぶ。
- 依存shiori3のRawShiori3／winapiをWindowsでのみコンパイルする。上流が説明するnon-WindowsのANSI/OEM＝UTF-8の実装を追加し、parserは保持する。
- Rustが生成するLua検索パスの区切りだけをPOSIXへ変更する。渡されたghostディレクトリ中の文字は置換しない。
- Luaのload callbackがfalseを返したときにロード成功としない。loggerの二重登録で同じmoduleの再loadが失敗しないようにする。loggerは同一moduleの最初のload先を使い、他ghostへ同じmodule instanceを共有する保証はない。
- 上流frameworkの `main_loop.lua` は存在しない `shiori.cts` をrequireしていた。実体の `libs.cts` へ修正する。これはframework側の参照修正であり、利用者のイベント辞書や保存データを変更するものではない。差分はport.patchに保存。

## 検証

`EmoRustEngineTests` は本番Factory／Native XPCから、Unicodeを含むディレクトリで上流OnBoot、日本語＋絵文字のOnTranslate、NOTIFY、終了、savedata生成と再load後の値保持を検証します。上流no_entryは初回の未処理GETを保存するため、2回目に同じIDを異なるReferenceで送り、初回値が保持されることを確認します。上流にないversion／OnCloseトークをstubで補いません。OnCloseは上流どおり204で、unloadにより保存されます。

未ビルド時は追加suiteを明示skipします。実配布「えも？」、全Lua辞書／追加C module、Intel実機は未検証です。Ourinへの自動同梱・配布を追加していません。出力には上流LICENSE、各Cargo packageのlicense宣言一覧、取得できたlicense/notice本文、Cargo.lockを保持します。mlua 0.8.10には将来Rustで拒否されるコードのcompiler警告が残るため、無検証の依存更新は行いません。

## 実配布「えも？」のLua 5.4 build

元emo-gs NARはLua5.3の整数除算・utf8標準library・日本語識別子を使います。配布のemo/とdic/は新版upstream-scriptへ置換せず、別variantを使います。

```sh
python3 engines/emo-rs/build.py --lua lua54
python3 engines/emo-rs/stage_distribution.py
```

出力はbuild/engines/emo-rs-lua54。lua-src546.0.2のucid featureでUnicode識別子を有効にし、Cargo.lua54.lockで依存を固定します。従来LuaJIT variantは変更しません。stage_distribution.pyはDISTRIBUTION.jsonのrevision/NAR SHA256を照合して一時fixture用のコピーを作り、全元ファイルのhashを保存します。元DLLやLuaを削除・書換えず、libemo.dylibとABI plistだけをghost/masterの隣接moduleとして追加してください。stage先が既存なら上書きせず停止します。自動配布や利用者ghostの置換は行いません。
