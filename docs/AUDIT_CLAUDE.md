# Ourin（桜鈴）技術監査レポート

- **監査日**: 2026-06-10
- **監査対象**: `/Users/eightman/Desktop/software_develop/Ourin`（master, 1ced22d）
- **照合情報源**: UKADOC（list_sakura_script / list_shiori_event / spec_shiori3 / spec_sstp / list_propertysystem を取得し全文照合）、YAYA本家実装（ponapalt/yaya-shiori `sysfunc.cpp` 関数表 163 項目）
- **検証方法**: 静的解析（ソースコードとUKADOC原文の突き合わせ）。SSP 2.8.27f バイナリは `~/Downloads/ssp_2_8_27f.exe` に存在を確認したが、本環境に Wine が無いため動的観察は未実施。デファクト動作の確認はUKADOC記載とSSP表記（※SSPのみ等）に依拠した。
- **規模**: Swift 129ファイル/約27,000行、yaya_core はC++（**注**: CLAUDE.md・docsは「Rust製」と記載しているが実体は `yaya_core/src/*.cpp` のC++実装。Cargo.toml由来の記述が陳腐化している）

---

## A. SHIORI プロトコル (`SSTP/`, `USL/ShioriLoader/`, `SHIORIEvents/`)

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）
- SHIORI/3.0 リクエスト構築（`GET SHIORI/3.0` + Charset/Sender/ID/Reference*、CRLF区切り・空行終端）: spec_shiori3 準拠 → `BridgeToSHIORI.swift:131-146`、`yaya_core/src/YayaCore.cpp:168-182`
- GET/NOTIFY 両メソッドの発行: `EventBridge.swift:280-339`（NOTIFY）、`GhostManager.swift:2332-2378`（ブートはGET）
- NOTIFY系イベントの返値無視リスト（UKADOC「Notifyイベント」準拠、URLコメント付き）: `EventBridge.swift:243-255`、`yaya_core/src/YayaCore.cpp:234-240` の2箇所で一致
- バックエンド多態（ネイティブ bundle/dylib、XPC、YAYAヘルパープロセス）と `shiori_free` によるメモリ解放契約: `ShioriLoader.swift:345-420`
- 400/505 受信時の旧バージョンへのフォールバック交渉: `BridgeToSHIORI.swift:159-173`

### 実装済み（要修正）
- **Reference順序が辞書順ソート**: `orderedRefs` が `params.sorted(by: { $0.key < $1.key })` のため、参照が10個以上のイベントで `Reference10` が `Reference2` より先に並ぶ（OnNotifyOSInfo等で実害）。
  - 修正箇所: `EventBridge.swift:275-277`
  - 修正案: `Reference` 接頭辞を外し数値でソートする。非Referenceキーが紛れ込むと位置引数化する問題も併せて解消すること。
- **SHIORI/2.x 互換レイヤーが2.x仕様と無関係**: フォールバックは `GET SHIORI/2.6` の1行目に3.0形式ヘッダ（ID:）を付けて再送するだけ。実際の SHIORI/2.x は `GET Sentence SHIORI/2.x` / `GET Word` / `GET Status` 等のメソッド体系・`Event:` ヘッダで、本実装では一切話が通じない。
  - 根拠: UKADOCトップ→DLL/SHIORI 2.x系資料
  - 修正箇所: `BridgeToSHIORI.swift:159-173`
  - 修正案: 2.x対応を謳うなら `GET Sentence` 変換テーブルを実装、そうでなければ「3.0専用」と明示してフォールバックを削除。
- **NOTIFY意図のイベントがGETで送信される経路**: `BridgeToSHIORI.ShioriHost.buildRequest` はメソッド固定 `GET`。`EventBridge.sendNotify` の非YAYA経路はここを通るため NOTIFY が GET に化ける。
  - 修正箇所: `BridgeToSHIORI.swift:131`（method引数を貫通させる）
- **Charset が UTF-8 固定**: ネイティブSHIORIモジュールが Shift_JIS を要求/返答するケース（古いSHIORI移植時）の変換層が無い。`SaoriProtocol.swift:158-176` には変換実装があるのでSHIORI側へも適用可能。

### 未実装（重要度: 中）
- リクエスト側 `SecurityLevel` の文脈依存設定: `EventBridge` 経由のイベントは常に `SecurityLevel: local` 固定（`EventBridge.swift:286,306,328`）。SSTP外部由来イベントを `\![raiseother]` 等で中継した場合に external が伝播しない。

### 互換性リスク
- 2.x SHIORI（華和梨旧版・里々旧版等）を持つ既存ゴーストはロードできても全リクエストが 400 になる。

---

## B. SSTP プロトコル (`ExternalServer/`, `SSTP/`)

### 準拠度スコア: 4/10

