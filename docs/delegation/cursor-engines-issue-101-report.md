# cursor-engines / P1 #101 委譲報告

作業日: 2026-10-25 (JST)<br>
担当: cursor-engines (Composer)<br>
Issue: [#101](https://github.com/eightman999/Ourin/issues/101)（KAWARI/KAGARI 実エンジン + 互換マトリクス基盤）

## 結論

- **KAWARI**: 上流 POSIX SHIORI（`ukagaka-long` + `loadu`）を Ourin の既存 `NativeShioriModule` でロード可能。Windows `*.dll` 名から同梱 `libkawari_shiori.dylib` へ解決する `BundledShioriEngine` を追加（親ビルド済み `8098dfb`）。
- **KAGARI**: `engines/kagari/build.sh` で **Lua 5.4.4 + sol2 3.2.2 を task-local 取得・ビルド**し、`libkagari.dylib` + 同梱 `liblua.5.4.dylib`（`@loader_path`）を **arm64 でビルド成功**。POSIX instance-ID ABI + load 失敗時 `-1` パッチ適用済み。
- **実ゴースト『もす』**: 一時展開で `kagari_load` まで進行。`socket.core` は luasocket v3.1.0 の macOS ビルドで解決。続きは `lua-utf8` / `luachild` / `iconv` / `saori_caller` 等 **Windows 同梱 DLL の macOS ネイティブ未整備**で `kagari_load -> -1`（ログは `verify_kagari_mosu.py` 出力）。

## 変更ファイル（本セッション追加分）

| ファイル | 内容 |
|---|---|
| `engines/kagari/build.sh` | Lua/sol2 取得・ハッシュ検証・パッチ・dylib 同梱ビルド |
| `engines/kagari/DEPENDENCIES.json` | Lua/sol2 URL・SHA256・ライセンス参照 |
| `engines/kagari/patches/001-apple-unix.patch` | `__APPLE__` で Unix パス拡張子 |
| `engines/kagari/patches/002-kagari-unix-load-failure.patch` | `Shiori::load` 失敗時 `-1` |
| `engines/kagari/patches/003-sol2-optional-ref-emplace.patch` | sol2 3.2.2 + Apple Clang |
| `engines/kagari/verify_kagari_mosu.py` | 最小ライフサイクル + もす NAR 検証 |
| `docs/KAWARI_KAGARI_ENGINES_ja-jp.md` | KAGARI ビルド手順更新 |

## 根拠（上流・依存）

| コンポーネント | revision / 版 | ライセンス |
|---|---|---|
| kagari_shiori | `ba87ccbd850c787aeeea7d31bed293d64bc09f01` | upstream `LICENSE` → `LICENSE.kagari` |
| Lua | 5.4.4 (`164c7849…`) | MIT |
| sol2 | v3.2.2 (`141790da…`) | MIT → `LICENSE.sol2` |
| luasocket（検証時のみ） | v3.1.0 | MIT |

## 実行コマンドと結果

```bash
./engines/kagari/build.sh
# → build/engines/kagari/libkagari.dylib, liblua.5.4.dylib, DEPENDENCIES.json, LICENSE.*

python3 engines/kagari/verify_kagari_mosu.py build/engines/kagari/libkagari.dylib
```

| 検証 | 結果 |
|---|---|
| `engines/kagari/build.sh` (arm64) | **PASS** |
| 最小 index.lua ライフサイクル（C probe） | **PASS** |
| `kagari_load` 失敗パス | **PASS**（`-1`、マップに未登録） |
| 『もす』OnBoot→会話→OnClose→reload | **INCOMPLETE**（exit 2）— `require('lua-utf8')` 等 |

### otool（成果物）

```
libkagari.dylib:
  @rpath/libkagari.dylib
  @loader_path/liblua.5.4.dylib
  /usr/lib/libc++.1.dylib
  /usr/lib/libSystem.B.dylib

liblua.5.4.dylib:
  @rpath/liblua.5.4.dylib
  /usr/lib/libSystem.B.dylib
```

## 親 worker 向け

- `project.pbxproj` は未変更（別担当）。
- 同梱: `build/engines/kagari/libkagari.dylib` + `liblua.5.4.dylib` + `.plist` + `LICENSE.*` + `DEPENDENCIES.json`
- Xcode 全体 test は親実行。`OURIN_KAGARI_ENGINE` で実エンジン統合テスト可能。

## 残件

- [ ] 『もす』完全 SHIORI: `lua-utf8`, `luachild`, `iconv`, `saori_caller` 等の macOS `.so` ビルドまたは同梱方針（#103 ライセンス表記）
- [ ] `OURIN_KAGARI_UNIVERSAL=1` の CI 確認（x86_64 ホスト）
- [ ] 互換マトリクス実測更新

## リスク

- sol2 3.2.2 は Ourin パッチ前提（上流 tarball 固定のまま）。
- 配布ゴーストの corelib は Windows DLL 前提が多く、KAGARI 実機検証はネイティブモジュール整備がボトルネック。
