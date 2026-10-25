# Ourin 監査項目 — 未完 / Audit Items — TODO

**最終更新 / Last Updated**: 2026-10-25（実装・GitHub issue照合 / implementation and GitHub issue reconciliation）
**集約元 / Consolidated from**: AUDIT_GLM / AUDIT_CODEX / AUDIT_CODEX_2026-06-27 / AUDIT_CLAUDE / AUDIT_AGY ＋ ドキュメント整合性監査 2026-08-15
**確認対象 / Scope**: `codex/ourin-pr-integration` @ `77500e31655a3b920c036e56fe7653050f3c0265` ＋未コミット統合変更。Claude PR 33件と今回の委譲成果を含む。 / The dedicated integration worktree includes 33 Claude PRs and subsequent delegated changes.
**検証方法 / Verification**: 実装・GitHub issueを照合し、ビルド・アプリ単体テスト・実エンジン/XPC・複製した実ゴーストを検証。最新の件数と制約は[引継ぎ記録](PR_TAKEOVER_2026-10-25.md)と[実ゴースト記録](REAL_GHOST_VERIFICATION_2026-10-25.md)を参照。過去のPASSは当時の結果。 / Source and live issues were reconciled; builds, unit tests, native engines/XPC and copied real ghosts were exercised. See the linked reports for current results and limitations.
**一覧 / Index**: [GitHub open 60件の全件照合](TODO_ISSUE_STATUS.md) / [完了記録](AUDITS_COMPLETED.md)。

> **一新について (2026-08-15)**: 本ファイルに「完了」注記付きで蓄積していた項目は `AUDITS_COMPLETED.md`（「移管記録」セクション）へ移管し、本ファイルは**真に未完の項目のみ**とした。旧記載・経緯は git 履歴（2026-08-15 以前）に保存されている。
> Renewal note: items previously kept here with "completed" annotations were migrated to `AUDITS_COMPLETED.md` ("migrated items" section); this file now lists only genuinely pending work. Prior wording is preserved in git history.

---

## 日本語

### 0. 今回の整理（2026-10-25追記、10/24監査）

- **更新**: Claude PR 33件をローカル統合済み。#131〜#194の対象項目は[全件表](TODO_ISSUE_STATUS.md)へ反映。公開・master反映とは区別する。下記12/45/3件は10/24の元ブランチ監査時点の集計。

- GitHub open 60件のうち **12件は現ブランチで実装・回帰テスト定義あり**。#106 / #107 / #108 / #110 / #112 / #115 / #116 / #117 / #119 / #120 / #123 / #132 を実装TODOから除外し、完了記録へ移した。issue自体はopenのままで、close/mergeは行っていない。
- **45件は残件・追跡、3件（#114 / #122 / #124）は対象外・保留**。[全件表](TODO_ISSUE_STATUS.md)に各番号・現在のコード・残件を記載。
- 旧 `AUDIT-TEST-BASELINE-001` は10月の修正と全体PASS記録に基づき完了記録へ移管。PR #125に残る単発heap corruptionは別件として下記5節へ残した。
- 「全コマンド実装済み」を現行UKADOCとの完全互換とは解釈しない。#131〜#154のイベント/内蔵SAORI、#163以降の多言語・Taromati2互換など、ローカル統合後にも残る互換性差は全件表で追跡する。
- #118のopen/close誤配線と#109のwire/Reference割当はローカル修正済み。FINEのSSP優先ghost fallbackは未対応。#121は手動.ssg入出力のみ完了で自動同期が残る。
- 10/25の追加実装・優先順・担当モデルは[委譲記録](DELEGATION_2026-10-25.md)。#95/#96/#97/#99/#104の文書・設定整備と、実機/remote CI/正式配布の未検証を区別する。

### 1. 実ゴースト・実機検証待ち（コード実装・単体テストは完了済み）

以下の既存監査範囲には実装とテストが存在するが、**実ゴースト／実シェル／実機での動作・目視確認**は未完。下表の2026-08-15の記録は履歴であり、今回の検証結果ではない。新規に報告された欠落や不具合は[issue全件表](TODO_ISSUE_STATUS.md)で別途追跡する。

