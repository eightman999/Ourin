# Ourin 監査項目 — 未完 / Audit Items — TODO

**最終更新 / Last Updated**: 2026-08-14
**集約元 / Consolidated from**: AUDIT_GLM / AUDIT_CODEX / AUDIT_CODEX_2026-06-27 / AUDIT_CLAUDE / AUDIT_AGY（各 ja-jp / en-us）
**検証方法 / Verification**: 全項目を現状ソースコード（file:line）と照合して未完判定。完了済み項目は `AUDITS_COMPLETED.md` 参照。

---

## 日本語

以下は過去の監査レポートで指摘され、**現状コードで未解決**であることを確認した項目です。優先度（P0=最高 → P3=最低）を併記します。

### A. SHIORI プロトコル

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| — | （SHIORI 2.x ABI 互換レイヤーはコア部分が完了 2026-07-09） | `Ourin/USL/Shiori2CompatAdapter.swift`（455行、2026-07-08新規）が `Shiori2CompatBackend` として実装され、`ShioriLoader.swift:846,853,855` でXPC/Bundle/Dylibの全バックエンド生成経路にラップ配線済み。`GET Version` によるバックエンド版数検出／3.0イベント→`GET Sentence SHIORI/2.2`+`Event:`+`Reference0-7`変換／2.xレスポンス（Sentence/BalloonOffset等）→3.0 `Value:`変換／`TEACH`→2.4/311/312往復／Shift_JISエンコードは実装済みで`OurinTests/ShioriLoaderTests.swift:54-253`のテストが通る。 |
| — | （Word/String/Status/OwnerGhostName/OtherGhostName/Communicate変換とOnTalk不一致は完了 2026-07-09） | `Shiori2CompatAdapter.swift:339-422` の6builderに `OurinTests/ShioriLoaderTests.swift` で単体テストを追加（`shiori2WordRequestUsesReference0AsTypeWhenTypeHeaderMissing`等6件）。`buildUserSentenceRequest` の判定を `ID: OnTalk`（存在しないID）から実在する `EventID.OnTalkRequest`（`EventID.swift:361`）に合わせて `lowerID == "ontalkrequest"` へ修正し到達可能化。回帰テスト `shiori2TalkRequestMapsToUserSentenceGet` 追加。 |
| — | （SHIORI 2.x 二重実装は誤りだったことを確認 2026-07-09） | `ShioriLoader.swift:842-853`（`makeBackend`）を実測: `Shiori2CompatBackend` は **XPC/Bundle/Dylib 経由で読み込む外部 SHIORI モジュール**のみをラップする（`ShioriLoader.swift:783-811` の `init?(module:base:)` で `yaya.dll` の場合は `YayaBackend` を直接使用、`Shiori2CompatBackend`でラップしない）。一方 `YayaBackend.parseRequest/buildResponse`（`:413-498`）は Ourin 内蔵 YAYA エンジン専用のワイヤ解析で、3.0形式に加え legacy TEACH SHIORI/2.x 形式も許容する内部実装。両者は disjoint な対象（外部2.xモジュール vs 内蔵YAYA）に別々の配線点から使われており、二重実装ではない。統合不要と判定し完了扱い。 |
| — | （SecurityLevel external 伝播は完了 2026-07-08） | 外部SSTP入口を `SSTPDispatcher.dispatchExternal` に集約し `ShioriSecurityContext.external(origin:)` を実使用。TCP/HTTP/XPC全経路でSHIORIへ `SecurityLevel: external` が届く。localOnlyポリシーの420拒否は維持。テスト追加済み。 |

### B. SSTP プロトコル

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| — | （210 Break nobreak キューイングは完了 2026-07-08、再生状態接続は完了 2026-08-12） | `SSTPBreakQueue` による busy 時ブロッキング待機（既定5秒タイムアウト→409）に、`EventBridge.isAnyGhostPlaying()` 経由の実ゴースト再生状態を接続。テスト `SSTPDispatcherTests` で再生中の待機・再生完了後の200・タイムアウト409を確認。 |

