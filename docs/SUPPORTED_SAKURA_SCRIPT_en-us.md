# SUPPORTED SAKURA SCRIPT (Ourin)

This document lists the SakuraScript commands currently implemented in Ourin, based on `SakuraScriptEngine.swift` parsing and `GhostManager.swift` execution paths.

> This file is a summary. For the comprehensive per-command list (including all `\![set,...]`/`\![enter,...]`/`\![lock,...]` subcommands), see `SAKURASCRIPT_COMMANDS_SUPPORTED_en-us.md`.

Status marks:
- ✅ Implemented
- ⚠️ Partially implemented / limited options
- ❌ Not implemented

## Scope commands

- ✅ `\0` / `\1` / `\h` / `\u`
- ✅ `\p[n]`

### Balloon display lifetime and scope switching behavior

Following SSP-compatible behavior, scope switches (`\0` / `\1` / `\p[n]`) do not clear balloon text. Each scope's balloon display is independent: switching scope neither wipes other scopes' balloons nor the target scope's own balloon. This allows multiple characters to display their balloons simultaneously (matching SSP).

Returning to a scope mid-script continues (appends to) its existing balloon rather than clearing it.

**When balloons are cleared:**

| Trigger | Detail |
|---------|--------|
| Script start (new utterance) | `runScript` / `runNotifyScript` (when text is present) / `runPluginScript` (without `nobreak`) clears all scopes' balloon text at once (`vm.text = ""` in `GhostManager.swift`) |
| Explicit clear commands | `\c`, `\e[clear]`, `\x` (without `noclear`) |

Scope switches themselves (`\0` / `\1` / `\p[n]`) never clear balloons (see `processNextUnit` `.scope` case in `GhostManager.swift`).

## Surface commands

- ✅ `\s[n]`
- ✅ `\i[n]`, `\i[n,wait]`
- ✅ `\![anim,clear,ID]`
- ✅ `\![anim,pause,ID]` / `\![anim,pauseID]`
- ✅ `\![anim,resume,ID]`
- ✅ `\![anim,offset,ID,x,y]`
- ✅ `\![anim,add,overlay|overlayfast,ID[,x,y]]`
- ✅ `\![anim,add,overlay,ID,x,y,duration,...[,runonce|always]]`
- ✅ `\![anim,add,base,ID]` / `\![anim,add,move,x,y]` / `\![anim,add,bind,ID]`
- ✅ `\![anim,add,text,x,y,width,height,text,...]` (text is required)
- ✅ `\![anim,stop]` / `\![anim,stop,ID]`
- ✅ `\![bind,category,part,value]`

## Balloon / text commands

- ✅ `\n`, `\n[half]`, `\n[percent]`
- ✅ `\b[n]`, `\b[...]`
- ✅ `\C`
- ✅ `\c[...]`
- ⚠️ `\f[...]` (major style controls implemented; unsupported subcommands are ignored)
- ✅ `\_l[x,y]`
- ✅ `\_v` / `\_V`
- ✅ `\![execute,resetballoonpos]`

## Character change commands

- ✅ `\4` / `\5`
- ✅ `\![change,ghost,...]`
- ✅ `\![change,shell,...]`
- ✅ `\![change,balloon,...]`
- ✅ `\![save,wallpaper]` / `\![restore,wallpaper]`

## Wait commands

- ✅ `\w[n]`
- ✅ `\_w[ms]`
- ✅ `\__w[...]` (`clear`, numeric timing, and `animation,ID` wait implemented)
- ✅ `\![wait,syncobject,name,timeout]` / `\![set,syncobject,name]` / `\![reset,syncobject,name]`
- ✅ `\t`
- ✅ `\x`, `\x[noclear]`

## Choice commands

- ✅ `\q[...]`
- ✅ `\*`
- ✅ `\a`
- ✅ `\z`
- ✅ `\-`
- ✅ `\__q[...]`

## Event commands

- ✅ `\![raise,...]`
- ✅ `\![notify,...]`
- ✅ `\![raiseother,...]` / `\![notifyother,...]`
- ✅ `\![raiseplugin,...]` / `\![notifyplugin,...]`
- ✅ `\![timerraise,...]` / `\![timernotify,...]`
- ✅ `\![timerraiseother,...]` / `\![timernotifyother,...]`
- ✅ `\![timerraiseplugin,...]` / `\![timernotifyplugin,...]`
- ✅ `\![embed,...]`

## Sound commands

- ✅ `\8[filename]`
- ✅ `\![sound,play,...]`
- ✅ `\![sound,load,...]`
- ✅ `\![sound,loop,...]`
- ✅ `\![sound,wait,...]`
- ✅ `\![sound,pause,...]`
- ✅ `\![sound,resume,...]`
- ✅ `\![sound,stop,...]`
- ✅ `\![sound,option,...]`

## Open commands

- ✅ `\v`
- ✅ `\6`
- ✅ `\7`
- ✅ `\+`
- ✅ `\_+`
- ⚠️ `\![open,...]` (many subcommands implemented; behavior varies by OS capability)

## Property operations

- ✅ `%property[...]` expansion
- ✅ `\![get,property,key]`
- ✅ `\![set,property,key,value]`

## Related commands with known partial behavior

- ✅ `\![move,...]` (named and legacy positional syntax, `fix` per-axis retention, anchors, duration, method, scope, and `--wait`; updated 2026-08-14)
- ✅ `\![moveasync,...]` (queued and running animations can be canceled with `\![moveasync,cancel]`; `fix` is supported in legacy syntax; updated 2026-08-14)
- ✅ `\![set,scaling,...]` (uniform/non-uniform scaling, duration, named options, and `--wait`; updated 2026-08-14)
- ✅ `\![set,alpha,...]` (0–100 value, negative redraw-only behavior, duration, named options, and `--wait`; updated 2026-08-14)
- ⚠️ `\![set,zorder,...]` (core ordering implemented; complex combinations are incomplete)
- ⚠️ `\![set,sticky-window,...]` (basic grouping implemented; complex group handling is incomplete)
