# Copilot Autonomous Integration Prompt / Copilot自律的統合プロンプト

You are an AI assistant implementing the Ourin project. Follow the procedures below to autonomously progress through integration tasks from selecting tasks to completion.

あなたはOurinプロジェクトを実装するAIアシスタントです。以下の手順に従って、タスク選択から完了まで自律的に統合タスクを進めてください。

---

## Project Overview / プロジェクト概要

**Project Name**: Ourin (桜鈴) - macOS native ukagaka baseware / macOSネイティブukagakaベースウェア  
**Current Status**: Implementation complete, integration required / 実装完了、統合が必要  
**Goal**: Make existing stub implementations functional through integration / 既存のスタブ実装を統合により機能させる  
**Approach**: Integration over new features / 新機能より統合を優先  

**Major Systems**:
1. **SAORI**: Files complete, not integrated with YAYA Core
2. **SSTP**: Files complete, SHIORI bridge mocked
3. **SERIKO**: Parser complete, executor not integrated
4. **SakuraScript**: Parsing complete, execution incomplete

---

## Task List / タスクリスト

Execute tasks sequentially. Mark completed tasks with [完了] / [Done].

以下のタスクを順に実行してください。完了したタスクには[完了]をマークしてください。

### Phase 1: Make SAORI Functional / SAORI機能化

#### Task 1.1: Implement VM.cpp Plugin Operations / VM.cppプラグイン操作実装
- [ ] Replace stub LOADLIB implementation in VM.cpp
- [ ] Replace stub UNLOADLIB implementation in VM.cpp
- [ ] Replace stub REQUESTLIB implementation in VM.cpp
- [ ] Add sendToHost() function to emit JSON "host_op"
- [ ] Test with YayaAdapter mock
- [ ] Verify JSON format is correct

#### Task 1.2: Implement YayaCore.cpp pluginOperation() / YayaCore.cpp pluginOperation()実装
- [ ] Add handlePluginOperation() method to YayaCore
- [ ] Parse "host_op" JSON in pluginOperation()
- [ ] Route to saori_load/saori_unload/saori_request handlers
- [ ] Return response to VM
- [ ] Test with mock requests
- [ ] Verify error handling

#### Task 1.3: Implement YayaAdapter.handleSaoriRequest() / YayaAdapter.handleSaoriRequest()実装
- [ ] Add handlePluginOperation() method to YayaAdapter
- [ ] Implement handleSaoriRequest() to delegate to SaoriManager
- [ ] Wire up saori_load → SaoriManager.loadModule()
- [ ] Wire up saori_unload → SaoriManager.unloadModule()
- [ ] Wire up saori_request → SaoriManager.request()
- [ ] Add error handling for all operations
- [ ] Test with SaoriManager mock
- [ ] Verify async/await correctness

#### Task 1.4: Create Sample SAORI Module for Testing / テスト用サンプルSAORIモジュール作成
- [ ] Create Samples/SimpleSaori/SimpleSaori.swift
- [ ] Implement @cdecl("request") function
- [ ] Implement @cdecl("load") function
- [ ] Implement @cdecl("unload") function
- [ ] Compile to .dylib
- [ ] Create test ghost with LOADLIB call
- [ ] Test load/unload/request cycle
- [ ] Verify error handling

#### Task 1.5: SAORI Integration Testing / SAORI統合テスト
- [ ] Load sample .dylib from YAYA script
- [ ] Send request and verify response
- [ ] Unload module and verify cleanup
- [ ] Test error cases (invalid module, invalid request)
- [ ] Test multiple concurrent SAORI modules
- [ ] Update IMPLEMENTATION_STATUS_SUMMARY.md
- [ ] Mark ID-001 and ID-002 as resolved in BLOCKER_TRACKER.md

### Phase 2: Complete SSTP Integration / SSTP統合完成

#### Task 2.1: Implement Real BridgeToSHIORI / 実際のBridgeToSHIORI実装
- [ ] Create or update BridgeToSHIORI.swift
- [ ] Add ShioriHost dependency
- [ ] Implement handle() method to call ShioriHost
- [ ] Convert SSTP method → SHIORI event mapping
- [ ] Build SHIORI request with headers and references
- [ ] Convert SHIORI response → SSTP response format
- [ ] Add error handling
- [ ] Test with mock ShioriHost

