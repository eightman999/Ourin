# Plugin Bridge Full Implementation Plan

**Created:** 2026-06-26  
**Target:** Ourin's PLUGIN/2.0M bridge / SSP PLUGIN compatibility / PLUGIN/1.0 behavior compatibility  
**Purpose:** Implement UKADOC PLUGIN/2.0's request/response, PLUGIN Event, plugin descript, and legacy PLUGIN/1.0-derived behavior to practical compatibility level as a macOS native plugin bridge.

## Reference Specifications

- UKADOC PLUGIN/2.0: https://ssp.shillest.net/ukadoc/manual/spec_plugin.html
- UKADOC PLUGIN Event: https://ssp.shillest.net/ukadoc/manual/list_plugin_event.html
- UKADOC Plugin descript.txt: https://ssp.shillest.net/ukadoc/manual/descript_plugin.html
- PLUGIN/1.0 Reference: http://usada.sakura.vg/contents/plugin.html
- Ourin Spec: `docs/SPEC_PLUGIN_2.0M_en-us.md`
- Ourin Event Spec: `docs/PLUGIN_EVENT_2.0M_SPEC_en-us.md`

## Completion Definition

Full plugin bridge implementation means meeting all of the following:

1. Sending to plugins complies with PLUGIN/2.0 wire semantics.
2. `Event` / `Reference*` / `Target` / `Script` / `ScriptOption` / `EventOption` responses from plugins are bridged to ghosts per spec.
3. All events in UKADOC PLUGIN Event list have at least correct ID, GET/NOTIFY, and Reference ordering send paths.
4. `descript.txt` `charset` / `secondchangeinterval` / `otherghosttalk` is wired into actual operation.
5. `property.get` / `property.set` is delegated to plugins as `pluginlist(...).ext` extended properties.
6. Both Shift_JIS/CP932 and UTF-8 plugins have no character encoding issues in request/response.
7. PLUGIN/1.0 doesn't directly load Windows DLLs on macOS, but provides behavior compatibility for event names, menu invocation, and old descript-derived metadata.

## Current Summary

Updated 2026-06-27: The runtime bridge items in this plan are implemented. `Charset` byte encode/decode, `Target` delivery, `Event`/`Script` fallback, `ScriptOption`, plugin-specific `secondchangeinterval`, `otherghosttalk` before/after, catalog/install/ghost/menu event wiring, `pluginlist(...).ext` property delegation, PLUGIN/1.0 metadata compatibility, DevTools console, choice/anchor plugin-origin one-shot hooks are connected. Regression validated via `PluginEncodingTests`, `PluginTargetRoutingTests`, `PluginPropertyBridgeTests` and existing matrix, plus full `xcodebuild -project Ourin.xcodeproj -scheme Ourin test`.

Implemented:

- `.plugin` / `.bundle` detection and `request` / `loadu` / `unload` calls.
- `PluginFrame` GET/NOTIFY frame construction.
- `PluginEventDispatcher` per-plugin sequential dispatch.
- `OurinPluginEventBridge` `raiseplugin` / `notifyplugin` response bridge.
- `EventOption: notify`, `ScriptOption` parse, basic `__SYSTEM_ALL_GHOST__` acceptance.
- `OnChoiceSelect(Ex)` / `OnAnchorSelect(Ex)` plugin-origin one-shot passthrough.
- Actual byte encode/decode based on negotiated `Charset`.
- `Target` delivery to specific ghost / all ghosts / baseware.
- `notranslate` / `nobreak` SakuraScript execution control.
- `property.get` / `property.set` plugin delegation.
- `OnOtherGhostTalk` actual talk pipeline connection and `before` / `after`.
- Catalog notification wiring at startup / install.
- PLUGIN/1.0-derived plugin metadata / menu/message behavior compatibility.

## Phase 0: Implementation Status Audit and Spec Sync