### C. SakuraScript

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| P2 | UKADOC SakuraScript 全コマンドとの機械的差分テスト | `SakuraScriptDocumentationCoverageTests` が対応表のインライン例（80件以上）を自動抽出し、パーサーの制御トークン到達を検証済み。UKADOC全コマンドの実行結果差分・完全性は未検証。 |
| — | （`\![cancel,http,...]` は完了 2026-07-09） | `GhostManager.swift:245`に`httpStreamingTasks`を新設し`executeHTTPStreaming`（`GhostManager+System.swift`）がURLキーでタスク追跡。`cancelHTTPStreaming(params:)`を追加し`\![cancel,http,URL]`分岐（`GhostManager.swift`の`cancel`ハンドラ）から配線。キャンセル時は`NSURLErrorCancelled`を検知して`OnExecuteHTTPFailure`を送らず静かに中断。テスト`HTTPStreamingCancelTests.swift`追加。 |
| — | （`\__q` 範囲ベース表示テキスト結合は完了 → `AUDITS_COMPLETED.md` 参照） | パーサで `\__q[ID,...]text\__q` を `.choiceQueue(title:id:references:)` にマージ。単一形式・範囲形式・script: 形式に対応。 |
| P2 | SERIKO 描画メソッド・レンダリング完全一致が未検証 | SERIKO の `surfaceID=-1/-2` 制御フレーム（自身／他アニメーション停止）、SSPのウェイト範囲（`最小-最大`）、`animation*.option,shared-index`（サーフェス切替時のpattern継続）は `SerikoExecutor` に実装し、回帰テストで確認済み。`collisionex` の rectangle/ellipse/circle/polygon/region の形状保持・当たり判定、および `animation*.collision*` の実行中限定を2026-08-14に実装・単体検証済み。残るのは `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift` の実シェル描画差分テスト。 |
| — | （lexicon 内蔵辞書は完了 2026-07-08） | `Ourin/Resources/SakuraScriptLexicon.json` を新設し `EnvironmentExpander` 初期化時に10キー（%ms/%mz/%ml/%mc/%mh/%mt/%me/%mp/%m?/%dms）を注入。回帰テスト追加。実ゴースト表示確認は未実施。 |

### D. SHIORIイベント

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| — | （WebSocket/アーカイブ系14イベントは完了 → `AUDITS_COMPLETED.md` 参照） | OnExecuteWebSocket×6, OnCompress/ExtractArchiveComplete/Failure, OnExecuteHTTPStreaming, OnMusicPlayEx, OnVideoPlayEx, OnSoundLoop を実装済み。 |

### E. プロパティシステム

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| — | （深い階層プロパティは完了 → `AUDITS_COMPLETED.md` 参照） | `seriko.cursor.*`/`tooltip.*`/`balloon.scope(ID).*` はパース済みだったが、`sakuraEngine.propertyManager` が `.shared` と別インスタンスだったためSETが反映されない配線切れが真因。修正済み。カーソル切り替え/ツールチップ表示UIも新規実装。 |

### F. YAYA言語VM

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| — | （実在YAYAゴーストの回帰テストは完了 → `AUDITS_COMPLETED.md` 参照） | `OurinTests/YayaEmily4RegressionTests.swift` 新設。SRANDスタブ修正・Emily4実辞書のフレームワーク応答・決定性・YAYA出力意味論の回帰テストを追加。 |
| — | （`ASEARCHPOS` は完了 → `AUDITS_COMPLETED.md` 参照） | `VM.cpp` に実装済み。 |

### G. プラグインシステム

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| — | SSPプラグインのバイナリ互換 | macOSではWin32 DLLを直接ロード不可。プラットフォーム差異として文書化済み（減点対象外）。対応`.plugin`/`.bundle`への移植が必要。 |
| — | （PLUGIN/2.0 通知網羅性監査は完了 → `AUDITS_COMPLETED.md` 参照） | 全17種の通知イベントに送信コード・呼び出し元とも揃っていることを確認。未使用の`onSecondChange()`公開メソッドは削除済み。 |

