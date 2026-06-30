# コードと仕様書の差異レポート (2026-06-14、追記 2026-06-15)

> 2026-06-15 追記: §1 の #5(HTTPポート)・#6(XPC命名)・#7(SERIKOカーソル) を解決（詳細は §5）。
> §2 の NAR 記載を実態（delete.txt/refresh/更新記述子取得は実装済み、更新の実適用のみ未配線）に訂正。
> さらに §2 の プロパティ汎用名(P1)・dylib `loadu`(P2)・Plugin XPC分離(P3)・SHIORI SecurityLevel差し込み(P4) を実装（🔧）。


`docs/` の各仕様書（ja-jp優先）と `Ourin/`・`yaya_core/` の実装を、
SHIORI / SSTP / さくらスクリプト・SERIKO / プロパティ / FMO他 / Plugin の6領域で突き合わせた結果。

凡例: ✅=実コードで裏取り済み / 🔧=本レポートのコミットで修正済み / 📝=未対応(要計画) / 📄=ドキュメント負債(コードは正)

---

## 0. 構造的傾向

1. **「仕様書が実装より古い」逆転現象が多数**。`TODO/todo.md`(2025-10-21)・`IMPLEMENTATION_STATUS_SUMMARY`(2026-03)・各SPECの「未実装」記載が、実装済み機能を「未実装」と誤記している。2026-06のCOMPAT_FIXES以降ドキュメントが追従できていない。
2. **ja-jp版が翻訳スタブのまま**の仕様が複数（`SHIORI_RESOURCE_3.0M_ja-jp`、`SAKURASCRIPT_COMMANDS_SUPPORTED_ja-jp` 等）。正本は en-us 側。
3. 差異の大半は「コードのバグ」ではなく**ドキュメント負債**。

---

## 1. 実装バグ・明確な不整合

| # | 重要度 | 差異 | 根拠 | 状態 |
|---|---|---|---|---|
| 1 | P1 | **CPU使用率が常時≈100%**。`(user+system+idle+nice)/total*100` で分子に idle を含む(=total/total)。正: idle 除外 | `Ourin/Property/PropertyManager.swift:292` | 🔧修正済 |
| 2 | P1 | **メモリプロパティのキー名相違**。実装 `system.memory.physical/.available` ⇔ 仕様 `.phyt/.phya` | `PropertyManager.swift:251-252` / `PROPERTY_1.0M_SPEC_ja-jp.md:86-88` | 🔧 phyt/phya を正式キーに追加（英語別名も互換維持） |
| 3 | P1 | **Plugin `OnOtherGhostTalk` の Ref5 仕様ずれ**。Ref5は「0x01区切りの単一Reference」だが実装は複数Referenceに展開 | `PluginEventDispatcher.swift:142-146` / `PLUGIN_EVENT_2.0M_SPEC_FULL_ja-jp.md:88-94` | 🔧 `ListDelimiter.join` で結合 |
| 4 | P1 | **Plugin version応答が破棄**。仕様は応答Valueと任意`Charset:`を以降の通信に適用。実装は `let _ = plugin.send(req)` でログのみ | `PluginEventDispatcher.swift:64-72` / `PLUGIN_EVENT_2.0M_SPEC_ja-jp.md §4.1` | 🔧 応答をparseし交渉Charsetをプラグイン毎に保持・送信に反映 |
| 5 | P1 | **HTTP SSTP のポートが 9810**（仕様はTCPと同じ9801） | `SstpHttpServer.swift` / `SstpTcpServer.swift` / `SSTP_1.xM_SPEC_ja-jp.md:71` | 🔧 **修正済 (2026-06-15)**。`UnifiedSstpListener` を新設し 9801 単一ポートで HTTP/生SSTP を先頭行判定により多重化。HTTP 専用 9810 リスナーは廃止 |
| 6 | P1 | **XPCプロトコル二重定義・メソッド名不一致**。`OurinSSTPXPC.executeSSTP` と `OurinExternalSstpXPC.deliverSSTP`。仕様は `executeSSTP(_:withReply:)` 単一 | `Ourin/SSTP/DirectSSTPXPC.swift` / `Ourin/ExternalServer/XpcDirectServer.swift` | 🔧 **修正済 (2026-06-15)**。`OurinExternalSstpXPC` を廃止し `XpcDirectServer` を共通 `OurinSSTPXPC.executeSSTP(_:withReply:)` に統一 |
| 7 | P0/P1 | **SERIKOカーソルキーの構造相違**。実装は単一 `cursor.scope(ID).mouselist`、仕様は `mouseup/mousedown/mousehover/mousewheellist` の4分岐 | `GhostPropertyProvider.swift` / `PROPERTY_1.0M_SPEC_ja-jp.md:109` | 🔧 **修正済 (2026-06-15)**。`serikoCursor` を `[scope:[種別:[name:path]]]` に再設計し4種リストの GET/SET に対応 |