### 実装済み（仕様準拠）
- TCP 9801 / localhost 限定リスニング: spec_sstp「ポート9801」準拠 → `SstpTcpServer.swift:29`
- SSTP over HTTP の `POST /api/sstp/v1`・`Content-Length` 必須(411)・`Content-Type: text/plain`: `SstpHttpServer.swift:48-95`、テスト `ExternalServerTests.swift:25-37`
- SecurityLevel / SecurityOrigin の解釈（Origin優先、localhost判定）: `SstpRouter.swift:173-185`（spec_sstp SecurityOrigin [SSP 2.6.59] 準拠）
- ステータスコード語彙（200/204/210/400/404/413/420/501/505/512）: `SstpRouter.swift:137-151`、`SSTPDispatcher.swift`
- `X-SSTP-PassThru-*` の双方向中継: `SSTPDispatcher.swift:725-727,764-773`（ただし後述の通り本番未配線）

### 実装済み（要修正）
- **【重大】応答ステータス行が `SSTP/SSTP/1.x ...` になる**: `SstpParser.parse` は version に `"SSTP/1.1"`（プレフィクス込み）を格納するが、`SstpRouter` は `"SSTP/\(version) \(status)..."` と再度プレフィクスを付ける。本番経路の全応答が不正形式。テストは応答ステータス行を検証していないため未検出。
  - 修正箇所: `ExternalServer/SstpParser.swift:28`（`comps[1]` から `SSTP/` を剥がす）または `SstpRouter.swift:108,150,159`
- **【重大】SEND の `Script:` ヘッダがバルーン再生されない**: 仕様は「Scriptヘッダで直接SakuraScriptを指定…再生させる」。`SstpRouter.swift:119-129` は Script を SHIORI 応答が空の時の**応答エコー**にしか使わず、`GhostManager.runScript/runNotifyScript` を一切呼ばない。SHIORI応答スクリプトも再生されない。SSTPの主機能（外部アプリからの喋らせ）が機能していない。
  - 修正案: ルーター成功経路で `DispatchQueue.main.async { ghostManager.runNotifyScript(script) }` を実行（nodescript時を除く）。
- **SEND（Event無し）でイベントIDが空のままSHIORIへ送信**: `SstpRouter.resolveEvent` は SEND のデフォルトを `""` とし、`ID: `（空）リクエストを発行する。
  - 修正箇所: `SstpRouter.swift:187-204`（Event無しSENDはSHIORIを介さずScript直接再生にすべき）
- **COMMUNICATE の Reference 対応が仕様と不一致**: 仕様は「SHIORI OnCommunicate Reference0=送信元ゴースト\0名、Reference1=Sentence、SSTP Reference0→SHIORI Reference2」。Ourin は Sentence を refs[0] に挿入するだけで送信元名が欠落し、拡張Referenceが2つ前にずれる。`Surface` ヘッダの中継も無い。
  - 修正箇所: `SstpRouter.swift:75-77`、`SSTPDispatcher.swift:588-592`
- **IfGhost の書式が独自発明**: 仕様は `IfGhost: \0側名,\1側名` を複数回書き、**直後の** `Script:` と出現順でペアリングする。Ourin は `IfGhost: ghost=script|kero`（`;`区切り）という存在しない書式をパースする（`SSTPRequest.swift:110-133`）。さらに `SstpParser`/`SSTPParser` ともヘッダを `[String:String]` に格納するため、**同名ヘッダ（複数Script/IfGhost）が上書き消失**し、仕様通りのリクエストは原理的に処理できない。
  - 修正案: パーサを `[(key,value)]` の順序保持リストに変更し、IfGhost/Scriptペアを出現順で対応付ける。デフォルトゴースト名（さくら/エミリ/えみりぃ）の特例も未実装。
- **EXECUTE コマンドの返値形式**: `GetName` は仕様「(\0名),(\1名)」だがゴースト名のみを返す。`GetNames`/`Get*NameList` は「改行区切り・空行終端」だがカンマ区切りで返す。`GetFMO` は「FMOの中身と同等（改行区切り）」だが `key=value;...` 独自形式。`Command: GetCookie[name]` の大かっこパラメータ書式が未対応。
  - 修正箇所: `SSTPDispatcher.swift:383-430`
- **Option: nodescript の意味違反**: 仕様は「バルーン表示の無効化」のみでイベント処理は行う。`SstpRouter.swift:87-99` はSHIORIへのイベント送出ごとスキップして即時リターンする。
- **HTTP サーバのポートが 9810**: 仕様は SSTPポート(9801)上で HTTP を受ける。`SstpHttpServer.swift:30`。また Origin が localhost 以外の場合、仕様は「リモート扱い（external強制）で処理続行」だが Ourin は 403 で拒否する（`SstpHttpServer.swift:88-91`）。
- **GIVE が何もしない**: `SstpRouter.swift:115-117` は無条件 204。`SSTPDispatcher` は `OnChoiceSelect` へマップしており（`SSTPDispatcher.swift:572-573`）これも誤り。GIVE Document/Song は旧仕様の教え込み系処理。
- **Sender/User-Agent 両方欠如時の 400 が未実装**（仕様: SEND/NOTIFYで必須）。
- **Owned SSTP（IDヘッダ）未実装**: SHIORI uniqueid による優先処理・セキュリティ緩和の仕組みが無い。

### 未実装（重要度: 中）
- `Entry` ヘッダ運用は `SSTPDispatcher` 側のみ実装（`SstpSessionStore`）で本番経路に無い。
- 210 Break の発生条件（実行中スクリプトのブレーク検知）が簡略化されており、`nobreak` 指定時に「キューイングして完了を待つ」のではなくOnSSTPBreak通知だけで終わる。

