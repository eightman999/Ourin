> 本書は en-us 版原文（PropertySystem_en-us.md）の日本語訳です。

# プロパティシステムの実装

## 概要

プロパティシステムは、伺かのプロパティシステム仕様に従い、ゴーストスクリプトが実行時にベースウェアのパラメータを読み書きできるようにする仕組みです。これにより、ゴーストはシステム情報、ベースウェアの詳細、実行時データへ標準化された方法でアクセスできます。

## アーキテクチャ

### 主要コンポーネント

1. **PropertyProvider プロトコル** (`PropertyProvider.swift`)
   - すべてのプロパティプロバイダの基底プロトコル
   - プロパティの読み取り用に `get(key:)` をサポート
   - プロパティの書き込み用に `set(key:value:)` をサポート（任意）

2. **PropertyManager** (`PropertyManager.swift`)
   - すべてのプロパティプロバイダを統括する中央マネージャ
   - プレフィックスに基づいて、プロパティ要求を適切なプロバイダへ振り分け
   - `%property[...]` 環境変数の展開をサポート

### プロパティプロバイダ

#### SystemPropertyProvider
`system.*` プロパティを提供します:
- 日付/時刻: `system.year`, `system.month`, `system.day`, `system.hour`, `system.minute`, `system.second`, `system.millisecond`, `system.dayofweek`
- カーソル: `system.cursor.pos`
- OS 情報: `system.os.type`, `system.os.name`, `system.os.version`, `system.os.build`
- CPU 情報: `system.cpu.num`, `system.cpu.vendor`, `system.cpu.name`, `system.cpu.clock`, `system.cpu.features`, `system.cpu.load`
- メモリ情報: `system.memory.phyt`, `system.memory.phya`, `system.memory.load`

#### BasewarePropertyProvider
`baseware.*` プロパティを提供します:
- `baseware.name` - "Ourin" を返す
- `baseware.version` - アプリケーションのバージョンを返す

#### GhostPropertyProvider
`ghostlist.*`, `activeghostlist.*`, `currentghost.*` に関するゴースト関連プロパティを提供します:

**共通プロパティ:**
- `name`, `sakuraname`, `keroname`
- `craftmanw`, `craftmanurl`
- `path`, `icon`, `homeurl`
- `username`

**ghostlist:**
- `ghostlist.count` - インストール済みゴーストの数
- `ghostlist.index(n).{property}` - インデックスでゴーストにアクセス
- `ghostlist({name|sakuraname|path}).{property}` - 識別子でゴーストにアクセス

**currentghost:**
- 上記の基本プロパティ
- `currentghost.status` - ゴーストのステータス
- `currentghost.shelllist.count` - シェルの数
- `currentghost.shelllist.current.{property}` - 現在のシェルのプロパティ
- `currentghost.shelllist({name|path}).{property}` - 識別子で指定したシェル
- `currentghost.shelllist.index(n).{property}` - インデックスで指定したシェル
- `currentghost.scope.count` - スコープの数
- `currentghost.scope(n).surface.num` - スコープのサーフェス番号
- `currentghost.scope(n).{x|y|rect|name}` - スコープの位置と情報

**シェルプロパティ:**
- `name`, `path`, `menu` (hidden/empty)

**スコーププロパティ:**
- `surface.num`, `surface.x`, `surface.y`
- `x`, `y`, `rect`
- `name`, `seriko.defaultsurface`

#### BalloonPropertyProvider
バルーン関連のプロパティを提供します:

**balloonlist:**
- `balloonlist.count`
- `balloonlist.index(n).{name|path|craftmanw|craftmanurl}`
- `balloonlist({name|path}).{property}`

**currentghost.balloon:**
- `balloon.scope(n).count` - バルーン画像の数
- `balloon.scope(n).num` - バルーン ID
- `balloon.scope(n).validwidth` - テキスト描画幅
- `balloon.scope(n).validheight` - テキスト描画高さ
- `balloon.scope(n).lines` - 最大行数
- `balloon.scope(n).basepos.{x|y}` - テキスト開始位置
- `balloon.scope(n).char_width` - 文字幅

#### HeadlinePropertyProvider
`headlinelist.*` プロパティを提供します:
- `headlinelist.count`
- `headlinelist.index(n).{name|path|craftmanw|craftmanurl}`
- `headlinelist({name|path}).{property}`