---

## 2. 未実装・部分実装（機能拡張として計画）

- 🔧 **NAR更新の実適用 → 対応済み (2026-06-15)**。`NarInstaller.downloadAndApply(entries:homeURLString:targetRoot:)` を新設し、`checkGhostUpdate` が更新記述子の列挙後に各ファイルをダウンロードして適用する（`.nar`/`.zip` は `install(fromNar:)`、それ以外は homeurl 基準の相対パスでゴーストルートへ保存、パストラバーサル防止）。OnUpdate.OnDownloadBegin/Complete・OnUpdateComplete を実適用結果で発火。`delete.txt`/`refresh`/`refreshundeletemask`/同梱`balloon.directory` は既存実装。
- 🔧 **汎用dylib直接ロード・`loadu`エントリ → 対応済み (2026-06-15)**。SAORI/SHIORI(DylibBackend)/Headline/Plugin の各ローダで `loadu`(UTF-8パス版)を `load` より優先解決。SHIORI DylibBackend は無印 `load/request/unload/free`（Windows由来）も解決する汎用化。
- 🔧 **Plugin XPC/プロセス分離 → 対応済み (2026-06-15)**。`PluginXpcBackend.swift`(`OurinPluginXPC`/`PluginXpcClient`)を新設。`OURIN_PLUGIN_ISOLATION_MODE=xpc` または `OURIN_PLUGIN_XPC_SERVICE` 指定時に `PluginEventDispatcher` が別プロセスワーカーへ送信（既定はインプロセス）。SHIORI XpcBackend と同設計。
- 🔧 **プロパティ汎用名 → 対応済み (2026-06-15)**: `thumbnail / update_result / update_time / shiori.<var> / index` を Ghost で解決、`(sakura|kero|char*).bind.menu` を currentghost runtime 状態として GET/SET 対応。`index` は Balloon/Headline/Plugin list でも対応。
- 🔧 **SHIORI Resource キャッシュ/SET → 対応済み (2026-06-15)**。`ResourceBridge` は既に5秒TTLキャッシュを保持。新たに SET 上書き層（`set(key:value:)`/`clearOverride(_:)`）を追加し、上書き値を SHIORI 問い合わせより優先（空文字=定義削除）。NSLock でスレッド安全化。
- 🔧 **バルーン高機能描画 → 一部対応 (2026-06-15)**。汎用 `ImageLoader.load` に PNA（別アルファファイル）合成を追加（`CIBlendWithMask`）。`BalloonView` の縁取りを単一ブラーから8方向オフセット影による実アウトラインに改善。残: Retina(@2x) アセット選択。
- 🔧 **Plugin `OnChoiceSelect(Ex)/OnAnchorSelect(Ex)` → 配線済み (2026-06-15)**。`GhostManager.forwardEventToPlugins` を新設し、選択肢確定（`showChoiceDialog`）とアンカークリック（`onBalloonClicked`）から `PluginEventDispatcher.onArbitraryEvent` へ横流し。残: `\q`(キュー済み選択肢) のプラグイン配線。
- 🔧 **SHIORI 内部イベントの SecurityLevel 差し込み → 対応済み (2026-06-15)**。`EventBridge` に `ShioriSecurityContext`(level/origin)を導入し `notify`/`notifyCustom`/`sendNotify`/`sendNotifyCustom`/`sendGet` へ伝搬（既定 local）。非YAYA(`BridgeToSHIORI.handle`)経路にもヘッダを渡すよう修正（従来は SecurityLevel が欠落していた）。
- 🔧 **大量Character表示 → 対応済み (2026-06-15)**。`GhostManager.ensureCharacterWindow(for:)` で scope ウィンドウを遅延生成。`setupWindows` は scope 0/1 のみ先行生成し、`\p[N]`(任意 N)はスコープ切替・サーフェス更新時に生成。残: 複数ゴースト同時実行（AppDelegate は単一 GhostManager 保持。アーキテクチャ変更が必要）。