後続改善として、SERIKO上下鏡映修正 `823c2bf`、選択肢のバルーン内表示 `7e82b7c`、位置・重なり修正 `00bebfe` / `bca164e`、OnIdle Reference `0a2a37d` は現ブランチに存在する。これらは全項目の目視完了を意味しない。

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
| — | SSP プラグインの Win32 DLL バイナリ互換 | PE形式のWindows DLLは直接ロード不可。`3bcf86b`でDLL名からmacOS native `.dylib` / `.plugin` / `.bundle`等への解決と共通ABIを追加済み（`UkagakaModuleABI`、`DLLCompatibilityTests`）。Windowsバイナリ実行とは区別する。 |
| — | Windows HWND 直接互換 | プラットフォーム差異として文書化済み。外部ツールは `EXECUTE GetFMO` または POSIX 共有メモリを使用。 |
| — | #114 / #122 / #124 | mcp.exeは伺か互換の対象外。IP Messenger/MsgSender連携とWindows FineFMOは保留。通常POSIX FMOの実装済み状態とは別。 |

### 3. 漸次対応

| 優先度 | 項目 | 現状 |
|---|---|---|
| P2（基盤完了） | イベント Reference 仕様の表駆動化 | 基盤・入力/ポインタ/選択・locale/displayは完了（`AUDITS_COMPLETED.md` S〜V節）。`OSUpdateObserver` と `SystemNotificationData` 等には手動Reference生成が残るため漸次移行を続ける。 |

### 4. ドキュメント（2026-08-15 整合性監査の残件）

| 優先度 | 項目 | 現状 |
|---|---|---|
| P3 | `docs/` の翻訳待ちプレースホルダー解消 | 2026-10-24に実ファイルのTranslation Pending/翻訳待ちを再確認し、英訳16＋和訳4＝20ペアが残存。#87はclosedだが翻訳完了の根拠にはしない。`TRANSLATION_MANIFEST.md`に従って消化する。 |

※ 2026-08-15 のドキュメント整合性監査で検出した他の項目（アーカイブ移動・README同期・ブロッカー矛盾解消・memories修正・時点注記・行番号注記）は同日中に対応済み → `AUDITS_COMPLETED.md` 移管記録参照。

### 5. 安定性の残件（2026-10-24）

