# Sakura Script Commands - Ourin 対応状況

これは en-us 版オリジナル（`SAKURASCRIPT_COMMANDS_SUPPORTED_en-us.md`）の日本語版です。

このドキュメントは、現在 Ourin の `SakuraScriptEngine` がサポートしているすべてのさくらスクリプトコマンドを一覧化したものです。

## 2026-03 ukadoc ギャップ監査（優先度順）

ukadoc（`/manual/list_sakura_script.html`）と `GhostManager` の現行ランタイムハンドラを比較した結果、主な残存ギャップは以下のとおりです。

1. **イベント連携のギャップ（高）**  
   - `\![embed,event,...]` インラインイベント埋め込み  
   - `\![timerraise,ms,repeat,event,...]` 遅延／繰り返しイベント発火  
   - ステータス: **本アップデートで実装済み**

2. **ランタイム切り替えのギャップ（高）**  
    - `\![change,ghost,name]` 完全なゴースト切り替えセマンティクス  
    - `\![change,shell,name]` シェル切り替えと再描画  
    - `\![change,balloon,name]` バルーン設定切り替え  
   - ステータス: **本アップデートで拡張**（`--option=raise-event`、`OnGhostChanging/Changed`、`OnShellChanging/Changed`、`OnBalloonChange`）
   - 関連: `\![call,ghost,name]` ランタイムパスを `OnGhostCalling/OnGhostCalled` とともに追加

3. **ダイアログ系のギャップ（高）**  
   - `\![open,inputbox|dateinput|sliderinput|dialog|teachbox,...]`  
   - ステータス: **本アップデートで拡張**（`passwordinput|timeinput|ipinput` を追加、`--timeout`、`--text` などのオプション形式引数、ダイアログサブタイプ `open/save/folder/color` に対応）

8. **入力以外の open 系（高）**  
   - `\![open,browser|mailer|editor|explorer|file|readme|terms|help,...]` および `\![open,communicatebox]`  
   - `\![close,inputbox|communicatebox|dialog|teachbox,...]`  
   - ステータス: **本アップデートで実装済み**（ランタイムルーティングを追加し、既存のダイアログイベントパスを再利用）
   - 拡張: `\![open,ghostexplorer|shellexplorer|balloonexplorer|headlinesensorexplorer|pluginexplorer|rateofusegraph|calendar|messenger|surfacetest|aigraph]`

9. **プラグインイベント系（高）**  
   - `\![raiseplugin|notifyplugin,plugin,event,...]`  
   - `\![timerraiseplugin|timernotifyplugin,ms,repeat,plugin,event,...]`  
   - ステータス: **本アップデートで実装済み**（id／name／filename に加えて `random`／`lastinstalled` によるプラグインターゲット解決、タイマーの上書き／キャンセルセマンティクス）

4. **サウンド拡張系（中）**  
   - `\![sound,play|load|loop|wait|pause|resume|stop|option,...]`  
   - ステータス: **本アップデートで拡張**（`load/wait/pause/resume/option` ランタイムパスを追加）

5. **セマンティクス不一致コマンド（中）**  
   - `\6`、`\7`、`\-` の挙動が一部 ukadoc の期待と異なる  
   - ステータス: **本アップデートで対応**（`\7` は SNTP フローを開始、`\6` は SNTP 調整アクションを適用、`\-` はゴーストを終了）

6. **ゴースト間イベントルーティング（高）**  
   - `\![raiseother,...]`、`\![notifyother,...]`  
   - `\![timerraiseother,...]`、`\![timernotifyother,...]`  
   - ステータス: **本アップデートで実装済み**（バイト1区切り文字や `__SYSTEM_ALL_GHOST__` を含むターゲット解析、キー単位のタイマースケジューリング／キャンセル）

7. **notify タイマーセマンティクス（高）**  
   - `\![notify,...]`、`\![timernotify,...]` のレスポンス処理とタイマー挙動  
   - ステータス: **本アップデートで実装済み**（`notify` はレスポンススクリプトを破棄するようになり、`timerraise/timernotify` は 0=繰り返し、>=1=一回限り に従い、`ms=0` によるイベント単位のキャンセル／上書きをサポート）

## スコープコマンド