---

## 3. ドキュメント負債（コードは正・要更新）

- 📄 `TODO/todo.md` が ❌NOT FOUND とする `\![embed]`/`\![timerraise]`/`\![change,*]`/`\_l[x,y]`/`\f[...]` は実装済み（`GhostManager.swift:1080-1165,2166-2170,2216-2380`）。→ `TODO/todo.md` 廃止、`docs/SUPPORTED_SAKURA_SCRIPT.md` を正本に。
- 📄 `SERIKO_IMPLEMENTATION.md` が「Executor未統合」と記すが統合済み（`GhostManager+Animation.swift:73-83,94,155`）。
- 📄 `SSTP_1.xM_SPEC_ja-jp.md:181-182` の未実装チェックリスト（SecurityLevel/Origin・ReceiverGhostName→404）は実装済み（`SSTPDispatcher.swift:92-113,530-537,617-637`）。
- 📄 `SHIORI_3.0M_SPEC` が「XPC分離=未実装」と記すが `ShioriLoader.swift:293-352` に `XpcBackend` 実装済み。
- 📄 `PLUGIN_EVENT_2.0M_SPEC_ja-jp.md:209-226` が全イベント「未実装」と記すが `PluginEventDispatcher.swift:76-151` に実装済み。
- 📄 ja-jp翻訳スタブ放置、Plugin改行の短版「CRLF厳守」vs完全版「LF推奨」矛盾、Sample(`OurinPluginEventBridge.swift:10`)の旧版 `GET PLUGIN/2.0`（実装は `2.0M`）。

---

## 4. 仕様通り実装済みの主要項目（確認済み）

- **SSTP**: SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE/INSTALL、CRLF+空行終端、Charset(UTF-8/CP932)、ステータスコード一式、Option(nodescript等)、X-SSTP-PassThru、ReceiverGhostName→404、SecurityLevel/Origin。
- **SHIORI**: 4関数 C ABI(load/unload/request/free)、UTF-8既定+SJIS受理、YAYAバックエンド、XpcBackend。
- **さくらスクリプト/SERIKO**: scope/surface/anim制御/balloon/sound/wait/cursor/環境変数/`\f[...]`装飾、SERIKO executor統合。
- **Property**: system.* 各種、os識別(Rosetta2検出含む)、ghost/balloon/headline/plugin各list、history、rateofuselist。
- **FMO/NAR/USL/SAORI/Web**: FMO共有メモリ名・SSP風 `id.key\x01value\r\n` レコード・Ourinウィンドウ識別子・構造化互換ビュー、NAR(ZIP検証/ZipSlip防止/install.txt UTF-8&CP932/型別振分/refresh)、YAYAアダプタJSON行IPC、SAORI(dlopen/dlsym統合)、Web(`x-ukagaka-link`→`OnXUkagakaLinkOpen` external/https強制)。
- **Plugin**: PLUGIN/2.0M Request/Responseパーサ・ビルダ、load/loadu/unload、文字コード正規化、macOS差分(POSIXパス/0x01区切り)、Windows DLL metadata-only と native `.plugin` / `.bundle` の互換ビュー。

---

## 5. #5/#6/#7 の対応記録（2026-06-15 解決）