| 優先度 / Priority | Issue | 状態 / Status |
|---|---|---|
| P2 | **AUDIT-TEST-HEAP-001**: テストホストの単発heap corruption | [PR #125](https://github.com/eightman999/Ourin/pull/125) に一度の `malloc: Heap corruption detected` abortを記録。10/25に`66749e3`の競合修正と関連root変更が統合済みと確認。元統合1465 PASS記録あり。今回の最終統合は1509ケースPASS、heap破損の再発なし。再発時に原因調査を再開する。旧BASELINEの並列未完走記載は完了記録へ移管した。 |
| P2 | 現ブランチ/作業ツリーのリリース検証 | 過去PRのPASSを現在の `3bcf86b`＋未コミット変更の結果とは扱わない。#96/#102に沿って現版の全体テスト・実機E2Eを確認する。今回の統合実装は全体テストを再実行。実機E2E・正式配布判定は別途残る。 |

---

## English

### 0. Reconciliation on 2026-10-24, updated October 25

- **Update:** 33 Claude PRs have been integrated locally; the issue matrix is updated. The 12/45/3 counts below are the original October 24 branch snapshot, not the integration totals.

- Of 60 open GitHub issues, **12 have implementation and regression test definitions in this branch**: #106 / #107 / #108 / #110 / #112 / #115 / #116 / #117 / #119 / #120 / #123 / #132. They were moved out of implementation TODOs into the completed record. Their GitHub state remains open; no close or merge was performed.
- **45 remain pending or tracking, and 3 (#114 / #122 / #124) are deferred or out of scope**. See the [complete issue mapping](TODO_ISSUE_STATUS.md).
- Historical `AUDIT-TEST-BASELINE-001` was moved to the completed record based on October fixes and full-suite PASS reports. The intermittent heap corruption mentioned in PR #125 remains a separate item in section 5.
- Historical command coverage does not establish full compatibility with the current UKADOC. New event/internal-SAORI issues #131–#154 and multilingual/Taromati2 issues from #163 onward remain tracked in the issue mapping.
- #118 `scriptbox` is incorrectly routed from the close branch to opening an input window. #109 FINE needs wire/Reference verification. #121 has manual .ssg import/export, with automatic cloud sync still pending.

### 1. Awaiting real-ghost / real-device verification (code + unit tests done)

Implementation and tests exist for the historical audit scope below; **real-ghost / shell / hardware verification** remains pending. The August records below are historical, not new results. Newly reported gaps are tracked separately in the [issue mapping](TODO_ISSUE_STATUS.md).

Subsequent improvements present in this branch include SERIKO orientation `823c2bf`, in-balloon choices `7e82b7c`, placement/overlap `00bebfe` / `bca164e`, and OnIdle references `0a2a37d`. These do not establish complete visual verification.

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
| — | SSP plugin Win32 DLL binary compatibility | PE binaries cannot load directly. `3bcf86b` adds DLL-name resolution to native `.dylib` / `.plugin` / `.bundle` etc. and a common ABI (`UkagakaModuleABI`, `DLLCompatibilityTests`). This does not execute Windows binaries. |
| — | Windows HWND direct compatibility | Documented platform difference. External tools use `EXECUTE GetFMO` or POSIX shared memory. |
| — | #114 / #122 / #124 | mcp.exe is outside Ukagaka compatibility. IP Messenger/MsgSender and Windows FineFMO remain deferred, distinct from implemented POSIX FMO. |

### 3. Incremental migration

| Priority | Item | Current State |
|---|---|---|
| P2 (foundation done) | Table-driven event Reference specs | Foundation, input/pointer/selection, locale and display migrations are complete (completed record sections S–V). Manual Reference construction remains in `OSUpdateObserver`, `SystemNotificationData` and other sites. |

### 4. Documentation (remainder of the 2026-08-15 consistency audit)

| Priority | Item | Current State |
|---|---|---|
| P3 | Resolve translation placeholders in `docs/` | Actual placeholder markers rechecked on 2026-10-24: 16 EN + 4 JA = 20 pairs remain. Closed issue #87 is not evidence of translation completion. Follow `TRANSLATION_MANIFEST.md`. |

All other findings of the 2026-08-15 documentation consistency audit (archive moves, README sync, blocker-contradiction fixes, memories fixes, snapshot notes, line-number caveat) were addressed the same day → see the migrated-items section in `AUDITS_COMPLETED.md`.

### 5. Remaining stability work (2026-10-24)

| Priority | Issue | Status |
|---|---|---|
| P2 | **AUDIT-TEST-HEAP-001**: intermittent test-host heap corruption | [PR #125](https://github.com/eightman999/Ourin/pull/125) records one `malloc: Heap corruption detected` abort. Fix `66749e3` and the related working-tree changes are included in the October 25 integration. The earlier integration recorded 1465 passing tests. The final integration passed 1509 executions without recurrence. Reopen investigation if it recurs. Historical BASELINE completion is recorded separately. |
| P2 | Current branch/working-tree release validation | Historical PR PASS reports do not validate `3bcf86b` plus current uncommitted edits. Run full-suite and real-device E2E checks under #96/#102 before release. This update only reconciles documentation. |

---

### 推奨対応順序 / Recommended Action Order

| 優先度 / Priority | 項目 / Item |
|---|---|
| **先行 / First** | [issue全件表](TODO_ISSUE_STATUS.md)の導入・会話blocker、#181増分build、#118誤配線、#109 wire互換を解消 / resolve installation/conversation, build and routing gaps |
| **P2** | 実ゴースト検証パス一式（SakuraScript → SERIKO/バルーン → 動画・イベント）と統合安定性検証 / real-ghost checks and integration stability |
| **P2 (基盤完了)** | イベント Reference 表駆動化の漸次移行 |
| **P3** | MAYUNA 実シェル確認・翻訳プレースホルダー消化 |

---

*本ファイルは監査レポート（GLM/CODEX/CLAUDE/AGY）の未完項目を集約したものです。完了済み項目は `AUDITS_COMPLETED.md` を参照してください。*

*This file consolidates pending items from audit reports (GLM/CODEX/CLAUDE/AGY). For completed items, see `AUDITS_COMPLETED.md`.*
