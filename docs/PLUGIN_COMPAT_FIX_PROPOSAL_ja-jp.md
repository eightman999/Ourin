# Plugin 互換実装修正案

**作成日:** 2026-06-26

この文書は、Ourin の SSP/PLUGIN 互換方針と現在の実装差分をそろえるための修正案をまとめる。

## 前提方針

今後の macOS 移植 plugin は、次の責務分離を基本形とする。

```text
SomePlugin_mac/
  install.txt
  descript.txt
  message.japanese.txt
  message.english.txt
  SomePlugin.plugin/
```

- Ourin ホスト側が `install.txt`、`descript.txt`、`message.*.txt` を解釈する。
- `.plugin` bundle は DLL の `load` / `loadu` / `request` / `unload` / `unloadu` 互換に集中する。
- 表示文字列・言語選択は原則として `message.*.txt` に寄せる。
- Windows DLL は macOS 上で直接ロードしない。

## 修正 1: PluginScaffolder の生成形式を `*_mac/` へ更新

**問題**

`docs/SPEC_PLUGIN_2.0M_ja-jp.md` と `docs/OURIN_MIGRATOR_PLAN.md` では `SomePlugin_mac/` 形式を標準形にしたが、現在の `PluginScaffolder` は旧形式の `ourin/macos/<name>.plugin/` を生成する。

**修正案**

`PluginScaffolder.scaffold` の出力を以下に変更する。

```text
ourin/macos/<name>_mac/
  install.txt
  descript.txt
  message.japanese.txt
  message.english.txt
  <name>.plugin/
    Contents/
      Info.plist
      MacOS/<name>
      Resources/
        descript.txt
        ourin.json
  Sources/
    <name>Plugin.c
  OriginalDocs/
    ReadMe.txt
```

**受け入れ条件**

- `OurinMigratorTests.scaffoldGeneratesPluginBundleStructure` を新構造に更新し、成功する。
- 既存 `descript.txt` / `install.txt` / `message.*.txt` がある場合は root と `OriginalDocs/` にコピーされる。
- `IMPLEMENTATION_TODO.md` は bundle 内ではなく `<name>_mac/README.md` か `Sources/` 側へ置く。

## 修正 2: 同一 plugin ID の二重ロードを防ぐ

**問題**

`/Users/eightman/Documents/Ourin/plugin/SAKNIFE.plugin` と `SAKNIFE_mac/SAKNIFE.plugin` が並ぶと、同じ `id` の plugin が二重ロードされる可能性がある。

**修正案**

`PluginRegistry.discoverAndLoad` にロード済み ID / bundle path の重複抑止を入れる。

優先順位は以下とする。

1. `install.txt` 付き package directory 内の native `.plugin`
2. 直置き native `.plugin`
3. legacy metadata-only directory

同じ ID が複数ある場合は、優先順位が高いものを採用し、低いものは skip してログへ残す。

**受け入れ条件**

- `LegacyPluginRegistryTests` に「直置き `.plugin` と `*_mac` が同一 ID の場合、1 件だけ登録される」テストを追加する。
- `installedplugin` と `pluginpathlist` に重複 ID が出ない。

## 修正 3: `PluginMeta.path` の意味を分離する

**現状:** 2026-06-27 実装済み。`PluginMeta.compatibilityPath` / `executablePath` / `packagePath` と
`PluginCompatibilityEntry` を追加し、`pluginlist.index(n).executablepath` /
`pluginlist.index(n).packagepath` / `executionstate` / `candispatchrequests` で参照できる。

**問題**

package root の `descript.txt` が元 DLL の `filename,SAKNIFE.dll` を保持する場合、`PluginMeta.path` は DLL パスになる。一方、実際にロードされた native bundle は `SAKNIFE.plugin` であり、`pluginpathlist` の意味が曖昧になる。

**修正案**

`PluginMeta` に互換パスと実行パスを分けて持たせる。

```swift
public let compatibilityPath: String   // descript.txt の filename 由来。元 DLL 互換。
public let executablePath: String      // 実ロード対象。native .plugin / .bundle。
public let packagePath: String?        // install.txt 付き package directory。
```

既存 `path` は互換性維持のため当面残し、段階的に `compatibilityPath` の alias として扱う。