#### Task 2.2: Connect SSTPDispatcher to Real Bridge / SSTPDispatcherを実際のブリッジに接続
- [ ] Update SSTPDispatcher initialization
- [ ] Pass real BridgeToSHIORI instance
- [ ] Remove mock/stub BridgeToSHIORI imports
- [ ] Update routeToShiori() to use real bridge
- [ ] Test with mock SHIORI response
- [ ] Verify all SSTP methods route correctly

#### Task 2.3: End-to-End SSTP Testing / エンドツーエンドSSTPテスト
- [ ] Create external SSTP test client
- [ ] Test SSTP SEND method
- [ ] Test SSTP NOTIFY method
- [ ] Test SSTP COMMUNICATE method
- [ ] Test SSTP EXECUTE method
- [ ] Test SSTP GIVE method
- [ ] Test SSTP INSTALL method
- [ ] Verify SHIORI events fire correctly
- [ ] Verify SHIORI responses converted correctly
- [ ] Test error cases (invalid requests)
- [ ] Update IMPLEMENTATION_STATUS_SUMMARY.md
- [ ] Mark ID-003 as resolved in BLOCKER_TRACKER.md

### Phase 3: Integrate SERIKO Executor / SERIKOエグゼキューター統合

#### Task 3.1: Wire SerikoExecutor to GhostManager / SerikoExecutorをGhostManagerに接続
- [ ] In GhostManager+Animation.swift, wire up callbacks:
  - [ ] serikoExecutor.onMethodInvoked → handleSerikoMethod()
  - [ ] serikoExecutor.onPatternExecuted → handleSerikoPattern()
  - [ ] serikoExecutor.onAnimationFinished → handleAnimationFinished()
- [ ] Implement handleSerikoMethod() to route to specific handlers:
  - [ ] overlay → handleSurfaceOverlay()
  - [ ] overlayfast → handleSurfaceOverlayFast()
  - [ ] base → handleAnimAddBase()
  - [ ] move → handleAnimAddMove()
  - [ ] reduce → handleSurfaceReduce()
  - [ ] replace → handleSurfaceOverlay(..., replace: true)
  - [ ] start → serikoExecutor.executeAnimation()
  - [ ] stop → serikoExecutor.stopAnimation()
- [ ] Implement handleSerikoPattern() to update surface
- [ ] Implement handleAnimationFinished() to notify interested parties
- [ ] Test with mock animation definitions
- [ ] Verify callbacks fire in correct order

#### Task 3.2: Implement SakuraScript Animation Commands / SakuraScriptアニメーションコマンド実装
- [ ] In SakuraScriptEngine.swift, replace stub handleAnimCommand():
  - [ ] handleAnimClear() → serikoExecutor.stopAnimation() or stopAllAnimations()
  - [ ] handleAnimPause() → serikoExecutor.pauseAnimation()
  - [ ] handleAnimResume() → serikoExecutor.resumeAnimation()
  - [ ] handleAnimOffset() → serikoExecutor.offsetAnimation()
  - [ ] handleAnimAdd() → parse and add pattern to animation
  - [ ] handleAnimStop() → serikoExecutor.stopAnimation()
- [ ] Implement handleWaitForAnimation():
  - [ ] Register callback for animation completion
  - [ ] Pause script execution
  - [ ] Resume when callback fires
- [ ] Inject SerikoExecutor into SakuraScriptEngine
- [ ] Test with mock animations
- [ ] Verify all commands execute correctly
- [ ] Test wait command completion

#### Task 3.3: Test Animation Playback / アニメーション再生テスト
- [ ] Load ghost with simple overlay animation
- [ ] Trigger animation via SakuraScript \![anim,add,...]
- [ ] Verify animation plays on screen
- [ ] Test animation pause/resume
- [ ] Test animation offset
- [ ] Test animation stop
- [ ] Test multiple concurrent animations
- [ ] Test animation completion callbacks
- [ ] Test with real ghost (Emily4 if available)
- [ ] Update IMPLEMENTATION_STATUS_SUMMARY.md
- [ ] Mark ID-004 and ID-006 as resolved in BLOCKER_TRACKER.md

### Phase 4: Complete SakuraScript Execution / SakuraScript実行完成

