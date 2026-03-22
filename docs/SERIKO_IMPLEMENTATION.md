# SERIKO Implementation in Ourin

## Scope

Ourin currently implements SERIKO in two layers:

- Legacy runtime path in `AnimationEngine.swift`
- New parser/executor path in:
  - `Ourin/Animation/SerikoParser.swift`
  - `Ourin/Animation/SerikoExecutor.swift`
  - `Ourin/Ghost/GhostManager+Animation.swift` integration

## Parser (`SerikoParser`)

`SerikoParser.parseSurfaces(_:)` reads `surfaces.txt` and extracts:

- `surfaceN { ... }` scope blocks
- `animation<ID>.interval,<value>`
- `animation<ID>.option,<value>`
- `animation<ID>.pattern<idx>,...`

Core model types:

- `SerikoInterval` (`always`, `sometimes`, `rarely`, `random`, `runonce`, `yen-e`, `talk`, `bind`, `never`)
- `SerikoMethod` (`overlay`, `overlayfast`, `base`, `move`, `reduce`, `replace`, `start`, `alternativestart`, `stop`, `asis`)
- `SerikoPattern`
- `AnimationDefinition`

Notes:

- Legacy numeric pattern format is treated as `overlay`.
- Unknown values are preserved via `.unknown(...)`.

## Executor (`SerikoExecutor`)

`SerikoExecutor` is a stateful animation scheduler:

- `register(animations:)` stores definitions
- `executeAnimation(id:)` starts an animation immediately
- `startLoop()` advances active animations based on elapsed time and interval rules
- `pauseAnimation`, `resumeAnimation`, `offsetAnimation`, `stopAnimation`, `stopAllAnimations`

Interval triggers:

- Probabilistic: `sometimes`, `rarely`, `random`
- One-shot: `runonce`
- Event-driven: `yenE`, `talk`, `bind` via trigger APIs

Callbacks:

- `onMethodInvoked`
- `onPatternExecuted`
- `onAnimationFinished`

## Ghost integration

`GhostManager+Animation.swift` wires executor callbacks into rendering actions:

- `overlay` / `overlayFast` -> `handleSurfaceOverlay`
- `base` -> `handleAnimAddBase`
- `move` -> `handleAnimAddMove`
- `replace` -> `handleSurfaceOverlay(..., .replace)`
- `start` / `alternativeStart` -> nested executor start
- `stop` -> executor stop

Runtime flow:

1. `loadAnimationsForCurrentSurface()` loads `surfaces.txt`
2. Parsed animations are registered to `SerikoExecutor`
3. `playAnimation(...)` tries executor first
4. Falls back to legacy `AnimationEngine` if executor has no matching definition

The loop is driven by a timer in `GhostManager+Animation` calling `serikoExecutor.startLoop()`.

## SakuraScript linkage

Current linkage is command-level through `GhostManager` handlers:

- `\i[ID]` / `\i[ID,wait]`
- `\![anim,clear|pause|resume|offset|add|stop,...]`

`waitForAnimation(id:)` exists for synchronized behavior and is used in animation flow.

## Test coverage

- `OurinTests/SerikoParserTests.swift`
  - parser correctness
  - real shell `surfaces.txt` parsing
- `OurinTests/SerikoExecutorTests.swift`
  - startup/advance/offset
  - runonce completion
  - interval trigger behavior

## Current Status / 現在のステータス

**Status**: Parser Complete, Executor Exists but Not Integrated / パーサー完了、エグゼキューターは存在するが統合されていない / 2026-03-15

### Implemented Components / 実装済みコンポーネント

#### ✅ **SerikoParser.swift** (Complete / 完全)
Complete SERIKO/2.0 parser with:
- All interval types (always, sometimes, rarely, random, runonce, yen-e, talk, bind, never)
- All method types (overlay, overlayfast, base, move, isReducing, replace, start, alternativestart, stop, asis)
- Pattern parsing and surface definitions
- surfaces.txt parsing

#### ✅ **SerikoExecutor.swift** (Exists but Not Connected / 存在するが接続されていない)
Fully functional animation execution engine with:
- Animation state management
- executeAnimation(), startLoop() methods
- All execute methods (overlay, base, move, reduce, replace, start, stop, etc.)
- Pause/resume/offset capabilities
- Callback system (onMethodInvoked, onPatternExecuted, onAnimationFinished)
- **BUT: Callbacks not wired to GhostManager**

#### ⚠️ **GhostManager+Animation.swift** (Partial / 部分的)
Integration hooks exist but:
- SerikoExecutor callbacks not connected
- Handler methods (handleSurfaceOverlay, etc.) may not invoke actual rendering

### Integration Gaps / 統合のギャップ
- ✅ **SerikoExecutor callbacks connected** - wired via GhostManager animation handlers
- ✅ **SakuraScript animation commands routed** - \![anim,*] path controls animation handling
- ⚠️ **Advanced dressup behavior coverage** - functional path exists, but broader ghost-matrix validation is ongoing

### Blocking Issues / ブロック中の問題
- No active SERIKO blockers in current tracker.

### Integration Required / 必要な統合

See INTEGRATION_ROADMAP.md **Phase 3** for detailed integration steps:

INTEGRATION_ROADMAP.mdの**フェーズ3**を参照して詳細な統合手順を確認してください：

1. **Wire SerikoExecutor to GhostManager** (Task 3.1):
   - In GhostManager+Animation.swift:
     ```swift
     serikoExecutor.onMethodInvoked = { [weak self] method in
         self?.handleSerikoMethod(method)
     }
     
     serikoExecutor.onPatternExecuted = { [weak self] pattern in
         self?.handleSerikoPattern(pattern)
     }
     
     serikoExecutor.onAnimationFinished = { [weak self] animationId in
         self?.handleAnimationFinished(animationId)
     }
     ```
   - Implement handler methods to update surface/rendering

2. **Implement SakuraScript animation commands** (Task 3.2):
   - In SakuraScriptEngine.swift:
     ```swift
     private func handleAnimCommand(arguments: [String]) {
         let command = arguments[0]
         switch command {
         case "clear":
             serikoExecutor.stopAnimation(id: animId)
         case "pause":
             serikoExecutor.pauseAnimation(id: animId)
         // ... etc
         }
     }
     ```
   - Implement wait handler for \__w[animation,ID]

3. **Testing** (Task 3.3):
   - Load ghost with animations
   - Trigger via SakuraScript
   - Verify playback works
   - Test pause/resume/offset

### Success Criteria / 成功基準
- [x] GhostManager callbacks connected
- [x] Animation commands execute
- [x] Pause/resume/offset work
- [x] Critical SERIKO blockers resolved
- [ ] Full multi-ghost on-screen matrix validation

---

## Current limitations / 現在の制限

- Advanced option compatibility varies by ghost data shape.
- Not all SERIKO options in `animation<ID>.option` are applied at runtime yet.
- Integration with advanced SakuraScript animation wait patterns remains partial.
- Legacy and new paths coexist for compatibility; behavior may differ by command/data shape.
