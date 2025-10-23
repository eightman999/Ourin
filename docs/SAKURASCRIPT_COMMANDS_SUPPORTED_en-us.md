# Sakura Script Commands - Supported in Ourin

This document lists all Sakura Script commands that are currently supported by Ourin's `SakuraScriptEngine`.

## Scope Commands

### Character/Scope Selection

| Command | Description | Example |
|---------|-------------|---------|
| `\0` or `\h` | Switch to Sakura (character 0) | `\0Hello from Sakura` |
| `\1` or `\u` | Switch to Unyuu (character 1) | `\1Hello from Unyuu` |
| `\pN` | Switch to character N (0-9) | `\p2Hello from third character` |
| `\p[N]` | Switch to character N (any ID) | `\p[15]Hello from character 15` |

## Surface Commands

### Surface Display

| Command | Description | Example |
|---------|-------------|---------|
| `\sN` | Change surface to ID N (0-9) | `\s1Switch to surface 1` |
| `\s[N]` | Change surface to ID N (any ID) | `\s[100]Switch to surface 100` |
| `\s[-1]` | Hide surface | `\s[-1]Character becomes invisible` |

## Animation Commands

### Basic Animation

| Command | Description | Example |
|---------|-------------|---------|
| `\i[ID]` | Play animation ID | `\i[10]Play animation 10` |
| `\i[ID,wait]` | Play animation and wait for completion | `\i[100,wait]This text appears after animation` |

### Animation Control (via `\!` command)

| Command | Description | Example |
|---------|-------------|---------|
| `\![anim,clear,ID]` | Stop animation ID | `\![anim,clear,100]` |
| `\![anim,pause,ID]` | Pause animation ID | `\![anim,pause,200]` |
| `\![anim,resume,ID]` | Resume paused animation ID | `\![anim,resume,200]` |
| `\![anim,offset,ID,x,y]` | Offset animation position | `\![anim,offset,300,40,50]` |
| `\![anim,stop]` | Stop all animations | `\![anim,stop]` |

### Animation Layer Control

| Command | Description | Example |
|---------|-------------|---------|
| `\![anim,add,overlay,ID]` | Overlay surface ID on current surface | `\![anim,add,overlay,10]` |
| `\![anim,add,overlayfast,ID]` | Overlay with overlayfast mode | `\![anim,add,overlayfast,10]` |
| `\![anim,add,base,ID]` | Change base surface to ID | `\![anim,add,base,5]` |
| `\![anim,add,move,x,y]` | Move surface to coordinates | `\![anim,add,move,100,200]` |

## Balloon Commands

### Balloon ID Switching

| Command | Description | Example |
|---------|-------------|---------|
| `\bN` | Change balloon to ID N (0-9 only) | `\b2Switch to balloon 2` |
| `\b[ID]` | Change balloon to ID (any ID, negative to hide) | `\b[2]Large balloon` |
| `\b[-1]` | Hide balloon | `\b[-1]Hidden` |

**Notes:**
- Only even IDs (0, 2, 4, 6, 8) are usable for main character balloons
- Odd IDs are reserved for partner/right-side balloons
- SSP 2.6.34+ supports fallback syntax: `\b[ID1,--fallback=ID2,--fallback=ID3]`

### Balloon Images

| Command | Description | Example |
|---------|-------------|---------|
| `\_b[file,x,y]` | Display image at XY coordinates (top-left transparent) | `\_b[image\test.png,50,100]` |
| `\_b[file,x,y,opaque]` | Display image without transparency | `\_b[test.png,0,15,opaque]` |
| `\_b[file,inline]` | Display image inline with text | `Text\_b[icon.png,inline]more` |
| `\_b[file,inline,opaque]` | Display inline image without transparency | `\_b[icon.png,inline,opaque]` |

**Options** (for `\_b[file,x,y,options...]` or `\_b[file,inline,options...]`):
- `--option=opaque` - No transparency
- `--option=use_self_alpha` - Use PNG alpha channel
- `--clipping=left top right bottom` - Crop image region
- `--option=fixed` - Don't scroll with text
- `--option=background` - Display behind text (default)
- `--option=foreground` - Display in front of text