### 互換性リスク（アーキテクチャ）
- **二重実装**: 高機能な `SSTPDispatcher`（cookie、EXECUTE拡張、PassThru、413、Entry、IfGhost処理）は `SSTPListener`/`HTTPBridge`/`DirectSSTPXPC` からしか呼ばれず、`AppDelegate` が起動するのは `OurinExternalServer`→`SstpRouter`（簡素版）のみ（`OurinApp.swift:174-178`）。**実運用に乗っているのは機能の少ない方**。両者の挙動も乖離している（GIVE、nodescript、EXECUTE等）。どちらかに統合すべき。
- 伺かエコシステムのSSTP送信ツール・連携アプリ（音楽プレーヤ連携、SSTP Bottle系クライアント等）は、応答行不正・Script非再生によりほぼ全滅する。

---

## C. SakuraScript (`SakuraScript/`, `Ghost/`, `Animation/`)

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）
- エスケープ（`\\`,`\%`、ブラケット内 `\]`/`\[`）と引数の `""` クォート規則（`""`→`"`）: notes_escape 準拠 → `SakuraScriptEngine.swift:16-27,544-587`
- `%*` = `\![*]` 同等: UKADOC `%*` 準拠 → `SakuraScriptEngine.swift:184-189`
- スコープ `\0/\h/\1/\u/\p[ID]`、`\s[ID]`、`\i[ID]`/`\i[ID,wait]`、`\n`/`\n[half]`/`\n[パーセント]`、`\b[ID]`、`\w*/\_w[ms]/\__w[...]`、`\q`（新旧両書式）、`\_q`、`\__q`、`\_s[...]`、`\_a`、`\_l[x,y]`、`\_v`、`\_u[0x....]`/`\_m[0x..]`、`\c[char/line,...]`、`\f[...]`（align/valign/name/height/color/shadowcolor/bold/italic/strike/underline/sub/sup/default/disable/outline 等）、`\_!`/`\_?` パススルー
- `\![...]` 系60以上の動詞: raise/notify/embed/timerraise(other/plugin)/timernotify(other/plugin)/change,ghost|shell|balloon/call,ghost/open(inputbox,passwordinput,dateinput,sliderinput,timeinput,ipinput,teachbox,communicatebox,configurationdialog,browser,mailer,各種explorer,readme,terms,help,dialog,file...)/close/enter,leave(passivemode,inductionmode,selectmode,collisionmode,nouserbreakmode,onlinemode)/sound(play,load,loop,wait,pause,resume,stop,option)/set(scaling,alpha,alignment*,position,zorder,sticky-window,balloonoffset,balloonalign,autoscroll,balloontimeout,choicetimeout,balloonwait,balloonmarker,balloonnum,wallpaper,tasktrayicon,trayballoon,otherghosttalk,othersurfacechange,windowstate,serikotalk...)/reset/lock,unlock(repaint)/anim(clear,pause,resume,stop,offset,add)/bind/effect/filter/move/moveasync/update*/vanishbymyself/reloadsurface/reload,*/execute(http-get等含む) → `GhostManager.swift:842-2200`、`GhostManager+System.swift`
- `\6`/`\7` のSNTP意味論（時計合わせ実行/開始）: UKADOC準拠 → `GhostManager.swift:830-836`（トークン名 `openURL`/`openEmail` は誤解を招くため改名推奨）
- 環境変数 `%month/%day/%hour/%minute/%second/%username/%selfname/%selfname2/%keroname/%screenwidth/%screenheight/%exh/%et(単位付きデタラメ時間)/%wronghour/%property[...]/単語系(%ms〜%dms)`: `EnvironmentExpander.swift:114-188`

### 実装済み（要修正）
- **`\t` の誤解釈**: 仕様は「タイムクリティカルセクション＝スクリプトブレークか `\e` までマウス系イベント通知を行わない」。Ourin は「100msポーズ」を挿入するだけで、コードコメント（`GhostManager.swift:769-771`「\t is a brief pause, not a click wait」）も仕様を誤認。
  - 修正箇所: `GhostManager.swift:768-772`。timecritical フラグを立て、InputMonitor/当たり判定からのイベント通知を抑止する実装へ。