### H. NARパッケージ

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| — | （複合install種別は**実装済みだったことを確認** → `AUDITS_COMPLETED.md` 参照） | 2026-07-05 監査で `NarInstall/Paths.swift:219-236` に `calendar/skin`・`calendar/plugin`・`calendar` 旧互換・`language` の設置先解決が実装済みと確認（本ファイルの旧記載が誤り）。`type,saori` も同ラウンドで追加実装。 |
| — | （同時インストール `*.directory` 系の完全処理は完了 2026-07-08） | `AttachedComponent` 構造化パース＋汎用展開（balloon/headline/plugin/calendar.skin等、refresh/refreshundeletemask対応）。この検証中に `ZipUtil.secureCopyTree` の /private/var シンボリックリンク起因の相対パス計算バグ（コピー先が `private/` 配下へズレる）を発見・修正。NarInstallTests 11件全パス。 |

### I. FMO

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| — | Windows HWND 直接互換 | プラットフォーム差異として扱うべき（文書化済み）。macOS外部ツールは `EXECUTE GetFMO` またはPOSIX共有メモリを使用。 |

### J. バルーン・シェル・リソース

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| P2 | SERIKO描画メソッド・バルーン右側表示・wordwrap/alignment の細部未検証 | `collisionex` の rectangle/ellipse/circle/polygon/region の形状判定と、`animation*.collision*` の実行中限定は2026-08-14に実装・単体検証済み。残るのは実シェル/バルーンセットでの描画差分テスト。 |
| — | （`surfacetable.txt` の体系的処理とサーフィステストUIは完了 2026-08-12 → `AUDITS_COMPLETED.md` 参照） | `SurfaceTableParser.swift` で `group,NAME { scope,N .. id,NAME }` 構文・`__disabled`/`__parts` マーカー・`option,DisableNoDefineSurfaces` を解釈。`SurfaceTestWindow.swift` の `\![open,surfacetest]` は `__disabled` を除外したグループ一覧、実画像プレビュー、scope切替、クリック適用まで接続済み。`SurfaceTestCatalogTests` で画像ID・無効グループ・未列挙画像を検証。実ゴーストでの目視は未実施。 |
| — | （レガシー画像透過処理は完了 2026-07-08） | サーフェス側クロマキーは実装済みだったことを実測確認。未実装だったバルーン側の左上ピクセル透過スタブを `applyTopLeftPixelChromakey` として本実装（アルファ無し画像のみ対象）。実表示の目視確認は未実施。 |
| P3 | MAYUNA（着せ替え）の網羅性 | `bindoption*.group` の `mustselect`/`multiple` を解析・状態制約へ接続し、`OnNotifyDressupInfo` のオプション欄も実装済み（2026-08-14、単体34件）。残りは実シェルのオーバーレイ描画と実ゴーストでの差分確認。 |
| — | （動画レンダラの非対応コーデックサイレント失敗は完了 2026-07-09） | `EventID.swift`/`EventReferenceSpec.swift` に `OnVideoPlayFailure`（Reference0=filename, Reference1=reason）を新設。`playVideo`（`GhostManager+Display.swift`）は `.unsupported` 判定時に旧来の `OnVideoPlayEx`（成功通知）ではなく `OnVideoPlayFailure`（reason=`unsupported_codec`）を発火し`Log.error`に変更。ファイル未検出時も同様に`reason=file_not_found`で失敗通知。テスト`EventIDAuditTests`/`VideoRendererTests`に追加。 |
| P2 | 動画の実機再生・音声バランス・`sound,load` | `VideoPlayerWindow` に `MTAudioProcessingTap` による2ch左右ゲイン適用を実装し、`AudioBalanceGains` の境界テストを追加済み。動画の `sound,load` プリロード（`VideoPreloadPlayer` が `AVURLAsset`/`AVPlayerItem`/`AVPlayer` を保持し、play時に load/play オプションをマージして1つ消費・stop/cleanup で破棄）は実装済み。実ゴーストでの映像表示・実音声・左右バランス、対応コーデック範囲の最終確認は未実施（実機検証待ち）。 |