**Purpose:** Eliminate gaps between old docs and actual code, fix baseline for subsequent implementation.

Target:

- `docs/SPEC_PLUGIN_2.0M_en-us.md`
- `docs/PLUGIN_EVENT_2.0M_SPEC_en-us.md`
- `docs/PLUGIN_COMPAT_FIX_PROPOSAL.md`
- `Ourin/PluginEvent/*`
- `Ourin/PluginHost/*`

Tasks:

1. Retranscribe UKADOC event list to Ourin implementation table.
2. Classify each event as `implemented` / `helper-only` / `not wired` / `not implemented`.
3. Split existing docs "implemented" terminology into helper-only and runtime-wired.

Acceptance Criteria:

- Docs implementation status does not contradict what `rg` confirms in code.
- Each unimplemented item maps to a Phase in this plan.

## Phase 1: Wire charset at byte level

**Purpose:** Apply PLUGIN/2.0 `Charset` to actual request/response encode/decode.

Target:

- `Ourin/PluginHost/Plugin.swift`
- `Ourin/PluginHost/PluginProtocol.swift`
- `Ourin/PluginEvent/PluginEncodingNormalizer.swift`
- `Ourin/PluginEvent/PluginEventDispatcher.swift`
- `OurinTests/OurinPluginEventBridgeTests.swift`
- New: `OurinTests/PluginEncodingTests.swift`

Tasks:

1. Make `Plugin.send` charset-specifiable via `String.Encoding`.
2. After `PluginRequest` build, wire with negotiated charset to bytes.
3. Decode plugin response with response `Charset` or request charset, normalize to internal UTF-8 `String`.
4. Retain `version` response `Charset` per plugin, apply to next request.
5. Add Shift_JIS/CP932 round-trip fixture plugin or mock request function to tests.

Acceptance Criteria:

- Shift_JIS plugin doesn't have character corruption even with Japanese `Reference*` sent.
- Shift_JIS response `Script` / `Event` / `Reference*` can be handled as UTF-8 internal strings.
- UTF-8 plugin existing tests don't regress.

## Phase 2: Complete Target routing

**Purpose:** Route `Target`-specified plugin responses to intended ghosts per spec.

Target:

- `Ourin/PluginEvent/OurinPluginEventBridge.swift`
- `Ourin/SHIORIEvents/EventBridge.swift`
- `Ourin/Ghost/GhostManager.swift`
- `Ourin/Ghost/GhostManager+System.swift`
- `Ourin/SSTP/BridgeToSHIORI.swift`

Tasks:

1. Evaluate `PluginTransportAction.target` not just as string, but pass to delivery target resolver.
2. Add target resolver:
   - `nil` / empty: prioritize calling ghost, else active ghost.
   - `__SYSTEM_ALL_GHOST__`: all running ghosts.
   - ghost name / ghost id / ghost path / owned SSTP id: matching ghost.
   - `baseware` / `ourin`: baseware processing.
3. Retain calling ghost in action context for `raiseplugin`.
4. System event-derived responses in `PluginEventDispatcher` follow active ghost or target spec.
5. Don't run fallback script on target mismatch.

Acceptance Criteria:

- With 2 ghosts running, `Target`-specified response reaches only that ghost.
- `__SYSTEM_ALL_GHOST__` reaches all ghosts.
- `raiseplugin` response returns to calling ghost if target unspecified.

## Phase 3: Tighten Event/Script response semantics

**Purpose:** Stabilize spec where `Event` fallback to default `Script` only if event doesn't respond.

Target:

- `Ourin/PluginEvent/OurinPluginEventBridge.swift`
- `Ourin/SHIORIEvents/EventBridge.swift`
- `Ourin/SHIORIEvents/EventID.swift`
- `Ourin/Ghost/GhostManager.swift`
- `Ourin/SakuraScriptEngine.swift`

Tasks:

1. Plugin response `Event` is GET to SHIORI if no `EventOption: notify`.
2. If GET response script is empty, use plugin response `Script` as fallback.
3. With `EventOption: notify`, don't look at response script, don't run plugin fallback.
4. Implement `ScriptOption: nobreak` as "enqueue after current talk".
5. Propagate `ScriptOption: notranslate` to SakuraScript execution context.
6. Enable `OnOtherGhostTalk` reasons to carry `plugin-script` / `plugin-event` / `notranslate`.

Acceptance Criteria:

- With `Event + Script` response and ghost GET response, default Script doesn't replay.
- Only when ghost returns empty does default Script replay.
- `nobreak` doesn't interrupt playing talk.
- `notranslate` bypasses translate pipeline.

## Phase 4: Wire all UKADOC PLUGIN Event send paths

**Purpose:** Connect all event IDs in list to runtime event sources.

Target:

- `Ourin/PluginEvent/PluginEventDispatcher.swift`
- `Ourin/OurinApp.swift`
- `Ourin/Ghost/GhostManager+System.swift`
- `Ourin/Ghost/GhostManager+Balloon.swift`
- `Ourin/NarInstall/*`
- `Ourin/HeadlineHost/*`
- `Ourin/Property/*`

Per-event tasks:

1. `version`
   - Keep as is, re-validate after charset byte implementation.
2. `installedplugin`
   - Send at startup, plugin reload, install/uninstall.
3. `installedghostname`
   - Send at startup, ghost install/uninstall.
   - `Reference0`: ghost names.
   - `Reference1`: sakura names.
   - `Reference2`: kero names.
4. `installedballoonname`
   - Send at startup, balloon install/uninstall.
5. `ghostpathlist`
   - Send at startup, ghost path setting change.
6. `balloonpathlist`
   - Send at startup, balloon path setting change.
7. `headlinepathlist`
   - Send at startup, headline path setting change.
8. `pluginpathlist`
   - Send at startup, plugin reload/install/uninstall.
9. `OnSecondChange`
   - Respect `secondchangeinterval` per plugin. Currently single batch timer; move to per-plugin timer or tick filter.
10. `OnOtherGhostTalk`
    - Connect just before/after ghost talk.
    - Respect `otherghosttalk` `false/0/true/1/after/before`.
11. `OnGhostBoot`
    - Send when ghost boot complete. `0` if window not yet built.
12. `OnGhostExit`
    - Send NOTIFY when ghost exits.
13. `OnGhostInfoUpdate`
    - Send NOTIFY on ghost config/shell/info update.
14. `OnMenuExec`
    - Send GET when plugin menu executed.
15. `OnInstallComplete`
    - Send on NAR / ghost / shell / balloon / plugin / headline install complete.
16. `OnChoiceSelect(Ex)` / `OnAnchorSelect(Ex)` / arbitrary choice event
    - Mark only choices from plugin response script/event, once, for plugin passthrough.
17. `raiseplugin` / `notifyplugin` arbitrary name
    - Keep as is, wire Target context and charset.
18. `property.get`
    - Implement in Phase 5.
19. `property.set`
    - Implement in Phase 5.

Acceptance Criteria:

- Each event Reference order matches UKADOC.
- `[NOTIFY]` events ignore response script.
- `OnSecondChange` respects per-plugin interval.
- `OnOtherGhostTalk` distinguishes `before` / `after`.

## Phase 5: plugin extended property.get / property.set

**Purpose:** Delegate `pluginlist(...).ext` extended properties to plugin requests.

Target:

- `Ourin/Property/PluginPropertyProvider.swift`
- `Ourin/Property/PropertyManager.swift`
- `Ourin/PluginHost/PluginRegistry.swift`
- `Ourin/PluginEvent/PluginEventDispatcher.swift`
- `OurinTests/PropertySystemTests.swift`

Design:

- Treat `pluginlist(name).ext.foo` or `pluginlist.index(n).ext.foo` as extended property.
- get:
  - Send `GET PLUGIN/2.0M` to target plugin
  - `ID: property.get`
  - `Reference0: foo`
  - Adopt response value as property value, not `Value` or `Script`.
- set:
  - Send per-spec, not GET or NOTIFY, but request-response equivalent.
  - `ID: property.set`
  - `Reference0: foo`
  - `Reference1: value`
  - Treat status `204` or `200` as success.

Acceptance Criteria:

- `pluginlist.index(0).ext.somekey` returns plugin `property.get` response.
- `PropertyManager.set("pluginlist.index(0).ext.somekey", value: "x")` calls `property.set`.
- 404/500 response becomes property get nil / set false.

## Phase 6: PLUGIN/1.0 behavior compatibility

**Purpose:** Provide macOS-friendly handling of old plugin distributions, old metadata, old menu behavior without Windows DLL binary compatibility.

Target:

- `Ourin/PluginHost/PluginRegistry.swift`
- `Ourin/PluginHost/PluginProtocol.swift`
- `Ourin/PluginEvent/PluginEventDispatcher.swift`
- `Ourin/OwnerDrawMenu/*`
- `OurinTests/LegacyPluginRegistryTests.swift`

Tasks:

1. Clarify conditions for treating legacy metadata-only plugin directory as bridge target.
2. Normalize old key aliases in `descript.txt`.
3. Windows DLL plugins without native `.plugin` are "unloadable but metadata visible"; show explicit error or disabled on menu execution.
4. Retain PLUGIN/1.0 menu / author / readme / charset keys in `PluginMeta`.
5. If native replacement exists for same ID, prioritize native, don't double-register legacy.

Acceptance Criteria:

- Legacy plugin directory is distinguishable in Ourin UI.
- Native replacement prevents double-loading.
- Old descript charset/name/id/filename readable as metadata.

## Phase 7: Menu / UI / DevTools bridge

**Purpose:** Make plugin bridge state and firing verifiable from UI.

Target:

- `Ourin/ContentView.swift`
- `Ourin/DevTools/*`
- `Ourin/OwnerDrawMenu/*`
- `Ourin/PluginHost/PluginRegistry.swift`

Tasks:

1. Show negotiated charset, package path, executable path, legacy/native state in Plugin DevTools.
2. Add or enhance test console to send arbitrary `GET` / `NOTIFY` request to any plugin.
3. Wire actual menu execution to `OnMenuExec` dispatcher.
4. Prioritize `message.*.txt` in plugin menu display text.

Acceptance Criteria:

- Manually verify `version` / arbitrary event / property.get from DevTools.
- Plugin menu text switches via `message.japanese.txt` / `message.english.txt`.

## Phase 8: Test plugin fixtures

**Purpose:** Lock real plugin compatibility via unit and integration tests.

Target:

- `OurinTests/Fixtures/plugin/*`
- New fixture plugin source
- `OurinTests/PluginBridgeIntegrationTests.swift`

Fixtures:

1. UTF-8 echo plugin.
2. Shift_JIS echo plugin.
3. `Event + Script fallback` plugin.
4. `Target` plugin.
5. `property.get/set` plugin.
6. Legacy metadata-only plugin.

Acceptance Criteria:

- CI or local `xcodebuild test` can load fixture plugins.
- Validate byte charset, Target, fallback, property via actual plugin response.

## Phase 9: Regression test matrix

**Target Tests**

- `OurinPluginEventBridgeTests`
- `LegacyPluginRegistryTests`
- `PropertySystemTests`
- `SakuraScriptEngineTests`
- `SSTPDispatcherTests`
- New `PluginEncodingTests`
- New `PluginTargetRoutingTests`
- New `PluginPropertyBridgeTests`
- New `PluginEventDispatchMatrixTests`

Verification Command:

```bash
xcodebuild -project Ourin.xcodeproj -scheme Ourin test
```

Additionally, during target changes run individually:

