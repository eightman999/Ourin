# YAYA_core Function Reference

## Overview

This document lists the functions available in `yaya_core`. The supported
built-ins have executable behavior; platform restrictions and known semantic
limits are called out explicitly below.

- **implemented** — behaves like the YAYA reference for common cases
- **partial** — works with restrictions / simplified behavior
- **stub** — reserved for an intentionally fixed compatibility default; no
  supported built-in currently has this status

See `IMPLEMENTATION_STATUS.md` for the overall system status and partial
compatibility limits.

## Function Categories

### Type Conversion Functions (10)

| Function | Description | Example |
|----------|-------------|---------|
| `TOINT(value)` | Convert value to integer | `TOINT("42")` → `42` |
| `TOSTR(value)` | Convert value to string | `TOSTR(42)` → `"42"` |
| `TOREAL(value)` | Convert value to real number | `TOREAL(42)` → `42` |
| `TOAUTO(value)` | Auto-detect and convert type | `TOAUTO("123")` → `123` |
| `TOAUTOEX(value)` | Extended auto-conversion | `TOAUTOEX(value)` |
| `CVINT(value)` | Alias for TOINT | `CVINT("42")` → `42` |
| `CVSTR(value)` | Alias for TOSTR | `CVSTR(42)` → `"42"` |
| `CVREAL(value)` | Alias for TOREAL | `CVREAL(42)` → `42` |
| `CVAUTO(value)` | Alias for TOAUTO | `CVAUTO(value)` |
| `CVAUTOEX(value)` | Alias for TOAUTOEX | `CVAUTOEX(value)` |
| `GETTYPE(value)` | Get type code (0=void, 1=int, 2=str, 3=array) | `GETTYPE("hi")` → `2` |
| `GETTYPEEX(value)` | Get type name | `GETTYPEEX("hi")` → `"str"` |

### String Operations (13)

| Function | Description | Example |
|----------|-------------|---------|
| `STRLEN(str)` | Get string length | `STRLEN("hello")` → `5` |
| `STRSTR(haystack, needle, [start])` | Find substring position (-1 if not found), optionally starting from position | `STRSTR("hello", "ll")` → `2`<br/>`STRSTR("hello", "l", 3)` → `3` |
| `SUBSTR(str, pos, len)` | Extract substring | `SUBSTR("hello", 0, 3)` → `"hel"` |
| `REPLACE(str, old, new)` | Replace all occurrences | `REPLACE("aa", "a", "b")` → `"bb"` |
| `ERASE(str, pos, len)` | Remove substring | `ERASE("hello", 1, 2)` → `"hlo"` |
| `INSERT(str, pos, text)` | Insert text at position | `INSERT("hlo", 1, "el")` → `"hello"` |
| `TOUPPER(str)` | Convert to uppercase | `TOUPPER("hello")` → `"HELLO"` |
| `TOLOWER(str)` | Convert to lowercase | `TOLOWER("HELLO")` → `"hello"` |
| `CUTSPACE(str)` | Trim whitespace | `CUTSPACE(" hi ")` → `"hi"` |
| `CHR(code)` | ASCII code to character | `CHR(65)` → `"A"` |
| `CHRCODE(str)` | Character to ASCII code | `CHRCODE("A")` → `65` |
| `GETSTRBYTES(str)` | Get byte length | `GETSTRBYTES("hi")` → `2` |
| `STRFORM(fmt, ...)` | Format string (simplified) | `STRFORM("Hi %s", "there")` |

### Math Operations (20)