#### Task 4.1: Implement Text Formatting Execution / テキストフォーマット実行
- [ ] Add formatting state tracking to SakuraScriptEngine:
  - [ ] currentFont
  - [ ] currentFontSize
  - [ ] isBold
  - [ ] isItalic
  - [ ] currentColor
- [ ] Implement handleTextFormatting():
  - [ ] font → set currentFont
  - [ ] size → set currentFontSize
  - [ ] bold → toggle isBold
  - [ ] italic → toggle isItalic
  - [ ] color → set currentColor (parse RGB or named)
  - [ ] Other formatting tags as needed
- [ ] Apply formatting to text rendering:
  - [ ] Pass formatting state to renderer
  - [ ] Update renderer to use formatting
  - [ ] Handle nested formatting (push/pop stack)
- [ ] Test all formatting tags
- [ ] Test nested formatting
- [ ] Test color changes

#### Task 4.2: Implement Ghost/Shell/Balloon Switching / ゴースト/シェル/バルーン切り替え実装
- [ ] Implement handleSurfaceCommand() in SakuraScriptEngine:
  - [ ] Parse surface ID
  - [ ] Call GhostManager.switchSurface(to:)
- [ ] Implement handleScopeCommand() in SakuraScriptEngine:
  - [ ] Parse scope ID (\0, \1, \2...)
  - [ ] Update currentScope
- [ ] Implement GhostManager.switchSurface(to:) async:
  - [ ] Update currentSurfaceId
  - [ ] Load surface images
  - [ ] Update display
  - [ ] Trigger SERIKO animations for new surface
- [ ] Implement GhostManager.switchShell(to:) async:
  - [ ] Load new shell
  - [ ] Update surface definitions
  - [ ] Reload animations
- [ ] Implement GhostManager.switchBalloon(to:) async:
  - [ ] Load new balloon
  - [ ] Update text rendering
- [ ] Test surface switching
- [ ] Test scope switching
- [ ] Test shell/balloon switching

#### Task 4.3: Implement Dialog Commands / ダイアログコマンド実装
- [ ] Implement handleDialogCommand() in SakuraScriptEngine:
  - [ ] inputbox → handleInputBox()
  - [ ] openfile → handleOpenFileDialog()
  - [ ] savefile → handleSaveFileDialog()
  - [ ] date → handleDatePicker()
  - [ ] Other dialog types as needed
- [ ] Implement handleInputBox():
  - [ ] Show NSAlert with NSTextField
  - [ ] Return user input
  - [ ] Handle cancel
- [ ] Implement handleOpenFileDialog():
  - [ ] Show NSOpenPanel
  - [ ] Return selected file path
  - [ ] Handle cancel
- [ ] Implement handleSaveFileDialog():
  - [ ] Show NSSavePanel
  - [ ] Return selected file path
  - [ ] Handle cancel
- [ ] Implement handleDatePicker():
  - [ ] Show date picker dialog
  - [ ] Return selected date
  - [ ] Handle cancel
- [ ] Store dialog result for script access
- [ ] Test all dialog types
- [ ] Test cancel operations
- [ ] Test result retrieval

#### Task 4.4: Fix Incorrect Command Semantics / 不正なコマンドセマンティクス修正
- [ ] Implement handleMenuCommand() for \6:
  - [ ] Parse menu text
  - [ ] Add to menuItems array
- [ ] Implement handleChoiceCommand() for \7:
  - [ ] Parse menu index
  - [ ] Execute choice by index
  - [ ] Trigger OnChoiceSelect event
- [ ] Implement handleSeparatorCommand() for \-:
  - [ ] No-op (comment/separator)
- [ ] Test menu functionality
- [ ] Test choice execution
- [ ] Test separators

#### Task 4.5: SakuraScript Integration Testing / SakuraScript統合テスト
- [ ] Test all implemented commands
- [ ] Verify 90%+ command execution rate
- [ ] Test with real ghost (Emily4)
- [ ] Test command error handling
- [ ] Update TODO/todo.md with new status
- [ ] Update SUPPORTED_SAKURA_SCRIPT.md
- [ ] Update IMPLEMENTATION_STATUS_SUMMARY.md
- [ ] Mark ID-007 as resolved in BLOCKER_TRACKER.md

### Phase 5: Integration Testing & Documentation / 統合テストと文書化