### キャラクター／スコープ選択

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\0` or `\h` | Sakura（キャラクター0）に切り替え | `\0Hello from Sakura` |
| `\1` or `\u` | Unyuu（キャラクター1）に切り替え | `\1Hello from Unyuu` |
| `\pN` | キャラクターN（0-9）に切り替え | `\p2Hello from third character` |
| `\p[N]` | キャラクターN（任意のID）に切り替え | `\p[15]Hello from character 15` |

## サーフェスコマンド

### サーフェス表示

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\sN` | サーフェスをID N（0-9）に変更 | `\s1Switch to surface 1` |
| `\s[N]` | サーフェスをID N（任意のID）に変更 | `\s[100]Switch to surface 100` |
| `\s[-1]` | サーフェスを非表示 | `\s[-1]Character becomes invisible` |

## アニメーションコマンド

### 基本アニメーション

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\i[ID]` | アニメーションIDを再生 | `\i[10]Play animation 10` |
| `\i[ID,wait]` | アニメーションを再生し完了まで待機 | `\i[100,wait]This text appears after animation` |

### アニメーション制御（`\!` コマンド経由）

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![anim,clear,ID]` | アニメーションIDを停止 | `\![anim,clear,100]` |
| `\![anim,pause,ID]` | アニメーションIDを一時停止 | `\![anim,pause,200]` |
| `\![anim,resume,ID]` | 一時停止中のアニメーションIDを再開 | `\![anim,resume,200]` |
| `\![anim,offset,ID,x,y]` | アニメーション位置をオフセット | `\![anim,offset,300,40,50]` |
| `\![anim,stop]` | すべてのアニメーションを停止 | `\![anim,stop]` |

### アニメーションレイヤー制御

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![anim,add,overlay,ID]` | 現在のサーフェスにサーフェスIDをオーバーレイ | `\![anim,add,overlay,10]` |
| `\![anim,add,overlayfast,ID]` | overlayfast モードでオーバーレイ | `\![anim,add,overlayfast,10]` |
| `\![anim,add,base,ID]` | ベースサーフェスをIDに変更 | `\![anim,add,base,5]` |
| `\![anim,add,move,x,y]` | サーフェスを座標に移動 | `\![anim,add,move,100,200]` |

## バルーンコマンド

### バルーンID切り替え

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\bN` | バルーンをID N（0-9のみ）に変更 | `\b2Switch to balloon 2` |
| `\b[ID]` | バルーンをID（任意のID、負数で非表示）に変更 | `\b[2]Large balloon` |
| `\b[-1]` | バルーンを非表示 | `\b[-1]Hidden` |

**注意:**
- メインキャラクターのバルーンには偶数ID（0, 2, 4, 6, 8）のみ使用可能
- 奇数IDはパートナー／右側バルーン用に予約されています
- SSP 2.6.34+ はフォールバック構文をサポート: `\b[ID1,--fallback=ID2,--fallback=ID3]`