| Function | Description | Example |
|----------|-------------|---------|
| `RAND(max)` or `RAND(array)` | Random integer 0 to max-1, or random element from array | `RAND(10)` → `0-9`<br/>`RAND(("a","b","c"))` → random element |
| `SRAND(seed)` | Seed random number generator | `SRAND(12345)` |
| `FLOOR(value)` | Round down | `FLOOR(3.7)` → `3` |
| `CEIL(value)` | Round up | `CEIL(3.2)` → `4` |
| `ROUND(value)` | Round to nearest | `ROUND(3.5)` → `4` |
| `SQRT(value)` | Square root | `SQRT(16)` → `4` |
| `POW(base, exp)` | Power | `POW(2, 3)` → `8` |
| `LOG(value)` | Natural logarithm | `LOG(100)` |
| `LOG10(value)` | Base-10 logarithm | `LOG10(100)` → `2` |
| `SIN(value)` | Sine | `SIN(0)` → `0` |
| `COS(value)` | Cosine | `COS(0)` → `1` |
| `TAN(value)` | Tangent | `TAN(0)` → `0` |
| `ASIN(value)` | Arc sine | `ASIN(0)` → `0` |
| `ACOS(value)` | Arc cosine | `ACOS(1)` → `0` |
| `ATAN(value)` | Arc tangent | `ATAN(0)` → `0` |
| `SINH(value)` | Hyperbolic sine | `SINH(0)` → `0` |
| `COSH(value)` | Hyperbolic cosine | `COSH(0)` → `1` |
| `TANH(value)` | Hyperbolic tangent | `TANH(0)` → `0` |

### Array Operations (10)

| Function | Description | Example |
|----------|-------------|---------|
| `IARRAY()` | Create empty array | `IARRAY()` → `[]` |
| `ARRAYSIZE(arr)` | Get array size | `ARRAYSIZE(arr)` → `3` |
| `SPLIT(str, delim)` | Split string to array | `SPLIT("a,b", ",")` → `["a","b"]` |
| `ASEARCH(arr, value)` | Search array, return index | `ASEARCH(arr, "b")` → `1` |
| `ASEARCHEX(arr, value, start)` | Search from position | `ASEARCHEX(arr, "b", 0)` → `1` |
| `ASEARCHPOS(arr, value, start)` | Search from position (default 0) | `ASEARCHPOS(arr, "b", 2)` → `3` |
| `ASORT(arr)` | Sort array | `ASORT(["c","a","b"])` → `["a","b","c"]` |
| `ARRAYDEDUP(arr)` | Remove duplicates | `ARRAYDEDUP(["a","a"])` → `["a"]` |
| `ANY(arr)` | Return random element | `ANY(["a","b"])` → `"a"` or `"b"` |
| `SPLITPATH(path)` | Split file path | `SPLITPATH("/a/b")` → `["a","b"]` |

### Bitwise Operations (5)

| Function | Description | Example |
|----------|-------------|---------|
| `BITWISE_AND(a, b)` | Bitwise AND | `BITWISE_AND(5, 3)` → `1` |
| `BITWISE_OR(a, b)` | Bitwise OR | `BITWISE_OR(5, 3)` → `7` |
| `BITWISE_XOR(a, b)` | Bitwise XOR | `BITWISE_XOR(5, 3)` → `6` |
| `BITWISE_NOT(a)` | Bitwise NOT | `BITWISE_NOT(5)` → `-6` |
| `BITWISE_SHIFT(value, shift)` | Bitwise shift | `BITWISE_SHIFT(1, 3)` → `8` |

### Hex/Binary Conversions (4)

| Function | Description | Example |
|----------|-------------|---------|
| `TOHEXSTR(value, digits)` | Integer to hex string | `TOHEXSTR(255, 2)` → `"FF"` |
| `HEXSTRTOI(str)` | Hex string to integer | `HEXSTRTOI("FF")` → `255` |
| `TOBINSTR(value, digits)` | Integer to binary string | `TOBINSTR(7, 4)` → `"0111"` |
| `BINSTRTOI(str)` | Binary string to integer | `BINSTRTOI("0111")` → `7` |

### Type Checking (2)

| Function | Description | Example |
|----------|-------------|---------|
| `ISINTSTR(str)` | Check if string is integer | `ISINTSTR("123")` → `1` |
| `ISREALSTR(str)` | Check if string is real number | `ISREALSTR("12.3")` → `1` |

### Variable/Function Management (13)