**Example:**
```
\_b[test.png,10,20,--option=use_self_alpha,--clipping=100 30 150 90,--option=foreground]
```

### Balloon Control

| Command | Description | Example |
|---------|-------------|---------|
| `\![set,autoscroll,disable]` | Disable auto-scroll | `\![set,autoscroll,disable]` |
| `\![set,autoscroll,enable]` | Enable auto-scroll | `\![set,autoscroll,enable]` |
| `\![set,balloonoffset,x,y]` | Set balloon offset | `\![set,balloonoffset,100,-50]` |
| `\![set,balloonoffset,@x,@y]` | Set relative balloon offset | `\![set,balloonoffset,@100,@-50]` |
| `\![set,balloonalign,DIR]` | Set balloon alignment (left/center/top/right/bottom/none) | `\![set,balloonalign,top]` |
| `\![set,balloonmarker,text]` | Set SSTP receive marker | `\![set,balloonmarker,SSTP]` |
| `\![set,balloonnum,file,cur,max]` | Set file transfer indicator | `\![set,balloonnum,test.zip,1,5]` |
| `\![set,balloontimeout,ms]` | Set balloon timeout (0 or -1 = no timeout) | `\![set,balloontimeout,3000]` |
| `\![set,balloonwait,rate]` | Set text speed multiplier | `\![set,balloonwait,1.5]` |
| `\![set,serikotalk,true/false]` | Enable/disable SERIKO mouth animation | `\![set,serikotalk,false]` |
| `\![enter,onlinemode]` | Force online marker display | `\![enter,onlinemode]` |
| `\![leave,onlinemode]` | Hide online marker | `\![leave,onlinemode]` |
| `\![enter,nouserbreakmode]` | Disable user script interruption | `\![enter,nouserbreakmode]` |
| `\![leave,nouserbreakmode]` | Enable user script interruption | `\![leave,nouserbreakmode]` |
| `\![lock,balloonrepaint]` | Lock balloon repaint until unlock or script end | `\![lock,balloonrepaint]` |
| `\![lock,balloonrepaint,manual]` | Lock balloon repaint until explicit unlock | `\![lock,balloonrepaint,manual]` |
| `\![unlock,balloonrepaint]` | Unlock balloon repaint | `\![unlock,balloonrepaint]` |
| `\![lock,balloonmove]` | Prevent balloon drag movement | `\![lock,balloonmove]` |
| `\![unlock,balloonmove]` | Allow balloon drag movement | `\![unlock,balloonmove]` |

## Text Control Commands

### Basic Text Control

| Command | Description | Example |
|---------|-------------|---------|
| `\n` | Newline | `Line 1\nLine 2` |
| `\n[half]` | Half-height newline | `Line 1\n[half]Line 2` |
| `\n[percent]` | Custom height newline (% of line height) | `Line 1\n[150]Line 2` |
| `\e` | End script | `Done\e` |
| `\C` | Append mode (append to previous balloon) | `\CAppend to previous` |

### Text Positioning

| Command | Description | Example |
|---------|-------------|---------|
| `\_l[x,y]` | Position cursor at XY coordinates | `\_l[30,100]Positioned` |

**Coordinate formats:**
- Numeric: Pixels from top-left (e.g., `30`)
- em: Character heights (e.g., `5em`)
- lh: Line heights (e.g., `2lh`)
- %: Percentage of character height (e.g., `100%`)
- @: Relative to current position (e.g., `@-100`)
- Omit parameter to keep current value (e.g., `\_l[,@-100]` only moves Y)

**Examples:**
```
\_l[30,5em]       Text at X=30px, Y=5 characters
\_l[@-1650%,100]  X=left 16.5 characters, Y=100px
\_l[,@-100]       Same X, 100px up
```

### Text Clearing