### バルーン画像

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\_b[file,x,y]` | XY座標に画像を表示（左上を透過） | `\_b[image\test.png,50,100]` |
| `\_b[file,x,y,opaque]` | 透過なしで画像を表示 | `\_b[test.png,0,15,opaque]` |
| `\_b[file,inline]` | テキストとインラインで画像を表示 | `Text\_b[icon.png,inline]more` |
| `\_b[file,inline,opaque]` | 透過なしでインライン画像を表示 | `\_b[icon.png,inline,opaque]` |

**オプション**（`\_b[file,x,y,options...]` または `\_b[file,inline,options...]` 用）:
- `--option=opaque` - 透過なし
- `--option=use_self_alpha` - PNGのアルファチャンネルを使用
- `--clipping=left top right bottom` - 画像領域を切り抜き
- `--option=fixed` - テキストとともにスクロールしない
- `--option=background` - テキストの背後に表示（デフォルト）
- `--option=foreground` - テキストの前面に表示

**例:**
```
\_b[test.png,10,20,--option=use_self_alpha,--clipping=100 30 150 90,--option=foreground]
```

### バルーン制御

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![set,autoscroll,disable]` | オートスクロールを無効化 | `\![set,autoscroll,disable]` |
| `\![set,autoscroll,enable]` | オートスクロールを有効化 | `\![set,autoscroll,enable]` |
| `\![set,balloonoffset,x,y]` | バルーンオフセットを設定 | `\![set,balloonoffset,100,-50]` |
| `\![set,balloonoffset,@x,@y]` | バルーンの相対オフセットを設定 | `\![set,balloonoffset,@100,@-50]` |
| `\![set,balloonalign,DIR]` | バルーンの配置を設定（left/center/top/right/bottom/none） | `\![set,balloonalign,top]` |
| `\![set,balloonmarker,text]` | SSTP受信マーカーを設定 | `\![set,balloonmarker,SSTP]` |
| `\![set,balloonnum,file,cur,max]` | ファイル転送インジケータを設定 | `\![set,balloonnum,test.zip,1,5]` |
| `\![set,balloontimeout,ms]` | バルーンタイムアウトを設定（0 または -1 = タイムアウトなし） | `\![set,balloontimeout,3000]` |
| `\![set,balloonwait,rate]` | テキスト速度の倍率を設定 | `\![set,balloonwait,1.5]` |
| `\![set,serikotalk,true/false]` | SERIKOの口パクアニメーションを有効化／無効化 | `\![set,serikotalk,false]` |
| `\![enter,onlinemode]` | オンラインマーカー表示を強制 | `\![enter,onlinemode]` |
| `\![leave,onlinemode]` | オンラインマーカーを非表示 | `\![leave,onlinemode]` |
| `\![enter,nouserbreakmode]` | ユーザーによるスクリプト中断を無効化 | `\![enter,nouserbreakmode]` |
| `\![leave,nouserbreakmode]` | ユーザーによるスクリプト中断を有効化 | `\![leave,nouserbreakmode]` |
| `\![lock,balloonrepaint]` | アンロックまたはスクリプト終了までバルーンの再描画をロック | `\![lock,balloonrepaint]` |
| `\![lock,balloonrepaint,manual]` | 明示的なアンロックまでバルーンの再描画をロック | `\![lock,balloonrepaint,manual]` |
| `\![unlock,balloonrepaint]` | バルーンの再描画をアンロック | `\![unlock,balloonrepaint]` |
| `\![lock,balloonmove]` | バルーンのドラッグ移動を禁止 | `\![lock,balloonmove]` |
| `\![unlock,balloonmove]` | バルーンのドラッグ移動を許可 | `\![unlock,balloonmove]` |

## テキスト制御コマンド

### 基本テキスト制御

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\n` | 改行 | `Line 1\nLine 2` |
| `\n[half]` | 半分の高さの改行 | `Line 1\n[half]Line 2` |
| `\n[percent]` | 任意の高さの改行（行高に対する%） | `Line 1\n[150]Line 2` |
| `\e` | スクリプト終了 | `Done\e` |
| `\C` | 追記モード（前のバルーンに追記） | `\CAppend to previous` |

### テキスト配置

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\_l[x,y]` | カーソルをXY座標に配置 | `\_l[30,100]Positioned` |

**座標フォーマット:**
- 数値: 左上からのピクセル（例: `30`）
- em: 文字の高さ（例: `5em`）
- lh: 行の高さ（例: `2lh`）
- %: 文字高に対する割合（例: `100%`）
- @: 現在位置からの相対（例: `@-100`）
- パラメータを省略すると現在値を維持（例: `\_l[,@-100]` はYのみ移動）

**例:**
```
\_l[30,5em]       Text at X=30px, Y=5 characters
\_l[@-1650%,100]  X=left 16.5 characters, Y=100px
\_l[,@-100]       Same X, 100px up
```

### テキストクリア

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\c` | 現在のスコープのバルーンをクリア | `Text\cCleared` |
| `\c[char,N]` | カーソルからN文字をクリア | `Delete\c[char,3]End` |
| `\c[char,N,start]` | 指定位置からN文字をクリア | `Text\c[char,3,4]End` |
| `\c[line,N]` | カーソルからN行をクリア | `Line 1\nLine 2\c[line,1]` |
| `\c[line,N,start]` | 指定位置からN行をクリア | `\c[line,1,2]` |

**注意:**
- 文字／行のカウントは表示位置ではなくスクリプト順に従います
- `\_b[file,inline]` 画像は1文字としてカウントされます
- `\n`、`\n[...]`、`\_l[x,y]` で区切られた行は別々の行としてカウントされます
- 空行（例: `\n\n`）はカウントされません

### テキスト折り返し

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\_n` | 自動折り返しを無効化（次の `\_n` まで） | `\_nNo wrap\_n` |