| Function | Description | Example |
|----------|-------------|---------|
| `ISVAR(name)` | Check if variable exists | `ISVAR("myvar")` → `1` |
| `ISFUNC(name)` | Check if function exists | `ISFUNC("OnBoot")` → `1` |
| `ISEVALUABLE(str)` | Check whether a string parses as one complete expression | `ISEVALUABLE("1+1")` → `1`; `ISEVALUABLE("1 +")` → `0` |
| `ERASEVAR(name)` | Delete variable | `ERASEVAR("myvar")` → `1` |
| `LETTONAME(name, value)` | Assign to variable by name | `LETTONAME("x", 42)` |
| `GETFUNCLIST()` | Get list of user functions | `GETFUNCLIST()` → array |
| `GETVARLIST()` | Get list of variables | `GETVARLIST()` → array |
| `GETSYSTEMFUNCLIST()` | Get list of system functions | `GETSYSTEMFUNCLIST()` → 160 items |
| `EVAL(funcname, ...)` | Execute function by name | `EVAL("OnBoot")` |
| `DUMPVAR()` | Dump all variables (debug) | `DUMPVAR()` → string |
| `DICLOAD(filename[, encoding])` | Load dictionary file at runtime (resolved under ghost/master) | `DICLOAD("dic.txt")` → `1` |
| `DICUNLOAD(filename)` | Unload dictionary (removes functions owned by that source) | `DICUNLOAD("dic.txt")` → `1` |
| `UNDEFFUNC(name)` | Disable all declarations of a function | `UNDEFFUNC("func")` → `1` |

Function declaration notes:

- Same-name functions overload by default: enabled declarations run in declaration order and their return values concatenate.
- `nonoverload` disables accumulation for that function name: the latest registered declaration replaces earlier declarations (last definition wins).
- `array`, `sequential`, `void`, `nonoverload`, and `when` modifiers are parsed and exposed through declaration metadata; standalone `when` dispatch remains a known limitation documented in `IMPLEMENTATION_STATUS.md`.

### System Operations (9 - Core functions IMPLEMENTED)

| Function | Description | Example | Status |
|----------|-------------|---------|--------|
| `GETTIME[index]` | Get time component (0=year, 1=month, 2=day, 3=weekday, 4=hour, 5=min, 6=sec) | `GETTIME[0]` → `2025` | ✅ Working |
| `GETTICKCOUNT()` | Get milliseconds since epoch | `GETTICKCOUNT()` | ✅ Working |
| `GETSECCOUNT()` | Get seconds since epoch | `GETSECCOUNT()` | ✅ Working |
| `GETENV(name)` | Get environment variable | `GETENV("PATH")` | ✅ Working |
| `GETMEMINFO()` | Get host memory info `[load,totalPhys,availPhys,totalVirtual,availVirtual]` | `GETMEMINFO()` | ✅ Working |
| `EXECUTE(cmd)` | Execute system command (non-blocking) | `EXECUTE("echo test")` → `1` | ✅ Working |
| `EXECUTE_WAIT(cmd)` | Execute and wait for completion | `EXECUTE_WAIT("ls")` → exit code | ✅ Working |
| `SLEEP(ms)` | Sleep for milliseconds | `SLEEP(1000)` | ✅ Working |
| `READFMO(name)` | Read Forged Memory Object through host IPC | `READFMO("name")` | ✅ Working |
| `SETTAMAHWND(hwnd)` | Store the logical TAMA window identifier (`tama.hwnd`) | `SETTAMAHWND(0)` | ✅ macOS-compatible |

**Example Usage**:
```yaya
// Execute command and wait
_result = EXECUTE_WAIT("ls -l")

// Execute in background
EXECUTE("open -a Safari")

// Delay execution
SLEEP(1000)  // Wait 1 second
```

### File Operations (20 - IMPLEMENTED with Security Restrictions)

**Note**: File operations are fully implemented with security restrictions:
- Only relative paths allowed (no absolute paths or .. traversal)
- Designed for safe use within ghost directories
- All standard file I/O operations work correctly