| Command | Description | Example |
|---------|-------------|---------|
| `\c` | Clear current scope balloon | `Text\cCleared` |
| `\c[char,N]` | Clear N characters from cursor | `Delete\c[char,3]End` |
| `\c[char,N,start]` | Clear N characters from position | `Text\c[char,3,4]End` |
| `\c[line,N]` | Clear N lines from cursor | `Line 1\nLine 2\c[line,1]` |
| `\c[line,N,start]` | Clear N lines from position | `\c[line,1,2]` |

**Notes:**
- Character/line counting follows script order, not display position
- `\_b[file,inline]` images count as 1 character
- Lines separated by `\n`, `\n[...]`, `\_l[x,y]` count as separate lines
- Empty lines (e.g., `\n\n`) don't count

### Text Wrapping

| Command | Description | Example |
|---------|-------------|---------|
| `\_n` | Disable auto-wrap (until next `\_n`) | `\_nNo wrap\_n` |

### Wait Commands

| Command | Description | Example |
|---------|-------------|---------|
| `\w[N]` | Wait N×50ms | `\w[10]Wait 500ms` |
| `\__w[animation,ID]` | Wait for animation ID to complete | `\__w[animation,400]` |

### Tag Passthrough

| Command | Description | Example |
|---------|-------------|---------|
| `\_!...\_!` | Display tags literally (old format) | `\_!\1Text\n\_!` displays `\1Text\n` |
| `\_?...\_?` | Display tags literally | `\_?\1Text\n\_?` displays `\1Text\n` |

**Notes:**
- Text between opening and closing tags is not parsed as SakuraScript
- Useful for displaying example scripts or debugging

### Voice Synthesis Control

| Command | Description | Example |
|---------|-------------|---------|
| `\__v[disable]...\__v` | Disable voice synthesis for text | `\__v[disable]Silent\__v` |
| `\__v[alternate,text]...\__v` | Override pronunciation | `\__v[alternate,ひらがな]漢字\__v` |

## Font & Text Styling Commands

### Text Alignment

| Command | Description | Example |
|---------|-------------|---------|
| `\f[align,left]` | Left-align text | `\f[align,left]Left aligned` |
| `\f[align,center]` | Center-align text | `\f[align,center]Centered` |
| `\f[align,right]` | Right-align text | `\f[align,right]Right aligned` |
| `\f[valign,top]` | Vertical align to top | `\f[valign,top]Top` |
| `\f[valign,center]` | Vertical align to center | `\f[valign,center]Middle` |
| `\f[valign,bottom]` | Vertical align to bottom | `\f[valign,bottom]Bottom` |

**Notes:**
- `\f[align,...]` affects text until next intentional newline (`\n`, `\_l`)
- `\_l` tag resets alignment to left
- `\f[valign,...]` does NOT reset on newline (unlike `align`)
- Text added after alignment command will retroactively align previous text on same line

### Font Properties

| Command | Description | Example |
|---------|-------------|---------|
| `\f[name,font]` | Change font (single name or file) | `\f[name,Arial]Arial font` |
| `\f[name,font1,font2,...]` | Change font with fallbacks | `\f[name,メイリオ,meiryo.ttf]Text` |
| `\f[height,size]` | Set font size (pixels) | `\f[height,15]Size 15` |
| `\f[height,+N]` | Relative size increase | `\f[height,+3]Bigger` |
| `\f[height,-N]` | Relative size decrease | `\f[height,-3]Smaller` |
| `\f[height,N%]` | Percentage of default size | `\f[height,200%]Double size` |

**Font name notes:**
- `default` - Reset to balloon default font
- `disable` - Use disabled text font
- Can specify font files in `ghost/master/` or balloon folder
- Multiple comma-separated names = priority order (SSP only)

### Text Colors

