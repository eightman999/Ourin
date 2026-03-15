# SUPPORTED SAKURA SCRIPT (Ourin)

This document lists the SakuraScript commands currently implemented in Ourin, based on `SakuraScriptEngine.swift` parsing and `GhostManager.swift` execution paths.

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
- ⚠️ `\__w[...]` (`clear` and numeric timing implemented; animation-specific waits are limited)
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

- ⚠️ `\![move,...]` (basic x/y/time/method/scope works; advanced option set is incomplete)
- ⚠️ `\![moveasync,...]` (basic async move works; cancellation/options are incomplete)
- ⚠️ `\![set,scaling,...]` (core scaling implemented; some extended flags are incomplete)
- ⚠️ `\![set,alpha,...]` (basic alpha set implemented; timed/wait variants are incomplete)
- ⚠️ `\![set,zorder,...]` (core ordering implemented; complex combinations are incomplete)
- ⚠️ `\![set,sticky-window,...]` (basic grouping implemented; complex group handling is incomplete)
