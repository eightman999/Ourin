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

## Compatibility Notes

These examples work with the current YAYA Core MVP implementation. They avoid:
- Array/tuple literals `(a, b, c)`
- Embedded expressions `%(func())`
- Complex array operations

For full Emily4 compatibility, these features will be added in Phase 2.