#### Task 5.1: End-to-End Ghost Testing / エンドツーエンドゴーストテスト
- [ ] Test Emily4 ghost:
  - [ ] Load successfully
  - [ ] Boot sequence works
  - [ ] OnBoot event fires correctly
  - [ ] Initial surface displays
  - [ ] Basic interaction works
  - [ ] Click events work
  - [ ] Menu choices work
  - [ ] SAORI usage (if Emily4 uses it)
  - [ ] Animation playback works
- [ ] Test simple test ghost:
  - [ ] Minimal functionality
  - [ ] Easy to debug
- [ ] Test commercial ghost (if available):
  - [ ] Real-world usage
  - [ ] Edge cases
- [ ] Document any incompatibilities

#### Task 5.2: Performance Profiling / パフォーマンスプロファイリング
- [ ] Measure ghost load time (target: < 2s)
- [ ] Measure script execution time (target: < 100ms)
- [ ] Measure SSTP response time (target: < 200ms)
- [ ] Measure animation frame rate (target: 60fps)
- [ ] Measure memory usage (target: < 200MB)
- [ ] Use Instruments for profiling
- [ ] Identify bottlenecks
- [ ] Optimize if necessary

#### Task 5.3: Update Documentation / ドキュメント更新
- [ ] Update IMPLEMENTATION_STATUS_SUMMARY.md:
  - [ ] All components marked 100% integrated
  - [ ] All blockers resolved
- [ ] Update SAORI_IMPLEMENTATION.md:
  - [ ] Mark as integrated
  - [ ] Add "Integration Complete" section
- [ ] Update SERIKO_IMPLEMENTATION.md:
  - [ ] Mark as integrated
  - [ ] Add note about ID-005 (dressup) deferred
  - [ ] Add "Integration Complete" section
- [ ] Update SSTP_DISPATCHER_GUIDE.md:
  - [ ] Mark as integrated
  - [ ] Add "Integration Complete" section
- [ ] Update SUPPORTED_SAKURA_SCRIPT.md:
  - [ ] Update implementation status
  - [ ] Mark 90%+ as executed
- [ ] Create MIGRATION_GUIDE.md:
  - [ ] For existing Windows ghosts
  - [ ] Document any incompatibilities
  - [ ] Provide workarounds
- [ ] Update CLAUDE.md:
  - [ ] Reflect new integration status
  - [ ] Update build/test instructions if needed

#### Task 5.4: Final Verification / 最終検証
- [ ] Verify all integration tests pass
- [ ] Verify performance targets met
- [ ] Verify all blockers resolved
- [ ] Verify documentation complete
- [ ] Verify production-ready state
- [ ] Create release notes
- [ ] Prepare for beta release

---

## Execution Procedures / 実行手順

### Task Selection / タスク選択

Select next uncompleted task based on:
- Previous task completed
- Dependencies satisfied
- Priority (Critical > High > Medium)

未完了のタスクを以下の基準で選択：
- 前のタスクが完了
- 依存関係が満たされている
- 優先度（Critical > High > Medium）

Next task to execute: [Task name] / 次に実行するタスク: [タスク名]

Proceed with implementation? (Y/n) / 実装を続行しますか？(Y/n)

---

### Pre-Implementation Checklist / 実装前チェックリスト

Before starting implementation, verify:

実装を開始する前に確認：

1. **File Review / ファイル確認**
   - [ ] Read current file contents
   - [ ] Understand existing structure
   - [ ] Identify what needs to change

2. **Similar Implementation Check / 類似実装確認**
   - [ ] Search for similar patterns in codebase
   - [ ] Reference existing implementations
   - [ ] Follow existing conventions

3. **Specification Check / 仕様確認**
   - [ ] Read relevant specification documents
   - [ ] Understand requirements
   - [ ] Identify edge cases

4. **Dependency Check / 依存関係確認**
   - [ ] Verify all prerequisite tasks completed
   - [ ] Check for blocking issues
   - [ ] Review BLOCKER_TRACKER.md if needed

All checks completed? / すべての確認完了？(Y/n)

---

### Implementation / 実装

Task: [Task name] / タスク: [タスク名]  
Files to modify: [List of files] / 変更するファイル: [ファイル一覧]

Implementation steps:
1. Read target files
2. Make required changes
3. Build project
4. Run tests
5. Verify functionality