- **`\-` の誤解釈**: 仕様は「本体（当該ゴースト）終了」。Ourin は選択肢内改行として `.newline` を積む（`SakuraScriptEngine.swift:398-401`, `GhostManager.swift:796-798`）。ゴーストが自発終了できない。
- **`\v` の誤解釈**: 仕様は「最前面表示（このスクリプト以降 stay-on-top）」。Ourin は Ourin自身の設定ウィンドウを開く（`GhostManager.swift:819-828`）。
- **`\4`/`\5` の誤解釈**: 仕様は「相方キャラから離れる方向へ移動」「接触する距離まで移動」（デスクトップ上の水平移動）。Ourin はウィンドウZオーダーの前後切替（`GhostManager.swift:800-806`）。
- **`\+`/`\_+` の誤解釈**: 仕様は「ランダムに他ゴーストへ**切替**」「シーケンシャルに次のゴーストへ**切替**」（OnGhostChanging非通知）。Ourin は SSTP NOTIFY による他ゴースト起動/全起動（`GhostManager+System.swift:18-44`）。切替と起動は別物。
- **`\*` の誤解釈**: 仕様は「このスクリプトの選択肢をタイムアウトさせない」。Ourin は選択肢ダイアログ表示トリガ（`GhostManager.swift:783-787`）。
- **`\a` の誤解釈**: 仕様（旧）は「OnAITalk を発生させる」。Ourin は選択肢ダイアログ表示（`GhostManager.swift:789-794`）。
- **`\&[ID]` の誤解釈**: 仕様は「識別子による実体参照」（文字参照）。Ourin はアンカー/イベントマーカー扱いで OnAnchorEnter/Hover を発火（`GhostManager.swift:2022-2032`）。
- **`\_V` が到達不能**: コマンド分岐が `switch name.lowercased()`（`GhostManager.swift:843`）のため `case "_V"`（`:2041`）は先行の `case "_v"`（`:2004`）に吸われる。`\_V`（再生完了待ち）が `\_v`（再生）として実行される。大文字小文字を保持した分岐に修正。
- **`%`変数展開の経路バグ**: `EnvironmentExpander.expand` は `%key[arg]` 形式が1つでもマッチすると早期 return し、同一テキスト内の裸の `%key` が展開されない（`EnvironmentExpander.swift:56-87` のパターン2で `return result`）。1パスの統合正規表現に修正すべき。
- `\z`: 仕様（旧）は「選択肢を含むスクリプトにおける `\e`」だが、Ourin はキャンセル可能フラグの設定のみ（`GhostManager.swift:778-781`）。

### 未実装（重要度: 高）
- **`\j[ID]`**: ID/URLジャンプ。パーサは `command("j",...)` を生成するが `GhostManager` に `case "j"` が存在せず黙殺される（リポジトリ全体に handler 無しを確認）。アンカー/メニューからの URL 起動・イベントジャンプを使うゴーストで機能欠落。
- `%lastghostname` / `%lastobjectname`（インストール時用）: `EnvironmentExpander` 未対応。

### 未実装（重要度: 低）
- 単語系 `%ms` 等の語彙（lexicon）がデフォルト空で常に空文字列を返す（`EnvironmentExpander.swift:180-182`）。SSPはベースウェア内蔵辞書を持つ。

### 互換性リスク
- `\t` を使う演出（強制イベント抑止つき長尺トーク）や `\-`（右クリックメニューの「終了」スクリプト末尾の定番）は事実上すべての老舗ゴーストが使用しており、現状では「終了を選んでも終了しない」「保護区間で割込みが入る」という体感バグになる。
- SERIKO連携は `SerikoParser`/`SerikoExecutor`/`AnimationEngine` が存在し interval/pattern 処理を確認したが、SERIKO/2.0表記・element合成・MAYUNA着せ替えの網羅性は本監査では深掘りしていない（部分検証に留まる）。

---

## D. SHIORIイベント (`SHIORIEvents/`)

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）
- **イベントID定義の網羅性は非常に高い**: `EventID.swift` に404イベント定義。UKADOC `list_shiori_event` の252イベントに対し未定義は14個のみ（OnExecuteWebSocket系×6、OnCompressArchiveComplete/Failure、OnExtractArchiveComplete/Failure、OnExecuteHTTPStreaming、OnMusicPlayEx、OnVideoPlayEx、OnSoundLoop）。
- 起動系を GET で送る方針（コメントでUKADOC言及）: `GhostManager.swift:604,2332-2378`
- システム観測層の広さ: 入力/スリープ/ディスプレイ/Space/電源/ロケール/外観/セッション/ネットワーク/ゲームパッド/デバイス/音声の各Observer（`SHIORIEvents/`）

### 実装済み（要修正）
- **【重大】OnSecondChange / OnMinuteChange / OnHourTimeSignal が Reference 無しで送信される**: 仕様は Reference0=OS連続起動時間(hour)、Reference1=見切れ、Reference2=重なり、Reference3=トーク再生可否（0で NOTIFY化・返値無視）、Reference4=放置時間[SSPのみ]。`TimerEmitter.swift:48-66` は `params: [:]`。さらに常時 NOTIFY 送信（`EventBridge.broadcastNotify`→`sendNotify`）であり、「再生可能時は GET、不能時のみ NOTIFY」という使い分けが無い。多くのゴーストは OnSecondChange の Reference3 と返値スクリプトでランダムトークを駆動するため、**ランダムトークが構造的に壊れる**。
  - 修正箇所: `TimerEmitter.swift`（参照値の生成）、`EventBridge.swift`（cantalk に応じた GET/NOTIFY 切替）
- **OnBoot に Reference0（シェル名）が無い**: `GhostManager.swift:2358`（refs無しの直接呼び出し）。OnFirstBoot の Reference0（vanish回数）も同様に欠落。
- **存在しないイベント `OnSecondBoot` を発明**: `GhostManager.swift:2347` 。UKADOCに存在しない（取得済みイベント一覧252件に無いことを確認）。2回目起動も OnBoot が正。
- **OnClose の応答スクリプトを破棄**: `EventBridge.swift:95` で `_ = sendGet(id: .OnClose)`。仕様ではOnClose応答（お別れトーク、末尾 `\-`）を再生してから終了する。Reference0（user/system等の終了理由）も未設定。
- **Reference順序の辞書順バグ**（A項と同一、`EventBridge.swift:275-277`）: 参照10個以上のイベント（OnNotifyOSInfo等）で順序が崩れる。