### K. 追加の静的コード監査（2026-08-14）

| 優先度 | 項目 | 現状・次の実装 |
|---|---|---|
| — | アンカー装飾（`anchorstyle` / `anchorvisited*`） | `BalloonView` に下線・矩形・背景・ペン色を描画し、ホバー/非選択/訪問済みを個別状態として反映。`descript.txt` の3状態設定と `anchor*fontcolor` も分離して適用済み。ROP2 の全SetROP2演算子は `AnchorRasterImageRenderer` でバルーン背景ピクセルへ合成する。残りは実ゴースト目視と実メディア環境での表示確認。 |
| — | `\\n[half]` / `%` 改行間隔 | `BalloonViewModel.lineAdvances` と再生キューに接続し、`BalloonView` の行単位レイアウトへ反映済み。明示4スイート26件で倍率・順序・クリア整合性を確認。負値はオフセットによる近似で、実ゴースト目視は未実施。 |
| — | `vanishbymyself` の消滅経路 | 確認問い合わせ、キャンセル／選択／消滅イベント、ゴミ箱移動、ランタイム解放、指定または自動の次ゴースト起動を実装済み。実ゴーストでのゴミ箱権限・復帰先選択は未実機確認。 |
| — | `updateother` の対象誤配線 | ゴースト名指定の絞り込みに加え、balloon/shell/plugin/headline/language をインストール済み descriptor の name／id から解決し、各対象ルートへ更新を適用する実装を完了。`testonly` のダウンロード・MD5検証・非置換も回帰テスト済み。実ネットワーク・実ゴーストでの更新確認は未実施。 |
| — | `\\f[cursor*]` と選択肢 hover | カーソル装飾値を実ボタンへ反映し、モーダル中の実ポインタ位置を監視して `OnChoiceEnter` の入退場と 500ms 静止後の `OnChoiceHover` を発火する。 |
| — | （`BalloonRichTextViewModel` のスタブ解消 2026-08-14） | `valign`、subscript、superscript を `NSAttributedString` の解決済み属性（縦寄せメタデータ、baselineOffset、縮小フォント）へ接続し、font fallback・style reset も実装。`OurinTests/BalloonRichTextViewModelTests.swift` の3件で確認。 |

---

## English

The following items were raised in prior audit reports and remain **unresolved** in the current source code. Priority tags (P0=highest → P3=lowest) are included.

### A. SHIORI Protocol