当初コミットでは設計判断を要するとして保留した3件を、2026-06-15 に以下の通り解決した。

- **#5 HTTPポート(9810→9801)**: 旧設計は TCP(9801)/HTTP(9810) を別リスナーとして同時バインドしていた。
  SSP 同様の単一ポート多重化へ移行。`UnifiedSstpListener` を新設し 9801 で待ち受け、接続の先頭リクエスト行に
  ` HTTP/` を含むかで HTTP / 生 SSTP を判別し、それぞれ `SstpHttpServer.adopt` / `SstpTcpServer.adopt`
  （先読みバッファ引き継ぎ）に委譲する。HTTP 専用 9810 は廃止。
- **#6 XPCプロトコル名**: `OurinExternalSstpXPC.deliverSSTP` を廃止し、`XpcDirectServer` を DirectSSTP と
  共通の `OurinSSTPXPC.executeSSTP(_:withReply:)` へ統一。direct/external の2リスナーは用途別に維持しつつ、
  プロトコル定義とメソッド名のみ一本化（exportedInterface も `OurinSSTPXPC` に統一）。
- **#7 SERIKOカーソル構造**: `serikoCursor` の格納を `[scope:[name:path]]` から
  `[scope:[種別:[name:path]]]` に再設計し、`mouseuplist/mousedownlist/mousehoverlist/mousewheellist`
  4種の `.count` / `(hit).path|name` / `.index(ID2).path|name` を GET/SET 両対応にした。

---

## 6. 推奨対応（優先度順）

1. ✅（PR #92）CPUバグ・メモリキー・Plugin Ref5/version。
2. ✅（2026-06-15）ポート多重化(#5)・XPC命名統一(#6)・SERIKOカーソル4分岐(#7)。
3. ✅（2026-06-15）プロパティ汎用名(P1)・dylib `loadu`(P2)・Plugin XPC分離(P3)・SHIORI SecurityLevel差し込み(P4)。
3b. ✅（2026-06-15 第2弾）NAR更新の実適用(R1)・Resource SET層(R2)・バルーンPNA/縁取り(R3)・Plugin選択/アンカー配線(R4)・大量Character遅延生成(R5)。
3c. ✅（2026-06-15 第3弾）複数ゴースト同時実行 基盤(M1)・サーフェス/バルーン @2x Retina(M2)・Plugin `\q` 配線(M3)・ja-jp 翻訳スタブ解消(M4)・ExternalServerTests 並列分離(M5)。
   - **M1**: `AppDelegate.additionalGhosts` / `launchAdditionalGhost(at:|named:)` / `terminateAdditionalGhost` を新設し複数 GhostManager を同時保持。FMO は全ゴースト集約。`\+`(bootOtherGhost) は in-process で追加起動。EventBridge は既に複数セッション対応。残: SSTP 応答ヘッダ副作用（Surface/Balloon）は依然プライマリ宛。
   - **M2**: `RetinaImageLoader`(新規)で `name@2x.png`/`@3x` を高解像度 representation として取り込み。surface/balloon/arrow/marker ローダに適用。
   - **M3**: `showChoiceDialog()` を再生完了時に発火するよう配線（従来は定義のみで未呼び出し）。`\q`/`\__q` が機能し、選択時に R4 経由でプラグインへ横流し。
   - **M4**: SHIORI_RESOURCE_3.0M / SAKURASCRIPT_COMMANDS_SUPPORTED / PropertySystem / GhostConfigurationImplementation / RightClickMenuMockup / SHIORI_EVENTS_FULL_1.0M_PATCHED の ja-jp を整備。残: `YAYA_CORE_*`（内部アーキテクチャ文書、低優先）。
   - **M5**: `ExternalServerTests` に `@Suite(.serialized)` と per-test シングルトン reset を付与（`SSTPDispatcherTests` と同方式）。
4. 📝 残（要アーキテクチャ判断）: 複数ゴーストの SSTP 応答ヘッダ個別ルーティング・右クリックメニューのゴースト選択、`YAYA_CORE_*` 内部文書の翻訳。