### 未実装（重要度: 中）
- 見切れ/重なり（mikire/kasanari）の判定ロジック自体が見当たらない（OnSurfaceRestore 等の発火条件にも関わる）。
- WebSocket/アーカイブ完了系14イベント（前掲）。

### 互換性リスク
- マウス系は `InputMonitor`（411行）が存在するが、OnMouseClick の Reference4（当たり判定名）/Reference5（ボタン種別）/Reference6（デバイス種別）の充足は本監査では未確認（要追検証）。

---

## E. プロパティシステム (`Property/`)

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）
- トップレベル名前空間のカバレッジ: system / baseware / ghostlist / activeghostlist / currentghost / balloonlist / headlinelist / pluginlist / history / rateofuselist — UKADOC `list_propertysystem` の主要名前空間と一致 → `PropertyManager.swift:14-31`
- `%property[...]` 展開と再帰展開の深さ制限: `PropertyManager.swift:157-`、`EnvironmentExpander.swift:177-179`
- 読み書き区別（provider.set の成否を返す）: `PropertyManager.swift:82-93`
- `\![set,property,...]` / `\![get,property,...]`、EXECUTE SetProperty/GetProperty 経由のアクセス: `SSTPDispatcher.swift:439-446`

### 実装済み（要修正）
- **【重大】値キャッシュが無期限**: `get()` は結果を `valueCache` に永続保存し、無効化は `set()`/`register()` 時のみ（`PropertyManager.swift:95-114,153-156`）。`system.second`/`system.cursor.pos` など毎秒変わる値が**初回取得時の値で固定**される。時刻系プロパティで時計が止まる。
  - 修正案: system.* はキャッシュ除外、またはTTL/世代カウンタ導入。
- **キー全体を lowercase してから照合**: `ghostlist(ゴースト名).name` のような名前パラメータ部分まで小文字化される（`PropertyManager.swift:96`）。大文字を含むゴースト名・シェル名で取得失敗の恐れ。パラメータ部分は原文を保持すべき。
- **`currentghost.balloon` プロバイダが到達不能の疑い**: `register("currentghost.balloon", ...)` するが、ルックアップは最初のドットで分割した `currentghost` をキーにするため `GhostPropertyProvider` に吸われる（`PropertyManager.swift:26,103-106`）。balloon.mousecursor系はGhostPropertyProvider側に重複実装があるため動くが、登録は死んでいる。整理が必要。

### 未実装（重要度: 低〜中）
- `currentghost.seriko.cursor.*` / `currentghost.seriko.tooltip.*` / `currentghost.balloon.scope(ID).validwidth` 等の深い階層は GhostPropertyProvider(580行)・BalloonPropertyProvider(205行) の範囲を超える分が未実装（UKADOC一覧147項目との完全照合は省略、主要75項目程度をカバーと推定）。

---

## F. YAYA言語VM (`yaya_core/`)

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）
- **組み込み関数 155/163**: 本家 yaya-shiori `sysfunc.cpp` の関数表163項目と名前単位で完全照合した結果、未実装は8項目のみ（後述）。RAND/STRFORM/RE_SEARCH/RE_MATCH/RE_REPLACE/RE_SPLIT/RE_GREP/F系ファイルIO/CHARSET系/EVAL/EXECUTE/SAVEVAR/RESTOREVAR/LOADLIB/REQUESTLIB等まで広くカバー → `yaya_core/src/VM.cpp:525-`
- ゴースト自身のYAYA製フレームワーク（`request`/`load` 関数）を通す設計: SHIORIリクエスト原文を `request` に渡し SHIORI3FW/SHIORI3EV ディスパッチを活かす → `YayaCore.cpp:147-210`。互換性確保の観点で適切なアーキテクチャ。
- NOTIFY返値無視リストのVM側二重ガード: `YayaCore.cpp:231-240`

### 実装済み（要修正）
- **【最重大】辞書ファイルの文字コード変換が未実装**: `DictionaryManager::load` は `(void)encoding; // TODO: Handle encoding conversion (UTF-8/CP932)`（`DictionaryManager.cpp:78`）、`loadFile` は生バイト読み（`DictionaryManager.cpp:20-30`、BOM除去も無し）。**既存YAYAゴーストの大半は Shift_JIS 辞書**であり、現状では文字化け・構文エラーで起動不能。yaya.txt の `charset` 指定や各dicのBOM検出→CP932/UTF-8変換が必須。
- **SHIORI応答の `Value:` 以外を全破棄**: フレームワーク応答から `"Value: "` の部分文字列検索で1行抜くのみ（`YayaCore.cpp:192-206`）。OnCommunicate 応答の `Reference0`（通信相手指定）、`ValueNotify`、`Status`、`Balloon` 等のヘッダが失われ、**ゴースト間コミュニケートの返信連鎖が成立しない**。substring検索は本文に「Value: 」を含む場合の誤抽出リスクもある。
  - 修正案: 応答をヘッダ単位でパースし、ホスト（Swift側）まで全ヘッダを引き渡す。