| Priority | Item | Current State / Fix |
|---|---|---|
| — | (SHIORI 2.x ABI compatibility layer core completed 2026-07-09) | `Ourin/USL/Shiori2CompatAdapter.swift` (455 lines, added 2026-07-08) implements `Shiori2CompatBackend`, wired into all XPC/Bundle/Dylib backend construction paths at `ShioriLoader.swift:846,853,855`. `GET Version` backend-version detection, 3.0-event → `GET Sentence SHIORI/2.2` + `Event:` + `Reference0-7` conversion, 2.x response (Sentence/BalloonOffset etc.) → 3.0 `Value:` conversion, `TEACH` → 2.4/311/312 round-trip, and Shift_JIS encoding are all implemented and covered by `OurinTests/ShioriLoaderTests.swift:54-253`. |
| — | (Word/String/Status/OwnerGhostName/OtherGhostName/Communicate conversion and the OnTalk mismatch completed 2026-07-09) | Added unit tests for all 6 builders in `Shiori2CompatAdapter.swift:339-422` (`OurinTests/ShioriLoaderTests.swift`, e.g. `shiori2WordRequestUsesReference0AsTypeWhenTypeHeaderMissing` and 5 others). Fixed `buildUserSentenceRequest`'s branch from the nonexistent `ID: OnTalk` to the real `EventID.OnTalkRequest` (`EventID.swift:361`) — now `lowerID == "ontalkrequest"`, making the path reachable. Regression test `shiori2TalkRequestMapsToUserSentenceGet` added. |
| — | (SHIORI 2.x "duplicate implementation" concern confirmed to be a false alarm 2026-07-09) | Traced `ShioriLoader.swift:842-853` (`makeBackend`): `Shiori2CompatBackend` only wraps **externally loaded SHIORI modules via XPC/Bundle/Dylib**. `init?(module:base:)` (`ShioriLoader.swift:783-811`) instantiates `YayaBackend` directly for `yaya.dll` without wrapping it in `Shiori2CompatBackend`. Meanwhile `YayaBackend.parseRequest/buildResponse` (`:413-498`) is wire parsing internal to Ourin's own bundled YAYA engine, tolerant of both 3.0-format and legacy TEACH SHIORI/2.x-format text. The two operate on disjoint backend types wired from separate call sites — not a duplicate implementation. No consolidation needed; marked resolved. |
| — | (SecurityLevel external propagation completed 2026-07-08) | External SSTP entry points consolidated into `SSTPDispatcher.dispatchExternal` using `ShioriSecurityContext.external(origin:)`; TCP/HTTP/XPC all deliver `SecurityLevel: external` to SHIORI. localOnly 420 policy preserved. Tests added. |

### B. SSTP Protocol

| Priority | Item | Current State / Fix |
|---|---|---|
| — | (210 Break nobreak queueing completed 2026-07-08; playback-state wiring completed 2026-08-12) | `SSTPBreakQueue` performs the blocking wait (default 5s timeout → 409), and `EventBridge.isAnyGhostPlaying()` now includes live ghost playback state. `SSTPDispatcherTests` covers playing wait, post-playback 200, and timeout 409. |

### C. SakuraScript

| Priority | Item | Current State / Fix |
|---|---|---|
| P2 | No machine-generated diff test vs. full UKADOC SakuraScript list | Parser/execution are broad, but fine compatibility unverified. |
| — | (`\![cancel,http,...]` completed 2026-07-09) | Added `httpStreamingTasks` (`GhostManager.swift:245`), tracked by URL key in `executeHTTPStreaming` (`GhostManager+System.swift`). New `cancelHTTPStreaming(params:)` wired from the `\![cancel,http,URL]` branch of the `cancel` command handler in `GhostManager.swift`. Detects `NSURLErrorCancelled` on cancellation to suppress the `OnExecuteHTTPFailure` notification for intentional aborts. Test `HTTPStreamingCancelTests.swift` added. |
| — | (`\__q` range-based display-text binding completed → see `AUDITS_COMPLETED.md`) | Parser merges `\__q[ID,...]text\__q` into a single `.choiceQueue(title:id:references:)` token. Supports single-form, range-form, and `script:` form. |
| P2 | SERIKO render methods and rendering perfect match unverified | SERIKO `surfaceID=-1/-2` control frames (stop the current animation / stop other running animations), SSP random pattern waits (`min-max`), and `animation*.option,shared-index` (continue the pattern across a surface switch) are implemented in `SerikoExecutor` and covered by regression tests. `collisionex` rectangle/ellipse/circle/polygon/region shape retention and hit testing, plus active-only `animation*.collision*` regions, were implemented and unit-tested on 2026-08-14. Remaining work is real-shell rendering diff testing in `Animation/SerikoParser.swift` / `Ghost/GhostManager+Animation.swift`. |
| — | (Built-in lexicon completed 2026-07-08) | New `Ourin/Resources/SakuraScriptLexicon.json` injected at `EnvironmentExpander` init for 10 keys (%ms/%mz/%ml/%mc/%mh/%mt/%me/%mp/%m?/%dms). Regression tests added. In-ghost visual check pending. |

