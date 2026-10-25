# KAWARI / KAGARI 実エンジン同梱

更新: 2026-10-25。開発版のビルド・解決規則。互換性マトリクスの実測は別途更新する。

## 上流の固定版

`engines/PINNED_UPSTREAM.json` に repository と revision を記録する。ライセンス本文は各上流の `LICENSE` をビルド出力へ `LICENSE.kawari` / `LICENSE.kagari` としてコピーする（リポジトリ全体の vendoring はしない）。

| エンジン | リポジトリ | macOS 成果物 | OurinShioriABI |
|---|---|---|---|
| 華和梨 (KAWARI) | [ukatech/kawari](https://github.com/ukatech/kawari) | `libkawari_shiori.dylib`（上流 POSIX 名は `libshiori.bundle` の単体 dylib） | `ukagaka-long`（`loadu` 優先） |
| KAGARI | [Tatakinov/kagari_shiori](https://github.com/Tatakinov/kagari_shiori) | `libkagari.dylib` | `kagari` |

KAGARI の Windows 版 `load` / `request` 2 引数 ABI とは別に、POSIX 版は `kagari_load` / `kagari_request(int id, …)` / `kagari_unload` の instance-ID 付き ABI を使う。Ourin は POSIX ビルドのみを対象とする。

## ビルド

```bash
./engines/kawari/build.sh    # → build/engines/kawari/libkawari_shiori.dylib
./engines/kagari/build.sh    # → build/engines/kagari/libkagari.dylib + liblua.5.4.dylib
```

KAGARI ビルドは `engines/kagari/DEPENDENCIES.json` に SHA256 付きで Lua 5.4.4 / sol2 v3.2.2 を記録し、`build/deps/kagari/` に展開する（Homebrew 不要）。上流 `kagari_shiori` には `engines/kagari/patches/` の macOS / load 失敗修正を適用する。sol2 3.2.2 は Apple Clang 向けに `003-sol2-optional-ref-emplace.patch` を当てる。

`OURIN_KAGARI_UNIVERSAL=1` で arm64 + x86_64 を別ビルドして `lipo` 結合できる（デフォルトはホスト arch のみ）。

検証:

```bash
python3 engines/kagari/verify_kagari_mosu.py build/engines/kagari/libkagari.dylib
```

（最小 SHIORI ライフサイクル + 『もす』NAR の `/tmp` コピー。luasocket は検証時に lunarmodules/luasocket v3.1.0 をビルドして `corelib/socket/core.so` へ配置）

検証用に `OURIN_KAWARI_ENGINE` / `OURIN_KAGARI_ENGINE` 環境変数で成果物パスを上書きできる。

## ゴーストからの解決

1. ゴースト同梱の `.dylib` / `.bundle` を USL 探索パスから探す（従来どおり）。
2. macOS で `.dll` しか無い場合、`BundledShioriEngine` がモジュール名と辞書マーカーからエンジン種別を推定し、`Frameworks` または `Resources/Engines` の同梱物へフォールバックする。
   - `kawari.dll` / `kosui.dll` → KAWARI
   - `kagari.dll` → KAGARI
   - `shiori.dll` かつ同フォルダに `kawarirc.ini` / `kawarirc.kis` → KAWARI

ScriptBridge プラグインの KAWARI 辞書パーサーは会話再生の補助であり、本エンジンの代替ではない。

## Xcodeへの同梱

アプリtargetの `Build and embed native SHIORI engines` フェーズが `engines/package.sh` を実行する。固定入力が変わったときにUniversal 2をビルドし、3本のdylibを `Contents/Frameworks` へコピー・署名する。ABI宣言は `Contents/Resources/EngineMetadata`、ライセンス本文は `EngineLicenses` へ配置する。Frameworksにplistを置くとapp署名が失敗するため、コードと宣言の配置を分けている。

`KawariKagariEngineTests` は環境変数なしでアプリ同梱物を使用する。実KAWARI/KAGARIのin-process/XPC往復、KAGARIのunload/reload・load失敗、instance-ID fixtureを検証。2026-10-25の対象検証は関連4suite、42実行/35固有test、失敗0・skip0。

## 実ゴーストの確認範囲

- LOBO: KAWARI実エンジンで起動・会話・終了・保存・別process再load成功。Ourin実アプリでも通常factoryが `kind=native` を選択し、OnBoot本文が返ることを確認。Macロック中のため画面操作は未確認。
- もす: 正規LuaSocket／luautf8／luachild／lua-iconvをmacOS向けにビルド。`saori_universal.native` のmacOS実装不足でloadが失敗し、実ゴーストの保存・再起動は未確認。Windows DLL/Linux ELFへの置換やLua側stubは使っていない。
- 詳細: [実ゴースト検証](REAL_GHOST_VERIFICATION_2026-10-25.md)、[KAGARI検証記録](delegation/kagari-mosu-report.md)。GUI・クリーンMac・Intel実機は別の検証項目。