- Charset を `UTF-8` 固定でフレームワークに渡す（`YayaCore.cpp:169`）: 辞書がSJISの場合の整合が取れない（上記と同根）。

### 未実装（重要度: 高→低の順）
- **RE_GETSTR / RE_GETPOS / RE_GETLEN**（重要度: 高）: RE_SEARCH/RE_MATCH 後にマッチ結果を取り出す常用関数。正規表現を使うゴースト（多数）が実質動かない。
- **RE_OPTION / RE_REPLACEEX**（重要度: 中）
- **FSTATUS**（重要度: 低）、**DIRECTSSTP**（重要度: 低、プラットフォーム差異として代替設計が必要）

### 互換性リスク
- ドキュメント（CLAUDE.md「Rustクレート」）と実体（C++）の乖離。ビルド手順 `yaya_core/build.sh` の記述は要確認。

---

## G. プラグインシステム (`PluginHost/`, `PluginEvent/`, `SaoriHost/`)

### 準拠度スコア: 7/10（構造検証中心。実プラグインでの動的検証は未実施）

### 実装済み（仕様準拠）
- PLUGIN/2.0 のリクエスト/レスポンス構造（GET/NOTIFY、ID必須、Charset/Sender/Target/Reference*、CRLF・空行終端）: `PluginProtocol.swift:86-130`（バージョン文字列は独自拡張の `PLUGIN/2.0M`）
- ライフサイクル `load`/`unload`/`request` シンボル解決（requestのみ必須）: `Plugin.swift:27-32` — Plugin/2.0 の必須/任意関係と一致
- レスポンスの Script/ScriptOption/Target/Value ヘッダ: `PluginProtocol.swift:44-76`、Script実行ブリッジ: `OurinPluginEventBridge.swift:60-70`
- SAORI/1.0 ホスト: `request`/`load`/`unload`（`saori_*` 別名対応）、charset変換（Shift_JIS含む）: `SaoriLoader.swift:44-61`、`SaoriProtocol.swift:158-176`

### 互換性リスク（プラットフォーム差異）
- Windows用 `.dll` プラグイン/SAORIはバイナリ互換で動作不可能（macOSネイティブ `.plugin`/`.bundle` の再ビルドが必要）。これは不可避のプラットフォーム差異であり減点対象とはしないが、エコシステム互換の観点では「既存プラグイン資産は流用不可」である旨をdocsに明記すべき。
- PLUGIN/2.0 の `OnSecondChange`/`installedghostname` 等ホスト→プラグイン通知イベントの網羅性は未深掘り（`PluginEventDispatcher` 存在確認まで）。

---

## H. NARパッケージ (`NarInstall/`, `Nar/`)

### 準拠度スコア: 6/10

### 実装済み（仕様準拠）
- ZIP形式検証（拡張子+PKヘッダ）・Zip Slip対策・一時展開→安全コピー: `LocalNarInstaller.swift:39-81`
- install.txt の `type`/`directory` 必須パース、カンマ区切り、`;`/`#` コメント、UTF-8→CP932フォールバックデコード: `InstallTxtParser.swift:11-44`
- 更新定義の探索順 `updates2.dau`→`updates.txt`→`update.txt` と `\x01` 区切り対応: `LocalNarInstaller.swift:84-116`、`InstallTxtParser.swift:46-75`（dev_nar/更新定義ファイル仕様準拠）
- delete.txt の処理とパストラバーサル検査: `LocalNarInstaller.swift:118-137`
- type別インストール先解決: `Paths.swift`

### 実装済み（要修正）
- **同梱バルーンが捨てられる**: `balloon.directory` / `*.source.directory` は extras に取り込むだけで未使用（`InstallTxtParser.swift:36-37`、install() に消費コード無し）。ゴースト+バルーン同梱NAR（配布形態として一般的）でバルーンがインストールされない。
- **`accept` の誤用**: 既存ディレクトリ衝突時に `accept == nil` なら即エラー（`LocalNarInstaller.swift:67-69`）。仕様の accept は「SSTP経由インストールの受理判定」であり、上書き更新の可否とは別概念。既存フォルダへの**上書き更新**（通常のゴースト更新手順）が常に失敗する。`refresh`/`refreshundeletemask`（全消し更新と保護マスク）も未実装。
- install.txt 自身の `charset` キー無視（ヒューリスティックで実害は小）。

---

## I. FMO (`FMO/`)

### 準拠度スコア: 3/10

### 実装済み（仕様準拠）
- POSIX共有メモリ+名前付きセマフォによる排他とサイズヘッダ付き読み書き: `FmoSharedMemory.swift:61-78`、`FmoMutex.swift` — Windows FMO/MUTEX の意味的対応物としての骨格は妥当（プラットフォーム差異として許容）