### D. SHIORI Events

| Priority | Item | Current State / Fix |
|---|---|---|
| — | (WebSocket/archive 14 events completed → see `AUDITS_COMPLETED.md`) | OnExecuteWebSocket×6, OnCompress/ExtractArchiveComplete/Failure, OnExecuteHTTPStreaming, OnMusicPlayEx, OnVideoPlayEx, OnSoundLoop implemented. |

### E. Property System

| Priority | Item | Current State / Fix |
|---|---|---|
| — | (Deep hierarchy properties completed → see `AUDITS_COMPLETED.md`) | `seriko.cursor.*`/`tooltip.*`/`balloon.scope(ID).*` parsing was already implemented; the real root cause was `sakuraEngine.propertyManager` being a separate instance from `.shared`, so SET never propagated. Fixed. New cursor-switching/tooltip UI also implemented. |

### F. YAYA Language VM

| Priority | Item | Current State / Fix |
|---|---|---|
| — | (Real YAYA ghost regression test completed → see `AUDITS_COMPLETED.md`) | New `OurinTests/YayaEmily4RegressionTests.swift`. Fixed the SRAND stub; added framework-response, determinism, and YAYA output-semantics regression tests against real Emily4 dictionaries. |
| — | (`ASEARCHPOS` completed → see `AUDITS_COMPLETED.md`) | Implemented in `VM.cpp`. |

### G. Plugin System

| Priority | Item | Current State / Fix |
|---|---|---|
| — | SSP plugin binary compatibility | macOS cannot load Win32 DLLs. Documented as platform difference (not penalized). Porting to corresponding `.plugin`/`.bundle` required. |
| — | (PLUGIN/2.0 notification coverage audit completed → see `AUDITS_COMPLETED.md`) | Verified all 17 notification events have both send code and a call site. Removed the unused `onSecondChange()` public method. |

### H. NAR Packages

| Priority | Item | Current State / Fix |
|---|---|---|
| — | (Composite install types **confirmed already implemented** → see `AUDITS_COMPLETED.md`) | 2026-07-05 audit confirmed `NarInstall/Paths.swift:219-236` resolves `calendar/skin`, `calendar/plugin`, legacy `calendar`, and `language` (the previous claim in this file was wrong). `type,saori` was also added in the same round. |
| — | (Concurrent-install `*.directory` family completed 2026-07-08) | Structured `AttachedComponent` parsing + generic deployment (balloon/headline/plugin/calendar.skin etc., refresh/refreshundeletemask). Also found & fixed a real `ZipUtil.secureCopyTree` bug (relative-path computation broken by the /private/var symlink, contents misplacing under `private/`). All 11 NarInstallTests pass. |

### I. FMO

| Priority | Item | Current State / Fix |
|---|---|---|
| — | Windows HWND direct compatibility | Should be treated as platform difference (documented). macOS external tools use `EXECUTE GetFMO` or POSIX shared memory. |

### J. Balloons, Shells, Resources

