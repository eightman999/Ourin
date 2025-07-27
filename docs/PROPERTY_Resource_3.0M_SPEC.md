
# SHIORI Resource — **3.0M（macOS）** 仕様書（2.x互換, M‑Add付き）
**Updated:** 2025-07-27 (JST)  
**対象:** Ourin (macOS 10.15+ / Universal 2)  
**互換:** UKADOC「SHIORI Resourceリスト」に準拠。返却は**短いテキスト**（bool様含む）、IDは小文字で「On」無し。

## 目次
- [1. 基本方針](#1-基本方針)
- [2. 文字コード/改行](#2-文字コード改行)
- [3. 座標・パス（M‑Diff）](#3-座標パスm-diff)
- [4. キー一覧（完全）](#4-キー一覧完全)
  - [4.1 SHIORI情報](#41-shiori情報)
  - [4.2 ゴースト情報](#42-ゴースト情報)
  - [4.3 更新情報](#43-更新情報)
  - [4.4 オーナードローメニュー画像](#44-オーナードローメニュー画像)
  - [4.5 オーナードローメニュー文字色](#45-オーナードローメニュー文字色)
  - [4.6 オーナードローメニュー項目表示](#46-オーナードローメニュー項目表示)
  - [4.7 オーナードローメニュー項目名 / ショートカット](#47-オーナードローメニュー項目名--ショートカット)
- [5. 返答コード規約](#5-返答コード規約)
- [6. M‑Add / 注意](#6-m-add--注意)
- [7. 出典](#7-出典)

---

## 1. 基本方針
- **語彙互換**：UKADOC のキー名・意味を継承。  
- **macOS 置換（M‑Diff）**：パスは POSIX/URL、座標は**左上原点で解釈**→内部では AppKit の**左下原点**に変換。

## 2. 文字コード/改行
- 送受信 **UTF‑8** 標準。CP932/SJIS 受理→内部UTF‑8。  
- 改行は `LF`（`CRLF` 受理）。

## 3. 座標・パス（M‑Diff）
- `*.defaultleft/top` 等は **左上原点スクリーン座標**として受理。Ourin内部で `y' = screenHeight - 1 - y` 等に変換。  
- 画像/ログのパスは **SHIORIの位置からの相対**または `file://`/POSIX を推奨。

## 4. キー一覧（完全）

### 4.1 SHIORI情報
|キー|カテゴリ|型|例/値域|備考|
|---|---|---|---|---|
|version|SHIORI情報|string|例:"Satori/3.0"|SHIORI本体の名称/版。|
|craftman|SHIORI情報|string(ASCII)|作者名(7bit)|作者名(7bit)。|
|craftmanw|SHIORI情報|string|作者名(マルチバイト可)|作者名(拡張)。|
|name|SHIORI情報|string(ASCII)|例:"A.L.I.C.E"|SHIORIの名前。|
|log_path|SHIORI情報|path|フルパス|SHIORIログのパス。|


### 4.2 ゴースト情報
|キー|カテゴリ|型|例/値域|備考|
|---|---|---|---|---|
|homeurl|ゴースト情報|URL|http(s)://...|ネットワーク更新のベースURL。|
|useorigin1|ゴースト情報|int(0|1)|0 or 1|更新のファイル数開始値。|
|username|ゴースト情報|string|任意|ユーザー名。|
|sakura.defaultx|ゴースト情報|int|px|画像ベースX|
|kero.defaultx|ゴースト情報|int|px|画像ベースX|
|char*.defaultx|ゴースト情報|int|px|画像ベースX|
|sakura.defaulty|ゴースト情報|int|px|画像ベースY|
|kero.defaulty|ゴースト情報|int|px|画像ベースY|
|char*.defaulty|ゴースト情報|int|px|画像ベースY|
|sakura.defaultleft|ゴースト情報|int|screen X|左上原点X|
|kero.defaultleft|ゴースト情報|int|screen X|左上原点X|
|char*.defaultleft|ゴースト情報|int|screen X|左上原点X|
|sakura.defaulttop|ゴースト情報|int|screen Y|左上原点Y|
|kero.defaulttop|ゴースト情報|int|screen Y|左上原点Y|
|char*.defaulttop|ゴースト情報|int|screen Y|左上原点Y|
|communicatebox.defaultleft|ゴースト情報|int|screen X|入力ボックス既定X|
|communicatebox.defaulttop|ゴースト情報|int|screen Y|入力ボックス既定Y|
|scriptbox.defaultleft|ゴースト情報|int|screen X||
|scriptbox.defaulttop|ゴースト情報|int|screen Y||
|addressbar.defaultleft|ゴースト情報|int|screen X||
|addressbar.defaulttop|ゴースト情報|int|screen Y||
|teachbox.defaultleft|ゴースト情報|int|screen X||
|teachbox.defaulttop|ゴースト情報|int|screen Y||
|dateinput.defaultleft|ゴースト情報|int|screen X||
|dateinput.defaulttop|ゴースト情報|int|screen Y||
|timeinput.defaultleft|ゴースト情報|int|screen X||
|timeinput.defaulttop|ゴースト情報|int|screen Y||
|ipinput.defaultleft|ゴースト情報|int|screen X||
|ipinput.defaulttop|ゴースト情報|int|screen Y||
|sliderinput.defaultleft|ゴースト情報|int|screen X||
|sliderinput.defaulttop|ゴースト情報|int|screen Y||
|passwordinput.defaultleft|ゴースト情報|int|screen X||
|passwordinput.defaulttop|ゴースト情報|int|screen Y||
|inputbox.defaultleft|ゴースト情報|int|screen X||
|inputbox.defaulttop|ゴースト情報|int|screen Y||
|sakura.recommendsites|ゴースト情報|list(string)|特殊区切り|項目名/URL/バナー/スクリプト|
|sakura.portalsites|ゴースト情報|list(string)|特殊区切り||
|kero.recommendsites|ゴースト情報|list(string)|特殊区切り||
|char*.recommendsites|ゴースト情報|list(string)|特殊区切り||
|sakura.recommendbuttoncaption|ゴースト情報|string|名称|従来ボタン名|
|sakura.portalbuttoncaption|ゴースト情報|string|名称||
|kero.recommendbuttoncaption|ゴースト情報|string|名称||
|char*.recommendbuttoncaption|ゴースト情報|string|名称||
|updatebuttoncaption|ゴースト情報|string|名称||
|vanishbuttoncaption|ゴースト情報|string|名称||
|readmebuttoncaption|ゴースト情報|string|名称||
|vanishbuttonvisible|ゴースト情報|int(0|1)|0/1|可視|
|sakura.popupmenu.visible|ゴースト情報|int(0|1)|0/1||
|kero.popupmenu.visible|ゴースト情報|int(0|1)|0/1||
|char*.popupmenu.visible|ゴースト情報|int(0|1)|0/1||
|sakura.popupmenu.type|ゴースト情報|string|型名|SSP定義に準拠|
|kero.popupmenu.type|ゴースト情報|string|型名||
|char*.popupmenu.type|ゴースト情報|string|型名||
|getaistate|ゴースト情報|string|数値列 + 区切り|AIグラフ|
|getaistateex|ゴースト情報|string/204|数値列 or 無|AIグラフ(多重)|
|legacyinterface|ゴースト情報|int(0|1)|0/1|レガシーUI|


### 4.3 更新情報
|キー|カテゴリ|型|例/値域|備考|
|---|---|---|---|---|
|other_homeurl_override|更新情報|special|URL or 空/204|更新先URLの強制置換|


### 4.4 オーナードローメニュー画像
|キー|カテゴリ|型|例/値域|備考|
|---|---|---|---|---|
|menu.sidebar.bitmap.filename|メニュー画像|path|相対パス|サイドバー|
|menu.background.bitmap.filename|メニュー画像|path|相対パス|背景|
|menu.foreground.bitmap.filename|メニュー画像|path|相対パス|前景|


### 4.5 オーナードローメニュー文字色
|キー|カテゴリ|型|例/値域|備考|
|---|---|---|---|---|
|menu.background.font.color.r|メニュー色|int(0..255)|0..255|背景文字色|
|menu.background.font.color.g|メニュー色|int(0..255)|0..255|背景文字色|
|menu.background.font.color.b|メニュー色|int(0..255)|0..255|背景文字色|
|menu.foreground.font.color.r|メニュー色|int(0..255)|0..255|前景文字色|
|menu.foreground.font.color.g|メニュー色|int(0..255)|0..255|前景文字色|
|menu.foreground.font.color.b|メニュー色|int(0..255)|0..255|前景文字色|
|menu.separator.color.r|メニュー色|int(0..255)|0..255|セパレータ色|
|menu.separator.color.g|メニュー色|int(0..255)|0..255|セパレータ色|
|menu.separator.color.b|メニュー色|int(0..255)|0..255|セパレータ色|
|menu.frame.color.r|メニュー色|int(0..255)|0..255|枠色|
|menu.frame.color.g|メニュー色|int(0..255)|0..255|枠色|
|menu.frame.color.b|メニュー色|int(0..255)|0..255|枠色|
|menu.disable.font.color.r|メニュー色|int(0..255)|0..255|無効文字色|
|menu.disable.font.color.g|メニュー色|int(0..255)|0..255|無効文字色|
|menu.disable.font.color.b|メニュー色|int(0..255)|0..255|無効文字色|


### 4.6 オーナードローメニュー項目表示
（**規則**）「項目名の `.caption` を `.visible` に置換したキー」が存在し、**1=表示、0=非表示**。  
|キー|カテゴリ|型|例/値域|備考|
|---|---|---|---|---|
|activaterootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|addressbarbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|alignrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|alwaysstayontopbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|alwaystrayiconvisiblebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|balloonhistorybutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|balloonrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|biffallbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|biffbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|calendarbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|callghosthistorybutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|callghostrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|callsstpsendboxbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|char*.recommendsites.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|charsetbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|closeballoonbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|closebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|collisionvisiblebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|configurationbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|configurationrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|debugballoonbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|definedsurfaceonlybutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|dressuprootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|duibutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|enableballoonmovebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|firststaffbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|ghostexplorerbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|ghosthistorybutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|ghostinstallbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|ghostrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|headlinesensehistorybutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|headlinesenserootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|helpbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|hidebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|historyrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|inforootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|leavepassivebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|messengerbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|pluginhistorybutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|pluginrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|portalrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|purgeghostcachebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|quitbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|rateofuseballoonbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|rateofusebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|rateofuserootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|rateofusetotalbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|readmebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|termsbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|recommendrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|regionenabledbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|reloadinfobutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|resetballoonpositionbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|resettodefaultbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|scriptlogbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|shellrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|shellscaleotherbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|shellscalerootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|sntpbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchactivatewhentalkbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchactivatewhentalkexceptupdatebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchautobiffbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchautoheadlinesensebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchblacklistingbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchcompatiblemodebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchconsolealwaysvisiblebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchconsolevisiblebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchdeactivatebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchdontactivatebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchdontforcealignbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchduivisiblebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchforcealignfreebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchforcealignlimitbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchignoreserikomovebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchlocalsstpbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchmovetodefaultpositionbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchproxybutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchquietbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchreloadbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchreloadtempghostbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchremotesstpbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|switchtalkghostbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|systeminfobutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|updatebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|updatefmobutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|updateplatformbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|utilityrootbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|vanishbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|aistatebutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|dictationbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|
|texttospeechbutton.visible|メニュー項目表示|int(0|1)|0/1|1=表示, 0=非表示|


### 4.7 オーナードローメニュー項目名 / ショートカット
キャプション文字列中に **`&X`** を含めると **X** がショートカットキーになる（大/小区別なし、記号も可）。  
|キー|カテゴリ|型|例/値域|備考|
|---|---|---|---|---|
|activaterootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|addressbarbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|alignrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|alwaysstayontopbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|alwaystrayiconvisiblebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|balloonhistorybutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|balloonrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|biffallbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|biffbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|calendarbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|callghosthistorybutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|callghostrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|callsstpsendboxbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|char*.recommendsites.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|charsetbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|closeballoonbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|closebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|collisionvisiblebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|configurationbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|configurationrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|debugballoonbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|definedsurfaceonlybutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|dressuprootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|duibutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|enableballoonmovebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|firststaffbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|ghostexplorerbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|ghosthistorybutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|ghostinstallbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|ghostrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|headlinesensehistorybutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|headlinesenserootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|helpbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|hidebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|historyrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|inforootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|leavepassivebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|messengerbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|pluginhistorybutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|pluginrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|portalrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|purgeghostcachebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|quitbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|rateofuseballoonbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|rateofusebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|rateofuserootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|rateofusetotalbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|readmebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|termsbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|recommendrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|regionenabledbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|reloadinfobutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|resetballoonpositionbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|resettodefaultbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|scriptlogbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|shellrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|shellscaleotherbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|shellscalerootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|sntpbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchactivatewhentalkbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchactivatewhentalkexceptupdatebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchautobiffbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchautoheadlinesensebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchblacklistingbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchcompatiblemodebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchconsolealwaysvisiblebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchconsolevisiblebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchdeactivatebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchdontactivatebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchdontforcealignbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchduivisiblebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchforcealignfreebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchforcealignlimitbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchignoreserikomovebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchlocalsstpbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchmovetodefaultpositionbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchproxybutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchquietbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchreloadbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchreloadtempghostbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchremotesstpbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|switchtalkghostbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|systeminfobutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|updatebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|updatefmobutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|updateplatformbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|utilityrootbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|vanishbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|aistatebutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|dictationbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|
|texttospeechbutton.caption|メニュー項目名|string|表示名|ショートカット: '&X' を文字列に含める|


## 5. 返答コード規約
- **200 OK**：値あり（本文=短いテキスト）。  
- **204 No Content**：未設定/該当なし（例：`getaistateex` で範囲外）。

## 6. M‑Add / 注意
- `log_path` は Ourin の UI から「ログを開く」で使用可能（パスは macOS のファイルURLに正規化可）。  
- `sakura.recommendsites` 等の**特殊区切り**は UKADOC の定義に従う（`[バイト1]` 区切り等）。  
- `.visible`/`.caption` の**組**をまとめて問い合わせる最適化キャッシュを実装可。

## 7. 出典
- UKADOC「SHIORI Resourceリスト」全体、`getaistate(ex)`、`legacyinterface`、オーナードローメニュー各種、ショートカット規定 等。  
