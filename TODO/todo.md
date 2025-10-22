# SakuraScript Implementation Status

**Source**: https://ssp.shillest.net/ukadoc/manual/list_sakura_script.html
**Date**: 2025-10-21

This document lists all SakuraScript commands from the official ukadoc specification and their implementation status in Ourin.

---

## Legend

- ✅ **FULLY IMPLEMENTED**: Command is parsed and executed
- ⚠️ **PARTIALLY IMPLEMENTED**: Command is parsed but execution is incomplete or missing features
- ❌ **NOT IMPLEMENTED**: Command is not parsed or handled

---

## 1. Scope Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\0` or `\h` | ✅ | Switch to main character (scope 0) |
| `\1` or `\u` | ✅ | Switch to sub-character (scope 1) |
| `\p[ID]` | ✅ | Display scope for character ID (0-9+) |

---

## 2. Surface Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\s[ID]` | ✅ | Change surface to specified ID |
| `\i[ID]` | ✅ | Display surface animation |
| `\i[ID,wait]` | ✅ | Display animation and wait for completion |
| `\![anim,clear,ID]` | ✅ | Stop animation playback |
| `\![anim,pause,ID]` | ✅ | Pause animation |
| `\![anim,resume,ID]` | ✅ | Resume paused animation |
| `\![anim,offset,ID,x,y]` | ✅ | Offset animation position |
| `\4` | ✅ | Move character away from other scope |
| `\5` | ✅ | Move character to adjacent distance |
| `\![move,x,y,time,method,scopeID]` | ✅ | Synchronous movement to coordinates |
| `\![moveasync,x,y,time,method,scopeID]` | ✅ | Asynchronous movement to coordinates |

---

## 3. Balloon & Text Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\b[ID]` | ✅ | Change balloon to specified ID |
| `\_b[path,x,y]` | ⚠️ | Embed image in balloon - parsed but may need verification |
| `\n` | ✅ | Line break |
| `\n[half]` | ✅ | Half-height line break |
| `\c` | ⚠️ | Clear balloon text - parsed but execution unknown |
| `\c[char,N]` | ⚠️ | Clear N characters from cursor - parsed but execution unknown |
| `\_l[x,y]` | ❌ | Move cursor to coordinates - NOT FOUND |
| `\C` | ✅ | Append to previous balloon |

---

## 4. Text Formatting Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\f[align,direction]` | ❌ | Text alignment (left/center/right) - parsed but NOT executed |
| `\f[valign,direction]` | ❌ | Vertical alignment (top/center/bottom) - parsed but NOT executed |
| `\f[name,font]` | ❌ | Set font name - parsed but NOT executed |
| `\f[height,size]` | ❌ | Set character size - parsed but NOT executed |
| `\f[color,RGB]` | ❌ | Set text color - parsed but NOT executed |
| `\f[bold,0/1]` | ❌ | Toggle bold - parsed but NOT executed |
| `\f[italic,0/1]` | ❌ | Toggle italic - parsed but NOT executed |
| `\f[underline,0/1]` | ❌ | Toggle underline - parsed but NOT executed |
| `\f[default]` | ❌ | Reset to default formatting - parsed but NOT executed |

---

## 5. Wait Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\w[1-9]` | ✅ | Wait (time × 50ms) |
| `\_w[ms]` | ✅ | Precise wait in milliseconds |
| `\_\_w[ms]` | ✅ | Wait from script start |
| `\x` | ✅ | Click-wait |
| `\t` | ✅ | Time-critical section (quick wait) |

---

## 6. Choice Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\q[title,ID]` | ✅ | Display choice option |
| `\q[title,OnEvent,r0,r1...]` | ✅ | Choice triggering custom event |
| `\_\_q[ID,...]` | ❌ | Multi-line choice with auto-wrap - NOT FOUND |

---

## 7. Anchor Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\_a[ID]` | ⚠️ | Create clickable anchor text - parsed but TODO comment indicates incomplete |
| `\_a[OnEvent,r0,r1...]` | ⚠️ | Anchor triggering custom event - parsed but TODO comment indicates incomplete |

---

## 8. Event Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\e` | ✅ | End script/event |
| `\-` | ❌ | Exit application - parsed as choiceLineBr, not exit app |
| `\![raise,event,r0,r1...]` | ✅ | Trigger SHIORI event |
| `\![embed,event,r0,r1...]` | ❌ | Embed event result inline - NOT FOUND |
| `\![timerraise,ms,repeat,event,r0,r1...]` | ❌ | Delayed event trigger - NOT FOUND |
| `\![change,ghost,name]` | ❌ | Switch ghost - NOT FOUND |
| `\![change,shell,name]` | ❌ | Switch shell - NOT FOUND |
| `\![change,balloon,name]` | ❌ | Switch balloon - NOT FOUND |
| `\![updatebymyself]` | ✅ | Check for network updates |
| `\![vanishbymyself]` | ✅ | Uninstall self |

---

## 9. Sound Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\_v[file]` | ✅ | Play audio file |
| `\_V` | ✅ | Wait for audio completion (stopAllSounds) |
| `\![sound,play,file]` | ❌ | Play sound with options - NOT FOUND |
| `\![sound,loop,file]` | ❌ | Loop audio - NOT FOUND |
| `\![sound,stop,file]` | ❌ | Stop playback - NOT FOUND |
| `\8[filename]` | ✅ | Play sound (legacy format) |

---

