# Implementation Status Summary / 実装状況サマリー

**Last Updated**: 2026-06-27
**Status**: Active Compatibility Hardening Phase
**目的**: Single source of truth for current implementation status / 現在の実装状況の単一の情報源

> 2026-06-27 の互換性監査で、従来の「Complete / 100%」表記は SSP/UKADOC 互換性の意味では過大であることを確認した。
> 機能実装の有無と、既存ゴースト資産に対する仕様互換性は分けて扱う。
> 詳細は [AUDIT_CODEX_2026-06-27.md](AUDIT_CODEX_2026-06-27.md) を参照。

---

# Current Status Matrix / 現在のステータス行列

| Component / コンポーネント | Files / ファイル | Implemented / 実装済み | Integrated / 統合済み | Tested / テスト済み | Blockers / ブロッカー | Progress / 進捗 |
|---------------------------|------------------|------------------------|----------------------|-------------------|---------------------|------------------|
| **SAORI** | 4 files | 🟡 Mostly implemented / 概ね実装 | ✅ Integrated / 統合済み | 🟡 Smoke tested / スモーク中心 | Real ghost matrix pending / 実ゴースト網羅未完 | 80% |
| **SSTP** | multiple files | 🟡 Partial compatible / 部分互換 | ✅ Integrated / 統合済み | 🟡 Targeted tests / 対象テスト | TCP bind/body, ReferenceN response | 60% |
| **SERIKO** | multiple files | 🟡 Partial compatible / 部分互換 | 🟡 Integrated / 統合中 | 🟡 Targeted tests / 対象テスト | Rendering fidelity and remaining SERIKO edge cases | 68% |
| **SakuraScript** | multiple files | 🟡 Broad partial / 広範な部分実装 | ✅ Runtime connected / 実行系接続済み | 🟡 Targeted tests / 対象テスト | Full UKADOC diff pending / 全差分未完 | 60% |
| **YAYA Core** | yaya_core | 🟡 Partial compatible / 部分互換 | ✅ Integrated / 統合済み | 🟡 Baseline tests / 基準テスト | by-ref, standalone when, stubs | 60% |
| **FMO** | FMO/ | 🟡 Semantic compatible / 意味互換 | ✅ Integrated / 統合済み | ✅ Targeted tests / 対象テスト済み | Windows FileMapping/HWND direct compatibility is platform-different / 直接互換はプラットフォーム差異 | 65% |
| **Plugin** | PluginHost/ | 🟡 Partial compatible / 部分互換 | ✅ Integrated / 統合済み | ✅ Targeted tests / 対象テスト済み | Windows DLL binary execution requires porting / DLL実行は移植が必要 | 60% |

**Overall Compatibility Progress**: 60% / 全体互換進捗: 60%

---

# Weekly Update Tracking / 週次更新トラッキング

## Week 2026-03-08 to 2026-03-14 / 2026年3月8日〜14日

### Completed / 完了したタスク
- ✅ Code review of all 9 implementation files
- ✅ Identified integration gaps and blockers
- ✅ Updated documentation structure

### In Progress / 進行中のタスク
- 🔄 Creating new documentation (status summary, roadmap, blocker tracker)
- 🔄 Updating implementation plans

### Blocked / ブロックされているタスク
- ❌ SSTP SHIORI bridge (blocked by ID-003)

## Week 2026-03-15 to 2026-03-21 / 2026年3月15日〜21日

### Completed / 完了したタスク
- ✅ BridgeToSHIORI core path implemented
- ✅ SERIKO callback integration wired in GhostManager
- ✅ `\![anim,*]` command execution path connected and validated with targeted tests

---

# Integration Dependencies / 統合依存関係

```
SAORI Integration (Completed)
  ↓ Enables / 有効化
SSTP Integration (ID-003)
  ↓ Enables / 有効化
SERIKO Integration (ID-004, ID-005)
  ↓ Enhances / 拡張
SakuraScript Execution (ID-006, ID-007)
  ↓ Enables / 有効化
End-to-End Ghost Testing / エンドツーエンドゴーストテスト
```

**Critical Path**:
1. SSTP BridgeToSHIORI must be functional (external communication)
2. SERIKO executor integration (animation support)
3. SakuraScript command execution (full ghost functionality)

---

# Blocker List / ブロッカー一覧

## Active Blockers / アクティブなブロッカー

- SHIORI bridge method propagation: `BridgeToSHIORI` still emits `GET SHIORI/3.0` for all native-host requests.
- SSTP response mapping: SHIORI `Reference1+` headers are not preserved in SSTP responses.
- SSTP listener binding/body handling: TCP/HTTP `host` is not used for bind, and raw TCP passes only header text.
- SakuraScript/SERIKO fidelity: some scope/display semantics and rendering edge cases still differ from SSP.
- YAYA fidelity: by-reference semantics, standalone `when`, and several builtins remain partial/stub.
- NAR install: `refreshundeletemask` separator and compound install types are not fully UKADOC-compatible.
- Property aliases: `sakura.*`, `kero.*`, `ghost.*`, and `shell.*` compatibility namespaces are incomplete.

