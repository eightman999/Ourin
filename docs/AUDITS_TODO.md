# Ourin 監査項目 — 未完 / Audit Items — TODO

**最終更新 / Last Updated**: 2026-08-15（一新 / renewed）
**集約元 / Consolidated from**: AUDIT_GLM / AUDIT_CODEX / AUDIT_CODEX_2026-06-27 / AUDIT_CLAUDE / AUDIT_AGY ＋ ドキュメント整合性監査 2026-08-15
**検証方法 / Verification**: 全項目を現状ソースコードと照合して未完判定。完了済み項目は `AUDITS_COMPLETED.md` 参照。

> **一新について (2026-08-15)**: 本ファイルに「完了」注記付きで蓄積していた項目は `AUDITS_COMPLETED.md`（「移管記録」セクション）へ移管し、本ファイルは**真に未完の項目のみ**とした。旧記載・経緯は git 履歴（2026-08-15 以前）に保存されている。
> Renewal note: items previously kept here with "completed" annotations were migrated to `AUDITS_COMPLETED.md` ("migrated items" section); this file now lists only genuinely pending work. Prior wording is preserved in git history.

---

## 日本語

### 1. 実ゴースト・実機検証待ち（コード実装・単体テストは完了済み）

いずれも実装とテストは存在し、残作業は**実ゴースト／実シェル／実機での動作・目視確認**。確認して問題があれば個別のバグとして切り出す。

| 優先度 | 項目 | 検証内容 |
|---|---|---|
| P2 | SakuraScript UKADOC 全コマンド実行差分 | パース網羅・ディスパッチ差分は `SakuraScriptDocumentationCoverageTests`（326タグ）で機械検証済み。2026-08-15 の権限付き `xcodebuild` で、構文トークン・GhostManager配送・複合サブコマンド配送の3テストメソッドが `** TEST SUCCEEDED **`（0 failed）となった。2026-08-15 に DevTools の実行経路から稼働中の `Emily/Phase4.5` へ安全な scope/surface/format/wait/設定/lock/resetballoonpos 群を投入し、対象解決とトークン列を確認した。`notify/raise` と `q` も投入し、選択肢ダイアログの表示・選択後の実行結果を確認したが、イベント側の応答ログは取得できなかった。**各コマンドの実行副作用・実ゴースト画面差分（更新・消滅・外部通信を含む）は未検証**。 |
| P2 | SERIKO 描画完全一致 | `surfaceID=-1/-2`・ウェイト範囲・`shared-index`・`collisionex` 各形状は単体検証済み。2026-08-15 に最新ビルドで `emily4` を実起動し、画面キャプチャ上は正立・全体表示・顔パーツ単独浮遊なしを確認した。関連スイートは 33 passed だが、実コマンドでの `surfaceID=-1/-2` 等の差分確認は未完。**テスト終了時のQoS warning issueは修正済み（完了根拠は `AUDITS_COMPLETED.md` のN節）**。 |
| P2 | バルーン描画の細部 | ROP2 アンカー装飾・可変改行（`\n[half]`・負値はオフセット近似）・バルーン右側表示・wordwrap/alignment の**実ゴースト目視**。 |
| P2 | 動画・音声の実機確認 | `MTAudioProcessingTap` 左右バランス・`sound,load` プリロードは実装済み。**実機での映像表示・実音声・対応コーデック範囲**の最終確認待ち。 |
| P2 | `vanishbymyself` / `updateother` の実環境確認 | 消滅経路・更新対象解決は実装＋回帰テスト済み。**ゴミ箱権限・復帰先選択・実ネットワーク更新**が未確認。 |
| P2 | SHIORI イベントの実機発火確認 | 静的抽出での型付きID・Reference定義漏れは0件。**動的ID・OS実機発火（電源/ディスプレイ/セッション等）・Reference値の実ゴースト検証**が未完。 |
| P3 | MAYUNA（着せ替え）網羅 | `bindoption*.group` 制約・`OnNotifyDressupInfo` は実装済み（単体34件）。**実シェルのオーバーレイ描画・実ゴースト差分**が未確認。 |
| P3 | lexicon・サーフェステストUI等の表示確認 | `SakuraScriptLexicon.json` 展開・`\![open,surfacetest]` は実装済み。**実ゴーストでの表示目視**が未実施。 |

### 2. プラットフォーム差異（文書化済み・対応は保留）

| 優先度 | 項目 | 現状 |
|---|---|---|
| — | SSP プラグインの Win32 DLL バイナリ互換 | macOS では直接ロード不可。文書化済み。対応 `.plugin`/`.bundle` への移植が必要になった時点で個別対応。 |
| — | Windows HWND 直接互換 | プラットフォーム差異として文書化済み。外部ツールは `EXECUTE GetFMO` または POSIX 共有メモリを使用。 |

