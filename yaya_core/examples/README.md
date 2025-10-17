# YAYA Core Examples

This directory contains example YAYA dictionary files that demonstrate the features supported by YAYA Core.

## simple_ghost.dic

A basic ghost dictionary demonstrating:
- Variable assignments
- String concatenation
- Conditional logic (if/else)
- Built-in functions (RAND, GETTIME)
- SHIORI reference access
- Multiple functions

### Usage

```bash
# Test loading the dictionary
echo '{"cmd":"load","ghost_root":"./examples","dic":["simple_ghost.dic"],"encoding":"utf-8"}' | ../build/yaya_core

# Test executing OnBoot
{
  echo '{"cmd":"load","ghost_root":"./examples","dic":["simple_ghost.dic"],"encoding":"utf-8"}'
  echo '{"cmd":"request","method":"GET","id":"OnBoot","ref":[]}'
} | ../build/yaya_core
```

## Phase 2 Features (Now Supported!)

The following Phase 2 features are now implemented and working:

### Array Literals and Operations

```yaya
_arr = (1, 2, 3)
_size = ARRAYSIZE(_arr)  // Returns 3

_empty = IARRAY
_empty ,= "first"
_empty ,= "second"
```

### Bare Function Calls

```yaya
GetTimeSlot { "morning" }
_slot = GetTimeSlot  // Calls function without ()
```

### String Interpolation

```yaya
_timeslot = "morning"
_funcname = "OnBoot_%(_timeslot)"  // Becomes "OnBoot_morning"
```

### Type Annotations

```yaya
RandomTalk : array {
    "Message 1"
    "Message 2"
    "Message 3"
}
```

## Emily4-Compatible Patterns

These patterns from Emily4 now work correctly:

```yaya
OnBoot_morning { "Morning boot" }

OnBoot {
    _timeslot = GetTimeSlot
    _array = IARRAY
    
    if ISFUNC("OnBoot_%(_timeslot)") {
        _array ,= EVAL("OnBoot_%(_timeslot)")
    }
    
    if ARRAYSIZE(_array) {
        _result = _array[RAND(ARRAYSIZE(_array))]
        "\0\s[0]" + _result + "\e"
    }
}
```

## Compatibility Notes

**Fully Supported:**
- Array literals `(a, b, c)`
- Array operations (IARRAY, ARRAYSIZE, indexing, ,=)
- Bare function calls
- Variable interpolation in strings `%(_varname)`
- Type annotations (`: array`)
- Nested conditionals
- All basic YAYA features

**Partially Supported:**
- Embedded function calls `%(funcname())` - works for simple cases
- Some complex Emily4 dictionary patterns

**Future (Phase 3):**
- Regular expressions
- SAORI plugin support
- Performance optimizations