| Command | Description | Example |
|---------|-------------|---------|
| `\f[color,name]` | Named color | `\f[color,red]Red text` |
| `\f[color,r,g,b]` | RGB color (0-255) | `\f[color,100,150,200]Blue` |
| `\f[color,#RRGGBB]` | Hex color | `\f[color,#ff6600]Orange` |
| `\f[color,default]` | Reset to balloon default | `\f[color,default]Normal` |
| `\f[shadowcolor,...]` | Shadow color (same formats) | `\f[shadowcolor,#ffff00]Yellow shadow` |
| `\f[shadowcolor,none]` | Disable shadow | `\f[shadowcolor,none]No shadow` |
| `\f[shadowstyle,offset]` | Offset shadow (default) | `\f[shadowstyle,offset]Offset` |
| `\f[shadowstyle,outline]` | Outline shadow | `\f[shadowstyle,outline]Outlined` |
| `\f[anchor.font.color,...]` | Anchor text color | `\f[anchor.font.color,50%,90%,20%]Link` |

**Color format notes:**
- Named colors: `red`, `blue`, `green`, `black`, `white`, etc.
- RGB: Three numbers 0-255, or percentages like `50%,90%,20%`
- Hex: Standard web format `#RRGGBB`

### Text Styles

| Command | Description | Example |
|---------|-------------|---------|
| `\f[bold,1]` or `\f[bold,true]` | Enable bold | `\f[bold,1]Bold text` |
| `\f[bold,0]` or `\f[bold,false]` | Disable bold | `\f[bold,0]Normal` |
| `\f[bold,default]` | Reset to balloon default | `\f[bold,default]Default` |
| `\f[bold,disable]` | Use disabled text style | `\f[bold,disable]Disabled` |
| `\f[italic,1]` | Enable italic | `\f[italic,1]Italic` |
| `\f[strike,1]` | Enable strikethrough | `\f[strike,1]Strike` |
| `\f[underline,1]` | Enable underline | `\f[underline,1]Underline` |
| `\f[outline,1]` | Enable outline (white text) | `\f[outline,1]Outlined` |