### 3. 漸次対応

| 優先度 | 項目 | 現状 |
|---|---|---|
| P2（基盤完了） | イベント Reference 仕様の表駆動化 | `EventReferenceTable` 新設・`notifyReturnIgnored` 単一ソース化済み。`OnLanguageChange` は **AUDIT-REF-LOCALE-001**、`OnDisplayChange` / `OnDisplayChangeEx` は **AUDIT-REF-DISPLAY-001** として表駆動移行済み。**残る発火箇所の表駆動移行**は漸次対応。 |

### 4. ドキュメント（2026-08-15 整合性監査の残件）

| 優先度 | 項目 | 現状 |
|---|---|---|
| P3 | `docs/` の翻訳待ちプレースホルダー解消 | `TRANSLATION_MANIFEST.md` 基準で20ペア未訳（`YAYA_CORE_ARCHITECTURE`／`EXECUTIVE_SUMMARY`／`TECHNICAL_SPEC` 等）。bilingual-doc ワークフローで消化する。 |

※ 2026-08-15 のドキュメント整合性監査で検出した他の項目（アーカイブ移動・README同期・ブロッカー矛盾解消・memories修正・時点注記・行番号注記）は同日中に対応済み → `AUDITS_COMPLETED.md` 移管記録参照。

### 5. 監査で追加したissue / Audit-added issues (2026-08-15)

| 優先度 / Priority | Issue | 状態 / Status |
|---|---|---|
| P2 | **AUDIT-TEST-BASELINE-001**: `OurinTests` 全体実行で並列時に失敗 | **未解決**。実在Emily4辞書を使う `YayaEmily4RegressionTests`、`EventBridge.shared` を使う `DressupBindTests`、埋め込みXPC fixtureを使う `ShioriLoaderTests` を `.serialized` 化し、`SurfaceOverlayOrderingTests` のTimer待機をMain RunLoop駆動へ変更した。さらに `GhostUtilityCommandTests` は標準NOTIFYの正当な他ゴースト配送を除外して、raise/notify自身の誤配送だけを検証するよう修正した。Xcodeプロジェクトの `OurinTests` / `OurinUITests` の依存target参照（`remoteInfo` / `TEST_TARGET_NAME`）も現行target名 `Ourin` に修正し、`-showBuildSettings` で解決を確認した。修正後の隔離DerivedDataによる直列全体実行は **OurinTests 1087 passed / 0 failed（99 suites）＋UI tests 6 passed / 0 failed**。一方、同環境の全体並列はsuite列挙後にテストworkerが終了してOurinプロセスだけが残る状態を再現し、2分超で対象PIDを停止したため集計不能。最後に集計できた修正前の並列全体実行は **1093 passed / 5 failed / 0 skipped / 1098 total**、`GhostUtilityCommandTests`＋`SoundPlayerTests` の並列subsetは **74 passed / 0 failed**。並列実行の完走は未確定のまま扱う。 |

---

## English

### 1. Awaiting real-ghost / real-device verification (code + unit tests done)

Implementation and tests exist for all of these; the remaining work is **verification on real ghosts / shells / hardware**. File individual bugs if verification fails.

| Priority | Item | What to verify |
|---|---|---|
| P2 | SakuraScript UKADOC full-command runtime diff | Parse coverage & dispatch diff machine-verified by `SakuraScriptDocumentationCoverageTests` (326 tags). A privileged `xcodebuild` run on 2026-08-15 passed all three test methods (`** TEST SUCCEEDED **`, 0 failed) covering syntax tokens, GhostManager dispatch, and compound subcommand dispatch. On 2026-08-15, the DevTools execution path delivered a safe scope/surface/format/wait/settings/lock/resetballoonpos matrix to the live `Emily/Phase4.5`; target resolution and the token sequence were confirmed. `notify/raise` and `q` were also delivered; the choice dialog appeared and the post-selection execution result was observed, but no event-side response log was captured. **Per-command side effects and real-ghost screen diffs (including update, vanish, and external I/O) remain unverified**. |
| P2 | SERIKO rendering parity | `surfaceID=-1/-2`, wait ranges, `shared-index`, `collisionex` shapes unit-tested. On 2026-08-15, the latest build launched `emily4`; the screen capture showed an upright complete character with no detached face part. The related suite passed 33 tests, but direct command-level diffs such as `surfaceID=-1/-2` remain pending. **The test-cleanup QoS warning issue is resolved; evidence is in section N of `AUDITS_COMPLETED.md`.** |
| P2 | Balloon rendering fine points | Visual check of ROP2 anchor decoration, variable newlines (`\n[half]`, negative values approximated by offsets), right-side balloons, wordwrap/alignment on real ghosts. |
| P2 | Video/audio on real hardware | `MTAudioProcessingTap` L/R balance and `sound,load` preloading implemented. **Real playback, actual audio, codec-scope confirmation** pending. |
| P2 | `vanishbymyself` / `updateother` in real environments | Paths implemented with regression tests. **Trash permissions, next-ghost choice, real-network updates** unverified. |
| P2 | SHIORI event firing on real hardware | Static extraction shows zero missing typed IDs / Reference specs. **Dynamic IDs, OS-device firing (power/display/session), real-ghost Reference values** pending. |
| P3 | MAYUNA (dressup) thoroughness | Constraints and `OnNotifyDressupInfo` implemented (34 unit tests). **Real-shell overlay rendering and in-ghost diffs** unverified. |
| P3 | Lexicon / surface-test UI visual checks | `SakuraScriptLexicon.json` expansion and `\![open,surfacetest]` implemented; **in-ghost visual inspection** pending. |