| Priority | Item | Current State / Fix |
|---|---|---|
| P2 | SERIKO render methods, balloon right display, wordwrap/alignment fine points unverified | `collisionex` rectangle/ellipse/circle/polygon/region hit testing and active-only `animation*.collision*` regions were implemented and unit-tested as of 2026-08-14. Real shell/balloon-set rendering diff testing remains unresolved. |
| — | (`surfacetable.txt` systematic processing and surface-test UI completed 2026-08-12 → see `AUDITS_COMPLETED.md`) | `SurfaceTableParser.swift` parses `group,NAME { scope,N .. id,NAME }`, `__disabled`/`__parts`, and `option,DisableNoDefineSurfaces`. `SurfaceTestWindow.swift` wires `\![open,surfacetest]` to a `__disabled`-filtered group list with real image previews, scope switching, and click-to-apply. `SurfaceTestCatalogTests` covers image IDs, disabled groups, and unlisted images. In-ghost visual inspection remains pending. |
| — | (Legacy image transparency completed 2026-07-08) | Surface-side chroma-key was confirmed already implemented; the missing balloon-side top-left-pixel stub is now implemented as `applyTopLeftPixelChromakey` (alpha-less images only). Visual on-screen check pending. |
| P3 | MAYUNA (dressup) thoroughness | `bindoption*.group` `mustselect`/`multiple` parsing and state constraints are wired, and the `OnNotifyDressupInfo` options field is populated (2026-08-14, 34 focused tests). Remaining work is real-shell overlay rendering and in-ghost diff verification. |
| — | (Video renderer silent failure on unsupported codecs completed 2026-07-09) | Added `OnVideoPlayFailure` (Reference0=filename, Reference1=reason) to `EventID.swift`/`EventReferenceSpec.swift`. `playVideo` (`GhostManager+Display.swift`) now fires `OnVideoPlayFailure` (reason=`unsupported_codec`) instead of the success event `OnVideoPlayEx` when format is `.unsupported`, and logs via `Log.error`. Missing files now also fire `OnVideoPlayFailure` (reason=`file_not_found`). Tests added to `EventIDAuditTests`/`VideoRendererTests`. |
| P2 | Video real playback, audio balance, and `sound,load` | `VideoPlayerWindow` now applies two-channel left/right gains through `MTAudioProcessingTap`, with boundary tests for `AudioBalanceGains`. Video `sound,load` preloading (`VideoPreloadPlayer` holds `AVURLAsset`/`AVPlayerItem`/`AVPlayer`, consumes one instance at play with load/play options merged, and is discarded on stop/cleanup) is implemented. In-ghost visual/audio/balance verification and final codec-scope confirmation remain unverified (awaiting real-device playback). |

### K. Additional static code audit (2026-08-14)

| Priority | Item | Current State / Next implementation |
|---|---|---|
| — | Anchor decoration (`anchorstyle` / `anchorvisited*`) | `BalloonView` now renders underline/rectangle/background/pen colors and tracks hover, non-selected, and visited states independently. The three-state `descript.txt` settings and `anchor*fontcolor` commands are separated. All SetROP2 `anchormethod` variants are composited against balloon pixels by `AnchorRasterImageRenderer`; in-ghost visual and real-media verification remain pending. |
| — | `\\n[half]` / percentage newline spacing | Connected to `BalloonViewModel.lineAdvances` and the playback queue, then applied by the line-based `BalloonView` layout. The explicit four-suite run passed 26 tests covering mapping, ordering, and clear/truncation consistency. Negative values use an offset approximation; an in-ghost visual check is still pending. |
| — | `vanishbymyself` removal path | Confirmation, cancel/select/vanish events, recoverable Trash move, runtime release, and explicit/automatic next-ghost launch are implemented. Trash permissions and next-ghost choice remain unverified with a real installed ghost. |
| — | `updateother` target routing | In addition to filtering ghost-name selectors, balloon/shell/plugin/headline/language targets are resolved from installed descriptor name/id values and updates are applied to each target's own root. `testonly` download, MD5 verification, and non-replacement behavior are covered by regression tests. Real-network and installed-ghost verification remain pending. |
| — | `\\f[cursor*]` and choice hover | Cursor decoration values are applied to the real choice buttons. A local mouse monitor tracks the actual button under the pointer, emitting `OnChoiceEnter` on enter/exit and `OnChoiceHover` after 500 ms of stillness. |
| — | (`BalloonRichTextViewModel` stub removal completed 2026-08-14) | `valign`, subscript, and superscript now produce resolved `NSAttributedString` metadata (`OurinVerticalAlignment`, `baselineOffset`, and a scaled font); font fallback and style reset are implemented. Covered by three `BalloonRichTextViewModelTests`. |

---