## 10. Dialog Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\![open,browser,URL]` | ✅ | Open web browser |
| `\![open,inputbox,ID,timeout,text]` | ❌ | Text input dialog - NOT FOUND |
| `\![open,dateinput,ID,timeout,year,month,day]` | ❌ | Date picker - NOT FOUND |
| `\![open,sliderinput,ID,timeout,value,min,max]` | ❌ | Slider dialog - NOT FOUND |
| `\![open,dialog,open,params]` | ❌ | File open dialog - NOT FOUND |
| `\![open,teachbox]` | ❌ | Learning dialog - NOT FOUND |
| `\![open,mailer,email]` | ✅ | Open email client |
| `\![open,configurationdialog,setup]` | ✅ | Show name input dialog |

---

## 11. System Commands

| Command | Status | Notes |
|---------|--------|-------|
| `\6` | ⚠️ | Perform time synchronization - parsed as openURL, not time sync |
| `\7` | ⚠️ | Begin time sync check - parsed as openEmail, not time sync |
| `\![execute,headline,name]` | ✅ | Execute headline |
| `\![executesntp]` | ✅ | Execute SNTP time synchronization |
| `\![set,wallpaper,file]` | ✅ | Set desktop wallpaper |
| `\![set,windowstate,stayontop]` | ✅ | Keep window on top |
| `\v` | ✅ | Display window on top / open preferences |

---

## 12. Environment Variables

| Command | Status | Notes |
|---------|--------|-------|
| `%month%` | ⚠️ | Needs verification in EnvironmentExpander |
| `%day%` | ⚠️ | Needs verification in EnvironmentExpander |
| `%hour%` | ⚠️ | Needs verification in EnvironmentExpander |
| `%minute%` | ⚠️ | Needs verification in EnvironmentExpander |
| `%second%` | ⚠️ | Needs verification in EnvironmentExpander |
| `%username%` | ⚠️ | Needs verification in EnvironmentExpander |
| `%selfname%` | ⚠️ | Needs verification in EnvironmentExpander |
| `%selfname2%` | ⚠️ | Needs verification in EnvironmentExpander |
| `%screenwidth%` | ⚠️ | Needs verification in EnvironmentExpander |
| `%screenheight%` | ⚠️ | Needs verification in EnvironmentExpander |

---

## Summary Statistics

- ✅ **Fully Implemented**: 34 commands
- ⚠️ **Partially Implemented**: 18 commands
- ❌ **Not Implemented**: 26 commands
- **Total Commands**: 78

**Implementation Rate**: ~43.6% fully implemented, ~23.1% partially implemented

---

## Priority TODO List

### HIGH PRIORITY (Core Functionality)

1. **Text Formatting Commands** (`\f[...]` family)
   - `\f[align,direction]` - Text alignment
   - `\f[valign,direction]` - Vertical alignment
   - `\f[name,font]` - Font name
   - `\f[height,size]` - Font size
   - `\f[color,RGB]` - Text color
   - `\f[bold,0/1]` - Bold toggle
   - `\f[italic,0/1]` - Italic toggle
   - `\f[underline,0/1]` - Underline toggle
   - `\f[default]` - Reset formatting
   - **Impact**: Essential for rich text display in balloons

2. **Ghost/Shell/Balloon Switching**
   - `\![change,ghost,name]` - Switch to different ghost
   - `\![change,shell,name]` - Switch character shell/appearance
   - `\![change,balloon,name]` - Switch balloon theme
   - **Impact**: Core ukagaka functionality for multi-ghost systems

3. **Event Embedding and Timing**
   - `\![embed,event,r0,r1...]` - Embed event result inline
   - `\![timerraise,ms,repeat,event,r0,r1...]` - Delayed event trigger
   - **Impact**: Advanced scripting capabilities

4. **Dialog Commands**
   - `\![open,inputbox,ID,timeout,text]` - Text input
   - `\![open,dateinput,ID,timeout,year,month,day]` - Date picker
   - `\![open,sliderinput,ID,timeout,value,min,max]` - Slider
   - `\![open,dialog,open,params]` - File open dialog
   - `\![open,teachbox]` - Learning dialog
   - **Impact**: User interaction features

### MEDIUM PRIORITY (Enhanced Features)

5. **Sound Commands**
   - `\![sound,play,file]` - Play sound with options
   - `\![sound,loop,file]` - Loop audio
   - `\![sound,stop,file]` - Stop specific playback
   - **Impact**: Better audio control

6. **Cursor Control**
   - `\_l[x,y]` - Move cursor to coordinates
   - **Impact**: Advanced balloon text positioning

7. **Multi-line Choices**
   - `\_\_q[ID,...]` - Multi-line choice with auto-wrap
   - **Impact**: Better choice UI

8. **Anchor Completion**
   - Complete `\_a[...]` implementation with clickable text
   - **Impact**: Interactive text features

### LOW PRIORITY (Polish & Compatibility)

9. **Fix Command Semantics**
   - `\6` should be time sync, not openURL
   - `\7` should be time sync check, not openEmail
   - `\-` should be exit app, not line break in choice

10. **Text Clear Commands**
    - Verify `\c` and `\c[char,N]` execution

11. **Environment Variables**
    - Verify all `%variable%` expansions work correctly

12. **Application Exit**
    - Implement `\-` as exit application command

---

## Implementation Files to Modify

1. **Ourin/Ghost/GhostManager.swift** - Main command execution
2. **Ourin/Ghost/BalloonView.swift** - Text formatting display
3. **Ourin/SakuraScript/SakuraScriptEngine.swift** - Command parsing
4. **Ourin/Property/EnvironmentExpander.swift** - Environment variables

---

## Notes

- The parser in `SakuraScriptEngine.swift` handles most commands, but many lack execution handlers in `GhostManager.swift`
- Text formatting (`\f[...]`) is completely parsed but has no execution logic
- Some command semantics are incorrect (`\6`, `\7`, `\-`)
- Dialog commands are mostly missing, limiting user interaction
- Ghost/shell switching is not implemented, affecting multi-ghost compatibility