| Function | Description | Returns | Status |
|----------|-------------|---------|--------|
| `FOPEN(file, mode)` | Open file | File handle (>= 0) or -1 on error | ✅ Working |
| `FCLOSE(handle)` | Close file | 1 on success, 0 on failure | ✅ Working |
| `FREAD(handle)` | Read line from file | String (line content) | ✅ Working |
| `FWRITE(handle, data)` | Write to file | Bytes written | ✅ Working |
| `FWRITE2(file, data)` | Write directly to file | 1 on success, 0 on failure | ✅ Working |
| `FSIZE(file)` | Get file size | Size in bytes or -1 on error | ✅ Working |
| `FSEEK(handle, pos)` | Seek in file | 0 on success, -1 on error | ✅ Working |
| `FTELL(handle)` | Get file position | Current position or -1 | ✅ Working |
| `FCHARSET(charset)` | Set text-file charset (`0`=CP932, `1`=UTF-8, `127`=OS default) | void | ✅ Working |
| `FATTRIB(file)` | Get 11-element POSIX/Windows-compatible attribute array | `[archive,...,ctime,mtime]` or `-1` | ✅ Working |
| `FREADBIN(handle)` | Read binary data | Binary string | ✅ Working |
| `FWRITEBIN(handle, data)` | Write binary data | Bytes written | ✅ Working |
| `FREADENCODE(handle, enc)` | Read with encoding | UTF-8 string | ✅ Working |
| `FWRITEDECODE(handle, data, enc)` | Write with encoding | Bytes written | ✅ Working |
| `FDIGEST(file, algo)` | File hash/digest (`md5`/`sha1`/`crc32`) | hex string | ✅ Working |
| `FENUM(path, pattern)` | Enumerate files | Matching filename array | ✅ Working |
| `FCOPY(src, dst)` | Copy file | 1 on success, 0 on failure | ✅ Working |
| `FMOVE(src, dst)` | Move/rename file | 1 on success, 0 on failure | ✅ Working |
| `FDEL(file)` | Delete file | 1 on success, 0 on failure | ✅ Working |
| `FRENAME(old, new)` | Rename file | 1 on success, 0 on failure | ✅ Working |
| `MKDIR(path)` | Create directory | 1 on success, 0 on failure | ✅ Working |
| `RMDIR(path)` | Remove directory | 1 on success, 0 on failure | ✅ Working |

**Example Usage**:
```yaya
// Write to file
_handle = FOPEN("data.txt", "w")
FWRITE(_handle, "Hello, World!\n")
FCLOSE(_handle)

// Read from file
_handle = FOPEN("data.txt", "r")
_content = FREAD(_handle)
FCLOSE(_handle)

// Direct write
FWRITE2("output.txt", "Direct write content")

// File operations
_size = FSIZE("data.txt")
FCOPY("data.txt", "backup.txt")
FDEL("old_file.txt")
```

### Regular Expression Functions (11 - IMPLEMENTED)

Regex functions implemented via C++ `std::regex` (ECMAScript syntax). 

| Function | Description | Returns |
|----------|-------------|---------|
| `RE_SEARCH(str, pattern)` | Search for pattern; stores match details | `1`/`0` |
| `RE_MATCH(str, pattern)` | Match the complete string; stores match details | `1`/`0` |
| `RE_GREP(str, pattern)` | Count matches and store them | count |
| `RE_REPLACE(str, pattern, new)` | Replace with regex | replaced string |
| `RE_REPLACEEX(str, pattern, new)` | Replace with regex backreferences | replaced string |
| `RE_SPLIT(str, pattern)` | Split by regex | string array |
| `RE_OPTION(options)` | Set regex options | `0` |
| `RE_GETSTR()` | Get last match strings, including groups | string array |
| `RE_GETPOS()` | Get last match positions | integer array |
| `RE_GETLEN()` | Get last match lengths | integer array |
| `RE_ASEARCH(arr, pattern)` | Array regex search (first match index) | `RE_ASEARCH(("a","an"),"an")` → `1` |
| `RE_ASEARCHEX(arr, pattern)` | Array regex search ext (all match indices) | `RE_ASEARCHEX(("a","an"),"an")` → `[1]` |

### Encoding/Decoding Functions (10)

