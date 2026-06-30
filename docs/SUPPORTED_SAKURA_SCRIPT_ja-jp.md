# 対応 SAKURA SCRIPT (Ourin)

本文書は、Ourin で現在実装されている SakuraScript コマンドを、`SakuraScriptEngine.swift` のパース処理と `GhostManager.swift` の実行パスに基づいて一覧にしたものです。

ステータスマーク：
- ✅ 実装済み
- ⚠️ 部分実装 / オプション限定
- ❌ 未実装

## スコープコマンド

- ✅ `\0` / `\1` / `\h` / `\u`
- ✅ `\p[n]`

### バルーン表示寿命とスコープ切替の動作

SSP 互換の実装として、スコープ切替（`\0` / `\1` / `\p[n]`）はバルーンテキストを消去しません。各スコープのバルーン表示は独立しており、スコープを切り替えるだけで他スコープや切替先スコープ自身の表示が失われることはありません。これにより複数キャラクターが同時にバルーンを表示し続けることができます（SSP の動作に準拠）。

スコープを切り替えた後に同一スコープへ戻った場合、既存のバルーンテキストへ追記する形になります（上書きや消去はしません）。

**バルーンが消去されるタイミング：**

| 契機 | 詳細 |
|------|------|
| スクリプト開始（新発話） | `runScript` / `runNotifyScript`（テキストあり）/ `runPluginScript`（`nobreak` なし）の呼び出し時に全スコープのバルーンテキストを一括クリア（`GhostManager.swift` の各 `vm.text = ""`）|
| 明示的消去コマンド | `\c`、`\e[clear]`、`\x`（`noclear` なし）|

スコープ切替自体（`\0` / `\1` / `\p[n]`）はバルーンを消去しません（`GhostManager.swift` `processNextUnit` `.scope` ケース参照）。

## サーフェスコマンド

- ✅ `\s[n]`
- ✅ `\i[n]`, `\i[n,wait]`
- ✅ `\![anim,clear,ID]`
- ✅ `\![anim,pause,ID]`
- ✅ `\![anim,resume,ID]`
- ✅ `\![anim,offset,ID,x,y]`
- ⚠️ `\![anim,add,...]` (`overlay`, `base`, `bind`, `text` は実装済み。その他は限定的)
- ✅ `\![anim,stop]`
- ✅ `\![bind,category,part,value]`

## バルーン / テキストコマンド

- ✅ `\n`, `\n[half]`, `\n[percent]`
- ✅ `\b[n]`, `\b[...]`
- ✅ `\C`
- ✅ `\c[...]`
- ⚠️ `\f[...]` (主要なスタイル制御は実装済み。未対応のサブコマンドは無視)
- ✅ `\_l[x,y]`
- ✅ `\_v` / `\_V`

## キャラクター変更コマンド

- ✅ `\4` / `\5`
- ✅ `\![change,ghost,...]`
- ✅ `\![change,shell,...]`
- ✅ `\![change,balloon,...]`

## 待機コマンド

- ✅ `\w[n]`
- ✅ `\_w[ms]`
- ✅ `\__w[...]` (`clear`, 数値タイミング、および `animation,ID` 待機は実装済み)
- ✅ `\t`
- ✅ `\x`, `\x[noclear]`

## 選択肢コマンド

- ✅ `\q[...]`
- ✅ `\*`
- ✅ `\a`
- ✅ `\z`
- ✅ `\-`
- ✅ `\__q[...]`

## イベントコマンド

- ✅ `\![raise,...]`
- ✅ `\![notify,...]`
- ✅ `\![raiseother,...]` / `\![notifyother,...]`
- ✅ `\![raiseplugin,...]` / `\![notifyplugin,...]`
- ✅ `\![timerraise,...]` / `\![timernotify,...]`
- ✅ `\![timerraiseother,...]` / `\![timernotifyother,...]`
- ✅ `\![timerraiseplugin,...]` / `\![timernotifyplugin,...]`
- ✅ `\![embed,...]`

## サウンドコマンド

- ✅ `\8[filename]`
- ✅ `\![sound,play,...]`
- ✅ `\![sound,load,...]`
- ✅ `\![sound,loop,...]`
- ✅ `\![sound,wait,...]`
- ✅ `\![sound,pause,...]`
- ✅ `\![sound,resume,...]`
- ✅ `\![sound,stop,...]`
- ✅ `\![sound,option,...]`

## オープンコマンド

- ✅ `\v`
- ✅ `\6`
- ✅ `\7`
- ✅ `\+`
- ✅ `\_+`
- ⚠️ `\![open,...]` (多くのサブコマンドが実装済み。動作は OS 機能に応じて異なる)

## プロパティ操作

- ✅ `%property[...]` 展開
- ✅ `\![get,property,key]`
- ✅ `\![set,property,key,value]`

## 既知の部分的動作を持つ関連コマンド

- ⚠️ `\![move,...]` (x/y/time/method/scope は動作；`--base`、`--base-offset`、`--move-offset`、`--wait` に対応；いくつかのエッジケースが残る)
- ⚠️ `\![moveasync,...]` (非同期移動とキャンセルに対応；いくつかの高度なオプションは未実装)
- ⚠️ `\![set,scaling,...]` (コアスケーリング実装；いくつかの拡張フラグは未実装)
- ⚠️ `\![set,alpha,...]` (基本的なアルファ設定は実装済み；タイミング/待機バリアントは未実装)
- ⚠️ `\![set,zorder,...]` (コア順序付けは実装済み；複雑な組み合わせは未実装)
- ⚠️ `\![set,sticky-window,...]` (基本的なグループ化は実装済み；複雑なグループ処理は未実装)
