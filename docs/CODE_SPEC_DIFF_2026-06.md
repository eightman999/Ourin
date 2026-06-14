# コードと仕様書の差異レポート (2026-06-14)

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
| 5 | P1 | **HTTP SSTP のポートが 9810**（仕様はTCPと同じ9801） | `SstpHttpServer.swift:29`(9810) / `SstpTcpServer.swift:29`(9801) / `SSTP_1.xM_SPEC_ja-jp.md:71` | 📝 未対応（理由は §5） |
| 6 | P1 | **XPCプロトコル二重定義・メソッド名不一致**。`OurinSSTPXPC.executeSSTP` と `OurinExternalSstpXPC.deliverSSTP`。仕様は `executeSSTP(_:withReply:)` 単一 | `Ourin/SSTP/DirectSSTPXPC.swift:3` / `Ourin/ExternalServer/XpcDirectServer.swift:5` / `SSTP_1.xM_SPEC_ja-jp.md:50,188-190` | 📝 未対応（理由は §5） |
| 7 | P0/P1 | **SERIKOカーソルキーの構造相違**。実装は単一 `cursor.scope(ID).mouselist`、仕様は `mouseup/mousedown/mousehover/mousewheellist` の4分岐 | `GhostPropertyProvider.swift:502-533` / `PROPERTY_1.0M_SPEC_ja-jp.md:109` | 📝 未対応（要構造再設計） |

---

## 2. 未実装・部分実装（機能拡張として計画）

- 📝 **NAR更新機能(updates2.dau/updates.txt)・delete.txt 未実装**。設計のみ。`LocalNarInstaller.swift` / `NAR_INSTALL_1.0M:162-164`
- 📝 **汎用dylib直接ロード・`loadu`エントリ未対応**。`HeadlineModule.swift:26-30`・`HeadlineRegistry.swift:26-28` は `load` のみ解決。USLはYAYA専用。
- 📝 **Plugin XPC/プロセス分離 未実装**（`DispatchQueue`直列のみ）。`SPEC_PLUGIN_2.0M_ja-jp.md:134` でも「未実装」と記載。
- 📝 **プロパティ汎用名 未実装**: `thumbnail / update_result / update_time / shiori.<var> / index / sakura.bind.menu`。`GhostPropertyProvider.swift:344-379`
- 📝 **SHIORI Resource のベースウェア側キャッシュ/SET書込が無い**（毎回 `ResourceBridge.query()`）。`ResourceManager.swift`
- 📝 **バルーン高機能描画が薄い**疑い。`Balloon/`（多形式画像/Retina/装飾が `BALLOON_1.0M_SPEC` 要求に対し簡潔）。
- 📝 **Plugin `OnChoiceSelect(Ex)/OnAnchorSelect(Ex)/\q`** は `onArbitraryEvent()` があるが呼び出し元なし。`PluginEventDispatcher.swift:149`
- 📝 **SHIORI 内部イベントの SecurityLevel が常に "local" 固定**（C ABI経路は SecurityLevel/Origin 差し込み機構なし）。`EventBridge.swift:397,418,440` / `ShioriLoader.swift:410-432`

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
- **FMO/NAR/USL/SAORI/Web**: FMO共有メモリ名・SSP風レコード・hwnd=0、NAR(ZIP検証/ZipSlip防止/install.txt UTF-8&CP932/型別振分/refresh)、YAYAアダプタJSON行IPC、SAORI(dlopen/dlsym統合)、Web(`x-ukagaka-link`→`OnXUkagakaLinkOpen` external/https強制)。
- **Plugin**: PLUGIN/2.0M Request/Responseパーサ・ビルダ、load/loadu/unload、文字コード正規化、macOS差分(CGWindowID/POSIXパス/0x01区切り)。

---

## 5. 本コミットで「修正しなかった」項目と理由

- **#5 HTTPポート(9810→9801)**: TCPサーバ(9801)とHTTPサーバ(9810)は `OurinExternalServer.swift:87,95` で**同時に別リスナーとしてバインド**される。HTTPを9801に変えると起動時にポート競合で破綻する。SSPは単一ポートを多重化(プロトコル判定)するが、Ourinはリスナー分離設計。正しい対応は「9801での多重化」または「設定可能ポート＋仕様文書の追従」であり、設計判断を要するため本コミットでは変更せず。
- **#6 XPCプロトコル名**: `DirectSSTP`(同一機内ダイレクト)と`External`(外部配送)は**用途の異なる2サービス**。安易な改名は対の接続コードを破壊する。命名統一は両サービスのクライアント整合を要するため保留。
- **#7 SERIKOカーソル構造**: 単一 `mouselist` → 4分岐への変更はプロパティ生成側の構造再設計が必要。互換影響が広く別タスクとして計画。

---

## 6. 推奨対応（優先度順）

1. 🔧（本コミット）CPUバグ・メモリキー・Plugin Ref5/version。
2. ポート/XPC命名の設計判断（§5）— 外部連携互換に直結。
3. SERIKOカーソルキー・プロパティ汎用名の仕様準拠 — 既存ゴースト資産互換。
4. ドキュメント同期: `TODO/todo.md` 廃止、各SPECの「未実装」記載と更新日の更新、ja-jp翻訳スタブ解消。
5. NAR更新/削除、dylib汎用ロード/`loadu`、Plugin XPC分離は機能拡張として別途計画。