### 2. Platform differences (documented; action deferred)

| Priority | Item | Current State |
|---|---|---|
| — | SSP plugin Win32 DLL binary compatibility | Cannot load Win32 DLLs on macOS; documented. Port to `.plugin`/`.bundle` case-by-case when needed. |
| — | Windows HWND direct compatibility | Documented platform difference. External tools use `EXECUTE GetFMO` or POSIX shared memory. |

### 3. Incremental migration

| Priority | Item | Current State |
|---|---|---|
| P2 (foundation done) | Table-driven event Reference specs | `EventReferenceTable` and single-sourced `notifyReturnIgnored` are in place. `OnLanguageChange` was migrated under **AUDIT-REF-LOCALE-001**; `OnDisplayChange` / `OnDisplayChangeEx` under **AUDIT-REF-DISPLAY-001**. **Remaining emission sites** proceed incrementally. |

### 4. Documentation (remainder of the 2026-08-15 consistency audit)

| Priority | Item | Current State |
|---|---|---|
| P3 | Resolve translation placeholders in `docs/` | 20 untranslated pairs per `TRANSLATION_MANIFEST.md` (`YAYA_CORE_ARCHITECTURE` / `EXECUTIVE_SUMMARY` / `TECHNICAL_SPEC` etc.). Process via the bilingual-doc workflow. |

All other findings of the 2026-08-15 documentation consistency audit (archive moves, README sync, blocker-contradiction fixes, memories fixes, snapshot notes, line-number caveat) were addressed the same day → see the migrated-items section in `AUDITS_COMPLETED.md`.

### 5. Audit-added issues (2026-08-15)

| Priority | Issue | Status |
|---|---|---|
| P2 | **AUDIT-TEST-BASELINE-001**: parallel `OurinTests` execution still has failures | **Unresolved**. The real-Emily4-dictionary `YayaEmily4RegressionTests`, `EventBridge.shared`-using `DressupBindTests`, and embedded-XPC-fixture `ShioriLoaderTests` suites are now `.serialized`; `SurfaceOverlayOrderingTests` drives the main RunLoop while waiting for Timer frames. `GhostUtilityCommandTests` now ignores legitimate broadcast NOTIFYs from other ghosts and checks only for misrouted raise/notify IDs. The Xcode project’s `OurinTests` / `OurinUITests` dependency references (`remoteInfo` / `TEST_TARGET_NAME`) were also corrected to the current `Ourin` target, confirmed by `-showBuildSettings`. After the fix, an isolated DerivedData serial run passed **1087 `OurinTests` cases / 0 failures (99 suites) plus 6 UI tests / 0 failures**. The same isolated full-parallel run still reproduced the worker-exit/parentless-Ourin condition after suite enumeration and was stopped after more than two minutes, so it produced no aggregate. The last aggregatable parallel full run before this project-reference fix was **1093 passed / 5 failed / 0 skipped / 1098 total** (the overlay Timer race is resolved); the parallel `GhostUtilityCommandTests` + `SoundPlayerTests` subset passed **74/74**. Parallel completion remains unconfirmed. |

---

### 推奨対応順序 / Recommended Action Order

| 優先度 / Priority | 項目 / Item |
|---|---|
| **P2** | 実ゴースト検証パス一式（SakuraScript 実行差分 → SERIKO/バルーン目視 → 動画・イベント実機） |
| **P2 (基盤完了)** | イベント Reference 表駆動化の漸次移行 |
| **P3** | MAYUNA 実シェル確認・翻訳プレースホルダー消化 |

---

*本ファイルは監査レポート（GLM/CODEX/CLAUDE/AGY）の未完項目を集約したものです。完了済み項目は `AUDITS_COMPLETED.md` を参照してください。*

*This file consolidates pending items from audit reports (GLM/CODEX/CLAUDE/AGY). For completed items, see `AUDITS_COMPLETED.md`.*