### 待機コマンド

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\w[N]` | N×50ms 待機 | `\w[10]Wait 500ms` |
| `\__w[animation,ID]` | アニメーションIDの完了を待機 | `\__w[animation,400]` |

### タグのそのまま表示（パススルー）

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\_!...\_!` | タグをそのまま表示（旧フォーマット） | `\_!\1Text\n\_!` は `\1Text\n` を表示 |
| `\_?...\_?` | タグをそのまま表示 | `\_?\1Text\n\_?` は `\1Text\n` を表示 |

**注意:**
- 開始タグと終了タグの間のテキストはさくらスクリプトとして解釈されません
- サンプルスクリプトの表示やデバッグに便利です

### 音声合成制御

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\__v[disable]...\__v` | テキストの音声合成を無効化 | `\__v[disable]Silent\__v` |
| `\__v[alternate,text]...\__v` | 読み上げを上書き | `\__v[alternate,ひらがな]漢字\__v` |

## フォント＆テキストスタイルコマンド

### テキスト揃え

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\f[align,left]` | テキストを左揃え | `\f[align,left]Left aligned` |
| `\f[align,center]` | テキストを中央揃え | `\f[align,center]Centered` |
| `\f[align,right]` | テキストを右揃え | `\f[align,right]Right aligned` |
| `\f[valign,top]` | 上に垂直揃え | `\f[valign,top]Top` |
| `\f[valign,center]` | 中央に垂直揃え | `\f[valign,center]Middle` |
| `\f[valign,bottom]` | 下に垂直揃え | `\f[valign,bottom]Bottom` |

**注意:**
- `\f[align,...]` は次の意図的な改行（`\n`、`\_l`）まで有効
- `\_l` タグは揃えを左にリセット
- `\f[valign,...]` は改行でリセットされません（`align` とは異なります）
- 揃えコマンドの後に追加されたテキストは、同じ行の前のテキストを遡及的に揃えます

### フォントプロパティ

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\f[name,font]` | フォントを変更（単一の名前またはファイル） | `\f[name,Arial]Arial font` |
| `\f[name,font1,font2,...]` | フォールバック付きでフォントを変更 | `\f[name,メイリオ,meiryo.ttf]Text` |
| `\f[height,size]` | フォントサイズを設定（ピクセル） | `\f[height,15]Size 15` |
| `\f[height,+N]` | 相対的にサイズを拡大 | `\f[height,+3]Bigger` |
| `\f[height,-N]` | 相対的にサイズを縮小 | `\f[height,-3]Smaller` |
| `\f[height,N%]` | デフォルトサイズに対する割合 | `\f[height,200%]Double size` |

**フォント名に関する注意:**
- `default` - バルーンのデフォルトフォントにリセット
- `disable` - 無効テキスト用フォントを使用
- `ghost/master/` またはバルーンフォルダ内のフォントファイルを指定可能
- カンマ区切りの複数の名前 = 優先順位（SSPのみ）

### テキストカラー

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\f[color,name]` | 名前付きカラー | `\f[color,red]Red text` |
| `\f[color,r,g,b]` | RGBカラー（0-255） | `\f[color,100,150,200]Blue` |
| `\f[color,#RRGGBB]` | 16進カラー | `\f[color,#ff6600]Orange` |
| `\f[color,default]` | バルーンのデフォルトにリセット | `\f[color,default]Normal` |
| `\f[shadowcolor,...]` | 影の色（同じフォーマット） | `\f[shadowcolor,#ffff00]Yellow shadow` |
| `\f[shadowcolor,none]` | 影を無効化 | `\f[shadowcolor,none]No shadow` |
| `\f[shadowstyle,offset]` | オフセット影（デフォルト） | `\f[shadowstyle,offset]Offset` |
| `\f[shadowstyle,outline]` | アウトライン影 | `\f[shadowstyle,outline]Outlined` |
| `\f[anchor.font.color,...]` | アンカーテキストの色 | `\f[anchor.font.color,50%,90%,20%]Link` |

