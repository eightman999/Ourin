# Ourin Migrator 計画

Ourin Migrator は、SSP/Windows 由来の資産を壊さずに読み取り、Ourin で利用可能な形へ段階的に変換・補助する DevTools 機能として実装する。

## 目的

- `/Users/eightman/Documents/Ourin` 配下の SSP 互換資産を解析する
- Windows 向け `.dll` / `.exe` を Ourin 本体では実行せず、移行対象として扱う
- `descript.txt` など既存の SSP 互換メタデータを維持する
- Ghidra headless 解析で疑似 C、imports、exports、strings、resources を取得する
- `ourin.json` を生成し、Ourin 側の builtin 置換や macOS plugin 実装へつなげる
- 未知 DLL については完全自動変換ではなく、`.plugin` 雛形と実装 TODO レポートを生成する

## 基本方針

DLL/EXE は Ourin 本体ではロードしない。通常起動時は `descript.txt`、`ourin.json`、macOS native plugin、builtin replacement だけを利用する。

Ghidra は Ourin に同梱しない。DevTools 側でユーザー指定の `analyzeHeadless` を外部プロセスとして呼び出す。

SSP 互換の元ファイル構造は保持し、Ourin 用の追加情報だけを `ourin.json` や `ourin/` 配下に置く。

移植済み plugin を配布・保管する場合は、`install.txt`、`descript.txt`、`message.*.txt` をパッケージディレクトリのルートに置き、Ourin ホストがそれらを解釈する。生成する macOS `.plugin` は、元 DLL の `load` / `loadu` / `request` / `unload` / `unloadu` 互換と、必要最小限の `descript.txt` fallback に責務を限定する。表示文言や言語選択は `.plugin` 内に固定せず、原則として `message.*.txt` へ委譲する。

```text
plugin/shared_value/
  descript.txt
  install.txt
  message.japanese.txt
  message.english.txt
  shared_value.dll
  ourin.json
  ourin/
    analysis/
      report.md
      imports.json
      exports.json
      strings.txt
      resources.txt
      decompiled.c
    macos/
      shared_value.plugin/
```

配布用の macOS パッケージディレクトリは以下を標準形とする。

```text
plugin/shared_value_mac/
  install.txt
  descript.txt
  message.japanese.txt
  message.english.txt
  shared_value.plugin/
  Sources/
    SharedValuePlugin.c
  OriginalDocs/
    ReadMe.txt
```

`OriginalDocs/` は元配布物の保存・参照用であり、通常の実行時入力ではない。

## 実装場所

```text
Ourin/DevTools/Migrator/
  OurinMigratorView.swift
  LegacyAssetScanner.swift
  LegacyBinaryAnalyzer.swift
  GhidraHeadlessRunner.swift
  MigrationReport.swift
  OurinManifest.swift
  PluginScaffolder.swift
  Resources/
    DecompileAll.java
```

既存の互換処理は以下を利用する。

```text
Ourin/Compat/LegacyDescriptor.swift
Ourin/Compat/SSPCompat.swift
Ourin/Calendar/CalendarRegistry.swift
Ourin/PluginHost/PluginRegistry.swift
```

## 対象ディレクトリ

初期スキャン対象は以下とする。

```text
/Users/eightman/Documents/Ourin/plugin
/Users/eightman/Documents/Ourin/calendar/plugin
/Users/eightman/Documents/Ourin/headline
/Users/eightman/Documents/Ourin/data
```

検出対象:

```text
*.dll
*.DLL
*.exe
*.EXE
descript.txt
ourin.json
```

## 表示情報

DevTools の一覧では以下を表示する。

```text
Name
Kind: plugin / calendar-plugin / headline / tool / unknown
Binary: PE32 / PE32+ / unknown
Filename
ID
Status: metadata-only / analyzed / mapped / scaffolded
Recommendation
```

UI の基本形:

```text
Ourin Migrator
  [Scan Documents/Ourin]
  [Ghidra Path: ...]
  [Analyze Selected]
  [Generate ourin.json]
  [Create Plugin Scaffold]

Name | Kind | Binary | Status | Action
```

詳細ペイン:

```text
descript.txt summary
imports
exports
strings preview
resources preview
migration recommendation
generated files
```

## Ghidra 解析

Ghidra の既定候補:

```text
/Users/eightman/Downloads/ghidra_12.0.4_PUBLIC/support/analyzeHeadless
```

解析は `Process` で外部プロセスとして実行する。プロジェクト作業領域は一時ディレクトリに作成し、成果物は各対象フォルダの `ourin/analysis/` に保存する。

生成物:

```text
ourin/analysis/decompiled.c
ourin/analysis/imports.json
ourin/analysis/exports.json
ourin/analysis/strings.txt
ourin/analysis/resources.txt
ourin/analysis/report.md
```

Ghidra 解析は時間がかかるため、DevTools 上で進捗表示とキャンセルを可能にする。

## ourin.json

`ourin.json` は、元 DLL/EXE と Ourin 側実装の対応関係を表す。

例:

```json
{
  "format": "ourin-migration-1",
  "source": {
    "filename": "shared_value.dll",
    "kind": "pe32-dll",
    "sspPluginId": "ABED14AF-F34B-4ff2-95B7-30ED37D5802D"
  },
  "mode": "native-replacement",
  "implementation": "builtin:shared_value",
  "analysis": {
    "decompiled": "ourin/analysis/decompiled.c",
    "report": "ourin/analysis/report.md"
  }
}
```

主な `mode`:

```text
metadata-only       DLL/EXE は実行せず、SSPメタデータだけ利用する
native-replacement  Ourin builtin 実装へ差し替える
native-plugin       macOS .plugin/.bundle を利用する
scaffold            雛形生成済み、実装待ち
unsupported         現時点では未対応
```

## 既知 DLL/EXE の builtin 置換候補

まずは以下を移行候補として扱う。

```text
shared_value.dll -> builtin:shared_value
SAKNIFE.DLL      -> builtin:saknife または scaffold
SCHEDULE.dll     -> builtin:calendar_schedule または scaffold
SSPH.exe         -> builtin:ssph_compat
mcp.exe          -> builtin:mcp_compat
```

既知 DLL は疑似 C から Swift へ機械変換するのではなく、Ourin 側で同等機能をネイティブ実装し、`ourin.json` で紐づける。

## .plugin 雛形生成

未知 DLL の場合は完全変換せず、macOS plugin の雛形を生成する。

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

`<name>.plugin` の内部構造:

```text
<name>.plugin/
  Contents/
    Info.plist
    MacOS/<name>
    Resources/
      descript.txt
      ourin.json
```

雛形には最低限の PLUGIN/DLL 互換入口を用意する。

```text
load
loadu
request
unload
unloadu
plugin_free（必要な場合のみ）
```

イベント ID ごとの挙動は `request` 内で分岐する。ただし、メニュー表示名やメッセージ文言は `message.*.txt` から Ourin ホストが読めるようにし、`.plugin` 側への固定埋め込みは避ける。

同時に `ourin/analysis/report.md` に、exports/imports/strings から推定した実装 TODO を出力する。

## 実装フェーズ

### Phase 1: スキャン

- 対象ディレクトリから `.dll` / `.exe` / `descript.txt` / `ourin.json` を検出する
- `file` 相当の判定で PE32 / PE32+ / unknown を分類する
- `LegacyDescriptor` で `descript.txt` を UTF-8 / Shift_JIS 両対応で読む
- DevTools に一覧表示する

### Phase 2: 解析

- Ghidra path を設定できるようにする
- 選択ファイルを headless 解析する
- 疑似 C、imports、exports、strings、resources を保存する
- 解析ログ、成功/失敗、所要時間を記録する

### Phase 3: レポート生成

- `report.md` を生成する
- binary kind、exports、imports、目立つ文字列、推定機能をまとめる
- Ourin 側の推奨移行モードを提示する

### Phase 4: ourin.json 生成

- `metadata-only` / `native-replacement` / `native-plugin` / `scaffold` / `unsupported` を書けるようにする
- 既知 DLL について builtin 実装名を自動提案する
- 既存 `ourin.json` がある場合は上書き確認を行う

### Phase 5: .plugin 雛形生成

- 未知 DLL 用に `.plugin` 雛形を生成する
- `Info.plist`、実行ファイル placeholder、`Resources/ourin.json` を作る
- 生成物と TODO を `report.md` に追記する

## MVP

最初の完成ラインは以下とする。

1. DLL/EXE 一覧を DevTools に表示する
2. 選択ファイルを Ghidra headless で解析する
3. `ourin/analysis/decompiled.c` と `report.md` を生成する
4. `ourin.json` を生成する
5. `shared_value.dll` を `builtin:shared_value` として認識する

MVP では自動変換を目標にしない。解析、分類、Ourin 用マニフェスト生成を主目的とする。

## 注意点

- Ghidra の疑似 C は元ソースではないため、Swift/macOS plugin への完全自動変換は行わない
- 未信頼バイナリを扱うため、Ourin 本体プロセス内では実行しない
- Ghidra/Java 依存を通常ユーザーへ強制しない
- 元の SSP 資産を破壊しない
- 生成物の上書きは確認またはバックアップを必須にする

## ライセンス・帰属 / License & Attribution

- **Ghidra**: 本機能は Ghidra（National Security Agency 開発、Apache License 2.0）を外部
  ツールとして呼び出す。Ghidra は Ourin に同梱しない。
  - https://ghidra-sre.org/
  - https://www.apache.org/licenses/LICENSE-2.0
- **DecompileAll.java**: Ghidra スクリプト API を使用する Ourin のコード（CC BY-NC-SA 4.0）。
  実行時に `GhidraScriptSource.swift` から実体化される。
- **解析対象 DLL/EXE**: SSP 互換資産は各々のライセンスに従う。Migrator は読み取り専用で
  解析・変換を補助するものであり、元資産の再配布許可を意味しない。

アプリ内 About → 「ライセンスを表示…」から Ghidra ライセンス文を参照できる。
