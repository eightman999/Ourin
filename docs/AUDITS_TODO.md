# Ourin 監査項目 — 未完 / Audit Items — TODO

**最終更新 / Last Updated**: 2026-07-05
**集約元 / Consolidated from**: AUDIT_GLM / AUDIT_CODEX / AUDIT_CODEX_2026-06-27 / AUDIT_CLAUDE / AUDIT_AGY（各 ja-jp / en-us）
**検証方法 / Verification**: 全項目を現状ソースコード（file:line）と照合して未完判定。完了済み項目は `AUDITS_COMPLETED.md` 参照。

---

## 日本語

以下は過去の監査レポートで指摘され、**現状コードで未解決**であることを確認した項目です。優先度（P0=最高 → P3=最低）を併記します。

### A. SHIORI プロトコル

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| P2 | **SHIORI 2.x ABI 互換レイヤーが実質不存在** | フォールバックは `GET SHIORI/2.6` 1行目＋3.0形式ヘッダを送るのみ。真の2.x（`GET Sentence`/`GET Word`/`Event:` ヘッダ）と通信できない。→ 2.x対応を正式実装するか、「3.0専用」と明記してフォールバックを削除。 |
| P3 | SecurityLevel が `EventBridge` 経由で常に `local` 固定 | SSTP外部由来イベントを `\![raiseother]` 等で中継した場合に `external` が伝播しない（`EventBridge.swift:286,306,328`）。 |

### B. SSTP プロトコル

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| P3 | 210 Break の `nobreak` 指定時「キューイングして完了を待つ」が簡略化 | OnSSTPBreak通知のみ。 |