### 実装済み（要修正）
- **【重大】作成直後に `shm_unlink` する「エフェメラル」運用**: `FmoSharedMemory.swift:36-37`。名前を消すため**他プロセスは二度とアタッチできず**、FMOの存在意義（プロセス間でのゴースト一覧共有・多重起動検出）が成立しない。
- **多重起動検出の名前不整合**: 検出は `/ninix` を見る（`FmoManager.swift:17`）が、自身は `/ssp_fmo`+`/ssp_mutex` を作成して即unlink（`FmoManager.swift:37-41`）。Ourin同士でも検出不能、ninix/SSP両規約のちゃんぽん状態。
- **FMO内容フォーマットが非互換**: SSPのFMOは `id.key\x01value\r\n` 形式のレコード集合（hwnd/name/keroname/sakura.surface/path等）。Ourinが `GetFMO` で返すのは `key=value;...` 独自形式（`SSTPDispatcher.swift:492-520`）。FMOパースを行う既存ツールと非互換。
  - 修正案: 少なくとも `GetFMO` 応答は SSP互換のレコード形式（改行区切り・空行終端）で返す。hwnd は Win32 HWND ではなく、macOS 上の安定した Ourin ウィンドウ識別子として扱う。
  - 現状: 2026-06-27時点で `FmoManager.buildSnapshot()` / `FmoCompatibilityView` により解消済み。Windows FileMapping/HWND の直接互換はプラットフォーム差異。

---

## J. バルーン・シェル・リソース (`Balloon/`, `ResourceBridge/`, `Ghost/`, `Animation/`)

### 準拠度スコア: 6/10（surfaces.txt 詳細仕様の深掘りは未実施）

### 実装済み（仕様準拠）
- balloon descript.txt のカンマ区切りパース・SJISフォールバック・`balloons*.txt` マージ: `Balloon/DescriptorLoader.swift`
- SERIKO interval/pattern パース: `Animation/SerikoParser.swift`（interval解釈 `:163-171` 等）、実行系 `SerikoExecutor`/`AnimationEngine`、テストあり（`SerikoParserTests`/`SerikoExecutorTests`/`SurfaceOverlayOrderingTests`）
- ICO/画像ローダ、リソースブリッジ、ゴースト descript: `GhostConfiguration.swift`（491行、テストあり）

### 実装済み（要修正）
- **descript.txt の `charset` 行を読まない**: コメントは「charset,Shift_JIS 対応」と謳うが実装はUTF-8→SJISの順の総当たり（`DescriptorLoader.swift:22-28`）。SJISファイルが偶然UTF-8として妥当な場合に誤デコードする。charset行を先頭で検出してから再デコードすべき（SSPと同じ二段読み）。

### 未実装/未検証（重要度: 中）
- surfaces.txt の括弧レンジ定義（`surface0-9`）、`element`合成、MAYUNA（着せ替え `\![bind,...]` のdressup定義との連携は `GhostManager+Dressup.swift` に存在）、`surfacetable.txt`、PNA/seriko.use_self_alpha の網羅性は本監査では確認しきれていない。追監査を推奨。
- バルーンの `validwidth/validheight`・オンラインマーカー・矢印/スクロールバー画像（balloon仕様のUI部品）の実装状況は `BalloonConfig.swift`/`BalloonView.swift` に部分実装を確認したが仕様全項目との照合は未実施。

---

# 最終サマリー

## 1. 全体準拠度スコア（SHIORI・SakuraScript を重み2倍）

| カテゴリ | スコア | 重み |
|---|---|---|
| A. SHIORI | 6 | ×2 |
| B. SSTP | 4 | ×1 |
| C. SakuraScript | 6 | ×2 |
| D. SHIORIイベント | 6 | ×1 |
| E. プロパティ | 6 | ×1 |
| F. YAYA VM | 6 | ×1 |
| G. プラグイン | 7 | ×1 |
| H. NAR | 6 | ×1 |
| I. FMO | 3 | ×1 |
| J. バルーン/シェル | 6 | ×1 |

**加重平均: 68/12 ≈ 5.7 / 10**

総評: イベントID定義（404個）、YAYA組み込み関数（155/163）、`\![...]`動詞群（60+）といった**「語彙の網羅」は非常に優秀**。一方で、`\t`/`\-`/`\v`/`\4`/`\5` のような**頻出タグの意味論の取り違え**、OnSecondChange の Reference 欠落、SSTP Script 非再生、YAYA辞書の文字コード未変換など、**「実在ゴーストを動かす」ために決定的な箇所の正確性が不足**しており、語彙力と意味論のギャップが現状の最大の課題。

## 2. クリティカルな互換性問題 Top 10