#### PluginPropertyProvider
`pluginlist.*` プロパティを提供します:
- `pluginlist.count`
- `pluginlist.index(n).{name|path|id|craftmanw|craftmanurl|filename|native|executablepath|packagepath|executionstate|candispatchrequests}`
- `pluginlist({name|path|id|executablepath|packagepath}).{property}`
- `pluginlist({name|path|id|executablepath|packagepath}).message.<key>` - plugin パッケージの `message.*.txt` から読み取った言語別文字列（例: `message.menu.title`）

`path` は SSP 互換の元モジュール位置、`executablepath` は macOS native `.plugin` / `.bundle` 実体、
`packagepath` は `install.txt` 付き package directory です。Windows DLL 由来 plugin は
`executionstate=metadataOnly`、`candispatchrequests=0` として列挙のみ行います。

## 使い方

### 環境変数の展開

SakuraScript のテキスト内で `%property[key]` を使用してプロパティ値を埋め込みます:

```
%property[baseware.name] ver,%property[baseware.version]
```

これは次のように展開されます:
```
Ourin ver,1.0
```

### SakuraScript タグ

#### プロパティの取得

プロパティ値を取得し、その値を伴って SHIORI イベントを発火させます:

```
\![get,property,EventName,PropertyKey]
```

例:
```
\![get,property,OnGetSakuraName,ghostlist(Emily/Phase4.5).keroname]
```

これは `Reference0` に値 "Teddy" を含めた `OnGetSakuraName` イベントを発火させます。

#### プロパティの設定

書き込み可能なプロパティ値を設定します:

```
\![set,property,PropertyKey,Value]
```

例:
```
\![set,property,currentghost.shelllist(ULTIMATE FORM).menu,hidden]
```

これはシェル変更メニューから "ULTIMATE FORM" シェルを非表示にします。

### プログラムからのアクセス

```swift
let manager = PropertyManager()

// Get property
if let year = manager.get("system.year") {
    print("Current year: \(year)")
}

// Set property
manager.set("currentghost.shelllist(Default).menu", value: "hidden")

// Expand text with properties
let text = "Welcome to %property[baseware.name]!"
let expanded = manager.expand(text: text)
```

## 書き込み可能なプロパティ

現在、以下のプロパティが書き込み操作をサポートしています:

1. `currentghost.shelllist({name}).menu` - "hidden" を設定するとメニューからシェルを非表示にする

## 統合ポイント

### GhostManager
`GhostManager` クラスはプロパティ関連の SakuraScript コマンドを処理します:
- `\![get,property,...]` （408 行目）
- `\![set,property,...]` （421 行目）

### SakuraScriptEngine
`SakuraScriptEngine` は `PropertyManager` と統合されています:
- プロパティアクセス用に `propertyManager` プロパティを提供
- `%property[...]` の展開を `EnvironmentExpander` に委譲

### EnvironmentExpander
テキスト内の `%property[key]` 展開を処理します:
- `EnvironmentExpander.swift` の 109-111 行目
- `PropertyManager.get()` に委譲

## テスト

包括的なテストが `PropertySystemTests.swift` に用意されています:
- システムプロパティ（日付/時刻、OS 情報）
- ベースウェアプロパティ
- ゴーストプロパティ（ghostlist, currentghost）
- プロパティの展開
- バルーン、ヘッドライン、プラグインのプロパティ
- SET 機能

テストの実行:
```bash
xcodebuild test -project Ourin.xcodeproj -scheme Ourin
```

## 今後の拡張

仕様への完全準拠に向けた追加候補:

1. **履歴プロパティ** (`history.*`)
   - `history.ghost.*`, `history.balloon.*` など
   - 最近使用した項目のトラッキング

2. **使用率** (`rateofuselist.*`)
   - ゴーストの使用統計
   - 起動時間のトラッキング
   - 使用率の計算

3. **追加の書き込み可能プロパティ**
   - マウスカーソルのカスタマイズ (`currentghost.mousecursor.*`)
   - ツールチップのカスタマイズ (`currentghost.seriko.tooltip.*`)
   - サーフェスリストのプロパティ (`currentghost.seriko.surfacelist.*`)

4. **動的データ連携**
   - 実際の実行時ゴースト/シェル/バルーンデータへの接続
   - リアルタイムなスコープ位置のトラッキング
   - ライブなバルーンメトリクス

## 参考資料

- UKADOC プロパティシステム仕様: https://usada.sakura.vg/contents/specification.html
- SSP のプロパティ実装
- CROW のプロパティテストケース