```bash
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/OurinPluginEventBridgeTests test
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/PropertySystemTests test
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/LegacyPluginRegistryTests test
```

## Implementation Order

Recommended:

1. Phase 0: docs/status audit.
2. Phase 1: charset byte implementation.
3. Phase 2: Target routing.
4. Phase 3: Event/Script semantics.
5. Phase 4: event wiring.
6. Phase 5: property.get/set.
7. Phase 6: PLUGIN/1.0 behavior compatibility.
8. Phase 7: UI/DevTools.
9. Phase 8/9: fixtures and test matrix expansion.

Rationale:

- Charset and Target are foundation for entire bridge; affect all subsequent events.
- Fixing Event/Script semantics first stabilizes OnMenuExec, raiseplugin, choice hook behavior.
- Property is independent but needs target plugin resolution from Phase 2.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Shift_JIS plugin response decode failure | Japanese plugins break | Add byte fixture and CP932 fallback |
| Target routing sends script to wrong ghost | User experience / compatibility hit | Add multi-ghost routing tests |
| `nobreak` breaks playback queue | Talk playback regressions | Add SakuraScript playback tests |
| `OnOtherGhostTalk` fires recursively | plugin-event loop | Introduce reason flag and re-entry suppress token |
| `property.set` has side effects | Unexpected plugin state change | Send to explicit target plugin only |
| Legacy plugin misload | Crash/broken bundle | Separate loadability by native bundle presence |

## Minimum Milestones

### M1: bridge core complete

- Charset byte implementation.
- Target routing.
- Event/Script fallback tighten.
- `OurinPluginEventBridgeTests` / `PluginEncodingTests` / `PluginTargetRoutingTests` pass.

### M2: event matrix complete

- All UKADOC PLUGIN Event IDs wired to runtime sources.
- `OnSecondChange` per-plugin interval.
- `OnOtherGhostTalk` before/after.
- `PluginEventDispatchMatrixTests` pass.

### M3: property and legacy compatibility

- `property.get/set` plugin delegation.
- PLUGIN/1.0 metadata-only compatibility.
- Native replacement priority and dedup.

### M4: UI and operational verification

- DevTools shows request/response.
- Plugin menu text reflects `message.*.txt`.
- Full `xcodebuild ... test` passes.

## Docs to Update After Completion

- `docs/SPEC_PLUGIN_2.0M_en-us.md`
- `docs/SPEC_PLUGIN_2.0M_ja-jp.md`
- `docs/PLUGIN_EVENT_2.0M_SPEC_en-us.md`
- `docs/PLUGIN_EVENT_2.0M_SPEC_ja-jp.md`
- `docs/PropertySystem_en-us.md`
- `docs/PropertySystem_ja-jp.md`
- `docs/SUPPORTED_SAKURA_SCRIPT.md`

## Checklist

- [x] Charset negotiated byte encode/decode
- [x] Target resolver
- [x] caller ghost context for `raiseplugin`
- [x] `__SYSTEM_ALL_GHOST__` multi-ghost delivery
- [x] `Event` GET fallback semantics
- [x] `EventOption: notify`
- [x] `ScriptOption: nobreak`
- [x] `ScriptOption: notranslate`
- [x] plugin-specific `secondchangeinterval`
- [x] `otherghosttalk` before/after
- [x] `installedghostname`
- [x] `installedballoonname`
- [x] `ghostpathlist`
- [x] `balloonpathlist`
- [x] `headlinepathlist`
- [x] `OnGhostBoot`
- [x] `OnGhostExit`
- [x] `OnGhostInfoUpdate`
- [x] `OnMenuExec`
- [x] `OnInstallComplete`
- [x] choice/anchor one-shot plugin-origin hook
- [x] `property.get`
- [x] `property.set`
- [x] PLUGIN/1.0 metadata-only compatibility
- [x] DevTools request console
- [x] fixture/plugin bridge regression suite
