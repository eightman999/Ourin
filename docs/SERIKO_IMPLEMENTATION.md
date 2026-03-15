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

## Current limitations

- Not all SERIKO options in `animation<ID>.option` are applied at runtime yet.
- Integration with advanced SakuraScript animation wait patterns remains partial.
- Legacy and new paths coexist for compatibility; behavior may differ by command/data shape.