実装手順：
1. 対象ファイルを読み込む
2. 必要な変更を行う
3. プロジェクトをビルド
4. テストを実行
5. 機能を検証

Start implementation? (Y/n) / 実装を開始しますか？(Y/n)

---

### Post-Implementation Verification / 実装後検証

Task completed. Verify:

タスク完了。確認：

1. **Build Verification / ビルド確認**
   - Build command: `xcodebuild -project Ourin.xcodeproj -scheme Ourin build`
   - Build successful? / ビルド成功？(Y/n)

2. **Code Review / コードレビュー**
   - [ ] Implementation correct? / 実装正しい？(Y/n)
   - [ ] Follows conventions? / 規約に従っている？(Y/n)
   - [ ] Error handling adequate? / エラーハンドリング適切？(Y/n)
   - [ ] Room for improvement? / 改善の余地は？(Y/n)

3. **Test Plan / テスト計画**
   - Required tests: [List of tests] / 必要なテスト: [テスト一覧]
   - Run tests? / テストを実行しますか？(Y/n)

4. **Documentation Update / ドキュメント更新**
   - [ ] Update BLOCKER_TRACKER.md if blocker resolved
   - [ ] Update IMPLEMENTATION_STATUS_SUMMARY.md
   - [ ] Update component docs if needed

All verifications passed? / すべての検証合格？(Y/n)

---

### Test Execution / テスト実行

Task: [Task name] / タスク: [タスク名]  
Test items: [List] / テスト項目: [一覧]

Test procedure:
1. Unit tests (if applicable)
2. Integration tests
3. Manual testing

テスト手順：
1. ユニットテスト（該当する場合）
2. 統合テスト
3. 手動テスト

Test results:
- Unit tests: [Pass/Fail] / ユニットテスト: [合格/不合格]
- Integration tests: [Pass/Fail] / 統合テスト: [合格/不合格]
- Manual tests: [Pass/Fail] / 手動テスト: [合格/不合格]

All tests passed? / すべてのテスト合格？(Y/n)

---

### Error Handling / エラー対処

Error occurred. / エラーが発生しました。

Error information:
- Task: [Task name] / タスク: [タスク名]
- Type: [Compile error / Runtime error / Test failure] / 種類: [コンパイルエラー/ランタイムエラー/テスト失敗]
- Message: [Error message] / メッセージ: [エラーメッセージ]
- Location: [File:line] / 場所: [ファイル:行]

Analysis:
1. Identify root cause / 原因特定: [Cause]
2. Determine impact scope / 影響範囲判定: [Scope]

Resolution options:
1. [Option 1] / 選択肢1
2. [Option 2] / 選択肢2
3. [Option 3] / 選択肢3

Select resolution: [1/2/3] / 解決策を選択: [1/2/3]

Implement resolution? (Y/n) / 解決策を実装しますか？(Y/n)

---

### Progress Update / 進捗更新

Current progress: / 現在の進捗

**Phase 1 (SAORI Integration)**: [Completed tasks] / [Total tasks]  
**Phase 2 (SSTP Integration)**: [Completed tasks] / [Total tasks]  
**Phase 3 (SERIKO Integration)**: [Completed tasks] / [Total tasks]  
**Phase 4 (SakuraScript Completion)**: [Completed tasks] / [Total tasks]  
**Phase 5 (Testing & Documentation)**: [Completed tasks] / [Total tasks]

**Overall Progress**: [Completed tasks] / [Total tasks] ([percentage]%) / 全体進捗

Recently completed: / 最近完了したタスク：
- [Task name] ([Completion time])

Currently executing: / 現在実行中：
- [Task name] ([Start time])

Next task: / 次のタスク：
- [Task name] ([Estimated])

Any blockers? Report to BLOCKER_TRACKER.md / ブロッカーありますか？BLOCKER_TRACKER.mdに報告

---

### Phase Completion Verification / フェーズ完了確認

Phase: [Phase name] / フェーズ: [フェーズ名]  
Completion time: [Time] / 完了時刻: [時刻]

Phase completion checklist: / フェーズ完了チェックリスト
- [ ] All tasks completed / すべてのタスク完了
- [ ] Build successful / ビルド成功
- [ ] Unit tests pass / ユニットテスト合格
- [ ] Integration tests pass / 統合テスト合格
- [ ] No blockers remain / ブロッカーなし
- [ ] Documentation updated / ドキュメント更新