| Function | Description | Example |
|----------|-------------|---------|
| `STRENCODE(str, encoding)` | URL encode (`url`/`url+`) | `STRENCODE("a b", "url")` → `"a+b"` |
| `STRDECODE(str, encoding)` | URL decode (`url`/`url+`) | `STRDECODE("a+b", "url")` → `"a b"` |
| `GETSTRURLENCODE(str)` | URL encode (alias) | `GETSTRURLENCODE("test")` |
| `GETSTRURLDECODE(str)` | URL decode (alias) | `GETSTRURLDECODE("test")` |
| `STRDIGEST(str, algo)` | String hash (`md5`/`sha1`/`crc32`) | `STRDIGEST("test", "md5")` |
| `CHARSETLIB(encoding)` | Set charset for subsequent SAORI requests | `CHARSETLIB("UTF-8")` → `1` |
| `CHARSETLIBEX(encoding)` | Set charset (extended alias) | `CHARSETLIBEX("Shift_JIS")` → `1` |
| `CHARSETTEXTTOID(text)` | Charset name to ID | `CHARSETTEXTTOID("UTF-8")` → `0` |
| `CHARSETIDTOTEXT(id)` | Charset ID to name | `CHARSETIDTOTEXT(0)` → `"UTF-8"` |
| `ZEN2HAN(str)` | Full to half-width ASCII/space conversion | `ZEN2HAN("ＡＢＣ")` |
| `HAN2ZEN(str)` | Half to full-width ASCII/space conversion | `HAN2ZEN("ABC")` |

### Other Utility Functions (18+)