**カラーフォーマットに関する注意:**
- 名前付きカラー: `red`、`blue`、`green`、`black`、`white` など
- RGB: 0-255 の3つの数値、または `50%,90%,20%` のような割合
- 16進: 標準的なWeb形式 `#RRGGBB`

### テキストスタイル

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\f[bold,1]` or `\f[bold,true]` | 太字を有効化 | `\f[bold,1]Bold text` |
| `\f[bold,0]` or `\f[bold,false]` | 太字を無効化 | `\f[bold,0]Normal` |
| `\f[bold,default]` | バルーンのデフォルトにリセット | `\f[bold,default]Default` |
| `\f[bold,disable]` | 無効テキストスタイルを使用 | `\f[bold,disable]Disabled` |
| `\f[italic,1]` | 斜体を有効化 | `\f[italic,1]Italic` |
| `\f[strike,1]` | 取り消し線を有効化 | `\f[strike,1]Strike` |
| `\f[underline,1]` | 下線を有効化 | `\f[underline,1]Underline` |
| `\f[outline,1]` | アウトライン（白文字）を有効化 | `\f[outline,1]Outlined` |

**注意:**
- すべてのスタイルコマンドは次に対応: `1`/`true`（有効）、`0`/`false`（無効）、`default`、`disable`
- フォントがそのスタイルに対応している必要があります（太字／斜体のバリアントがないフォントもあります）

### テキスト位置

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\f[sub,1]` | 下付き文字を有効化 | `H\f[sub,1]2\f[sub,0]O` |
| `\f[sup,1]` | 上付き文字を有効化 | `X\f[sup,1]2\f[sup,0]` |

