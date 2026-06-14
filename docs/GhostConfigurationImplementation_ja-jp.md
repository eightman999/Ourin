> 本書は英語版原文 `GhostConfigurationImplementation_en-us.md` の日本語版です。

# ゴースト設定システムの実装

## 概要

`descript.txt` ファイルからゴースト設定を読み込み、適用するための包括的なシステムを実装しました。これにより、伺かの仕様に従って、ゴーストは起動時および読み込み時に環境変数やプロパティを設定できます。

## 実装の概要

### 1. GhostConfiguration 構造体 (`Ourin/Ghost/GhostConfiguration.swift`)

すべての `descript.txt` の値を保持する包括的な構造体を作成しました。

**基本情報:**
- `charset`, `type`, `name`
- `sakura.name`, `kero.name`, `char*.name`
- `id`, `title`

**作者情報:**
- `craftman`, `craftmanw`, `craftmanurl`
- `homeurl`

**SHIORI 設定:**
- `shiori` (DLL ファイル名)
- `shiori.version`, `shiori.cache`, `shiori.encoding`, `shiori.forceencoding`
- `shiori.escape_unknown`

**サーフェス設定:**
- `sakura.seriko.defaultsurface`, `kero.seriko.defaultsurface`
- `char*.seriko.defaultsurface`
- `balloon.defaultsurface`

**位置設定:**
- `seriko.alignmenttodesktop` (top/bottom/free)
- スコープ固有のアライメント: `sakura.seriko.alignmenttodesktop`, `kero.seriko.alignmenttodesktop`, `char*.seriko.alignmenttodesktop`
- 基準位置: `sakura.defaultx/y`, `kero.defaultx/y`, `char*.defaultx/y`
- 表示位置: `sakura.defaultleft/top`, `kero.defaultleft/top`, `char*.defaultleft/top`

**SSTP 設定:**
- `sstp.allowunspecifiedsend`, `sstp.allowcommunicate`, `sstp.alwaystranslate`

**バルーン設定:**
- `balloon`, `default.balloon.path`
- `recommended.balloon`, `recommended.balloon.path`
- `balloon.dontmove`, `balloon.syncscale`

**UI 設定:**
- `icon`, `icon.minimize`
- `mousecursor`, `mousecursor.text`, `mousecursor.wait`, `mousecursor.hand`, `mousecursor.grip`, `mousecursor.arrow`
- `menu.font.name`, `menu.font.height`

**動作設定:**
- `name.allowoverride`
- `don't need onmousemove`, `don't need bind`, `don't need seriko talk`

**AI グラフ設定:**
- `shiori.logo.file`, `shiori.logo.x`, `shiori.logo.y`, `shiori.logo.align`

**インストール:**
- `install.accept`, `readme`, `readme.charset`

### 2. ゴースト統合 (`Ourin/Property/GhostPropertyProvider.swift`)

設定を含めるように `Ghost` 構造体を拡張しました。
- `configuration: GhostConfiguration?` プロパティを追加
- `init(from config: GhostConfiguration, path: String, username: String?)` イニシャライザを追加

### 3. GhostManager 統合 (`Ourin/Ghost/GhostManager.swift`)

**設定の読み込み:**
- `ghostConfig: GhostConfiguration?` プロパティを追加
- `start()` 中に `descript.txt` から設定を読み込み
- デバッグ用に設定の詳細をログ出力

**設定の適用:**
- `applyGhostConfiguration(_:ghostRoot:)` メソッドを追加
- homeurl を ResourceManager に適用
- デフォルトのサーフェス位置 (sakura/kero/char*.defaultx/y) を適用
- アライメント設定に基づいて表示位置を適用
- 位置を適用する際に `seriko.alignmenttodesktop` を尊重
- 永続化のために位置を ResourceManager に保存

### 4. 包括的なテストスイート (`OurinTests/GhostConfigurationTests.swift`)

以下をカバーする広範なテストを作成しました。
- 基本パース (必須/任意フィールド)
- サーフェス設定
- 位置設定 (アライメントを含む)
- キャラクター固有の位置 (char2, char3 など)
- SSTP 設定
- バルーン設定
- UI 設定
- 動作設定
- SHIORI 設定
- インストール設定
- AI グラフ設定
- Emily4 の実環境テストケース
- Ghost 構造体の統合

## 使い方

### 自動読み込み

設定はゴーストの起動時に自動的に読み込まれます。

```swift
let ghostRoot = ghostURL.appendingPathComponent("ghost/master", isDirectory: true)
if let config = GhostConfiguration.load(from: ghostRoot) {
    self.ghostConfig = config
    applyGhostConfiguration(config, ghostRoot: ghostRoot)
}
```

### 手動読み込み

```swift
// Load from a ghost directory
let config = GhostConfiguration.load(from: ghostRootURL)

// Parse from a dictionary
let dict = ["name": "MyGhost", "sakura.name": "Sakura"]
let config = GhostConfiguration.parse(from: dict)

// Create programmatically
let config = GhostConfiguration(
    name: "TestGhost",
    sakuraName: "Sakura",
    keroName: "Kero"
)
```