## Resolved Blockers / 解決されたブロッカー

- ✅ ID-001 (SAORI Not Connected to YAYA Core)
- ✅ ID-002 (SaoriManager Exists but Not Used)
- ✅ ID-003 (BridgeToSHIORI E2E validation completed)
- ✅ ID-004 (SERIKO Executor Not Integrated)
- ✅ ID-005 (SERIKO Dressup Build Failures)
- ✅ ID-006 (SakuraScript Animation Commands Stubbed)
- ✅ ID-007 (SakuraScript Text Formatting Not Executed)
- ✅ FMO macOS compatibility boundary documented and structured view added
- ✅ Plugin Windows DLL metadata-only constraint documented and compatibility view added

---

# Component Status Details / コンポーネント詳細ステータス

## SAORI / SAORIシステム

### Implemented Features / 実装済み機能
- ✅ SaoriLoader.swift: macOS native .dylib loading with dlopen/dlsym
- ✅ SaoriProtocol.swift: SAORI/1.0 request/response parser
- ✅ SaoriRegistry.swift: Module discovery and caching
- ✅ SaoriManager.swift: Unified API for plugin operations

### Integration Gaps / 統合のギャップ
- ✅ VM.cpp LOADLIB/UNLOADLIB/REQUESTLIB integrated
- ✅ YayaCore.cpp pluginOperation() integrated with plugin host_op routing
- ✅ YayaAdapter.swift SAORI operation bridge integrated
- ⚠️ Broader end-to-end ghost matrix validation is still in progress

### Required Integration Work / 必要な統合作業
1. Expand end-to-end tests across real ghost scripts
2. Add additional negative-path coverage for malformed SAORI responses

### Test Coverage / テストカバレッジ
- 📄 Test files exist (SaoriProtocolTests.swift, SaoriRegistryTests.swift)
- ❌ Test implementations are stubs/minimal

---

## SSTP / SSTPシステム

### Implemented Features / 実装済み機能
- ✅ SSTPDispatcher.swift: Parses all SSTP methods (SEND, NOTIFY, COMMUNICATE, EXECUTE, GIVE, INSTALL)
- ✅ SSTPResponse.swift: Wire format generation with all status codes
- ✅ Header mapping and event resolution

### Integration Gaps / 統合のギャップ
- ✅ BridgeToSHIORI core handler path is implemented
- ✅ Dispatcher method mapping includes SEND/NOTIFY/COMMUNICATE/EXECUTE/GIVE/INSTALL
- ✅ External router tests validated with serial execution mode

### Required Integration Work / 必要な統合作業
1. Pass the actual SHIORI method (`GET` vs `NOTIFY`) through `BridgeToSHIORI` / `ShioriHost`.
2. Preserve SHIORI response `Reference1+` headers when mapping back to SSTP.
3. Bind TCP/HTTP listeners according to configured host and forward raw TCP body data where applicable.
4. Expand compatibility tests with external SSTP clients and SSP-like response expectations.

### Test Coverage / テストカバレッジ
- 📄 Test files exist (SSTPDispatcherTests.swift, SSTPResponseTests.swift)
- ✅ Route/method tests expanded and passing
- ✅ ExternalServerTests passed for SSTP router flows (including EXECUTE/GIVE/INSTALL)
- ⚠️ Full SSP/client interoperability matrix is still pending

---

## SERIKO / SERIKOシステム

### Implemented Features / 実装済み機能
- ✅ SerikoParser.swift: Complete SERIKO/2.0 parser
  - All interval types (always, sometimes, rarely, random, runonce, yen-e, talk, bind, never)
  - All method types (overlay, overlayfast, base, move, isReducing, replace, start, alternativestart, stop, asis)
  - Pattern parsing and surface definitions
- ✅ SerikoExecutor.swift: Animation execution engine
  - Animation state management
  - All execute methods (overlay, base, move, reduce, replace, start, stop, etc.)
  - Pause/resume/offset capabilities
  - Callback system

### Integration Gaps / 統合のギャップ
- ✅ SerikoExecutor callbacks connected to GhostManager handlers
- ✅ Script animation commands route into animation handlers/executor path
- ⚠️ Dressup functionality has build failures (deferred)

### Required Integration Work / 必要な統合作業
1. Wire SerikoExecutor to GhostManager callbacks
2. Implement SakuraScriptEngine \![anim,...] commands to call executor
3. Test animation playback from SakuraScript
4. (Optional) Fix dressup build failures (lower priority)

### Test Coverage / テストカバレッジ
- 📄 Test files exist (SerikoParserTests.swift, SerikoExecutorTests.swift)
- ✅ SerikoExecutorTests passing in targeted runs

