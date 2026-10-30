// Local POSIX equivalents for aktk's original Windows export boundary.
#pragma once
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <string>
#include <unistd.h>
#include <mruby.h>
#include <mruby/compile.h>
#include <mruby/value.h>
#include <mruby/string.h>
using namespace std;
using BOOL = int32_t;
using HGLOBAL = void*;
#define __cdecl
#define GMEM_FIXED 0
inline void GlobalFree(void* value) { free(value); }
inline void* GlobalAlloc(int, size_t length) { return malloc(length); }
static mrb_state* mrb = nullptr;
