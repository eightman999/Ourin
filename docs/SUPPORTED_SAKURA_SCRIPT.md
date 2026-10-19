# SUPPORTED SAKURA SCRIPT (Ourin)

This document lists the SakuraScript commands currently implemented in Ourin, based on `SakuraScriptEngine.swift` parsing and `GhostManager.swift` execution paths.

> This file is a summary. For the comprehensive per-command list (including all `\![set,...]`/`\![enter,...]`/`\![lock,...]` subcommands), see `SAKURASCRIPT_COMMANDS_SUPPORTED_ja-jp.md` / `SAKURASCRIPT_COMMANDS_SUPPORTED_en-us.md`.

Status marks:
- ✅ Implemented
- ⚠️ Partially implemented / limited options
- ❌ Not implemented

## Scope commands

- ✅ `\0` / `\1` / `\h` / `\u`
- ✅ `\p[n]`

## Surface commands

- ✅ `\s[n]`
- ✅ `\i[n]`, `\i[n,wait]`
- ✅ `\![anim,clear,ID]`
- ✅ `\![anim,pause,ID]`
- ✅ `\![anim,resume,ID]`
- ✅ `\![anim,offset,ID,x,y]`
- ⚠️ `\![anim,add,...]` (`overlay`, `base`, `bind`, `text` implemented; other variants are limited)
- ✅ `\![anim,stop]`
- ✅ `\![bind,category,part,value]`

## Balloon / text commands

- ✅ `\n`, `\n[half]`, `\n[percent]`
- ✅ `\b[n]`, `\b[...]`
- ✅ `\C`
- ✅ `\c[...]`
- ⚠️ `\f[...]` (major style controls implemented; unsupported subcommands are ignored)
- ✅ `\_l[x,y]`
- ✅ `\_v` / `\_V`

## Character change commands

- ✅ `\4` / `\5`
- ✅ `\![change,ghost,...]`
- ✅ `\![change,shell,...]`
- ✅ `\![change,balloon,...]`

## Wait commands

- ✅ `\w[n]`
- ✅ `\_w[ms]`
- ✅ `\__w[...]` (`clear`, numeric timing, and `animation,ID` wait implemented)
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

## Window and visual-effect commands

- ✅ `\![move,...]` (named and legacy positional syntax, `fix` per-axis retention, anchors, duration, method, scope, and `--wait`)
- ✅ `\![moveasync,...]` (queued and running animations can be canceled with `\![moveasync,cancel]`; `fix` is supported in legacy syntax)
- ✅ `\![set,scaling,...]` (uniform/non-uniform scaling, duration, named options, and `--wait`)
- ✅ `\![set,alpha,...]` (0–100 value, negative redraw-only behavior, duration, named options, and `--wait`)
- ⚠️ `\![set,zorder,...]` (scope ordering and reset are implemented; complex multi-window UI combinations still need real-shell verification)
- ⚠️ `\![set,sticky-window,...]` (grouping, relative offsets, drag following, and reset are implemented; complex multi-window UI combinations still need real-shell verification)

The runtime behavior above is covered by unit/regression tests. Visual equivalence against a real shell remains an integration verification item; see `docs/AUDITS_TODO.md`.