### リセットコマンド

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\f[default]` | すべてのフォント属性をバルーンのデフォルトにリセット | `\f[default]Reset all` |
| `\f[disable]` | すべての属性を無効テキストスタイルに設定 | `\f[disable]Disabled` |

**組み合わせ例:**
```
\f[shadowcolor,#6699cc]\f[bold,1]\f[underline,1]\f[height,20]Styled text\f[default]Normal
\f[align,center]\f[color,red]\f[height,24]Centered Red Title\n
H\f[sub,1]2\f[sub,0]O + O\f[sub,1]2\f[sub,0] → H\f[sub,1]2\f[sub,0]O\f[sub,1]2\f[sub,0]
```

## キャラクター移動コマンド

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\4` | 他のキャラクターから離れる | `Moving...\4Done` |
| `\5` | 他のキャラクターに近づく | `Moving...\5Done` |
| `\![move,args...]` | 指定位置へ移動（下記参照） | 移動セクション参照 |
| `\![moveasync,args...]` | 非同期で移動 | 移動セクション参照 |
| `\![moveasync,cancel]` | 非同期移動をキャンセル | `\![moveasync,cancel]` |

### move コマンドのパラメータ

フォーマット: `\![move,--X=x,--Y=y,--time=ms,--base=ref,--base-offset=pos,--move-offset=pos,--option=opt]`

**パラメータ:**
- `--X=value`: X座標（負数可）
- `--Y=value`: Y座標（負数可）
- `--time=ms`: 移動時間（ミリ秒）
- `--base=ref`: 基準点（screen, primaryscreen, ID, ghost/ID, me, global）
- `--base-offset=pos`: 基準点のアンカー（left.top, right.bottom, center.center など）
- `--move-offset=pos`: 揃えるキャラクターのアンカー
- `--option=opt`: オプション（ignore-sticky-window）

**例:**
```
\![move,--X=80,--Y=-400,--time=2500,--base=screen,--base-offset=left.bottom,--move-offset=left.top]
```

## 着せ替え／バインドコマンド

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![bind,category,part,1]` | カテゴリのパーツを装着 | `\![bind,head,ribbon,1]` |
| `\![bind,category,part,0]` | カテゴリからパーツを外す | `\![bind,head,ribbon,0]` |
| `\![bind,category,,0]` | カテゴリ内のすべてのパーツを外す | `\![bind,arm,,0]` |
| `\![bind,category,part]` | パーツの装着／解除をトグル | `\![bind,head,ribbon]` |

## 描画制御

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![lock,repaint]` | アンロックまたはスクリプト終了まで再描画を停止 | `\![lock,repaint]` |
| `\![lock,repaint,manual]` | 明示的なアンロックまで再描画を停止 | `\![lock,repaint,manual]` |
| `\![unlock,repaint]` | 再描画を再開 | `\![unlock,repaint]` |

## 位置＆配置

### デスクトップ配置

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![set,alignmentondesktop,bottom]` | デスクトップ下端にスナップ | `\![set,alignmentondesktop,bottom]` |
| `\![set,alignmentondesktop,top]` | デスクトップ上端にスナップ | `\![set,alignmentondesktop,top]` |
| `\![set,alignmenttodesktop,DIR]` | 配置方向を設定 | 下表参照 |

**配置方向:**
- `top` - 上端にスナップ
- `bottom` - 下端にスナップ
- `left` - 左端にスナップ
- `right` - 右端にスナップ
- `free` - スナップなし
- `default` - デフォルトにリセット

### 位置ロック

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![set,position,x,y,scopeID]` | キャラクターを指定位置にロック | `\![set,position,100,200,0]` |
| `\![reset,position]` | 位置のロックを解除 | `\![reset,position]` |

## ビジュアルエフェクト

### スケーリング

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![set,scaling,ratio]` | 等倍スケーリング（%） | `\![set,scaling,50]` |
| `\![set,scaling,x,y]` | 非等倍スケーリング（%） | `\![set,scaling,50,100]` |
| `\![set,scaling,x,y,time]` | アニメーションスケーリング（time はミリ秒） | `\![set,scaling,50,100,2500]` |

**注意:**
- 100 = ユーザーが設定したスケール（100%）
- 負の値は軸を反転（-100 = 反転）
- ゴーストが終了するまで持続します

### 透明度

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![set,alpha,value]` | 透明度を設定（0-100） | `\![set,alpha,50]` |

**注意:**
- 0 = 完全に透明（不可視）
- 100 = 完全に不透明
- ゴーストが終了するまで持続します

### エフェクト＆フィルタ

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![effect,plugin,speed,params]` | プラグインエフェクトを適用 | `\![effect,plugin1,2.0,param]` |
| `\![effect2,surfaceID,plugin,speed,params]` | 追加サーフェスにエフェクトを適用 | `\![effect2,10,plugin1,2.0,param]` |
| `\![filter,plugin,time,params]` | 継続的なフィルタを適用 | `\![filter,plugin2,1000,param]` |
| `\![filter]` | フィルタをクリア | `\![filter]` |

## ウィンドウ管理

### Zオーダー

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![set,zorder,ID1,ID2,...]` | ウィンドウの重なり順を設定 | `\![set,zorder,1,0]` |
| `\![reset,zorder]` | デフォルトのZオーダーにリセット | `\![reset,zorder]` |

**注意:**
- 左から右の順にリストされたID = 前面から背面
- 例: `\![set,zorder,1,0]` はキャラクター1を常にキャラクター0の前面にします

### スティッキーウィンドウ

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![set,sticky-window,ID1,ID2,...]` | ウィンドウを連動して移動するようリンク | `\![set,sticky-window,1,0]` |
| `\![reset,sticky-window]` | ウィンドウのリンクを解除 | `\![reset,sticky-window]` |

**注意:**
- リンクされたウィンドウはドラッグ時に連動して移動します
- `\![move]` コマンドでも機能します（--option=ignore-sticky-window を除く）

### ウィンドウリセット

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `\![execute,resetwindowpos]` | すべてのウィンドウを初期位置にリセット | `\![execute,resetwindowpos]` |

## 特殊コマンド

### マーカー

| コマンド | 説明 | 例 |
|---------|-------------|---------|
| `%*` or `\![*]` | マーカーを挿入 | `Text before%*Text after` |

## エスケープシーケンス

| シーケンス | 結果 | 例 |
|----------|--------|---------|
| `\\` | リテラルの `\` | `C:\\Users` → `C:\Users` |
| `\%` | リテラルの `%` | `100\%` → `100%` |
| `\]` | リテラルの `]`（ブラケット内） | `\![test,a\]b]` → 引数: `["test", "a]b"]` |
| `\[` | リテラルの `[`（ブラケット内） | `\![test,a\[b]` → 引数: `["test", "a[b"]` |

## 引数のクォート

`[...]` ブラケット内の引数はカンマ区切りで、クォートに対応しています。

| ルール | 例 | 結果 |
|------|---------|--------|
| 基本 | `\![raise,OnTest,100]` | `["raise", "OnTest", "100"]` |
| クォート内のカンマ | `\![raise,OnTest,"100,2"]` | `["raise", "OnTest", "100,2"]` |
| エスケープされたクォート | `\![call,ghost,"the ""Master"""]` | `["call", "ghost", "the \"Master\""]` |

## 実装ステータス

### ✅ 完全実装

#### パーサーレベル（SakuraScriptEngine.swift）
上記のすべてのコマンドは **正しくパースされます**。パーサーはさくらスクリプトのテキストを、レンダリングエンジンが処理できるトークンに変換します。

#### レンダリングレベル（GhostManager.swift + CharacterViewModel/CharacterView）

**ビジュアルエフェクト - 実装済み:**
- ✅ `\![set,scaling,ratio]` - 等倍スケーリング
- ✅ `\![set,scaling,x,y]` - 非等倍スケーリング
- ✅ `\![set,alpha,value]` - 透明度（0-100）
- ✅ `\![lock,repaint]` / `\![unlock,repaint]` - 描画制御
- ✅ `\![set,alignmenttodesktop,DIR]` - デスクトップ配置の状態
- ✅ `\![set,position,x,y,scopeID]` / `\![reset,position]` - 位置ロックの状態
- ✅ `\![set,zorder,...]` / `\![reset,zorder]` - Zオーダーグルーピングの状態
- ✅ `\![set,sticky-window,...]` / `\![reset,sticky-window]` - スティッキーウィンドウグルーピングの状態
- ✅ `\![execute,resetwindowpos]` - すべてのウィンドウ位置／配置をリセット

**コマンド処理:**
- キャラクターのビジュアル状態は `CharacterViewModel` に `@Published` プロパティとして保存されます
- ビジュアルエフェクトは `CharacterView` で SwiftUI モディファイア（`.scaleEffect()`、`.opacity()`、`.allowsHitTesting()`）を使って適用されます
- すべての設定はゴーストが終了するまで持続します（UKADOC仕様に準拠）
- `\![lock,repaint]` は `manual` オプションが使われていない限り、スクリプト終了時に自動的にアンロックされます

### ⚠️ 部分実装

**ウィンドウ管理 - 状態は保存、挙動はTODO:**
これらのコマンドは ViewModel の状態を正しく更新しますが、実際のウィンドウ挙動にはプラットフォーム側の実装が必要です。
- ⚠️ 配置制約（特定方向へのウィンドウ移動の防止）
- ⚠️ 位置ロック（ウィンドウのドラッグを無効化）
- ⚠️ Zオーダーの強制（ウィンドウを指定の重なり順に維持）
- ⚠️ スティッキーウィンドウの同期（複数ウィンドウの連動移動）

### ❌ 未実装（実行レベル）

**バルーン＆テキストコマンド - パースのみ:**
すべてのバルーンおよびテキストコマンドは完全にパースされますが、実行はまだ実装されていません。
- ❌ `\bN` / `\b[ID]` - バルーンID切り替え（パース済み、プレースホルダーあり）
- ❌ `\C` - 追記モード（パース済み、プレースホルダーあり）
- ❌ `\n[half]` / `\n[percent]` - 可変改行高（パース済み、通常の改行として扱われる）
- ❌ `\_b[...]` - バルーン画像（インラインおよび位置指定）
- ❌ `\_l[x,y]` - テキストカーソルの配置
- ❌ `\c` / `\c[char/line,...]` - テキストクリア
- ❌ `\_n` - 自動折り返し無効モード
- ❌ `\_!...\_!` / `\_?...\_?` - タグのパススルー（正しくパース済み）
- ❌ `\__v[...]` - 音声合成制御
- ❌ `\![set,autoscroll,...]` - オートスクロール制御
- ❌ `\![set,balloonoffset,...]` - バルーンオフセット
- ❌ `\![set,balloonalign,...]` - バルーン配置
- ❌ `\![set,balloonmarker,...]` - SSTPマーカー
- ❌ `\![set,balloonnum,...]` - ファイル転送インジケータ
- ❌ `\![set,balloontimeout,...]` - バルーンタイムアウト
- ❌ `\![set,balloonwait,...]` - テキスト速度
- ❌ `\![set,serikotalk,...]` - SERIKO口パクアニメーション
- ❌ `\![enter/leave,onlinemode]` - オンラインマーカー
- ❌ `\![enter/leave,nouserbreakmode]` - ユーザーブレイク制御
- ❌ `\![lock/unlock,balloonrepaint]` - バルーン再描画制御
- ❌ `\![lock/unlock,balloonmove]` - バルーンドラッグ制御

**フォント＆テキストスタイルコマンド - パースのみ:**
すべてのフォントおよびテキストスタイルコマンドは完全にパースされますが、実行はまだ実装されていません。
- ❌ `\f[align,...]` - テキスト揃え（left/center/right）
- ❌ `\f[valign,...]` - テキストの垂直揃え（top/center/bottom）
- ❌ `\f[name,...]` - フォントファミリの変更
- ❌ `\f[height,...]` - フォントサイズ（絶対・相対・割合）
- ❌ `\f[color,...]` - テキストカラー
- ❌ `\f[shadowcolor,...]` - 影の色
- ❌ `\f[shadowstyle,...]` - 影のスタイル（offset/outline）
- ❌ `\f[anchor.font.color,...]` - アンカーテキストの色
- ❌ `\f[bold,...]` - 太字スタイル
- ❌ `\f[italic,...]` - 斜体スタイル
- ❌ `\f[strike,...]` - 取り消し線
- ❌ `\f[underline,...]` - 下線
- ❌ `\f[outline,...]` - アウトライン（白文字）スタイル
- ❌ `\f[sub,...]` - 下付き文字
- ❌ `\f[sup,...]` - 上付き文字
- ❌ `\f[default]` - すべてのフォント属性をリセット
- ❌ `\f[disable]` - 無効テキストスタイルを設定

**移動:**
- ❌ `\4` および `\5` - 基本的なキャラクター移動（パース済み、ハンドラのプレースホルダーあり）
- ❌ `\![move,...]` / `\![moveasync,...]` - パラメータ付きの複雑な移動

**アニメーション:**
- ❌ `\![anim,clear,ID]` / `\![anim,pause,ID]` / `\![anim,resume,ID]` / `\![anim,stop]`
- ❌ `\![anim,offset,ID,x,y]`
- ❌ `\![anim,add,*]` - アニメーションレイヤリング
- ❌ `\__w[animation,ID]` - アニメーション完了の待機

**着せ替え:**
- ❌ `\![bind,category,part,value]` - 着せ替えシステム全体はまだ実装されていません

**エフェクト＆フィルタ:**
- ❌ `\![effect,...]` / `\![effect2,...]` / `\![filter,...]` - プラグインベースのエフェクト
- ❌ `\![set,scaling,x,y,time]` - 時間経過によるアニメーションスケーリング

**注意:**
- パーサーはすべてのコマンドを正しく識別し、パラメータを抽出します
- 将来の実装に向けて、TODOコメント付きのプレースホルダーハンドラが存在します
- 一部の機能はプラットフォーム固有の NSWindow 操作を必要とします
- アニメーション、バルーン、着せ替えの各システムには追加のインフラが必要です

## テスト

すべてのコマンドは `OurinTests/SakuraScriptEngineTests.swift` で包括的なテストカバレッジを持っています。次のコマンドでテストを実行します。

```bash
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/SakuraScriptEngineTests test
```

## 参考資料

- 完全仕様: `docs/SAKURASCRIPT_FULL_1.0M_PATCHED.md`
- パーサー実装: `Ourin/SakuraScript/SakuraScriptEngine.swift`
- テストスイート: `OurinTests/SakuraScriptEngineTests.swift`