1. **YAYA辞書の Shift_JIS 変換未実装**（F, `DictionaryManager.cpp:78`）— 既存YAYAゴーストの大半が起動不能。単独で最大のブロッカー。
2. **OnSecondChange/OnMinuteChange が Reference 無し・常時NOTIFY**（D, `TimerEmitter.swift`）— ランダムトーク・cantalk制御という伺かの基本動作が壊れる。
3. **RE_GETSTR/RE_GETPOS/RE_GETLEN/RE_OPTION 未実装**（F）— 正規表現を使うYAYAゴーストの会話処理が崩壊。
4. **SSTP SEND の Script ヘッダがバルーン再生されない + 応答行が `SSTP/SSTP/1.x`**（B, `SstpRouter.swift`）— SSTP連携アプリが全滅。
5. **`\t`（タイムクリティカル）の誤実装**（C）— 保護区間に割り込みが入る。
6. **`\-`（終了）の誤実装**（C）— メニューから終了を選んでもゴーストが終了しない定番動線の破壊。
7. **`\j[ID]` ハンドラ欠落**（C）— URL/イベントジャンプの黙殺。
8. **OnClose 応答破棄・OnBoot Reference0 欠落・OnSecondBoot 発明**（D）— 起動/終了トークの不全。
9. **COMMUNICATE の Reference マッピング誤り + YayaCore の応答ヘッダ破棄**（B/F）— ゴースト間コミュニケート不能。
10. **IfGhost 独自書式 + 重複ヘッダ消失**（B, `SSTPRequest.swift`/`SstpParser.swift`）— 保険スクリプト付きSSTPの仕様逸脱。

次点: FMO即時unlink（I）、プロパティ無期限キャッシュ（E）、NAR同梱バルーン破棄・上書き更新不能（H）。

## 3. 推奨修正優先順位（影響度×コスト）

| 優先 | 項目 | コスト感 |
|---|---|---|
| P0 | YAYA辞書 CP932→UTF-8 変換（iconv/ICU、BOM処理込み） | 小〜中 |
| P0 | `SstpParser` の version 二重プレフィクス修正 | 極小（1行） |
| P0 | TimerEmitter に Reference0-4 を付与、cantalk で GET/NOTIFY 切替 | 小 |
| P0 | RE_GETSTR/RE_GETPOS/RE_GETLEN/RE_OPTION 実装（マッチ状態保持） | 小〜中 |
| P1 | SSTP SEND/NOTIFY のスクリプト再生配線（router→GhostManager） | 小 |
| P1 | `\t`/`\-`/`\v`/`\4`/`\5`/`\*`/`\a`/`\&` の意味論修正、`\j` 実装、`\_V` 分岐修正 | 中 |
| P1 | OnClose 応答再生＋終了シーケンス、OnBoot/OnFirstBoot の Reference | 小 |
| P1 | YayaCore の SHIORI 応答全ヘッダ引き渡し | 中 |
| P2 | SSTPスタック統合（SSTPDispatcher へ一本化し SstpRouter を廃止） | 中〜大 |
| P2 | orderedRefs 数値ソート、PropertyManager キャッシュ戦略、IfGhost 順序保持パーサ | 小 |
| P2 | NAR: 同梱バルーン処理・refresh更新・accept意味修正 | 中 |
| P3 | FMO 設計見直し（unlink タイミング、GetFMO の SSP互換レコード形式） | 中 |
| P3 | SHIORI/2.x 互換層の正実装 or 削除 | 中 |

## 4. SSPとの主要な仕様解釈の差異（仕様が曖昧な箇所含む）

- **512 Invisible の用途**: 仕様は「最小化等で表示されていない」。Ourin は「インストール済みゴーストが無い」に流用（`SstpRouter.swift:58-62`）。SSPは該当時 404/420 系。許容範囲だが要注記。
- **SSTP over HTTP のポート**: SSP は SSTPポート(9801)に同居。Ourin は 9810 の独立サーバ。クライアントの既定値と合わない。Origin 非localhost時も SSP は「external扱いで継続」、Ourin は 403 拒否。
- **GIVE**: SSP では教え込み系処理に接続。Ourin は無処理204（router）/OnChoiceSelect（dispatcher）と内部でも不統一。
- **EXECUTE GetFMO**: SSP は「アプリ内管理分の FMO 相当をFMOレコード形式で返す」。Ourin は独自 key=value 形式。
- **`\![raise]` のメソッド**: SSP は GET 相当（返値スクリプト再生）。Ourin は NOTIFY で送って返値があれば再生するハイブリッド（`GhostManager.swift:885-903` → `EventBridge.sendNotify`）。YAYAフレームワークは NOTIFY に 204 を返すため返値再生が機能しない可能性が高い。
- **プラットフォーム差異（減点対象外）**: DirectSSTP(WM_COPYDATA)→XPC代替、SHIORI DLL ABI（`shiori_load/request/unload/free` 独自シンボル）、HWnd のダミー化、パス区切り、FMOのPOSIX実装。これらは docs/ に「Ourin拡張仕様」として明文化されており方針自体は妥当。

## 5. Ourin側ドキュメントへの修正提案

- CLAUDE.md / docs の「yaya_core は Rust製」記述を C++ 実装の実態に合わせて更新（ビルド手順含む）。
- `SakuraScriptEngine.swift` 冒頭および `GhostManager.swift:769-771` のコメントが `\t` を「短いポーズ」と誤記述 — UKADOC原文（タイムクリティカルセクション）に合わせて修正。
- docs/ の SSTP 仕様書（Ourin独自 1.xM）に、本レポート B 項の非互換点（IfGhost書式・nodescript意味・EXECUTE返値形式）を UKADOC 準拠へ改める旨を反映。

---

*本レポートは静的解析に基づく。SSP 2.8.27f との動的比較（Wine 実行）と、実在ゴースト（おおやしまDB上位の YAYA 製ゴースト等）でのインストール〜起動〜会話の E2E 検証を次フェーズとして推奨する。*