**受け入れ条件**

- `pluginlist.index(n).path` は従来互換として残る。
- `pluginlist.index(n).executablepath` で native `.plugin` のパスを取得できる。
- `pluginpathlist` は仕様上どちらを送るか明記する。推奨は package path、なければ executable path。

## 修正 4: `message.*.txt` を実表示へ接続する

**問題**

Ourin は `message.*.txt` を `PluginMeta.localizedMessages` に保持できるが、SAKNIFE の `.plugin` 実装内にはまだ一部メニュー文言が固定で残っている。

**修正案**

短期対応：

- Ourin の plugin メニュー UI / DevTools 表示では `PluginMeta.message(for:)` を優先する。
- `pluginlist(...).message.<key>` を使った表示例を追加する。

中期対応：

- `.plugin` の `load` に package root path を渡している場合、plugin 側が root の `message.*.txt` を読む補助関数を提供する。
- ただし方針としては、メニュー構築を Ourin ホスト側へ寄せ、`.plugin` は command ID を処理するだけにする。

**受け入れ条件**

- `SAKNIFE_mac/message.japanese.txt` の `menu.empty_recycle_bin` を変更すると、Ourin 側表示に反映される。
- `.plugin` のソースに固定されたメニュー表示名が最小限になる。

## 修正 5: `install.txt` package の reload / rescan を明確化する

**問題**

Plugin registry が package directory を読むようになったが、更新・再読み込み時の単位が bundle なのか package なのか曖昧。

**修正案**

- registry の内部 record に `packageURL` を持たせる。
- `unloadAll()` は native bundle を unload し、package metadata も消す。
- `discoverAndLoad()` は package 単位で再評価する。
- DevTools の plugin list は `packageURL` と `executablePath` を両方表示できるようにする。

**受け入れ条件**

- `SAKNIFE_mac/message.*.txt` を変更後、Plugin reload で metadata が更新される。
- bundle 直置き plugin と package plugin の表示差が分かる。

## 修正 6: SAKNIFE の配置を標準形へ一本化する

**問題**

現在は検証用として `SAKNIFE.plugin` 直置き版と `SAKNIFE_mac/SAKNIFE.plugin` が併存している。

**修正案**

標準は `SAKNIFE_mac/` とし、直置き `/plugin/SAKNIFE.plugin` は検証用または旧成果物として退避する。

推奨配置：

```text
/Users/eightman/Documents/Ourin/plugin/SAKNIFE_mac/
```

退避候補：

```text
/Users/eightman/Documents/Ourin/plugin/_legacy_native/SAKNIFE.plugin
```

**受け入れ条件**

- Ourin 起動時に SAKNIFE は 1 件だけ登録される。
- `installedplugin` に SAKNIFE が重複しない。

## 修正 7: docs と tests の同期

**問題**

方針が docs に入り始めているが、実装と tests が完全には追従していない。

**修正案**

- `SPEC_PLUGIN_2.0M_ja-jp.md` の `*_mac` 方針を正とする。
- `OURIN_MIGRATOR_PLAN.md` と `PluginScaffolder` の出力を一致させる。
- `PropertySystem_ja-jp/en-us.md` に追加した `message.<key>` のテストを追加する。

**受け入れ条件**

- `xcodebuild -project Ourin.xcodeproj -scheme Ourin build` が成功する。
- 追加または更新したテストが成功する。
- docs にある標準構成を Migrator が実際に生成する。

## 推奨実装順

1. SAKNIFE 直置き `.plugin` の扱いを決め、二重ロードの危険を消す。
2. `PluginMeta.path` の意味分離を実装する。
3. `PluginRegistry` に同一 ID の優先順位・重複抑止を入れる。
4. `PluginScaffolder` を `*_mac/` 生成へ更新する。
5. `message.*.txt` を UI 表示へ接続する。
6. tests と docs を同期する。

## 最小修正セット

まず壊れやすいところだけ直すなら、以下の 3 点を先に行う。

1. 同一 plugin ID の二重ロード抑止。
2. `PluginMeta` に `executablePath` / `packagePath` を追加。
3. `PluginScaffolder` の出力を `*_mac/` に変更。

この 3 点で、現在の方針と実装の大きなズレはほぼ解消できる。