| Function | Description | Example |
|----------|-------------|---------|
| `SAVEVAR(file)` | Save variables (anchored under ghost root; JSON with type info) | `SAVEVAR("var/s.json")` → `1` |
| `RESTOREVAR(file)` | Restore variables | `RESTOREVAR("var/s.json")` → `1` |
| `REGISTERTEMPVAR(name)` | Mark a variable as temporary so `SAVEVAR` excludes it | `REGISTERTEMPVAR("tempvar")` → `1` |
| `UNREGISTERTEMPVAR(name)` | Remove a variable from the temp-var exclusion list | `UNREGISTERTEMPVAR("tempvar")` → `1` |
| `LOGGING(msg...)` | Write message(s) to stderr with `[YAYA][LOGGING]` prefix (real since 2026-07-05) | `LOGGING("test")` → `1` |
| `LSO()` | Last selected parallel option index | `LSO()` → index or `-1` |
| `LICENSE()` | Get license info | `LICENSE()` → license text |
| `TRANSLATE(str, from, to)` | tr-style character-set mapping (upstream-compatible: `-` ranges, `\` escapes, delete mode when `to` empty; real since 2026-07-05) | `TRANSLATE("abc","ab","xy")` → `"xyc"` |
| `GETDELIM()` | Get the default array delimiter | `GETDELIM()` → `","` |
| `SETDELIM(delim)` | Set the default array delimiter | `SETDELIM(",")` → `1` |
| `GETSETTING(key)` | Get setting value | `GETSETTING("key")` → stored value |
| `SETSETTING(key, val)` | Set setting | `SETSETTING("k", "v")` → `1` |
| `GETLASTERROR()` | Get last error code | `GETLASTERROR()` → `0` |
| `SETLASTERROR(code)` | Set last error | `SETLASTERROR(0)` → `1` |
| `GETERRORLOG()` | Get accumulated error log | `GETERRORLOG()` → newline-joined log |
| `GETCALLSTACK()` | Get call stack (recursion depth) | `GETCALLSTACK()` → `[depth]` |
| `GETFUNCINFO(name)` | Get function info `[type, enabled_count, source_id]` | `GETFUNCINFO("func")` → array |
| `LOADLIB(file)` | Load SAORI/Plugin lib (via host IPC) | `LOADLIB("lib.dll")` → `1` |
| `UNLOADLIB(file)` | Unload SAORI/Plugin lib | `UNLOADLIB("lib.dll")` → `1` |
| `REQUESTLIB(file, request[, charset])` | Request from SAORI; parses Result + Value0.. | `REQUESTLIB("lib", req)` → Result value |

**Note on Plugin Functions**: LOADLIB/UNLOADLIB/REQUESTLIB route through the Swift host `SaoriManager` via JSON IPC. REQUESTLIB parses the SAORI response (`Result` header + `Value0`/`Value1`/...) and exposes extras via the `valueex`/`valueex0..15` builtins. `FUNCTIONLOAD`/`FUNCTIONEX`/`SAORI` yaya-dic wrappers are also provided.

Plus advanced functions: `ISGLOBALDEFINE`, `SETGLOBALDEFINE`, `UNDEFGLOBALDEFINE`, `PROCESSGLOBALDEFINE` (runtime global defines), `APPEND_RUNTIME_DIC`, `FUNCDECL_READ`, `FUNCDECL_WRITE`, `FUNCDECL_ERASE`, `CHARSETTEXTTOID`, `CHARSETIDTOTEXT`, `valueex`/`valueex0..15`, `OUTPUTNUM`, `EmBeD_HiStOrY`

## Implementation Status (Honest)

- **Total functions present**: ~160 (for compatibility with yaya-shiori-500)
- **Fully implemented**: type conversion, string, math, array, bitwise, hex/binary, type checking, file I/O (restricted), system/time, most variable/function management, regular expressions (`RE_*` via std::regex, incl. `RE_ASEARCH`/`RE_ASEARCHEX`), dynamic dictionaries (`DICLOAD`/`DICUNLOAD`/`APPEND_RUNTIME_DIC`), persistence (`SAVEVAR`/`RESTOREVAR` with `REGISTERTEMPVAR` exclusions), SAORI helpers (`LOADLIB`/`UNLOADLIB`/`REQUESTLIB` + valueex), settings, diagnostics (`GETERRORLOG`/`GETCALLSTACK`/`GETFUNCINFO`), encoding utils (`CHARSETLIB`/`CHARSETTEXTTOID`/`CHARSETIDTOTEXT`/`ZEN2HAN`/`HAN2ZEN`), global defines
- **Core runtime stubs remaining**: none in the supported YAYA built-in set. Windows HWND routing is represented by the macOS logical `tama.hwnd` setting; FMO uses the host IPC bridge.
- **File I/O**: working but restricted to relative paths (no absolute / no `..`)
- **System commands**: `EXECUTE`/`EXECUTE_WAIT`/`SLEEP` working
- **Plugin/SAORI functions**: routed through Swift host IPC; multi-value responses parsed

The previous claim of "160 / 160 = 100% fully implemented" was inaccurate. Many
entries exist only so that ghosts which *call* these functions do not crash; they
do not perform the documented operation.

## Notes

1. **Security**: File I/O and system execution are restricted. File operations
   allow only relative paths (no absolute paths, no `..` traversal) to keep
   access within the ghost directory.

2. **Performance**: Core functions (type conversion, string ops, math, arrays,
   bitwise) run with native C++ performance. Host-bound operations fail closed
   when the host does not provide a corresponding capability.

3. **Compatibility**: This is **not** a 100% faithful reimplementation of the
   Windows `yaya-shiori` reference. It can load and run many ghosts (including
   Emily4, which loads 33/33 dictionaries), but platform restrictions and
   simplified constructs limit full fidelity for advanced ghosts.

4. **Testing**: Core functions are exercised by `examples/`. See
   `IMPLEMENTATION_STATUS.md` for the per-feature status matrix.

## Usage Example

```yaya
OnBoot
{
    // Type conversion
    _num = TOINT("42")
    _str = TOSTR(_num)
    
    // String operations
    _upper = TOUPPER("hello")
    _len = STRLEN(_upper)
    
    // Math
    _sqrt = SQRT(16)
    _pow = POW(2, 3)
    
    // Arrays
    _arr = SPLIT("a,b,c", ",")
    _size = ARRAYSIZE(_arr)
    _random = ANY(_arr)
    
    // Bitwise
    _and = BITWISE_AND(5, 3)
    
    // System
    _year = GETTIME[0]
    _funcs = GETSYSTEMFUNCLIST()
    _count = ARRAYSIZE(_funcs)
    
    "Hello! I have %(_count) functions available!"
}
```

## See Also

- `IMPLEMENTATION_STATUS.md` - Detailed implementation notes
- `YAYA_CORE_COMPLETE.md` - Project summary
- `examples/all_functions_test.dic` - Comprehensive test suite
- `examples/simple_ghost.dic` - Basic example
- `examples/phase2_features.dic` - Advanced features demo