### 推奨対応順序 / Recommended Action Order

| 優先度 / Priority | 項目 / Item |
|---|---|
| **P2** | SakuraScript 差分テスト / SERIKO 描画差分テスト / SHIORI 2.x 判断 |
| **P2** | 実ゴーストでのROP2アンカー／可変改行の目視検証 |
| **P2 (基盤完了)** | イベントReference表駆動化 — `EventReferenceTable` 新設・`notifyReturnIgnored` 単一ソース化済み。全発火箇所（216箇所）の表駆動移行は漸次対応。 |
| **P3** | MAYUNA網羅（実シェル描画・実ゴースト差分） |

2026-07-15 追記: P3のNative SHIORI embedded XPC実fixtureを別PIDで再試験し、`nativeDylibFixtureRunsThroughEmbeddedXpcService`を含む`ShioriLoaderTests`が成功。P3受け入れ条件は `docs/SHIORI_RUNTIME_COMPATIBILITY_MATRIX_ja-jp.md` に反映済み。

2026-07-08 完了分（詳細は `docs/STUB_COMPLETION_PLAN_ja-jp.md`）: NAR同時インストール完全処理 / lexicon内蔵 / レガシー透過処理（バルーン左上ピクセル） / SecurityLevel伝播 / 210 Breakキューイング / SAORI `.plugin` 対応 / Plugin bridge Phase 7-9（menu統合・fixture・行列テスト） / 動画レンダラ / `\j[label]` / SHIORI ResourceのSSP互換永続化 / yaya_core 4関数（FREADENCODE/FWRITEDECODE/LSO/OUTPUTNUM）。

2026-07-09 追記: 同日夜（fd0fdd8）に `Shiori2CompatAdapter.swift` が実装・配線されSHIORI 2.xのコア変換（GET Version検出／イベント／TEACH／レスポンス正規化）はテスト付きで完了していたことをukadoc突合＋実装棚卸しで確認（旧記載「方針未決」は実態と不一致だったため訂正）。ただしWord/String/Status/GhostName/Communicate変換とユーザー入力経路(`OnTalk`/`OnTalkRequest`不一致)は未検証のまま残置。同時に、動画レンダラの非対応コーデック時サイレント失敗、`\![cancel,http,...]`未実装を新規に検出しTODO化した。

2026-07-09 続報: 同日中に本ラウンドで新規TODO化した5項目すべてを実装・解消。(1) 動画レンダラの非対応コーデック/ファイル未検出時に`OnVideoPlayFailure`イベントを新設し発火（旧`OnVideoPlayEx`誤発火を修正）。(2) `\![cancel,http,URL]`を`httpStreamingTasks`追跡+`cancelHTTPStreaming`で実装。(3) Word/String/Status/OwnerGhostName/OtherGhostName/Communicate各builderに単体テスト追加。(4) `buildUserSentenceRequest`の`ID: OnTalk`判定を実在する`EventID.OnTalkRequest`に合わせ`ontalkrequest`へ修正。(5) 旧`YayaBackend`と`Shiori2CompatAdapter`の「二重実装」懸念は実測の結果、外部2.xモジュール(XPC/Bundle/Dylib)専用ラッパーと内蔵YAYAエンジン専用パーサーという disjoint な役割分担であることを確認し誤解と判明、統合不要と結論。全項目にビルド成功+テストパスを確認済み。残る未完了項目はSakuraScript全コマンド差分テスト・SERIKO描画完全一致検証・MAYUNA網羅性検証で、いずれも実シェル/実ゴーストでの目視検証が必要なため引き続き未完了。

---

*本ファイルは監査レポート（GLM/CODEX/CLAUDE/AGY）の未完項目を集約したものです。完了済み項目は `AUDITS_COMPLETED.md` を参照してください。*

*This file consolidates pending items from audit reports (GLM/CODEX/CLAUDE/AGY). For completed items, see `AUDITS_COMPLETED.md`.*