---

## SakuraScript / SakuraScriptエンジン

### Implemented Features / 実装済み機能
- ✅ SakuraScriptEngine.swift: Comprehensive token parsing
  - All major command types (scopes, surfaces, animations, balloons, newlines, waits, choices, anchors, tags)
  - Escape sequence handling
  - Argument parsing
  - 34 commands fully implemented (see TODO/todo.md)
- ✅ Runtime execution path is handled in `GhostManager` (`sakuraEngine(_:didEmit:)` and command handlers)
  - Note: command *parsing* is in `SakuraScriptEngine`, while command *execution* is primarily in `GhostManager*` files.

### Integration Gaps / 統合のギャップ
- ✅ Animation commands (\![anim,clear|pause|resume|offset|add|stop]) execute through GhostManager handlers
- ✅ Text formatting commands (\f[...]) execute via balloon style state and rendering
- ✅ Dialog commands implemented (inputbox/password/date/time/slider/ip/choice/teach/communicate/system)
- ✅ Ghost/shell/balloon switching implemented
- ⚠️ Some advanced options remain partially implemented (move/moveasync flags, extended set,* variants)

### Required Integration Work / 必要な統合作業
1. Refine advanced movement/resize options (move/moveasync base/offset edge-cases)
2. Expand timed variants for set,* where applicable and add more wait coverage
3. Fix any remaining minor command semantic differences (e.g. legacy edge-cases)
4. Target: 90%+ command execution rate

### Test Coverage / テストカバレッジ
- 📄 Test files exist (SakuraScriptEngineTests.swift)
- ✅ Targeted animation command tests passing
- ✅ Build/test validation after formatting execution updates
- ⚠️ Some unrelated SakuraScript tests remain unstable in this environment

---

# Success Criteria / 成功基準

## Integration Completion / 統合完了基準

A component is considered "Integrated" when:
- All stub implementations are replaced with real functionality
- End-to-end data flow works from entry point to execution
- Integration tests pass
- No blockers remain for that component

### SAORI Integration Complete
- [x] LOADLIB successfully loads .dylib module
- [x] REQUESTLIB successfully sends request and gets response
- [x] UNLOADLIB successfully unloads module
- [x] Integration smoke tests pass
- [x] No SAORI blockers remain

### SSTP Integration Functional
- [x] External app can send SSTP request
- [x] Request reaches SHIORI system
- [x] SHIORI processes request and generates response
- [x] Response returned to external app
- [x] Integration tests pass (targeted e2e/route coverage)
- [x] No wiring blockers remain
- [ ] Compatibility blockers from the 2026-06-27 audit are resolved

### SERIKO Integration Complete
- [x] SakuraScript animation commands execute animations
- [x] Pause/resume/offset work as expected
- [x] Critical SERIKO blockers resolved (ID-004, ID-006)
- [ ] Animations play correctly on screen (broader e2e matrix pending)
- [ ] Integration tests pass (full suite stability pending)

### SakuraScript Execution Complete
- [ ] 90%+ of commands execute correctly
- [ ] Text formatting works
- [ ] Dialogs work
- [ ] Ghost/shell/balloon switching works
- [ ] Integration tests pass
- [ ] No SakuraScript blockers remain

---

# Related Documents / 関連ドキュメント

- **INTEGRATION_ROADMAP.md**: Detailed integration plan with prerequisites
- **BLOCKER_TRACKER.md**: Detailed blocker information with workarounds
- **AUDIT_CODEX_2026-06-27.md**: Current SSP/UKADOC compatibility audit
- **COPILOT_AUTO_PROMPT.md**: Task structure for integration work
- **Component Implementation Docs**: SAORI_IMPLEMENTATION.md, SERIKO_IMPLEMENTATION.md, SSTP_DISPATCHER_GUIDE.md
- **yaya_core/IMPLEMENTATION_STATUS.md**: YAYA Core specific status

---

# Change Log / 変更ログ

## 2026-03-15
- Created document / ドキュメント作成
- Initial status matrix populated / 初期ステータス行列作成
- Added weekly tracking structure / 週次トラッキング構造追加
- Mapped integration dependencies / 統合依存関係マッピング
- Added blocker references / ブロッカー参照追加

## 2026-06-27
- Reclassified status from implementation-complete to compatibility-hardening.
- Added Codex compatibility audit reference and active blockers from UKADOC/SSP-oriented review.
- Downgraded YAYA Core from "100%" to partial compatibility to match `yaya_core/IMPLEMENTATION_STATUS.md`.
- Marked `surfaces*.txt` all-file loading as resolved after adding SSP filename-order loading.
- Documented FMO/Plugin macOS-only constraints and added structured compatibility views for FMO snapshots and plugin metadata.

---

**Maintainer**: Development Team  
**Update Frequency**: Weekly / 更新頻度: 週次  
**Version**: 1.0