### 設定からの Ghost の作成

```swift
let ghost = Ghost(from: config, path: "/path/to/ghost")
```

## 設定の優先順位

1. **位置設定:**
   - `seriko.alignmenttodesktop` がグローバルなデフォルト (top/bottom/free) を設定
   - `sakura.seriko.alignmenttodesktop` が sakura について上書き
   - `kero.seriko.alignmenttodesktop` が kero について上書き
   - `char*.seriko.alignmenttodesktop` が追加キャラクターについて上書き
   - 表示位置 (`defaultleft/top`) はアライメントが `free` の場合のみ適用

2. **実行時の値と descript.txt:**
   - 設定値は起動時に読み込まれる
   - ユーザーが変更した設定については ResourceManager の実行時の値が優先される
   - 設定は妥当なデフォルト値を提供する

## 対応エンコーディング

- UTF-8 (推奨)
- Shift_JIS/CP932 (互換性のためのフォールバック)

## descript.txt の例

```
charset,Shift_JIS
type,ghost
name,Emily/Phase4.5
sakura.name,Emily
kero.name,Teddy
balloon,emily4
id,Emily/Phase4.5
char2.seriko.defaultsurface,200
name.allowoverride,0
craftmanurl,http://ssp.shillest.net/
craftman,[SSPBT/GL03B]Emily Development Team
sstp.allowunspecifiedsend,1
icon,icon.ico
shiori,yaya.dll
shiori.version,SHIORI/3.0
```

## 今後の拡張

仕様で確認された追加候補。

1. **MAKOTO サポート:**
   - `makoto` DLL の指定

2. **高度な位置制御:**
   - シェル固有の位置の上書き
   - 実行時の位置の永続化

3. **カーソル管理:**
   - カスタムカーソルファイルの読み込みと適用
   - スコープ固有のカーソル設定

4. **ツールチップ設定:**
   - `currentghost.seriko.tooltip.*` プロパティ

5. **履歴の追跡:**
   - 最近使用したゴースト/バルーン/シェル
   - 使用統計

## 参考資料

- UKADOC descript.txt 仕様: https://ssp.shillest.net/ukadoc/manual/descript_ghost.html
- SSP プロパティシステム仕様
- Ourin プロパティシステムのドキュメント: `docs/PropertySystem.md`

## 変更されたファイル

- **新規:** `Ourin/Ghost/GhostConfiguration.swift`
- **新規:** `OurinTests/GhostConfigurationTests.swift`
- **変更:** `Ourin/Property/GhostPropertyProvider.swift`
- **変更:** `Ourin/Ghost/GhostManager.swift`
- **修正:** `OurinTests/NarInstallTests.swift` (不足していた Foundation import を追加)
- **修正:** `OurinTests/ShioriLoaderTests.swift` (非推奨の `#fail` を `Issue.record` に置き換え)

## ビルド状況

✅ ビルド成功
✅ すべてのコードがエラーなくコンパイル
✅ 包括的なテストスイートを作成 (すべての設定項目をカバーする 18 個のテスト)

## 技術的詳細

### パース戦略

本実装は 2 段階のパースアプローチを採用しています。

1. **ファイル読み込み:** エンコーディング検出に既存の `DescriptorLoader` パターンを使用 (まず UTF-8、次に Shift_JIS のフォールバック)

2. **値のパース:** `GhostConfiguration.parse(from:)` が辞書を処理する。
   - 必須フィールドを検証 (name は存在しなければならない)
   - 任意フィールドには妥当なデフォルト値
   - 安全な型変換 (Int パース、enum マッチング)
   - `char*` エントリは正規表現パターンマッチングでパース

### キャラクターパターンのパース

追加キャラクター (char2, char3 など) は正規表現を用いてパースされます。

```swift
let charPattern = "^char(\\d+)\\.(.+)$"
// Matches: char2.name, char3.defaultx, etc.
```

### エラー処理

- 必須フィールドが欠けている場合は `nil` を返す
- 無効な値を適切に処理 (デフォルトにフォールバック)
- 不正な形式の設定については警告をログ出力
- 重要でないフィールドには Swift のオプショナルを使用

### パフォーマンス

- パースはゴースト起動時に一度だけ実行される
- 設定はメモリにキャッシュされる
- 実行時の操作にパフォーマンスへの影響はない

## 既存システムとの統合

- **PropertyManager:** プロパティクエリに設定値を使用できる
- **ResourceManager:** 設定から初期値を受け取り、実行時の変更を保存する
- **GhostPropertyProvider:** プロパティシステムを通じて設定を公開できる
- **SERIKO Engine:** 設定からサーフェスのデフォルト値を使用する
- **SSTP Server:** SSTP の許可設定を尊重する
- **Balloon System:** 設定からバルーンの設定を使用する