**Notes:**
- All style commands support: `1`/`true` (enable), `0`/`false` (disable), `default`, `disable`
- Font must support the style (some fonts don't have bold/italic variants)

### Text Position

| Command | Description | Example |
|---------|-------------|---------|
| `\f[sub,1]` | Enable subscript | `H\f[sub,1]2\f[sub,0]O` |
| `\f[sup,1]` | Enable superscript | `X\f[sup,1]2\f[sup,0]` |

### Reset Commands

| Command | Description | Example |
|---------|-------------|---------|
| `\f[default]` | Reset all font attributes to balloon default | `\f[default]Reset all` |
| `\f[disable]` | Set all attributes to disabled text style | `\f[disable]Disabled` |

**Example combinations:**
```
\f[shadowcolor,#6699cc]\f[bold,1]\f[underline,1]\f[height,20]Styled text\f[default]Normal
\f[align,center]\f[color,red]\f[height,24]Centered Red Title\n
H\f[sub,1]2\f[sub,0]O + O\f[sub,1]2\f[sub,0] → H\f[sub,1]2\f[sub,0]O\f[sub,1]2\f[sub,0]
```

## Character Movement Commands

| Command | Description | Example |
|---------|-------------|---------|
| `\4` | Move away from other character | `Moving...\4Done` |
| `\5` | Move close to other character | `Moving...\5Done` |
| `\![move,args...]` | Move to position (see below) | See Movement section |
| `\![moveasync,args...]` | Move asynchronously | See Movement section |
| `\![moveasync,cancel]` | Cancel async movement | `\![moveasync,cancel]` |

### Move Command Parameters

Format: `\![move,--X=x,--Y=y,--time=ms,--base=ref,--base-offset=pos,--move-offset=pos,--option=opt]`

**Parameters:**
- `--X=value`: X coordinate (can be negative)
- `--Y=value`: Y coordinate (can be negative)
- `--time=ms`: Movement time in milliseconds
- `--base=ref`: Reference point (screen, primaryscreen, ID, ghost/ID, me, global)
- `--base-offset=pos`: Reference anchor (left.top, right.bottom, center.center, etc.)
- `--move-offset=pos`: Character anchor to align
- `--option=opt`: Options (ignore-sticky-window)

**Example:**
```
\![move,--X=80,--Y=-400,--time=2500,--base=screen,--base-offset=left.bottom,--move-offset=left.top]
```

## Dressup/Bind Commands

| Command | Description | Example |
|---------|-------------|---------|
| `\![bind,category,part,1]` | Equip part in category | `\![bind,head,ribbon,1]` |
| `\![bind,category,part,0]` | Remove part from category | `\![bind,head,ribbon,0]` |
| `\![bind,category,,0]` | Remove all parts in category | `\![bind,arm,,0]` |
| `\![bind,category,part]` | Toggle part on/off | `\![bind,head,ribbon]` |

## Rendering Control

| Command | Description | Example |
|---------|-------------|---------|
| `\![lock,repaint]` | Stop repainting until unlock or script end | `\![lock,repaint]` |
| `\![lock,repaint,manual]` | Stop repainting until explicit unlock | `\![lock,repaint,manual]` |
| `\![unlock,repaint]` | Resume repainting | `\![unlock,repaint]` |

## Position & Alignment

### Desktop Alignment

| Command | Description | Example |
|---------|-------------|---------|
| `\![set,alignmentondesktop,bottom]` | Snap to desktop bottom | `\![set,alignmentondesktop,bottom]` |
| `\![set,alignmentondesktop,top]` | Snap to desktop top | `\![set,alignmentondesktop,top]` |
| `\![set,alignmenttodesktop,DIR]` | Set alignment direction | See table below |

**Alignment Directions:**
- `top` - Snap to top
- `bottom` - Snap to bottom
- `left` - Snap to left
- `right` - Snap to right
- `free` - No snapping
- `default` - Reset to default

### Position Locking

| Command | Description | Example |
|---------|-------------|---------|
| `\![set,position,x,y,scopeID]` | Lock character at position | `\![set,position,100,200,0]` |
| `\![reset,position]` | Unlock position | `\![reset,position]` |

## Visual Effects

### Scaling

| Command | Description | Example |
|---------|-------------|---------|
| `\![set,scaling,ratio]` | Uniform scaling (%) | `\![set,scaling,50]` |
| `\![set,scaling,x,y]` | Non-uniform scaling (%) | `\![set,scaling,50,100]` |
| `\![set,scaling,x,y,time]` | Animated scaling (time in ms) | `\![set,scaling,50,100,2500]` |

**Notes:**
- 100 = user's configured scale (100%)
- Negative values flip the axis (-100 = flipped)
- Persists until ghost terminates

### Transparency

| Command | Description | Example |
|---------|-------------|---------|
| `\![set,alpha,value]` | Set transparency (0-100) | `\![set,alpha,50]` |

**Notes:**
- 0 = fully transparent (invisible)
- 100 = fully opaque
- Persists until ghost terminates

### Effects & Filters

| Command | Description | Example |
|---------|-------------|---------|
| `\![effect,plugin,speed,params]` | Apply plugin effect | `\![effect,plugin1,2.0,param]` |
| `\![effect2,surfaceID,plugin,speed,params]` | Effect on added surface | `\![effect2,10,plugin1,2.0,param]` |
| `\![filter,plugin,time,params]` | Apply continuous filter | `\![filter,plugin2,1000,param]` |
| `\![filter]` | Clear filter | `\![filter]` |

## Window Management

### Z-Order

| Command | Description | Example |
|---------|-------------|---------|
| `\![set,zorder,ID1,ID2,...]` | Set window stacking order | `\![set,zorder,1,0]` |
| `\![reset,zorder]` | Reset to default z-order | `\![reset,zorder]` |

**Notes:**
- IDs listed left to right = front to back
- Example: `\![set,zorder,1,0]` makes character 1 always in front of character 0

### Sticky Windows

| Command | Description | Example |
|---------|-------------|---------|
| `\![set,sticky-window,ID1,ID2,...]` | Link windows to move together | `\![set,sticky-window,1,0]` |
| `\![reset,sticky-window]` | Unlink windows | `\![reset,sticky-window]` |

**Notes:**
- Linked windows move together when dragged
- Works with `\![move]` commands (unless --option=ignore-sticky-window)

### Window Reset

| Command | Description | Example |
|---------|-------------|---------|
| `\![execute,resetwindowpos]` | Reset all windows to initial positions | `\![execute,resetwindowpos]` |

## Special Commands

### Marker

| Command | Description | Example |
|---------|-------------|---------|
| `%*` or `\![*]` | Insert marker | `Text before%*Text after` |

## Escape Sequences

| Sequence | Result | Example |
|----------|--------|---------|
| `\\` | Literal `\` | `C:\\Users` → `C:\Users` |
| `\%` | Literal `%` | `100\%` → `100%` |
| `\]` | Literal `]` (in brackets) | `\![test,a\]b]` → args: `["test", "a]b"]` |
| `\[` | Literal `[` (in brackets) | `\![test,a\[b]` → args: `["test", "a[b"]` |

## Argument Quoting

Arguments in `[...]` brackets are comma-separated and support quoting:

| Rule | Example | Result |
|------|---------|--------|
| Basic | `\![raise,OnTest,100]` | `["raise", "OnTest", "100"]` |
| Quoted comma | `\![raise,OnTest,"100,2"]` | `["raise", "OnTest", "100,2"]` |
| Escaped quote | `\![call,ghost,"the ""Master"""]` | `["call", "ghost", "the \"Master\""]` |

## Implementation Status

### ✅ Fully Implemented

#### Parser Level (SakuraScriptEngine.swift)
All commands listed above are **parsed correctly**. The parser converts Sakura Script text into tokens that can be processed by the rendering engine.

#### Rendering Level (GhostManager.swift + CharacterViewModel/CharacterView)

**Visual Effects - IMPLEMENTED:**
- ✅ `\![set,scaling,ratio]` - Uniform scaling
- ✅ `\![set,scaling,x,y]` - Non-uniform scaling
- ✅ `\![set,alpha,value]` - Transparency (0-100)
- ✅ `\![lock,repaint]` / `\![unlock,repaint]` - Rendering control
- ✅ `\![set,alignmenttodesktop,DIR]` - Desktop alignment state
- ✅ `\![set,position,x,y,scopeID]` / `\![reset,position]` - Position locking state
- ✅ `\![set,zorder,...]` / `\![reset,zorder]` - Z-order grouping state
- ✅ `\![set,sticky-window,...]` / `\![reset,sticky-window]` - Sticky window grouping state
- ✅ `\![execute,resetwindowpos]` - Reset all window positions/alignments

**Command Handling:**
- Character visual state is stored in `CharacterViewModel` with `@Published` properties
- Visual effects are applied in `CharacterView` using SwiftUI modifiers (`.scaleEffect()`, `.opacity()`, `.allowsHitTesting()`)
- All settings persist until ghost terminates (per UKADOC specification)
- `\![lock,repaint]` auto-unlocks at script end unless `manual` option is used

### ⚠️ Partially Implemented

**Window Management - STATE STORED, BEHAVIOR TODO:**
These commands update the ViewModel state correctly, but actual window behavior needs platform implementation:
- ⚠️ Alignment constraints (preventing window movement in certain directions)
- ⚠️ Position locking (disabling window drag)
- ⚠️ Z-order enforcement (keeping windows in specified stacking order)
- ⚠️ Sticky window synchronization (moving multiple windows together)

### ❌ Not Yet Implemented (Execution Level)

**Balloon & Text Commands - PARSED ONLY:**
All balloon and text commands are fully parsed, but execution is not yet implemented:
- ❌ `\bN` / `\b[ID]` - Balloon ID switching (parsed, placeholder exists)
- ❌ `\C` - Append mode (parsed, placeholder exists)
- ❌ `\n[half]` / `\n[percent]` - Variable newline height (parsed, treated as regular newline)
- ❌ `\_b[...]` - Balloon images (inline and positioned)
- ❌ `\_l[x,y]` - Text cursor positioning
- ❌ `\c` / `\c[char/line,...]` - Text clearing
- ❌ `\_n` - No auto-wrap mode
- ❌ `\_!...\_!` / `\_?...\_?` - Tag passthrough (parsed correctly)
- ❌ `\__v[...]` - Voice synthesis control
- ❌ `\![set,autoscroll,...]` - Auto-scroll control
- ❌ `\![set,balloonoffset,...]` - Balloon offset
- ❌ `\![set,balloonalign,...]` - Balloon alignment
- ❌ `\![set,balloonmarker,...]` - SSTP marker
- ❌ `\![set,balloonnum,...]` - File transfer indicator
- ❌ `\![set,balloontimeout,...]` - Balloon timeout
- ❌ `\![set,balloonwait,...]` - Text speed
- ❌ `\![set,serikotalk,...]` - SERIKO mouth animation
- ❌ `\![enter/leave,onlinemode]` - Online marker
- ❌ `\![enter/leave,nouserbreakmode]` - User break control
- ❌ `\![lock/unlock,balloonrepaint]` - Balloon repaint control
- ❌ `\![lock/unlock,balloonmove]` - Balloon drag control

**Font & Text Styling Commands - PARSED ONLY:**
All font and text styling commands are fully parsed, but execution is not yet implemented:
- ❌ `\f[align,...]` - Text alignment (left/center/right)
- ❌ `\f[valign,...]` - Vertical text alignment (top/center/bottom)
- ❌ `\f[name,...]` - Font family change
- ❌ `\f[height,...]` - Font size (absolute, relative, percentage)
- ❌ `\f[color,...]` - Text color
- ❌ `\f[shadowcolor,...]` - Shadow color
- ❌ `\f[shadowstyle,...]` - Shadow style (offset/outline)
- ❌ `\f[anchor.font.color,...]` - Anchor text color
- ❌ `\f[bold,...]` - Bold text style
- ❌ `\f[italic,...]` - Italic text style
- ❌ `\f[strike,...]` - Strikethrough text
- ❌ `\f[underline,...]` - Underline text
- ❌ `\f[outline,...]` - Outline (white text) style
- ❌ `\f[sub,...]` - Subscript text
- ❌ `\f[sup,...]` - Superscript text
- ❌ `\f[default]` - Reset all font attributes
- ❌ `\f[disable]` - Set disabled text style

**Movement:**
- ❌ `\4` and `\5` - Basic character movement (parsed, handler placeholder exists)
- ❌ `\![move,...]` / `\![moveasync,...]` - Complex movement with parameters

**Animation:**
- ❌ `\![anim,clear,ID]` / `\![anim,pause,ID]` / `\![anim,resume,ID]` / `\![anim,stop]`
- ❌ `\![anim,offset,ID,x,y]`
- ❌ `\![anim,add,*]` - Animation layering
- ❌ `\__w[animation,ID]` - Wait for animation completion

**Dressup:**
- ❌ `\![bind,category,part,value]` - Full dressup system not yet implemented

**Effects & Filters:**
- ❌ `\![effect,...]` / `\![effect2,...]` / `\![filter,...]` - Plugin-based effects
- ❌ `\![set,scaling,x,y,time]` - Animated scaling over time

**Notes:**
- Parser correctly identifies all commands and extracts parameters
- Placeholder handlers exist with TODO comments for future implementation
- Some features require platform-specific NSWindow manipulation
- Animation, balloon, and dressup systems require additional infrastructure

## Testing

All commands have comprehensive test coverage in `OurinTests/SakuraScriptEngineTests.swift`. Run tests with:

```bash
xcodebuild -project Ourin.xcodeproj -scheme Ourin -only-testing:OurinTests/SakuraScriptEngineTests test
```

## References

- Full specification: `docs/SAKURASCRIPT_FULL_1.0M_PATCHED.md`
- Parser implementation: `Ourin/SakuraScript/SakuraScriptEngine.swift`
- Test suite: `OurinTests/SakuraScriptEngineTests.swift`