### C. SakuraScript

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| P2 | UKADOC SakuraScript 全コマンドとの機械的差分テスト未生成 | パーサ・実行とも広いが、細部互換の完全性は未検証。 |
| — | （`\__q` 範囲ベース表示テキスト結合は完了 → `AUDITS_COMPLETED.md` 参照） | パーサで `\__q[ID,...]text\__q` を `.choiceQueue(title:id:references:)` にマージ。単一形式・範囲形式・script: 形式に対応。 |
| P2 | SERIKO 描画メソッド・collisionex・レンダリング完全一致が未検証 | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift`。実シェルでの描画差分テストが必要。 |
| P3 | 単語系 `%ms` 等の語彙（lexicon）がデフォルト空 | SSPはベースウェア内蔵辞書を持つが、Ourinは常に空文字列。 |

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
| — | （実在YAYAゴーストの回帰テストは完了 → `AUDITS_COMPLETED.md` 参照） | `OurinTests/YayaEmily4RegressionTests.swift` 新設。SRANDスタブ修正・Emily4実辞書のゴールデン/決定性テスト追加。 |
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
| P2 | 同時インストールの `*.directory`, `*.source.directory`, `*.refresh`, `*.refreshundeletemask` の完全処理 | 複合NAR・更新NARでの追加バルーン/カレンダー/言語パック挙動がSSPとずれる可能性。 |

### I. FMO

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| — | Windows HWND 直接互換 | プラットフォーム差異として扱うべき（文書化済み）。macOS外部ツールは `EXECUTE GetFMO` またはPOSIX共有メモリを使用。 |

### J. バルーン・シェル・リソース

| 優先度 | 項目 | 現状・修正案 |
|---|---|---|
| P2 | SERIKO描画メソッド・collisionex・バルーン右側表示・wordwrap/alignment の細部未検証 | 実シェル/バルーンセットでのレンダリング差分テストが必要。 |
| — | （`surfacetable.txt` の体系的処理は完了 → `AUDITS_COMPLETED.md` 参照） | `SurfaceTableParser.swift` 新設。`group,NAME { scope,N .. id,NAME }` 構文・`__disabled`/`__parts` マーカー・`option,DisableNoDefineSurfaces` を解釈。`loadImage` で未定義サーフェス描画スキップを適用。※サーフィステストダイアログ UI（`\![open,surfacetest]`）は別課題。 |
| P3 | レガシー画像透過処理（クロマキー・左上ピクセル透過色） | アルファチャンネル無しの古いゴーストで表示崩れの可能性。 |
| P3 | MAYUNA（着せ替え）の網羅性 | `\![bind,...]` 連携は `GhostManager+Dressup.swift` に存在するが、完全性は未検証。 |

---

## English

The following items were raised in prior audit reports and remain **unresolved** in the current source code. Priority tags (P0=highest → P3=lowest) are included.

### A. SHIORI Protocol

| Priority | Item | Current State / Fix |
|---|---|---|
| P2 | **SHIORI 2.x ABI compatibility layer effectively absent** | Fallback only sends `GET SHIORI/2.6` line 1 + 3.0-format header. Cannot communicate with true 2.x (`GET Sentence`/`GET Word`/`Event:` headers). → Either implement real 2.x support or explicitly mark "3.0-only" and remove fallback. |
| P3 | SecurityLevel hardcoded to `local` via `EventBridge` | External flag not propagated for SSTP-sourced events relayed via `\![raiseother]` (`EventBridge.swift:286,306,328`). |

### B. SSTP Protocol

| Priority | Item | Current State / Fix |
|---|---|---|
| P3 | 210 Break `nobreak` "queue and await completion" simplified | OnSSTPBreak notification only. |

### C. SakuraScript

| Priority | Item | Current State / Fix |
|---|---|---|
| P2 | No machine-generated diff test vs. full UKADOC SakuraScript list | Parser/execution are broad, but fine compatibility unverified. |
| — | (`\__q` range-based display-text binding completed → see `AUDITS_COMPLETED.md`) | Parser merges `\__q[ID,...]text\__q` into a single `.choiceQueue(title:id:references:)` token. Supports single-form, range-form, and `script:` form. |
| P2 | SERIKO render methods, collisionex, rendering perfect match unverified | `Animation/SerikoParser.swift`, `Ghost/GhostManager+Animation.swift`. Needs rendering diff tests with real shells. |
| P3 | Word-based `%ms` etc. lexicon defaults to empty | SSP has built-in baseware dictionary; Ourin always returns empty string. |

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
| — | (Real YAYA ghost regression test completed → see `AUDITS_COMPLETED.md`) | New `OurinTests/YayaEmily4RegressionTests.swift`. Fixed the SRAND stub; added golden/determinism tests against real Emily4 dictionaries. |
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
| P2 | Incomplete concurrent-install processing (`*.directory`, `*.source.directory`, `*.refresh`, `*.refreshundeletemask`) | Composite/update NAR behavior for bundled balloon/calendar/language pack may diverge from SSP. |

### I. FMO

| Priority | Item | Current State / Fix |
|---|---|---|
| — | Windows HWND direct compatibility | Should be treated as platform difference (documented). macOS external tools use `EXECUTE GetFMO` or POSIX shared memory. |

### J. Balloons, Shells, Resources

| Priority | Item | Current State / Fix |
|---|---|---|
| P2 | SERIKO render methods, collisionex, balloon right display, wordwrap/alignment fine points unverified | Needs rendering diff tests with real shell/balloon sets. |
| — | (`surfacetable.txt` systematic processing completed → see `AUDITS_COMPLETED.md`) | New `SurfaceTableParser.swift`. Parses `group,NAME { scope,N .. id,NAME }` syntax, `__disabled`/`__parts` markers, and `option,DisableNoDefineSurfaces`. `loadImage` now skips undefined surfaces. ※Surface-test dialog UI (`\![open,surfacetest]`) remains a separate task. |
| P3 | Legacy image transparency (chroma-key, top-left pixel transparency color) | Display corruption risk for old ghosts without alpha channel. |
| P3 | MAYUNA (dressup) thoroughness | `\![bind,...]` integration exists in `GhostManager+Dressup.swift` but completeness unverified. |

---

### 推奨対応順序 / Recommended Action Order

| 優先度 / Priority | 項目 / Item |
|---|---|
| **P2** | SakuraScript 差分テスト / SERIKO 描画差分テスト / NAR 同時インストール完全処理 / SHIORI 2.x 判断 |
| **P2 (基盤完了)** | イベントReference表駆動化 — `EventReferenceTable` 新設・`notifyReturnIgnored` 単一ソース化済み。全発火箇所（216箇所）の表駆動移行は漸次対応。 |
| **P3** | SHIORI 2.x 互換の正実装or削除 / lexicon内蔵 / レガシー透過処理 / SecurityLevel伝播 / 210 Breakキューイング / MAYUNA網羅 |

---

*本ファイルは監査レポート（GLM/CODEX/CLAUDE/AGY）の未完項目を集約したものです。完了済み項目は `AUDITS_COMPLETED.md` を参照してください。*

*This file consolidates pending items from audit reports (GLM/CODEX/CLAUDE/AGY). For completed items, see `AUDITS_COMPLETED.md`.*