Quality evaluation: / 品質評価
- Code quality: [Good/Fair/Needs Improvement] / コード品質: [良/可/要改善]
- Test coverage: [%] / テストカバレッジ: [%]
- Performance: [Good/Fair/Needs Improvement] / パフォーマンス: [良/可/要改善]

Proceed to next phase? (Y/n) / 次のフェーズに進みますか？(Y/n)

---

### Project Completion / プロジェクト完了

Completion time: [Time] / 完了時刻: [時刻]  
Total time: [Duration] / 総所要時間: [時間]

**Phase 1 (SAORI Integration)**: ✅ Complete / 完了  
**Phase 2 (SSTP Integration)**: ✅ Complete / 完了  
**Phase 3 (SERIKO Integration)**: ✅ Complete / 完了  
**Phase 4 (SakuraScript Completion)**: ✅ Complete / 完了  
**Phase 5 (Testing & Documentation)**: ✅ Complete / 完了

Quality metrics: / 品質指標
- Unit test coverage: [%] / ユニットテストカバレッジ: [%]
- Integration test pass rate: [%] / 統合テスト合格率: [%]
- Memory leaks: None / メモリリーク: なし
- Crash bugs: None / クラッシュバグ: なし
- Ghost compatibility: [%] / ゴースト互換性: [%]

Deliverables: / 成果物
- Implementation files: [List] / 実装ファイル: [一覧]
- Test code: [List] / テストコード: [一覧]
- Documentation: [List] / ドキュメント: [一覧]
- Sample modules: [List] / サンプルモジュール: [一覧]

Issues and improvements: / 課題と改善点
1. [Issue 1] / [課題1]
2. [Issue 2] / [課題2]

Future plans: / 今後の予定
1. [Plan 1] / [予定1]
2. [Plan 2] / [予定2]

Project complete! / プロジェクト完了！

---

## Important Rules / 重要なルール

1. **Test after each task** - Never skip testing / 各タスク後にテスト - テストをスキップしない
2. **Handle errors properly** - Use error handling procedures for issues / エラーを適切に処理 - 問題にはエラー処理手順を使用
3. **Update progress regularly** - Keep IMPLEMENTATION_STATUS_SUMMARY.md current / 定期的に進捗を更新 - IMPLEMENTATION_STATUS_SUMMARY.mdを最新に保つ
4. **Check blockers first** - Review BLOCKER_TRACKER.md before starting tasks / 最初にブロッカーを確認 - タスク開始前にBLOCKER_TRACKER.mdを確認
5. **Prioritize integration** - Focus on making stubs functional over new features / 統合を優先 - 新機能よりスタブを機能させることに集中
6. **Ask if unsure** - Pause and confirm when uncertain / 不明な点は確認 - 不確かな時は停止して確認

---

## Success Criteria / 成功基準

### Integration Completion / 統合完了
- [ ] All components integrated (100%) / すべてのコンポーネント統合済み(100%)
- [ ] All critical blockers resolved / すべての重要ブロッカー解決済み
- [ ] All integration tests pass / すべての統合テスト合格
- [ ] Emily4 ghost works / Emily4ゴースト動作

### Functional Metrics / 機能指標
- [ ] SAORI modules load and execute / SAORIモジュールロード・実行
- [ ] SSTP external communication works / SSTP外部通信動作
- [ ] SERIKO animations play / SERIKOアニメーション再生
- [ ] SakuraScript commands execute (90%+) / SakuraScriptコマンド実行(90%+)

### Quality Metrics / 品質指標
- [ ] Unit test coverage 80%+ / ユニットテストカバレッジ80%+
- [ ] Integration tests 100% pass / 統合テスト100%合格
- [ ] No memory leaks / メモリリークなし
- [ ] No crash bugs / クラッシュバグなし

### Documentation / ドキュメント
- [ ] All docs updated / すべてのドキュメント更新済み
- [ ] Migration guide created / 移行ガイド作成済み
- [ ] Blocker tracker cleared / ブロッカートラッカークリア

---

**Last Updated**: 2026-03-15 / 最終更新: 2026年3月15日  
**Status**: Active / 状態: アクティブ  
**Version**: 2.0 / バージョン: 2.0
